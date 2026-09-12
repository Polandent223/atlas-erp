import { isSupabaseConfigured } from './config.js';
import { RemoteRepo } from './repositories.js';
import { DB } from './data.js';
import { pullCoreWorkspace, pullTransactions, pullAccounting } from './sync.js';

function esc(v){return String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));}
function field(label,name,value,type='text',extra=''){return `<div class="field"><label>${label}</label><input name="${name}" type="${type}" value="${esc(value)}" ${extra}></div>`;}
function modal(title,body,onSave){
 const bg=document.createElement('div');
 bg.className='modal-bg';
 bg.innerHTML=`<div class="modal"><h3>${esc(title)}</h3><form id="atlasRemoteAdminForm">${body}<div class="modal-actions"><button type="button" class="btn btn-soft" data-cancel>Cancelar</button><button class="btn btn-primary">Guardar</button></div></form></div>`;
 document.body.appendChild(bg);
 bg.querySelector('[data-cancel]').onclick=()=>bg.remove();
 bg.querySelector('form').onsubmit=async e=>{
   e.preventDefault();
   const btn=e.submitter||bg.querySelector('button.btn-primary');
   if(btn){btn.disabled=true;btn.dataset.oldText=btn.textContent;btn.textContent='Guardando…';}
   try{await onSave(new FormData(e.target));bg.remove();window.location.reload();}
   catch(error){DB.setSyncStatus('error',error?.message||String(error));alert(error?.message||'No se pudo completar la operación');if(btn){btn.disabled=false;btn.textContent=btn.dataset.oldText||'Guardar';}}
 };
}

async function refreshAll(){
 DB.setSyncStatus('syncing');
 const s=DB.getState();
 const results=await Promise.allSettled([pullCoreWorkspace(s),pullTransactions(s),pullAccounting(s)]);
 const failed=results.find(x=>x.status==='rejected');
 if(failed){DB.setSyncStatus('error',failed.reason?.message||String(failed.reason));throw failed.reason;}
 DB.setSyncStatus('synced');
}

function openRemoteAdjustment(invId){
 const s=DB.getState();
 const inv=(s.inventory||[]).find(x=>x.id===invId);
 if(!inv) return alert('Inventario no encontrado.');
 const product=(s.products||[]).find(x=>x.id===inv.productId);
 const branch=(s.branches||[]).find(x=>x.id===inv.branchId);
 modal(`Ajustar stock — ${product?.name||''}`,`
   <div class="notice">${esc(branch?.name||'Sucursal')} · Stock actual: <strong>${Number(inv.stock||0).toFixed(2)}</strong></div>
   ${field('Nueva existencia','stock',Number(inv.stock||0),'number','step="0.0001" min="0"')}
   ${field('Motivo','note','Ajuste manual')}
 `,async fd=>{
   const stock=Number(fd.get('stock'));
   const reason=String(fd.get('note')||'').trim();
   if(!Number.isFinite(stock)||stock<0) throw new Error('Existencia inválida.');
   if(!reason) throw new Error('Indica el motivo del ajuste.');
   await RemoteRepo.rpc('atlas_adjust_inventory',{p_branch_id:inv.branchId,p_product_id:inv.productId,p_new_stock:stock,p_reason:reason});
   await refreshAll();
 });
}

async function saveRemoteCashAccount(form){
 const fd=new FormData(form);
 const name=String(fd.get('name')||'').trim();
 const currency=String(fd.get('currency')||'USD').trim().toUpperCase();
 const branchId=String(fd.get('branchId')||'').trim()||null;
 if(!name) throw new Error('Nombre es obligatorio.');
 await RemoteRepo.rpc('atlas_create_cash_account',{p_name:name,p_currency:currency,p_branch_id:branchId});
 await refreshAll();
}

async function saveRemoteBranch(form){
 const fd=new FormData(form);
 const name=String(fd.get('name')||'').trim();
 const city=String(fd.get('city')||'').trim();
 if(!name) throw new Error('Nombre es obligatorio.');
 const code=name.normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^A-Za-z0-9]/g,'').slice(0,8).toUpperCase()||null;
 await RemoteRepo.createBranch({p_name:name,p_code:code,p_city:city||null});
 await refreshAll();
}

async function saveRemotePaymentMethod(form){
 const fd=new FormData(form);
 const name=String(fd.get('name')||'').trim();
 const kind=String(fd.get('type')||'other').trim().toUpperCase();
 if(!name) throw new Error('Nombre es obligatorio.');
 await RemoteRepo.createPaymentMethod({p_name:name,p_kind:kind});
 await refreshAll();
}

async function saveRemoteRate(form){
 const fd=new FormData(form);
 const currency=String(fd.get('currency')||'').trim().toUpperCase();
 const rate=Number(fd.get('rate'));
 const source=String(fd.get('source')||'Manual').trim()||'Manual';
 const date=String(fd.get('date')||'').trim();
 if(!currency) throw new Error('Selecciona una moneda.');
 if(!Number.isFinite(rate)||rate<=0) throw new Error('La tasa debe ser mayor a cero.');
 const effectiveAt=date?`${date}T12:00:00Z`:new Date().toISOString();
 await RemoteRepo.createExchangeRate({p_currency:currency,p_rate:rate,p_source:source,p_effective_at:effectiveAt});
 await refreshAll();
}

async function saveRemoteCompany(form){
 const fd=new FormData(form);
 const name=String(fd.get('name')||'').trim();
 if(!name) throw new Error('Nombre de empresa obligatorio.');
 await RemoteRepo.updateCompany({
   p_name:name,
   p_tax_id:String(fd.get('taxId')||'').trim(),
   p_phone:String(fd.get('phone')||'').trim(),
   p_email:String(fd.get('email')||'').trim(),
   p_country:String(fd.get('country')||'VE').trim().toUpperCase(),
   p_base_currency:String(fd.get('baseCurrency')||'USD').trim().toUpperCase(),
   p_display_currency:String(fd.get('displayCurrency')||'USD').trim().toUpperCase()
 });
 await pullCoreWorkspace(DB.getState());
 DB.setSyncStatus('synced');
}

async function changeRemoteMasterState(kind,id){
 const s=DB.getState();
 const key=kind==='branch'?'branches':'users';
 const item=(s[key]||[]).find(x=>x.id===id);
 if(!item) throw new Error('Registro no encontrado.');
 const active=(item.status||'Activo')==='Inactivo';
 if(kind==='user' && id===s.session?.userId && !active) throw new Error('No puedes desactivar tu propia sesión.');
 if(!confirm(`¿${active?'Reactivar':'Desactivar'} este ${kind==='branch'?'registro de sucursal':'usuario'}?`)) return false;
 await RemoteRepo.rpc('atlas_set_master_active',{p_entity:kind,p_id:id,p_active:active});
 await pullCoreWorkspace(s);
 DB.setSyncStatus('synced');
 return true;
}

async function toggleRemotePaymentMethod(id){
 const s=DB.getState();
 const item=(s.paymentMethods||[]).find(x=>x.id===id);
 if(!item) throw new Error('Método de pago no encontrado.');
 await RemoteRepo.rpc('atlas_set_payment_method_active',{p_id:id,p_active:!item.active});
 await pullCoreWorkspace(s);
 DB.setSyncStatus('synced');
}

document.addEventListener('click',event=>{
 if(!isSupabaseConfigured()) return;
 const adjust=event.target.closest?.('[data-adjust]');
 if(adjust){event.preventDefault();event.stopImmediatePropagation();openRemoteAdjustment(adjust.dataset.adjust);return;}
 const del=event.target.closest?.('[data-delete]');
 if(del){
   const [kind,id]=String(del.dataset.delete||'').split(':');
   if(kind==='branch'||kind==='user'){
     event.preventDefault();event.stopImmediatePropagation();
     DB.setSyncStatus('syncing');
     changeRemoteMasterState(kind,id).then(changed=>{if(changed)window.location.reload();}).catch(error=>{DB.setSyncStatus('error',error?.message||String(error));alert(error?.message||'No se pudo cambiar el estado');});
     return;
   }
 }
 const pm=event.target.closest?.('[data-toggle-pm]');
 if(pm){
   event.preventDefault();event.stopImmediatePropagation();
   DB.setSyncStatus('syncing');
   toggleRemotePaymentMethod(pm.dataset.togglePm).then(()=>window.location.reload()).catch(error=>{DB.setSyncStatus('error',error?.message||String(error));alert(error?.message||'No se pudo cambiar el método');});
 }
},true);

document.addEventListener('submit',event=>{
 if(!isSupabaseConfigured()) return;
 const form=event.target;
 if(!(form instanceof HTMLFormElement)) return;
 if(form.id==='companyForm'){
   event.preventDefault();event.stopImmediatePropagation();
   const btn=form.querySelector('button[type="submit"],button.btn-primary');
   if(btn){btn.disabled=true;btn.dataset.oldText=btn.textContent;btn.textContent='Guardando…';}
   DB.setSyncStatus('syncing');
   saveRemoteCompany(form).then(()=>{alert('Empresa actualizada en la nube.');window.location.reload();}).catch(error=>{DB.setSyncStatus('error',error?.message||String(error));alert('No se pudo actualizar la empresa: '+(error?.message||error));if(btn){btn.disabled=false;btn.textContent=btn.dataset.oldText||'Guardar';}});
   return;
 }
 if(form.id!=='modalForm') return;
 const title=form.closest('.modal')?.querySelector('h3')?.textContent?.trim()||'';
 let handler=null,label='';
 if(title==='Nueva cuenta'){handler=saveRemoteCashAccount;label='la cuenta';}
 else if(title==='Nueva sucursal'){handler=saveRemoteBranch;label='la sucursal';}
 else if(title==='Nuevo método de pago'){handler=saveRemotePaymentMethod;label='el método de pago';}
 else if(title==='Nueva tasa'){handler=saveRemoteRate;label='la tasa';}
 else return;
 event.preventDefault();
 event.stopImmediatePropagation();
 const btn=form.querySelector('button.btn-primary');
 if(btn){btn.disabled=true;btn.dataset.oldText=btn.textContent;btn.textContent='Guardando…';}
 handler(form).then(()=>{form.closest('.modal-bg')?.remove();window.location.reload();}).catch(error=>{DB.setSyncStatus('error',error?.message||String(error));alert(`No se pudo guardar ${label} en la nube: `+(error?.message||error));if(btn){btn.disabled=false;btn.textContent=btn.dataset.oldText||'Guardar';}});
},true);
