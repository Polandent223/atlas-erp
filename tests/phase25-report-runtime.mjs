globalThis.localStorage={data:new Map(),getItem(k){return this.data.has(k)?this.data.get(k):null},setItem(k,v){this.data.set(k,String(v))},removeItem(k){this.data.delete(k)}};
const {DB}=await import("../assets/data.js");
const s=DB.getState();
if(s.schemaVersion!==25)throw new Error("schemaVersion incorrecta");
if(!s.settings.reporting)throw new Error("configuración reporting faltante");
let valuation=0;
for(const inv of s.inventory||[]){const p=s.products.find(x=>x.id===inv.productId);valuation+=Number(inv.stock||0)*Number(p?.cost||0)}
if(!Number.isFinite(valuation))throw new Error("valorización inválida");
console.log("ATLAS Fase 25 report runtime OK");
