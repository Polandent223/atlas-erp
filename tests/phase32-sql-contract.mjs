import fs from "node:fs";
const s=fs.readFileSync("sql/ATLAS_PRODUCTION_PHASE32.sql","utf8").toLowerCase();
for(const t of ["companies","profiles","roles","branches","customers","suppliers","products","inventory","cash_accounts","sales","sale_items","purchases","purchase_items","receivables","payables","cash_movements","journal_entries","journal_lines","audit_log","company_settings"])
 if(!s.includes(`public.${t}`))throw new Error("Tabla faltante: "+t);
if(!s.includes("auth.uid()"))throw new Error("RLS no usa auth.uid()");
console.log("ATLAS Fase 32 SQL contract OK");
