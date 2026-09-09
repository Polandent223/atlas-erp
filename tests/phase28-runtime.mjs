globalThis.localStorage={data:new Map(),getItem(k){return this.data.has(k)?this.data.get(k):null},setItem(k,v){this.data.set(k,String(v))},removeItem(k){this.data.delete(k)}};
const {DB}=await import("../assets/data.js");
const s=DB.getState();
if(s.schemaVersion!==28)throw new Error("schemaVersion incorrecta");
if(!s.settings.securityPolicy)throw new Error("securityPolicy faltante");
if(!DB.login("admin@atlas.local","1234"))throw new Error("login admin falló");
if(!DB.can("sales")||!DB.can("settings"))throw new Error("permisos admin fallaron");
DB.logout();
console.log("ATLAS Fase 28 security runtime OK");
