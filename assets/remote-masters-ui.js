import { isSupabaseConfigured } from './config.js';
import { RemoteRepo } from './repositories.js';
import { DB, PERMISSIONS } from './data.js';
import { pullCoreWorkspace } from './sync.js';

const titleEntity = new Map([
  ['Nuevo cliente','customer'],
  ['Nuevo proveedor','supplier'],
  ['Nuevo producto','product']
]);

function esc(v){return String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));}
function field(label,name,value,type='text',extra=''){return `<div class="field"><label>${label}</label><input name="${name}" type="${type}" value="${esc(value)}" ${extra}></div>`;}
function modal(title,body,onSave){
  const bg=document.createElement('div');
  bg.className='modal-bg';
  bg.innerHTML=`<div class="modal"><h3>${esc(title)}</h3><form id="atlasRemoteMasterForm">${body}<div class="modal-actions"><button type="button" class="btn btn-soft" data-cancel>Cancelar</button><button class="btn btn-primary">Guardar</button></div></form></div>`;
  document.body.appendChild(bg);
  bg.querySelector('[data-cancel]').onclick=()=>bg.remove();
  bg.querySelector('form').onsubmit=async event=>{
    event.preventDefault();
    const btn=event.submitter||bg.querySelector('.btn-primary');
    if(btn){btn.disabled=true;btn.dataset.oldText=btn.textContent;btn.textContent='Guardando…';}
    try{
      await onSave(new FormData(event.target));
      bg.remove();
      window.location.reload();
    }catch(error){
      DB.setSyncStatus('error',error?.message||String(error));
      alert('No se pudo guardar en la nube: '+(error?.message||error));
      if(btn){btn.disabled=false;btn.textContent=btn.dataset.oldText||'Guardar';}
    }
  };
}

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

async function refreshCore(){
  DB.setSyncStatus('syncing');
  await pullCoreWorkspace(DB.getState());
  DB.setSyncStatus('synced');
}

async function saveRemoteMaster(form, entity){
  const button=form.querySelector('button[type="submit"],button:not([type])');
  if(button){button.disabled=true;button.dataset.oldText=button.textContent;button.textContent='Guardando…';}
  try{
    const payload=payloadFor(entity,new FormData(form));
    await RemoteRepo.rpc('atlas_create_master',{p_entity:entity,p_payload:payload});
    await refreshCore();
    form.closest('.modal-bg')?.remove();
    window.location.reload();
  }catch(error){
    DB.setSyncStatus('error',error?.message||String(error));
    alert('No se pudo guardar en la nube: '+(error?.message||error));
    if(button){button.disabled=false;button.textContent=button.dataset.oldText||'Guardar';}
  }
}

function openMasterEdit(entity,id){
  const s=DB.getState();
  const key=entity==='customer'?'customers':entity==='supplier'?'suppliers':'products';
  const item=(s[key]||[]).find(x=>String(x.id)===String(id));
  if(!item) return alert('Registro no encontrado.');
  const title=entity==='customer'?'Editar cliente':entity==='supplier'?'Editar proveedor':'Editar producto';
  const body=entity==='product'
    ? `${field('SKU','sku',item.sku||'')}${field('Nombre','name',item.name||'')}${field('Categoría','category',item.category||'General')}${field('Costo','cost',Number(item.cost||0),'number','step="0.0001" min="0"')}${field('Precio','price',Number(item.price||0),'number','step="0.0001" min="0"')}${field('IVA (%)','tax',Number(item.tax||0),'number','step="0.01" min="0" max="100"')}${field('Stock mínimo','minStock',Number(item.minStock||0),'number','step="0.0001" min="0"')}`
    : `${field('Código','code',item.code||'')}${field('Nombre','name',item.name||'')}${field('RIF / ID','taxId',item.taxId||'')}${field('Teléfono','phone',item.phone||'')}${field('Correo','email',item.email||'','email')}${field('Ciudad / dirección','city',item.city||item.address||'')}`;
  modal(title,body,async fd=>{
    await RemoteRepo.rpc('atlas_update_master',{p_entity:entity,p_id:id,p_payload:payloadFor(entity,fd)});
    await refreshCore();
  });
}

function permissionsFromText(value){
  return [...new Set(String(value||'').split(',').map(x=>x.trim()).filter(Boolean))];
}

async function createRemoteRole(form){
  const fd=new FormData(form);
  const name=String(fd.get('name')||'').trim();
  if(!name) throw new Error('Nombre es obligatorio.');
  const permissions=permissionsFromText(fd.get('permissions')||'dashboard');
  await RemoteRepo.rpc('atlas_create_role',{p_name:name,p_permissions:permissions});
  await refreshCore();
}

function openRoleEdit(id){
  const s=DB.getState(), role=(s.roles||[]).find(x=>String(x.id)===String(id));
  if(!role) return alert('Rol no encontrado.');
  const current=Array.isArray(role.permissions)?role.permissions:[];
  const all=current.includes('*');
  const checks=PERMISSIONS.map(p=>`<label class="perm-item"><input type="checkbox" name="perm" value="${esc(p)}" ${all||current.includes(p)?'checked':''}> <span>${esc(p)}</span></label>`).join('');
  modal(`Permisos · ${role.name}`,`
    ${field('Nombre del rol','name',role.name||'')}
    <div class="notice">Selecciona sólo los permisos necesarios. El acceso total se conserva únicamente si el rol ya usa "*".</div>
    <div class="permission-grid">${checks}</div>
  `,async fd=>{
    const selected=fd.getAll('perm').map(String);
    const permissions=all&&selected.length===PERMISSIONS.length?['*']:selected;
    await RemoteRepo.rpc('atlas_update_role',{p_role_id:id,p_name:String(fd.get('name')||role.name).trim(),p_permissions:permissions});
    await refreshCore();
  });
}

function normalize(v){return String(v||'').trim().replace(/\s+/g,' ').toLowerCase();}
function injectEditButtons(){
  if(!isSupabaseConfigured()) return;
  const heading=document.querySelector('.content .hero h2')?.textContent?.trim();
  const config=heading==='Clientes'?{entity:'customer',key:'customers'}:heading==='Proveedores'?{entity:'supplier',key:'suppliers'}:heading==='Productos'?{entity:'product',key:'products'}:null;
  if(!config) return;
  const items=DB.getState()[config.key]||[];
  document.querySelectorAll('.content table.table tbody tr').forEach(row=>{
    if(row.querySelector('[data-remote-edit-master]')) return;
    const cells=row.querySelectorAll('td');
    if(cells.length<2) return;
    const code=normalize(cells[0].textContent), name=normalize(cells[1].textContent);
    const item=items.find(x=>normalize(config.entity==='product'?x.sku:x.code)===code&&normalize(x.name)===name)
      || items.find(x=>normalize(x.name)===name);
    if(!item) return;
    const action=cells[cells.length-1];
    const btn=document.createElement('button');
    btn.type='button'; btn.className='btn btn-soft'; btn.dataset.remoteEditMaster=String(item.id); btn.dataset.entity=config.entity; btn.textContent='Editar';
    action.prepend(btn,document.createTextNode(' '));
  });
}

let scheduled=false;
const observer=new MutationObserver(()=>{
  if(scheduled) return;
  scheduled=true;
  queueMicrotask(()=>{scheduled=false;injectEditButtons();});
});
observer.observe(document.documentElement,{childList:true,subtree:true});
document.addEventListener('DOMContentLoaded',injectEditButtons);

document.addEventListener('click',event=>{
  if(!isSupabaseConfigured()) return;
  const edit=event.target.closest?.('[data-remote-edit-master]');
  if(edit){
    event.preventDefault();event.stopImmediatePropagation();
    return openMasterEdit(edit.dataset.entity,edit.dataset.remoteEditMaster);
  }
  const role=event.target.closest?.('[data-edit-role]');
  if(role){
    event.preventDefault();event.stopImmediatePropagation();
    return openRoleEdit(role.dataset.editRole);
  }
},true);

document.addEventListener('submit',event=>{
  if(!isSupabaseConfigured()) return;
  const form=event.target;
  if(!(form instanceof HTMLFormElement) || form.id!=='modalForm') return;
  const title=form.closest('.modal')?.querySelector('h3')?.textContent?.trim()||'';
  const entity=titleEntity.get(title);
  if(entity){
    event.preventDefault();event.stopImmediatePropagation();
    return void saveRemoteMaster(form,entity);
  }
  if(title==='Nuevo rol'){
    event.preventDefault();event.stopImmediatePropagation();
    const button=form.querySelector('button.btn-primary');
    if(button){button.disabled=true;button.dataset.oldText=button.textContent;button.textContent='Guardando…';}
    createRemoteRole(form).then(()=>{form.closest('.modal-bg')?.remove();window.location.reload();}).catch(error=>{
      DB.setSyncStatus('error',error?.message||String(error));
      alert('No se pudo crear el rol en la nube: '+(error?.message||error));
      if(button){button.disabled=false;button.textContent=button.dataset.oldText||'Guardar';}
    });
  }
},true);
