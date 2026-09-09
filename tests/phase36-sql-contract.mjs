import fs from "node:fs";const s=fs.readFileSync("sql/ATLAS_ID_MAPPING_PHASE36.sql","utf8");
for(const x of ["prepare_migration_id","current_company_id()","migration_runs","migration_id_map","auth.uid()","gen_random_uuid()"])if(!s.includes(x))throw new Error(x);
console.log("ATLAS Fase 36 SQL mapping contract OK");
