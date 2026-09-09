globalThis.localStorage={
 data:new Map(),
 getItem(k){return this.data.has(k)?this.data.get(k):null},
 setItem(k,v){this.data.set(k,String(v))},
 removeItem(k){this.data.delete(k)}
};
const mod=await import("../assets/data.js");
if(!Array.isArray(mod.PERMISSIONS)||!mod.PERMISSIONS.includes("sales")) throw new Error("Catálogo de permisos inválido");
const s=mod.DB.getState();
if(s.schemaVersion!==18) throw new Error("schemaVersion incorrecta");
if(!mod.DB.can("dashboard")) throw new Error("Administrador sin permiso dashboard");
console.log("ATLAS Fase 18 data runtime OK");
