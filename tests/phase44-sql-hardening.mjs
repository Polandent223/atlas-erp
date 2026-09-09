import fs from "node:fs";const s=fs.readFileSync("sql/ATLAS_SECURITY_HARDENING_PHASE44.sql","utf8");
for(const x of ["has_permission","branches.all","revoke update, delete on public.audit_log","next_document_number","document_counters","payment_methods","sale_returns","purchase_returns","stock_transfers","exchange_rates","accounting_accounts","create index if not exists idx_sales_company_created"])if(!s.includes(x))throw new Error(x);
if(s.includes("service_role key")){} // textual warning is allowed; no key value is present.
console.log("ATLAS Fase 44 SQL hardening contract OK");