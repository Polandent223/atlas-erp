globalThis.localStorage={data:new Map(),getItem(k){return this.data.has(k)?this.data.get(k):null},setItem(k,v){this.data.set(k,String(v))},removeItem(k){this.data.delete(k)}};
const {DB}=await import("../assets/data.js");
const s=DB.getState();
if(s.schemaVersion!==31)throw new Error("schema incorrecta");
if(!s.company||!Array.isArray(s.users)||!s.settings?.fiscalConfig||!s.settings?.securityPolicy)throw new Error("estado incompleto");
const raw=JSON.stringify(s); localStorage.setItem("atlas_phase3_data",raw);
if(localStorage.getItem("atlas_phase3_data")!==raw)throw new Error("persistencia local falló");
console.log("ATLAS Fase 31 runtime OK");
