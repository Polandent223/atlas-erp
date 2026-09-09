globalThis.localStorage={
 data:new Map(),
 getItem(k){return this.data.has(k)?this.data.get(k):null},
 setItem(k,v){this.data.set(k,String(v))},
 removeItem(k){this.data.delete(k)}
};
const {DB}=await import("../assets/data.js");
let s=DB.getState();
if(s.schemaVersion!==19) throw new Error("schemaVersion incorrecta");
const before=JSON.stringify(s);
let failed=false;
try{
 DB.atomic(()=>{
   s.customers.push({id:"TEMP",name:"No debe quedar"});
   throw new Error("prueba");
 });
}catch(e){failed=true}
if(!failed) throw new Error("La transacción de prueba no falló");
s=DB.getState();
if(s.customers.some(x=>x.id==="TEMP")) throw new Error("Rollback no restauró el estado");
console.log("ATLAS Fase 19 atomic runtime OK");
