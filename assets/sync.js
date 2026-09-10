import { RemoteRepo } from "./repositories.js";
import { getRemoteProfile } from "./supabase.js";
const now=()=>new Date().toISOString();
function mapBranch(r){return {id:r.id,name:r.name,code:r.code||"",city:r.city||"",status:r.active===false?"Inactivo":"Activo"}}
function mapCustomer(r){return {id:r.id,code:r.code||"",name:r.name,taxId:r.tax_id||"",phone:r.phone||"",email:r.email||"",city:r.address||"",creditLimit:0,status:r.active===false?"Inactivo":"Activo",balance:0}}
function mapSupplier(r){return {id:r.id,code:r.code||"",name:r.name,taxId:r.tax_id||"",phone:r.phone||"",email:r.email||"",city:r.address||"",status:r.active===false?"Inactivo":"Activo",balance:0}}
function mapProduct(r){return {id:r.id,sku:r.sku||"",name:r.name,category:r.category||"General",cost:Number(r.cost||0),price:Number(r.price||0),tax:Number(r.tax||0),minStock:Number(r.min_stock||0),status:r.active===false?"Inactivo":"Activo"}}
function mapInventory(r){return {id:`${r.branch_id}:${r.product_id}`,productId:r.product_id,branchId:r.branch_id,stock:Number(r.stock||0),reserved:Number(r.reserved||0)}}
function mapRate(r){return {id:r.id,date:(r.effective_at||now()).slice(0,10),currency:r.currency,rate:Number(r.rate||0),source:r.source||""}}
function mapPaymentMethod(r){const kind=String(r.kind||'OTHER').toLowerCase();return {id:r.id,name:r.name,type:kind,active:r.active!==false,status:r.active===false?'Inactivo':'Activo'}}
function applyAccessSnapshot(localState,snapshot){
 const roles=Array.isArray(snapshot?.roles)?snapshot.roles:[];
 const users=Array.isArray(snapshot?.users)?snapshot.users:[];
 localState.roles=roles.map(r=>({id:r.id,name:r.name,description:'',permissions:Array.isArray(r.permissions)?r.permissions:[]}));
 localState.users=users.map(u=>({
   id:u.id,name:u.name||'Usuario',email:'',pin:'',roleId:u.role_id||null,
   branchId:Array.isArray(u.branch_ids)&&u.branch_ids.length===1?u.branch_ids[0]:'all',
   branchIds:Array.isArray(u.branch_ids)?u.branch_ids:[],status:u.status==='INACTIVE'?'Inactivo':'Activo'
 }));
}
export async function pullCoreWorkspace(localState){
 const profile=await getRemoteProfile(); if(!profile)throw new Error("No hay perfil remoto.");
 const [branches,customers,suppliers,products,inventory,rates,paymentMethods,access]=await Promise.all([
  RemoteRepo.list("branches",{order:{column:"name",ascending:true}}),
  RemoteRepo.list("customers",{order:{column:"created_at",ascending:true}}),
  RemoteRepo.list("suppliers",{order:{column:"created_at",ascending:true}}),
  RemoteRepo.list("products",{order:{column:"sku",ascending:true}}),
  RemoteRepo.list("inventory"),
  RemoteRepo.list("exchangeRates",{order:{column:"effective_at",ascending:false}}),
  RemoteRepo.list("paymentMethods",{order:{column:"name",ascending:true}}),
  RemoteRepo.accessSnapshot()
 ]);
 localState.branches=branches.map(mapBranch); localState.customers=customers.map(mapCustomer); localState.suppliers=suppliers.map(mapSupplier); localState.products=products.map(mapProduct); localState.inventory=inventory.map(mapInventory); localState.exchangeRates=rates.map(mapRate); localState.paymentMethods=paymentMethods.map(mapPaymentMethod); applyAccessSnapshot(localState,access);
 if(profile.company){
   localState.company={...(localState.company||{}),id:profile.company.id,name:profile.company.name||localState.company?.name,taxId:profile.company.tax_id||'',country:profile.company.country||'VE',baseCurrency:profile.company.base_currency||'USD'};
 }
 return {profile,counts:{branches:localState.branches.length,customers:localState.customers.length,suppliers:localState.suppliers.length,products:localState.products.length,inventory:localState.inventory.length,exchangeRates:localState.exchangeRates.length,paymentMethods:localState.paymentMethods.length,users:localState.users.length,roles:localState.roles.length}};
}
export async function pullTransactions(localState){
 const [sales,saleItems,purchases,purchaseItems,receivables,payables,cashAccounts,cashMovements,expenses]=await Promise.all([RemoteRepo.list("sales",{order:{column:"created_at",ascending:false}}),RemoteRepo.list("saleItems"),RemoteRepo.list("purchases",{order:{column:"created_at",ascending:false}}),RemoteRepo.list("purchaseItems"),RemoteRepo.list("receivables",{order:{column:"due_date",ascending:false}}),RemoteRepo.list("payables",{order:{column:"due_date",ascending:false}}),RemoteRepo.list("cashAccounts",{order:{column:"name",ascending:true}}),RemoteRepo.list("cashMovements",{order:{column:"created_at",ascending:false}}),RemoteRepo.list("expenses",{order:{column:"created_at",ascending:false}})]);
 const saleLines={}; for(const i of saleItems)(saleLines[i.sale_id]||=[]).push({id:i.id,productId:i.product_id,qty:Number(i.qty||0),price:Number(i.unit_price||0),cost:Number(i.unit_cost||0),tax:0});
 const purchaseLines={}; for(const i of purchaseItems)(purchaseLines[i.purchase_id]||=[]).push({id:i.id,productId:i.product_id,qty:Number(i.qty||0),cost:Number(i.unit_cost||0),taxRate:0});
 localState.receivables=receivables.map(r=>({id:r.id,reference:r.reference,customerId:r.customer_id,saleId:r.sale_id,date:r.created_at||r.due_date||now(),dueDate:r.due_date||now(),total:Number(r.total||0),balance:Number(r.balance||0),status:r.status==="PAID"?"Pagada":(r.status==="PARTIAL"?"Parcial":"Pendiente")}));
 localState.payables=payables.map(r=>({id:r.id,reference:r.reference,supplierId:r.supplier_id,purchaseId:r.purchase_id,date:r.created_at||r.due_date||now(),dueDate:r.due_date||now(),total:Number(r.total||0),balance:Number(r.balance||0),status:r.status==="PAID"?"Pagada":(r.status==="PARTIAL"?"Parcial":"Pendiente")}));
 const arBySale=new Map(localState.receivables.map(r=>[r.saleId,r])),apByPurchase=new Map(localState.payables.map(r=>[r.purchaseId,r]));
 localState.sales=sales.map(r=>({id:r.id,number:r.number,date:r.created_at,customerId:r.customer_id,branchId:r.branch_id,subtotal:Number(r.subtotal||0),tax:Number(r.tax||0),total:Number(r.total||0),baseTotalUSD:Number(r.base_total_usd||r.total||0),currency:r.document_currency||"USD",documentSubtotal:Number(r.subtotal||0),documentTax:Number(r.tax||0),documentTotal:Number(r.total||0),exchangeRate:Number(r.exchange_rate||1),condition:arBySale.has(r.id)?"credit":"cash",status:r.status==="ACTIVE"?"Completada":(r.status||"Completada"),items:saleLines[r.id]||[]}));
 localState.purchases=purchases.map(r=>({id:r.id,number:r.number,date:r.created_at,supplierId:r.supplier_id,branchId:r.branch_id,subtotal:Number(r.subtotal||0),tax:Number(r.tax||0),total:Number(r.total||0),baseTotalUSD:Number(r.base_total_usd||r.total||0),currency:r.document_currency||"USD",documentSubtotal:Number(r.subtotal||0),documentTax:Number(r.tax||0),documentTotal:Number(r.total||0),exchangeRate:Number(r.exchange_rate||1),condition:apByPurchase.has(r.id)?"credit":"cash",status:r.status==="ACTIVE"?"Recibida":(r.status||"Recibida"),items:purchaseLines[r.id]||[]}));
 localState.cashAccounts=cashAccounts.map(r=>({id:r.id,name:r.name,type:"Caja/Banco",currency:r.currency||"USD",branchId:r.branch_id,balance:Number(r.balance||0),status:r.active===false?"Inactivo":"Activo"}));
 localState.cashMovements=cashMovements.map(r=>({id:r.id,date:r.created_at,accountId:r.account_id,type:r.direction==="IN"?"IN":"OUT",amount:Number(r.amount||0),currency:r.currency||"USD",reference:r.reference||"",note:r.description||""}));
 localState.expenses=expenses.map(r=>({id:r.id,date:r.created_at,category:r.category||"General",description:r.description||"",amount:Number(r.amount||0),currency:r.currency||"USD",accountId:r.cash_account_id,reference:r.reference||""}));
 return {sales:localState.sales.length,purchases:localState.purchases.length,receivables:localState.receivables.length,payables:localState.payables.length,cashMovements:localState.cashMovements.length,expenses:localState.expenses.length};
}
export async function pullAccounting(localState){
 const [accounts,entries,lines]=await Promise.all([RemoteRepo.list("accounting_accounts",{order:{column:"code",ascending:true}}),RemoteRepo.list("journal_entries",{order:{column:"created_at",ascending:false}}),RemoteRepo.list("journal_lines")]);
 localState.chartOfAccounts=accounts.map(r=>({id:r.id,code:r.code,name:r.name,type:r.type||"Activo",active:r.active!==false})); const byCode=new Map(localState.chartOfAccounts.map(a=>[a.code,a.id])),byEntry={};
 for(const l of lines)(byEntry[l.entry_id]||=[]).push({accountId:byCode.get(l.account_code)||null,accountCode:l.account_code,debit:Number(l.debit||0),credit:Number(l.credit||0),description:l.description||""});
 localState.journalEntries=entries.map(e=>({id:e.id,date:e.created_at,reference:e.reference||"",description:e.description||"",status:"Contabilizado",lines:byEntry[e.id]||[]})); return {accounts:accounts.length,entries:entries.length,lines:lines.length};
}
