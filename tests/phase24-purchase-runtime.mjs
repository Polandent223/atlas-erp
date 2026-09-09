globalThis.localStorage={data:new Map(),getItem(k){return this.data.has(k)?this.data.get(k):null},setItem(k,v){this.data.set(k,String(v))},removeItem(k){this.data.delete(k)}};
const {DB}=await import("../assets/data.js");
const s=DB.getState();
if(s.schemaVersion!==24)throw new Error("schemaVersion incorrecta");
if(!Array.isArray(s.purchaseReturns)||!Array.isArray(s.supplierCredits))throw new Error("estructuras faltantes");
if(!s.chartOfAccounts.some(a=>a.name==="Créditos de proveedores"))throw new Error("cuenta contable faltante");

const before=JSON.stringify(s);
let failed=false;
try{DB.atomic(()=>{s.supplierCredits.push({id:"tmp-sc",amount:10,balance:10});throw new Error("rollback")})}catch(e){failed=true}
if(!failed||DB.getState().supplierCredits.some(x=>x.id==="tmp-sc"))throw new Error("rollback proveedor inválido");
console.log("ATLAS Fase 24 purchase runtime OK");
