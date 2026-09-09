import fs from "node:fs";
const d=fs.readFileSync("assets/data.js","utf8"),a=fs.readFileSync("assets/app.js","utf8"),sql=fs.readFileSync("sql/ATLAS_PRODUCTION_PHASE32.sql","utf8");
const checks=[
 ["schema32",d.includes("s.schemaVersion=32")],
 ["cloud page",a.includes("function cloudReadinessPage")],
 ["companies",sql.includes("create table if not exists public.companies")],
 ["profiles auth",sql.includes("references auth.users(id)")],
 ["rls",sql.includes("enable row level security")],
 ["company helper",sql.includes("current_company_id()")],
 ["branch helper",sql.includes("can_access_branch")],
 ["no browser service role",sql.includes("No service_role key is needed in the browser")]
];
for(const [n,ok] of checks)if(!ok)throw new Error("Falla: "+n);
console.log("ATLAS Fase 32 smoke test OK");
