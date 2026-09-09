globalThis.localStorage={data:new Map(),getItem(k){return this.data.has(k)?this.data.get(k):null},setItem(k,v){this.data.set(k,String(v))},removeItem(k){this.data.delete(k)}};
const {DB}=await import("../assets/data.js");
const {buildMigrationPackage,validateMigrationPackage}=await import("../assets/migration.js");
const s=DB.getState(); if(s.schemaVersion!==33)throw new Error("schema incorrecta");
const p=buildMigrationPackage(s),v=validateMigrationPackage(p);
if(!p.atlasMigration||!p.tables||!Array.isArray(p.users))throw new Error("paquete inválido");
if(p.users.some(u=>"pin" in u||"password" in u))throw new Error("credencial local incluida");
if(!v.ok)throw new Error("validación falló: "+v.errors.join("; "));
console.log("ATLAS Fase 33 migration runtime OK");
