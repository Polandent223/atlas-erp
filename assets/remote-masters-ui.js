import { isSupabaseConfigured } from './config.js';
import { RemoteRepo } from './repositories.js';
import { DB } from './data.js';
import { pullCoreWorkspace } from './sync.js';

const titleEntity = new Map([
  ['Nuevo cliente','customer'],
  ['Nuevo proveedor','supplier'],
  ['Nuevo producto','product']
]);

function payloadFor(entity, fd){
  if(entity==='product'){
    const tax=Number(fd.get('tax')||0), cost=Number(fd.get('cost')||0), price=Number(fd.get('price')||0), min=Number(fd.get('minStock')||0);
    if(!String(fd.get('sku')||'').trim() || !String(fd.get('name')||'').trim()) throw new Error('SKU y nombre son obligatorios.');
    if([tax,cost,price,min].some(x=>!Number.isFinite(x)||x<0)) throw new Error('Costos, precio, IVA y stock mínimo deben ser valores válidos.');
    if(tax>100) throw new Error('IVA no puede superar 100%.');
    return {sku:String(fd.get('sku')).trim(),name:String(fd.get('name')).trim(),category:String(fd.get('category')||'General').trim()||'General',cost,price,tax,min_stock:min};
  }
  const name=String(fd.get('name')||'').trim();
  if(!name) throw new Error('Nombre es obligatorio.');
  return {code:String(fd.get('code')||'').trim(),name,tax_id:String(fd.get('taxId')||'').trim(),phone:String(fd.get('phone')||'').trim(),email:String(fd.get('email')||'').trim(),address:String(fd.get('city')||'').trim()};
}

async function saveRemoteMaster(form, entity){
  const button=form.querySelector('button[type="submit"],button:not([type])');
  if(button){button.disabled=true;button.dataset.oldText=button.textContent;button.textContent='Guardando…';}
  try{
    const fd=new FormData(form);
    const payload=payloadFor(entity,fd);
    await RemoteRepo.rpc('atlas_create_master',{p_entity:entity,p_payload:payload});
    DB.setSyncStatus('syncing');
    await pullCoreWorkspace(DB.getState());
    DB.setSyncStatus('synced');
    form.closest('.modal-bg')?.remove();
    // app.js mantiene su render en ámbito de módulo; una recarga corta garantiza que toda la UI refleje la nube.
    window.location.reload();
  }catch(error){
    DB.setSyncStatus('error',error?.message||String(error));
    alert('No se pudo guardar en la nube: '+(error?.message||error));
    if(button){button.disabled=false;button.textContent=button.dataset.oldText||'Guardar';}
  }
}

document.addEventListener('submit',event=>{
  if(!isSupabaseConfigured()) return;
  const form=event.target;
  if(!(form instanceof HTMLFormElement) || form.id!=='modalForm') return;
  const title=form.closest('.modal')?.querySelector('h3')?.textContent?.trim()||'';
  const entity=titleEntity.get(title);
  if(!entity) return;
  event.preventDefault();
  event.stopImmediatePropagation();
  saveRemoteMaster(form,entity);
},true);
