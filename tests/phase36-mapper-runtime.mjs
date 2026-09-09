globalThis.localStorage={data:new Map(),getItem(k){return this.data.has(k)?this.data.get(k):null},setItem(k,v){this.data.set(k,String(v))},removeItem(k){this.data.delete(k)}};
const {DB}=await import("../assets/data.js");const {buildMigrationPackage}=await import("../assets/migration.js");const {buildIdMap,mappingCoverage,validateReferences}=await import("../assets/migration-mapper.js");
const s=DB.getState();if(s.schemaVersion!==36)throw new Error("schema");
const pkg=buildMigrationPackage(s),refs=validateReferences(pkg),cov=mappingCoverage(buildIdMap(pkg));
if(!refs.ok)throw new Error(refs.errors.join(";"));if(cov.pending!==cov.total)throw new Error("cobertura inicial incorrecta");
console.log("ATLAS Fase 36 mapper runtime OK");
