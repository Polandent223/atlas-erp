globalThis.localStorage={data:new Map(),getItem(k){return this.data.has(k)?this.data.get(k):null},setItem(k,v){this.data.set(k,String(v))},removeItem(k){this.data.delete(k)}};
const {DB}=await import("../assets/data.js");
let s=DB.getState(),failed=false;
try{DB.atomic(()=>{s.sales.push({id:"TEMP-SALE"});throw new Error("rollback")})}catch(e){failed=true}
if(!failed||DB.getState().sales.some(x=>x.id==="TEMP-SALE"))throw new Error("Rollback inválido");
console.log("ATLAS Fase 21 rollback runtime OK");
