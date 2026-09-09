const store=new Map();
Object.defineProperty(globalThis,'localStorage',{value:{getItem:k=>store.has(k)?store.get(k):null,setItem:(k,v)=>store.set(k,String(v)),removeItem:k=>store.delete(k),clear:()=>store.clear()},configurable:true});
const appEl={innerHTML:'',classList:{toggle(){}},addEventListener(){},remove(){},dataset:{},style:{}};
const dummy=()=>({innerHTML:'',value:'',checked:false,dataset:{},style:{},classList:{toggle(){}},onclick:null,onchange:null,onsubmit:null,oninput:null,addEventListener(){},remove(){},appendChild(){},click(){},files:[]});
Object.defineProperty(globalThis,'document',{value:{getElementById(id){return id==='app'?appEl:null},querySelector(){return null},querySelectorAll(){return []},addEventListener(){},createElement(){return dummy()},body:{appendChild(){}}},configurable:true});
globalThis.window=globalThis;globalThis.addEventListener=()=>{};
Object.defineProperty(globalThis,'navigator',{value:{serviceWorker:{register:async()=>{}}},configurable:true});
globalThis.alert=()=>{};globalThis.confirm=()=>true;globalThis.performance={now:()=>0};
globalThis.FormData=class{constructor(){} get(){return null}};globalThis.FileReader=class{};globalThis.open=()=>dummy();globalThis.setInterval=()=>({unref(){}});
const {DB}=await import('../assets/data.js');
DB.setRemoteSession({
 id:'test-user', email:'samuel.eliuzeq.223@gmail.com', full_name:'Administrador Principal', status:'ACTIVE',
 company:{id:'test-company',name:'ATLAS',tax_id:'',country:'VE',base_currency:'VES'},
 role_id:'test-role', role:{id:'test-role',name:'Administrador',permissions:['*']},
 branch_ids:['test-branch'], branches:[{id:'test-branch',name:'Sucursal Principal',code:'PRINCIPAL',active:true}]
});
await import('../assets/app.js');
if(!appEl.innerHTML.includes('Bienvenido a ATLAS')) throw new Error('Dashboard no renderizó');
if(!appEl.innerHTML.includes('Integridad')) throw new Error('KPI Integridad no renderizó');
if(appEl.innerHTML.includes('No se pudo iniciar')) throw new Error('Se mostró diagnóstico de error');
console.log('ATLAS Fase52 dashboard runtime OK');
