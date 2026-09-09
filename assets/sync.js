import { RemoteRepo } from "./repositories.js";
import { getRemoteProfile } from "./supabase.js";

function mapCustomer(r){return {id:r.id,code:r.code||"",name:r.name,taxId:r.tax_id||"",phone:r.phone||"",email:r.email||"",city:r.city||"",creditLimit:Number(r.credit_limit||0),status:r.active===false?"Inactivo":(r.status||"Activo"),balance:Number(r.balance||0)}}
function mapSupplier(r){return {id:r.id,code:r.code||"",name:r.name,taxId:r.tax_id||"",phone:r.phone||"",email:r.email||"",city:r.city||"",status:r.active===false?"Inactivo":(r.status||"Activo"),balance:Number(r.balance||0)}}
function mapProduct(r){return {id:r.id,sku:r.sku||"",name:r.name,category:r.category||"",cost:Number(r.cost||0),price:Number(r.price||0),tax:Number(r.tax||0),minStock:Number(r.min_stock||0),status:r.active===false?"Inactivo":(r.status||"Activo")}}
function mapInventory(r){return {id:r.id,productId:r.product_id,branchId:r.branch_id,stock:Number(r.stock||0),reserved:Number(r.reserved||0)}}
function mapRate(r){return {id:r.id,date:r.rate_date,currency:r.currency,rate:Number(r.rate||0),source:r.source||""}}

export async function pullCoreWorkspace(localState){
  const profile=await getRemoteProfile();
  if(!profile) throw new Error("No hay perfil remoto.");

  const [customers,suppliers,products,inventory,rates] = await Promise.all([
    RemoteRepo.list("customers",{order:{column:"created_at",ascending:true}}),
    RemoteRepo.list("suppliers",{order:{column:"created_at",ascending:true}}),
    RemoteRepo.list("products",{order:{column:"created_at",ascending:true}}),
    RemoteRepo.list("inventory"),
    RemoteRepo.list("exchangeRates",{order:{column:"rate_date",ascending:false}})
  ]);

  localState.customers=customers.map(mapCustomer);
  localState.suppliers=suppliers.map(mapSupplier);
  localState.products=products.map(mapProduct);
  localState.inventory=inventory.map(mapInventory);
  localState.exchangeRates=rates.map(mapRate);

  return {profile,counts:{
    customers:localState.customers.length,
    suppliers:localState.suppliers.length,
    products:localState.products.length,
    inventory:localState.inventory.length,
    exchangeRates:localState.exchangeRates.length
  }};
}

export async function pullTransactions(localState){
  const [sales,purchases,receivables,payables,cashAccounts,cashMovements,expenses] = await Promise.all([
    RemoteRepo.list("sales",{order:{column:"document_date",ascending:false}}),
    RemoteRepo.list("purchases",{order:{column:"document_date",ascending:false}}),
    RemoteRepo.list("receivables",{order:{column:"issue_date",ascending:false}}),
    RemoteRepo.list("payables",{order:{column:"issue_date",ascending:false}}),
    RemoteRepo.list("cashAccounts"),
    RemoteRepo.list("cashMovements",{order:{column:"movement_date",ascending:false}}),
    RemoteRepo.list("expenses",{order:{column:"expense_date",ascending:false}})
  ]);

  localState.sales=sales.map(r=>({id:r.id,number:r.document_number,date:r.document_date,customerId:r.customer_id,branchId:r.branch_id,subtotal:Number(r.subtotal||0),tax:Number(r.tax||0),total:Number(r.total||0),condition:r.payment_condition,status:r.status,items:[]}));
  localState.purchases=purchases.map(r=>({id:r.id,number:r.document_number,date:r.document_date,supplierId:r.supplier_id,branchId:r.branch_id,total:Number(r.total||0),condition:r.payment_condition,status:r.status,items:[]}));
  localState.receivables=receivables.map(r=>({id:r.id,reference:r.reference,customerId:r.customer_id,date:r.issue_date,dueDate:r.due_date,total:Number(r.total||0),balance:Number(r.balance||0),status:r.status}));
  localState.payables=payables.map(r=>({id:r.id,reference:r.reference,supplierId:r.supplier_id,date:r.issue_date,dueDate:r.due_date,total:Number(r.total||0),balance:Number(r.balance||0),status:r.status}));
  localState.cashAccounts=cashAccounts.map(r=>({id:r.id,name:r.name,type:r.account_type,currency:r.currency,branchId:r.branch_id,balance:Number(r.balance||0),status:r.status}));
  localState.cashMovements=cashMovements.map(r=>({id:r.id,date:r.movement_date,accountId:r.cash_account_id,type:r.movement_type,amount:Number(r.amount||0),reference:r.reference||"",note:r.note||""}));
  localState.expenses=expenses.map(r=>({id:r.id,date:r.expense_date,category:r.category||"",description:r.description||"",amount:Number(r.amount||0),accountId:r.cash_account_id,reference:r.reference||""}));

  return {
    sales:localState.sales.length,
    purchases:localState.purchases.length,
    receivables:localState.receivables.length,
    payables:localState.payables.length,
    cashMovements:localState.cashMovements.length,
    expenses:localState.expenses.length
  };
}


export async function pullAccounting(localState){
  const [accounts,entries,lines] = await Promise.all([
    RemoteRepo.list("chart_of_accounts",{order:{column:"code",ascending:true}}),
    RemoteRepo.list("journal_entries",{order:{column:"entry_date",ascending:false}}),
    RemoteRepo.list("journal_lines")
  ]);
  localState.chartOfAccounts=accounts.map(r=>({id:r.id,code:r.code,name:r.name,type:r.account_type||"Activo",active:r.active!==false}));
  const byEntry={};
  for(const l of lines){(byEntry[l.journal_entry_id] ||= []).push({accountId:l.account_id,debit:Number(l.debit||0),credit:Number(l.credit||0)});}
  localState.journalEntries=entries.map(e=>({id:e.id,date:e.entry_date||e.created_at,reference:e.reference||"",description:e.description||"",status:e.status||"Contabilizado",lines:byEntry[e.id]||[]}));
  return {accounts:accounts.length,entries:entries.length,lines:lines.length};
}
