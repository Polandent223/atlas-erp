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
 const roles=Array.isArray(snapshot?.roles)?snapshot.roles:[],users=Array.isArray(snapshot?.users)?snapshot.users:[];
 localState.roles=roles.map(r=>({id:r.id,name:r.name,description:'',permissions:Array.isArray(r.permissions)?r.permissions:[]}));
 localState.users=users.map(u=>({id:u.id,name:u.name||'Usuario',email:'',pin:'',roleId:u.role_id||null,branchId:Array.isArray(u.branch_ids)&&u.branch_ids.length===1?u.branch_ids[0]:'all',branchIds:Array.isArray(u.branch_ids)?u.branch_ids:[],status:u.status==='INACTIVE'?'Inactivo':'Activo'}));
}
export async function pullCoreWorkspace(localState){
 const profile=await getRemoteProfile(); if(!profile)throw new Error("No hay perfil remoto.");
 const [branches,customers,suppliers,products,inventory,rates,paymentMethods]=await Promise.all([
  RemoteRepo.list("branches",{order:{column:"name",ascending:true}}),
  RemoteRepo.list("customers",{order:{column:"created_at",ascending:true}}),
  RemoteRepo.list("suppliers",{order:{column:"created_at",ascending:true}}),
  RemoteRepo.list("products",{order:{column:"sku",ascending:true}}),
  RemoteRepo.list("inventory"),
  RemoteRepo.list("exchangeRates",{order:{column:"effective_at",ascending:false}}),
  RemoteRepo.list("paymentMethods",{order:{column:"name",ascending:true}})
 ]);
 localState.branches=branches.map(mapBranch);localState.customers=customers.map(mapCustomer);localState.suppliers=suppliers.map(mapSupplier);localState.products=products.map(mapProduct);localState.inventory=inventory.map(mapInventory);localState.exchangeRates=rates.map(mapRate);localState.paymentMethods=paymentMethods.map(mapPaymentMethod);
 try{const access=await RemoteRepo.accessSnapshot();applyAccessSnapshot(localState,access);localState.accessSyncError=null;}
 catch(error){localState.accessSyncError=error?.message||String(error);console.warn("ATLAS: metadatos de acceso no sincronizados",error);}
 if(profile.company)localState.company={
   ...(localState.company||{}),id:profile.company.id,name:profile.company.name||localState.company?.name,
   taxId:profile.company.tax_id||'',phone:profile.company.phone||'',email:profile.company.email||'',
   country:profile.company.country||'VE',baseCurrency:profile.company.base_currency||'USD',
   displayCurrency:profile.company.display_currency||profile.company.base_currency||'USD'
 };
 return {profile,counts:{branches:localState.branches.length,customers:localState.customers.length,suppliers:localState.suppliers.length,products:localState.products.length,inventory:localState.inventory.length,exchangeRates:localState.exchangeRates.length,paymentMethods:localState.paymentMethods.length,users:(localState.users||[]).length,roles:(localState.roles||[]).length}};
}
function statusDoc(v,activeLabel){return v==='CANCELLED'?'Anulada':(v==='ACTIVE'?activeLabel:(v||activeLabel));}
export async function pullTransactions(localState){
 const [sales,saleItems,purchases,purchaseItems,receivables,payables,cashAccounts,cashMovements,expenses,saleReturns,purchaseReturns,customerCredits,supplierCredits,cashClosings,cashTransfers]=await Promise.all([
  RemoteRepo.list("sales",{order:{column:"created_at",ascending:false}}),RemoteRepo.list("saleItems"),RemoteRepo.list("purchases",{order:{column:"created_at",ascending:false}}),RemoteRepo.list("purchaseItems"),RemoteRepo.list("receivables",{order:{column:"due_date",ascending:false}}),RemoteRepo.list("payables",{order:{column:"due_date",ascending:false}}),RemoteRepo.list("cashAccounts",{order:{column:"name",ascending:true}}),RemoteRepo.list("cashMovements",{order:{column:"created_at",ascending:false}}),RemoteRepo.list("expenses",{order:{column:"created_at",ascending:false}}),RemoteRepo.list("returns",{order:{column:"created_at",ascending:false}}),RemoteRepo.list("purchaseReturns",{order:{column:"created_at",ascending:false}}),RemoteRepo.list("customerCredits",{order:{column:"created_at",ascending:false}}),RemoteRepo.list("supplierCredits",{order:{column:"created_at",ascending:false}}),RemoteRepo.list("cashClosings",{order:{column:"created_at",ascending:false}}),RemoteRepo.list("cashTransfers",{order:{column:"created_at",ascending:false}})
 ]);
 const saleLines={};for(const i of saleItems)(saleLines[i.sale_id]||=[]).push({id:i.id,productId:i.product_id,qty:Number(i.qty||0),price:Number(i.unit_price||0),cost:Number(i.unit_cost||0),tax:0});
 const purchaseLines={};for(const i of purchaseItems)(purchaseLines[i.purchase_id]||=[]).push({id:i.id,productId:i.product_id,qty:Number(i.qty||0),cost:Number(i.unit_cost||0),taxRate:0});
 localState.receivables=receivables.map(r=>({id:r.id,reference:r.reference,customerId:r.customer_id,saleId:r.sale_id,date:r.created_at||r.due_date||now(),dueDate:r.due_date||now(),total:Number(r.total||0),balance:Number(r.balance||0),status:r.status==="PAID"?"Pagada":(r.status==="PARTIAL"?"Parcial":"Pendiente")}));
 localState.payables=payables.map(r=>({id:r.id,reference:r.reference,supplierId:r.supplier_id,purchaseId:r.purchase_id,date:r.created_at||r.due_date||now(),dueDate:r.due_date||now(),total:Number(r.total||0),balance:Number(r.balance||0),status:r.status==="PAID"?"Pagada":(r.status==="PARTIAL"?"Parcial":"Pendiente")}));
 const arBySale=new Map(localState.receivables.map(r=>[r.saleId,r])),apByPurchase=new Map(localState.payables.map(r=>[r.purchaseId,r]));
 localState.sales=sales.map(r=>({id:r.id,number:r.number,date:r.created_at,customerId:r.customer_id,branchId:r.branch_id,subtotal:Number(r.subtotal||0),tax:Number(r.tax||0),total:Number(r.total||0),baseTotalUSD:Number(r.base_total_usd||r.total||0),currency:r.document_currency||"USD",documentSubtotal:Number(r.subtotal||0),documentTax:Number(r.tax||0),documentTotal:Number(r.total||0),exchangeRate:Number(r.exchange_rate||1),condition:arBySale.has(r.id)?"credit":"cash",status:statusDoc(r.status,"Completada"),items:saleLines[r.id]||[]}));
 localState.purchases=purchases.map(r=>({id:r.id,number:r.number,date:r.created_at,supplierId:r.supplier_id,branchId:r.branch_id,subtotal:Number(r.subtotal||0),tax:Number(r.tax||0),total:Number(r.total||0),baseTotalUSD:Number(r.base_total_usd||r.total||0),currency:r.document_currency||"USD",documentSubtotal:Number(r.subtotal||0),documentTax:Number(r.tax||0),documentTotal:Number(r.total||0),exchangeRate:Number(r.exchange_rate||1),condition:apByPurchase.has(r.id)?"credit":"cash",status:statusDoc(r.status,"Recibida"),items:purchaseLines[r.id]||[]}));
 localState.cashAccounts=cashAccounts.map(r=>({id:r.id,name:r.name,type:"Caja/Banco",currency:r.currency||"USD",branchId:r.branch_id,balance:Number(r.balance||0),status:r.active===false?"Inactivo":"Activo"}));
 localState.cashMovements=cashMovements.map(r=>({id:r.id,date:r.created_at,accountId:r.account_id,type:r.direction==="IN"?"IN":"OUT",amount:Number(r.amount||0),currency:r.currency||"USD",reference:r.reference||"",note:r.description||""}));
 localState.expenses=expenses.map(r=>({id:r.id,date:r.created_at,category:r.category||"General",description:r.description||"",amount:Number((r.base_amount_usd ?? r.amount) || 0),baseAmountUSD:Number((r.base_amount_usd ?? r.amount) || 0),cashAmount:Number(r.amount||0),currency:r.currency||"USD",exchangeRate:Number(r.exchange_rate||1),accountId:r.cash_account_id,reference:r.reference||""}));
 localState.returns=saleReturns.map(r=>({id:r.id,number:r.number,date:r.created_at,saleId:r.sale_id,saleNumber:localState.sales.find(s=>s.id===r.sale_id)?.number||'',productId:r.payload?.product_id||null,qty:Number(r.payload?.qty||0),net:Number(r.payload?.subtotal||0),tax:Number(r.payload?.tax||0),amount:Number(r.total||0),cost:Number(r.payload?.cost||0),arReduction:Number(r.payload?.ar_applied||0),customerCredit:Number(r.payload?.customer_credit||0),status:'Completada'}));
 localState.purchaseReturns=purchaseReturns.map(r=>({id:r.id,number:r.number,date:r.created_at,purchaseId:r.purchase_id,purchaseNumber:localState.purchases.find(p=>p.id===r.purchase_id)?.number||'',supplierId:localState.purchases.find(p=>p.id===r.purchase_id)?.supplierId||null,branchId:localState.purchases.find(p=>p.id===r.purchase_id)?.branchId||null,productId:r.payload?.product_id||null,qty:Number(r.payload?.qty||0),net:Number(r.payload?.subtotal||0),tax:Number(r.payload?.tax||0),amount:Number(r.total||0),payableReduction:Number(r.payload?.ap_applied||0),supplierCredit:Number(r.payload?.supplier_credit||0),status:'Completada'}));
 localState.customerCredits=customerCredits.map(r=>({id:r.id,customerId:r.customer_id,amount:Number((r.original_amount ?? r.balance)||0),balance:Number(r.balance||0),reference:r.reference||'',date:r.created_at,currency:r.currency||'USD',status:Number(r.balance||0)>0?'Disponible':'Utilizado'}));
 localState.supplierCredits=supplierCredits.map(r=>({id:r.id,supplierId:r.supplier_id,amount:Number((r.original_amount ?? r.balance)||0),balance:Number(r.balance||0),reference:r.reference||'',date:r.created_at,currency:r.currency||'USD',status:Number(r.balance||0)>0?'Disponible':'Utilizado'}));
 localState.cashClosings=cashClosings.map(r=>({id:r.id,number:r.reference||r.id,date:r.created_at,accountId:r.cash_account_id,branchId:r.branch_id,currency:r.currency||localState.cashAccounts.find(a=>a.id===r.cash_account_id)?.currency||'USD',systemBalance:Number(r.expected||0),countedBalance:Number(r.counted||0),difference:Number(r.difference||0),note:r.note||'',status:r.status==='BALANCED'?'Cuadrado':(r.status==='RECONCILED'?'Conciliado':'Con diferencia'),reconciledAt:r.reconciled_at||null,reconciliationReason:r.reconciliation_reason||''}));
 localState.cashTransfers=cashTransfers.map(r=>({id:r.id,date:r.created_at,reference:r.reference,fromAccountId:r.from_account_id,toAccountId:r.to_account_id,fromAmount:Number(r.from_amount||0),fromCurrency:r.from_currency,toAmount:Number(r.to_amount||0),toCurrency:r.to_currency,baseAmountUSD:Number(r.base_amount_usd||0),fromRate:Number(r.from_rate||1),toRate:Number(r.to_rate||1),note:r.note||'',status:'Completada'}));
 return {sales:localState.sales.length,purchases:localState.purchases.length,receivables:localState.receivables.length,payables:localState.payables.length,cashMovements:localState.cashMovements.length,expenses:localState.expenses.length,returns:localState.returns.length,purchaseReturns:localState.purchaseReturns.length,cashClosings:localState.cashClosings.length,cashTransfers:localState.cashTransfers.length};
}
export async function pullAccounting(localState){
 const [accounts,entries,lines]=await Promise.all([RemoteRepo.list("accounting_accounts",{order:{column:"code",ascending:true}}),RemoteRepo.list("journal_entries",{order:{column:"created_at",ascending:false}}),RemoteRepo.list("journal_lines")]);
 localState.chartOfAccounts=accounts.map(r=>({id:r.id,code:r.code,name:r.name,type:r.type||"Activo",active:r.active!==false}));const byCode=new Map(localState.chartOfAccounts.map(a=>[a.code,a.id])),byEntry={};
 for(const l of lines)(byEntry[l.entry_id]||=[]).push({accountId:byCode.get(l.account_code)||null,accountCode:l.account_code,debit:Number(l.debit||0),credit:Number(l.credit||0),description:l.description||""});
 localState.journalEntries=entries.map(e=>({id:e.id,date:e.created_at,reference:e.reference||"",description:e.description||"",status:"Contabilizado",lines:byEntry[e.id]||[]}));return {accounts:accounts.length,entries:entries.length,lines:lines.length};
}
