import { isSupabaseConfigured } from './config.js';
import { RemoteRepo } from './repositories.js';
import { DB } from './data.js';
import { pullTransactions, pullAccounting } from './sync.js';

const esc=v=>String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
function activeAccounts(){return (DB.getState().cashAccounts||[]).filter(a=>a.status!=='Inactivo');}
function rateFor(currency){
 const cur=String(currency||'USD').toUpperCase(); if(cur==='USD')return 1;
 const rows=(DB.getState().exchangeRates||[]).filter(r=>String(r.currency||'').toUpperCase()===cur&&Number(r.rate)>0).sort((a,b)=>String(b.date||'').localeCompare(String(a.date||'')));
 return rows.length?Number(rows[0].rate):null;
}
async function refresh(){DB.setSyncStatus('syncing');await Promise.all([pullTransactions(DB.getState()),pullAccounting(DB.getState())]);DB.setSyncStatus('synced');DB.save();}
function modal(title,body,onSave){
 const bg=document.createElement('div');bg.className='modal-bg';bg.innerHTML=`<div class="modal"><h3>${esc(title)}</h3><form id="atlasRemoteCashForm">${body}<div class="modal-actions"><button type="button" class="btn btn-soft" data-cancel>Cancelar</button><button class="btn btn-primary">Confirmar</button></div></form></div>`;document.body.appendChild(bg);
 bg.querySelector('[data-cancel]').onclick=()=>bg.remove();
 bg.querySelector('form').onsubmit=async e=>{e.preventDefault();const btn=e.submitter||bg.querySelector('.btn-primary');if(btn){btn.disabled=true;btn.textContent='Procesando…';}try{const msg=await onSave(new FormData(e.target));bg.remove();await refresh();alert(msg||'Operación registrada.');window.location.reload();}catch(error){DB.setSyncStatus('error',error?.message||String(error));if(btn){btn.disabled=false;btn.textContent='Confirmar';}alert(error?.message||'No se pudo completar la operación');}};
 return bg;
}
function accountOptions(){return activeAccounts().map(a=>`<option value="${a.id}">${esc(a.name)} · ${esc(a.currency)} · ${Number(a.balance||0).toFixed(2)}</option>`).join('');}
function openTransfer(){
 const accounts=activeAccounts();if(accounts.length<2)return alert('Necesitas al menos dos cuentas activas.');
 modal('Transferencia entre cuentas · nube',`<div class="notice">ATLAS usa una referencia USD y guarda las tasas exactas usadas en la operación.</div><div class="field"><label>Cuenta origen</label><select name="from">${accountOptions()}</select></div><div class="field"><label>Cuenta destino</label><select name="to">${accountOptions()}</select></div><div class="field"><label>Monto a enviar</label><input name="amount" type="number" min="0.0001" step="0.0001" required></div><div class="field"><label>Referencia (opcional)</label><input name="reference"></div><div class="field"><label>Nota</label><input name="note" value="Transferencia entre cuentas"></div>`,async fd=>{
  const from=accounts.find(a=>a.id===fd.get('from')),to=accounts.find(a=>a.id===fd.get('to'));if(!from||!to)throw new Error('Cuenta inválida.');if(from.id===to.id)throw new Error('Origen y destino deben ser distintos.');
  const amount=Number(fd.get('amount'));if(!Number.isFinite(amount)||amount<=0)throw new Error('Monto inválido.');if(Number(from.balance||0)<amount)throw new Error('Saldo insuficiente.');
  const fr=rateFor(from.currency),tr=rateFor(to.currency);if(!fr||!tr)throw new Error('Falta una tasa vigente para una de las monedas.');
  const base=String(from.currency).toUpperCase()==='USD'?amount:amount/fr;const received=String(to.currency).toUpperCase()==='USD'?base:base*tr;
  const r=await RemoteRepo.cashTransfer({p_from_account:from.id,p_to_account:to.id,p_from_amount:amount,p_to_amount:received,p_base_amount_usd:base,p_from_rate:fr,p_to_rate:tr,p_reference:String(fd.get('reference')||'').trim()||null,p_note:String(fd.get('note')||'').trim()||null});
  return `Transferencia ${r?.reference||''} registrada.`;
 });
}
function openClosing(){
 const accounts=activeAccounts();if(!accounts.length)return alert('No hay cuentas activas.');
 modal('Cierre de caja · nube',`<div class="field"><label>Cuenta</label><select name="account">${accountOptions()}</select></div><div class="field"><label>Monto contado físicamente</label><input name="counted" type="number" min="0" step="0.0001" required></div><div class="field"><label>Observación</label><input name="note" value="Cierre de caja"></div>`,async fd=>{
  const counted=Number(fd.get('counted'));if(!Number.isFinite(counted)||counted<0)throw new Error('Monto contado inválido.');const r=await RemoteRepo.cashClose({p_cash_account:fd.get('account'),p_counted:counted,p_note:String(fd.get('note')||'').trim()||null});return `Cierre ${r?.reference||''} registrado. Diferencia: ${r?.currency||''} ${Number(r?.difference||0).toFixed(2)}.`;
 });
}
function openReconcile(id){
 const c=(DB.getState().cashClosings||[]).find(x=>x.id===id);if(!c)return alert('Cierre no encontrado.');
 modal('Conciliar diferencia · nube',`<div class="notice">Diferencia: <strong>${esc(c.currency)} ${Number(c.difference||0).toFixed(2)}</strong></div><div class="field"><label>Motivo</label><input name="reason" value="Diferencia de cierre" required></div>`,async fd=>{const reason=String(fd.get('reason')||'').trim();if(!reason)throw new Error('Motivo obligatorio.');const r=await RemoteRepo.reconcileCashClosing({p_closing:id,p_reason:reason});return `Cierre ${r?.reference||''} conciliado.`;});
}
function openCustomerCredit(id){
 const s=DB.getState(),c=(s.customerCredits||[]).find(x=>x.id===id);if(!c)return alert('Crédito no encontrado.');const debts=(s.receivables||[]).filter(r=>r.customerId===c.customerId&&Number(r.balance||0)>0);if(!debts.length)return alert('Este cliente no tiene cuentas pendientes.');
 modal('Aplicar crédito de cliente · nube',`<div class="notice">Disponible: USD ${Number(c.balance||0).toFixed(2)}</div><div class="field"><label>Cuenta por cobrar</label><select name="receivable">${debts.map(r=>`<option value="${r.id}">${esc(r.reference)} · USD ${Number(r.balance||0).toFixed(2)}</option>`).join('')}</select></div><div class="field"><label>Monto</label><input name="amount" type="number" min="0.01" step="0.01" value="${Math.min(Number(c.balance||0),Number(debts[0].balance||0))}"></div>`,async fd=>{const r=await RemoteRepo.applyCustomerCredit({p_credit:id,p_receivable:fd.get('receivable'),p_amount:Number(fd.get('amount'))});return `Crédito aplicado: USD ${Number(r?.amount||0).toFixed(2)}.`;});
}
function openSupplierCredit(id){
 const s=DB.getState(),c=(s.supplierCredits||[]).find(x=>x.id===id);if(!c)return alert('Crédito no encontrado.');const debts=(s.payables||[]).filter(r=>r.supplierId===c.supplierId&&Number(r.balance||0)>0);if(!debts.length)return alert('Este proveedor no tiene cuentas pendientes.');
 modal('Aplicar crédito de proveedor · nube',`<div class="notice">Disponible: USD ${Number(c.balance||0).toFixed(2)}</div><div class="field"><label>Cuenta por pagar</label><select name="payable">${debts.map(r=>`<option value="${r.id}">${esc(r.reference)} · USD ${Number(r.balance||0).toFixed(2)}</option>`).join('')}</select></div><div class="field"><label>Monto</label><input name="amount" type="number" min="0.01" step="0.01" value="${Math.min(Number(c.balance||0),Number(debts[0].balance||0))}"></div>`,async fd=>{const r=await RemoteRepo.applySupplierCredit({p_credit:id,p_payable:fd.get('payable'),p_amount:Number(fd.get('amount'))});return `Crédito aplicado: USD ${Number(r?.amount||0).toFixed(2)}.`;});
}

document.addEventListener('click',event=>{
 if(!isSupabaseConfigured())return;const t=event.target.closest?.('#newCashTransfer,#newCashClosing,[data-reconcile-cash],[data-use-credit],[data-use-supplier-credit]');if(!t)return;event.preventDefault();event.stopImmediatePropagation();
 if(t.id==='newCashTransfer')return openTransfer();if(t.id==='newCashClosing')return openClosing();if(t.dataset.reconcileCash)return openReconcile(t.dataset.reconcileCash);if(t.dataset.useCredit)return openCustomerCredit(t.dataset.useCredit);if(t.dataset.useSupplierCredit)return openSupplierCredit(t.dataset.useSupplierCredit);
},true);
