import {getSupabase} from "./supabase.js";
const SAFE_TABLES=new Set(["branches","customers","suppliers","products","payment_methods","cash_accounts","inventory","sales","purchases","receivables","payables","cash_movements","expenses","quotations","sale_returns","purchase_returns","stock_transfers","customer_credits","supplier_credits","cash_closings","exchange_rates","accounting_accounts","journal_entries","audit_log","company_settings"]);
async function client(){const c=await getSupabase();if(!c)throw new Error("Supabase todavía no está conectado.");return c;}
export async function verifyCloudTarget(){
 const c=await client();
 const {data:{session},error}=await c.auth.getSession();
 if(error||!session?.user)throw new Error("No existe una sesión autenticada.");
 const {data,error:scopeError}=await c.rpc("current_user_scope");
 if(scopeError)throw new Error(scopeError.message||"No se pudo validar el ámbito.");
 if(!data?.company_id)throw new Error("El usuario no tiene empresa asignada.");
 return data;
}
export async function compareCloudCounts(plan){
 const c=await client(),out=[];
 for(const step of plan.steps||[]){
  if(!SAFE_TABLES.has(step.table))continue;
  const {count,error}=await c.from(step.table).select("*",{count:"exact",head:true});
  out.push({table:step.table,local:step.count,cloud:error?null:(count||0),error:error?.message||null});
 }
 return out;
}
export async function executeCloudImport(plan,{confirmToken,dryRun=true}={}){
 if(confirmToken!=="IMPORTAR-ATLAS")throw new Error("Importación bloqueada: falta confirmación explícita.");
 const scope=await verifyCloudTarget();
 if(dryRun)return {dryRun:true,companyId:scope.company_id,steps:(plan.steps||[]).map(s=>({table:s.table,count:s.count}))};
 const c=await client(),results=[];
 for(const step of plan.steps||[]){
  if(!SAFE_TABLES.has(step.table)||!step.rows?.length){results.push({table:step.table,inserted:0,skipped:true});continue;}
  // La escritura final solo se habilita después de mapear IDs locales -> UUID nube.
  throw new Error(`Escritura detenida en ${step.table}: falta aplicar el mapa de identificadores de producción.`);
 }
 return {dryRun:false,results};
}
