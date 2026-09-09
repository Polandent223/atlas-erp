globalThis.localStorage={data:new Map(),getItem(k){return this.data.has(k)?this.data.get(k):null},setItem(k,v){this.data.set(k,String(v))},removeItem(k){this.data.delete(k)}};
const {DB}=await import("../assets/data.js");
const s=DB.getState();
if(s.schemaVersion!==22)throw new Error("schemaVersion incorrecta");
const before=JSON.stringify(s);
let failed=false;
try{DB.atomic(()=>{s.customerCredits.push({id:"TMP",amount:10,balance:10});throw new Error("rollback")})}catch(e){failed=true}
if(!failed||DB.getState().customerCredits.some(x=>x.id==="TMP"))throw new Error("Rollback de crédito inválido");
console.log("ATLAS Fase 22 credit/rollback runtime OK");
