const A=v=>Array.isArray(v)?v:[];
const clone=v=>JSON.parse(JSON.stringify(v??null));
export const MIGRATION_SCHEMA=42;
export function buildMigrationPackage(s){
 const tables={
  branches:clone(A(s.branches)),customers:clone(A(s.customers)),suppliers:clone(A(s.suppliers)),
  products:clone(A(s.products)),inventory:clone(A(s.inventory)),cash_accounts:clone(A(s.cashAccounts)),
  sales:clone(A(s.sales)),purchases:clone(A(s.purchases)),receivables:clone(A(s.receivables)),
  payables:clone(A(s.payables)),cash_movements:clone(A(s.cashMovements)),journal_entries:clone(A(s.journalEntries)),
  audit_log:clone(A(s.audit)),company_settings:[clone(s.settings||{})],
  payment_methods:clone(A(s.paymentMethods)),expenses:clone(A(s.expenses)),quotations:clone(A(s.quotations)),
  sale_returns:clone(A(s.returns||s.saleReturns)),purchase_returns:clone(A(s.purchaseReturns)),
  stock_transfers:clone(A(s.stockTransfers)),customer_credits:clone(A(s.customerCredits)),
  supplier_credits:clone(A(s.supplierCredits)),cash_closings:clone(A(s.cashClosings)),
  exchange_rates:clone(A(s.exchangeRates)),accounting_accounts:clone(A(s.accounts||s.accountingAccounts))
 };
 return {atlasMigration:true,schemaVersion:MIGRATION_SCHEMA,createdAt:new Date().toISOString(),
  company:clone(s.company||{}),roles:clone(A(s.roles)),
  users:A(s.users).map(({pin,password,...u})=>clone(u)),tables};
}
export function validateMigrationPackage(pkg){
 const errors=[];if(!pkg?.atlasMigration)errors.push("No es un paquete ATLAS.");
 if(!pkg?.company||typeof pkg.company!=="object")errors.push("Empresa ausente.");
 if(!pkg?.tables||typeof pkg.tables!=="object")errors.push("Tablas ausentes.");
 for(const k of ["branches","customers","suppliers","products","inventory","sales","purchases"])if(!Array.isArray(pkg?.tables?.[k]))errors.push(`Tabla ${k} inválida.`);
 return {ok:errors.length===0,errors};
}
export function migrationStats(pkg){const out={};for(const [k,v] of Object.entries(pkg?.tables||{}))out[k]=Array.isArray(v)?v.length:0;return out;}
