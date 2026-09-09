globalThis.localStorage={data:new Map(),getItem(k){return this.data.has(k)?this.data.get(k):null},setItem(k,v){this.data.set(k,String(v))},removeItem(k){this.data.delete(k)}};
const {DB}=await import("../assets/data.js");
const s=DB.getState();
if(s.schemaVersion!==29)throw new Error("schemaVersion incorrecta");
const n=s.sales.length, stock=s.inventory[0]?.stock;
let failed=false;
try{DB.atomic(()=>{s.sales.push({id:"bad",number:"TMP"});if(s.inventory[0])s.inventory[0].stock=-999;throw new Error("rollback")})}catch{failed=true}
if(!failed||DB.getState().sales.length!==n)throw new Error("Rollback de ventas falló");
if(DB.getState().inventory[0]&&DB.getState().inventory[0].stock!==stock)throw new Error("Rollback de inventario falló");
console.log("ATLAS Fase 29 atomic runtime OK");
