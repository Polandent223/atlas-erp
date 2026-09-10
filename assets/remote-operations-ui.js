import { isSupabaseConfigured } from './config.js';
import { RemoteRepo } from './repositories.js';
import { DB } from './data.js';
import { pullCoreWorkspace, pullTransactions, pullAccounting } from './sync.js';

const esc=v=>String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));

async function refreshAll(){
  DB.setSyncStatus('syncing');
  await Promise.all([pullCoreWorkspace(DB.getState()),pullTransactions(DB.getState()),pullAccounting(DB.getState())]);
  DB.setSyncStatus('synced');
  DB.save();
}
function modal(title,body,onSave){
  const bg=document.createElement('div'); bg.className='modal-bg';
  bg.innerHTML=`<div class="modal"><h3>${esc(title)}</h3><form id="atlasRemoteOperationForm">${body}<div class="modal-actions"><button type="button" class="btn btn-soft" data-cancel>Cancelar</button><button class="btn btn-primary">Confirmar</button></div></form></div>`;
  document.body.appendChild(bg);
  bg.querySelector('[data-cancel]').onclick=()=>bg.remove();
  bg.querySelector('form').onsubmit=async e=>{
    e.preventDefault(); const btn=e.submitter||bg.querySelector('.btn-primary');
    if(btn){btn.disabled=true;btn.textContent='Procesando…';}
    try{const result=await onSave(new FormData(e.target)); bg.remove(); await refreshAll(); alert(result||'Operación registrada correctamente.'); window.location.reload();}
    catch(error){DB.setSyncStatus('error',error?.message||String(error)); if(btn){btn.disabled=false;btn.textContent='Confirmar';} alert(error?.message||'No se pudo completar la operación');}
  };
  return bg;
}
function productSelectFor(doc){
  const s=DB.getState(); return (doc?.items||[]).map(i=>`<option value="${esc(i.productId)}">${esc(s.products.find(p=>p.id===i.productId)?.name||i.productId)} · ${Number(i.qty||0)} u.</option>`).join('');
}
function openSaleReturn(){
  const s=DB.getState(),sales=(s.sales||[]).filter(x=>x.status!=='Anulada');
  if(!sales.length)return alert('No hay ventas activas para devolver.');
  const first=sales[0];
  const bg=modal('Devolución de venta · nube',`
    <div class="notice">La devolución actualiza inventario, CxC/crédito del cliente, contabilidad y auditoría. Por seguridad no genera un reembolso de caja manual; si la venta ya estaba cobrada, queda crédito a favor.</div>
    <div class="field"><label>Venta</label><select name="saleId" data-doc>${sales.map(v=>`<option value="${v.id}">${esc(v.number)}</option>`).join('')}</select></div>
    <div class="field"><label>Producto</label><select name="productId" data-product>${productSelectFor(first)}</select></div>
    <div class="field"><label>Cantidad</label><input name="qty" type="number" min="0.001" step="0.001" value="1"></div>
  `,async fd=>{
    const qty=Number(fd.get('qty')); if(!Number.isFinite(qty)||qty<=0)throw new Error('Cantidad inválida.');
    const r=await RemoteRepo.returnSale({p_sale_id:fd.get('saleId'),p_product_id:fd.get('productId'),p_qty:qty});
    return `Devolución ${r?.number||''} registrada en la nube.`;
  });
  const doc=bg.querySelector('[data-doc]'),prod=bg.querySelector('[data-product]');
  doc.onchange=()=>{prod.innerHTML=productSelectFor(sales.find(v=>v.id===doc.value));};
}
function openPurchaseReturn(){
  const s=DB.getState(),purchases=(s.purchases||[]).filter(x=>x.status!=='Anulada');
  if(!purchases.length)return alert('No hay compras activas para devolver.');
  const first=purchases[0];
  const bg=modal('Devolución de compra · nube',`
    <div class="notice">La devolución reduce inventario, ajusta CxP o crea crédito del proveedor y registra contabilidad/auditoría. No mueve caja con una tasa implícita.</div>
    <div class="field"><label>Compra</label><select name="purchaseId" data-doc>${purchases.map(v=>`<option value="${v.id}">${esc(v.number)}</option>`).join('')}</select></div>
    <div class="field"><label>Producto</label><select name="productId" data-product>${productSelectFor(first)}</select></div>
    <div class="field"><label>Cantidad</label><input name="qty" type="number" min="0.001" step="0.001" value="1"></div>
  `,async fd=>{
    const qty=Number(fd.get('qty')); if(!Number.isFinite(qty)||qty<=0)throw new Error('Cantidad inválida.');
    const r=await RemoteRepo.returnPurchase({p_purchase_id:fd.get('purchaseId'),p_product_id:fd.get('productId'),p_qty:qty});
    return `Devolución ${r?.number||''} registrada en la nube.`;
  });
  const doc=bg.querySelector('[data-doc]'),prod=bg.querySelector('[data-product]');
  doc.onchange=()=>{prod.innerHTML=productSelectFor(purchases.find(v=>v.id===doc.value));};
}
function openCancel(kind,id){
  const s=DB.getState(),doc=(kind==='sale'?s.sales:s.purchases).find(x=>x.id===id);
  if(!doc)return alert('Documento no encontrado.');
  if(doc.status==='Anulada')return alert('El documento ya está anulado.');
  modal(kind==='sale'?'Anular venta · nube':'Anular compra · nube',`
    <div class="notice">ATLAS hará el reverso atómico de inventario, caja/CxC/CxP, contabilidad y auditoría. Si existen cobros, pagos o devoluciones que impidan un reverso seguro, la operación será bloqueada.</div>
    <div class="field"><label>Documento</label><input value="${esc(doc.number)}" disabled></div>
    <div class="field"><label>Motivo</label><input name="reason" value="Error de operación" required></div>
  `,async fd=>{
    const reason=String(fd.get('reason')||'').trim(); if(!reason)throw new Error('Motivo obligatorio.');
    const r=kind==='sale'?await RemoteRepo.voidSale({p_sale:id,p_reason:reason}):await RemoteRepo.voidPurchase({p_purchase:id,p_reason:reason});
    return `${kind==='sale'?'Venta':'Compra'} ${r?.number||doc.number} anulada en la nube.`;
  });
}

document.addEventListener('click',event=>{
  if(!isSupabaseConfigured())return;
  const target=event.target.closest?.('#newReturn,#newPurchaseReturn,[data-void-sale],[data-void-purchase]');
  if(!target)return;
  event.preventDefault(); event.stopImmediatePropagation();
  if(target.id==='newReturn')return openSaleReturn();
  if(target.id==='newPurchaseReturn')return openPurchaseReturn();
  if(target.dataset.voidSale)return openCancel('sale',target.dataset.voidSale);
  if(target.dataset.voidPurchase)return openCancel('purchase',target.dataset.voidPurchase);
},true);
