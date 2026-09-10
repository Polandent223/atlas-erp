import { getSupabase } from "./supabase.js";
import { isSupabaseConfigured } from "./config.js";

const TABLES = {
  customers:"customers",
  suppliers:"suppliers",
  products:"products",
  inventory:"inventory",
  sales:"sales",
  saleItems:"sale_items",
  purchases:"purchases",
  purchaseItems:"purchase_items",
  receivables:"receivables",
  payables:"payables",
  cashAccounts:"cash_accounts",
  cashMovements:"cash_movements",
  expenses:"expenses",
  accountingAccounts:"accounting_accounts",
  exchangeRates:"exchange_rates",
  quotations:"quotations",
  stockTransfers:"stock_transfers",
  returns:"sale_returns",
  purchaseReturns:"purchase_returns"
};

export const RemoteRepo = {
  async enabled(){ return isSupabaseConfigured(); },

  async list(key, opts={}){
    const supabase=await getSupabase();
    if(!supabase) throw new Error("Supabase no configurado");
    const table=TABLES[key]||key;
    let q=supabase.from(table).select(opts.select||"*");
    if(opts.eq) for(const [k,v] of Object.entries(opts.eq)) q=q.eq(k,v);
    if(opts.order) q=q.order(opts.order.column,{ascending:opts.order.ascending??true});
    const {data,error}=await q;
    if(error) throw error;
    return data||[];
  },

  async insert(key,row){
    const supabase=await getSupabase();
    if(!supabase) throw new Error("Supabase no configurado");
    const table=TABLES[key]||key;
    const {data,error}=await supabase.from(table).insert(row).select().single();
    if(error) throw error;
    return data;
  },

  async update(key,id,patch){
    const supabase=await getSupabase();
    if(!supabase) throw new Error("Supabase no configurado");
    const table=TABLES[key]||key;
    const {data,error}=await supabase.from(table).update(patch).eq("id",id).select().single();
    if(error) throw error;
    return data;
  },

  async remove(key,id){
    const supabase=await getSupabase();
    if(!supabase) throw new Error("Supabase no configurado");
    const table=TABLES[key]||key;
    const {error}=await supabase.from(table).delete().eq("id",id);
    if(error) throw error;
    return true;
  },

  async hasPermission(permission){
    return await this.rpc("has_permission",{p_permission:permission}) === true;
  },

  async requirePermission(permission){
    if(!(await this.hasPermission(permission))) throw new Error("No tienes permiso para realizar esta acción.");
    return true;
  },

  async rpc(name,args={}){
    const supabase=await getSupabase();
    if(!supabase) throw new Error("Supabase no configurado");
    const {data,error}=await supabase.rpc(name,args);
    if(error) throw error;
    return data;
  },

  trialBalance(){ return this.list("atlas_trial_balance",{order:{column:"code",ascending:true}}); },
  generalLedger(){ return this.list("atlas_general_ledger",{order:{column:"entry_date",ascending:false}}); },
  financialSummary(){ return this.rpc("atlas_financial_summary",{}); },

  seedChartOfAccounts(){ return this.rpc("atlas_seed_chart_of_accounts",{}); },

  createSale(args){ return this.rpc("atlas_create_sale",args); },
  createPurchase(args){ return this.rpc("atlas_create_purchase",args); },
  collectReceivable(args){ return this.rpc("atlas_collect_receivable",args); },
  payPayable(args){ return this.rpc("atlas_pay_payable",args); },
  transferStock(args){ return this.rpc("atlas_transfer_stock",args); },
  returnSale(args){ return this.rpc("atlas_return_sale",args); },
  returnPurchase(args){ return this.rpc("atlas_return_purchase",args); },
  voidSale(args){ return this.rpc("atlas_void_sale",args); },
  voidPurchase(args){ return this.rpc("atlas_void_purchase",args); },
  createExpense(args){ return this.rpc("atlas_create_expense",args); },
  createMaster(args){ return this.rpc("atlas_create_master",args); },
  updateMaster(args){ return this.rpc("atlas_update_master",args); }
};

export function toRemoteRow(key,row,companyId){
  const base={...row,company_id:companyId};
  delete base.companyId;
  switch(key){
    case "customers":
    case "suppliers":
      return {
        id:row.id,company_id:companyId,code:row.code||null,name:row.name,tax_id:row.taxId||null,
        phone:row.phone||null,email:row.email||null,address:row.city||null,active:row.status!=="Inactivo"
      };
    case "products":
      return {
        id:row.id,company_id:companyId,sku:row.sku,name:row.name,category:row.category||"General",
        cost:Number(row.cost||0),price:Number(row.price||0),tax:Number(row.tax||0),
        min_stock:Number(row.minStock||0),active:row.status!=="Inactivo"
      };
    default: return base;
  }
}