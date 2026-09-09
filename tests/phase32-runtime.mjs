globalThis.localStorage={data:new Map(),getItem(k){return this.data.has(k)?this.data.get(k):null},setItem(k,v){this.data.set(k,String(v))},removeItem(k){this.data.delete(k)}};
const {DB}=await import("../assets/data.js");
if(DB.getState().schemaVersion!==32)throw new Error("schema incorrecta");
console.log("ATLAS Fase 32 local compatibility OK");
