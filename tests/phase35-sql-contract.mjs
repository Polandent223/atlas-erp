import fs from "node:fs";
const s=fs.readFileSync("sql/ATLAS_MIGRATION_STAGING_PHASE35.sql","utf8");
for(const x of ["migration_runs","migration_id_map","enable row level security","current_company_id()","auth.uid()"])if(!s.includes(x))throw new Error(x);
console.log("ATLAS Fase 35 SQL staging contract OK");
