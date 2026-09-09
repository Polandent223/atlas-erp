globalThis.localStorage={data:new Map(),getItem(k){return this.data.has(k)?this.data.get(k):null},setItem(k,v){this.data.set(k,String(v))},removeItem(k){this.data.delete(k)}};
const {DB}=await import("../assets/data.js");const s=DB.getState();if(s.schemaVersion!==27)throw new Error("schema");console.log("ATLAS Fase 27 runtime OK");
