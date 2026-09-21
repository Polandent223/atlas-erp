import { CONFIG, isSupabaseConfigured } from "./config.js";

let client = null;

export async function getSupabase(){
  if(!isSupabaseConfigured()) return null;
  if(client) return client;
  const mod = await import("https://esm.sh/@supabase/supabase-js@2");
  client = mod.createClient(CONFIG.supabaseUrl, CONFIG.supabaseAnonKey, {
    auth: {persistSession:true, autoRefreshToken:true, detectSessionInUrl:true}
  });
  globalThis.ATLAS_SUPABASE_CLIENT = client;
  globalThis.supabaseClient = client;
  return client;
}

export async function remoteLogin(email,password){
  const supabase = await getSupabase();
  if(!supabase) throw new Error("Supabase no está configurado.");
  const {data,error}=await supabase.auth.signInWithPassword({email,password});
  if(error) throw error;
  return data;
}

export async function remoteLogout(){
  const supabase=await getSupabase();
  if(!supabase) return;
  const {error}=await supabase.auth.signOut();
  if(error) throw error;
}

export async function getRemoteProfile(){
  const supabase=await getSupabase();
  if(!supabase) return null;
  const {data:{user},error:userError}=await supabase.auth.getUser();
  if(userError) throw userError;
  if(!user) return null;

  const {data:profile,error}=await supabase.from("profiles").select("id,company_id,full_name,status").eq("id",user.id).single();
  if(error) throw error;
  const [{data:ur,error:urError},{data:ubs,error:ubError},{data:company,error:companyError}]=await Promise.all([
    supabase.from("user_roles").select("role_id").eq("user_id",user.id).maybeSingle(),
    supabase.from("user_branches").select("branch_id").eq("user_id",user.id),
    supabase.from("companies").select("id,name,tax_id,phone,email,country,base_currency,display_currency").eq("id",profile.company_id).single()
  ]);
  if(urError) throw urError; if(ubError) throw ubError; if(companyError) throw companyError;
  let role=null;
  if(ur?.role_id){
    const {data,error:roleError}=await supabase.from("roles").select("id,name,permissions").eq("id",ur.role_id).single();
    if(roleError) throw roleError; role=data;
  }
  const branchIds=(ubs||[]).map(x=>x.branch_id);
  let branches=[];
  if(branchIds.length){
    const {data,error:branchError}=await supabase.from("branches").select("id,name,code,city,active").in("id",branchIds);
    if(branchError) throw branchError; branches=data||[];
  }
  return {...profile,email:user.email,role_id:ur?.role_id||null,role,branch_id:branchIds[0]||"all",branch_ids:branchIds,branches,company};
}

export async function pullWorkspace(){
  const supabase=await getSupabase();
  if(!supabase) throw new Error("Supabase no configurado.");
  const {data,error}=await supabase.rpc("atlas_workspace_snapshot");
  if(error) throw error;
  return data;
}

export async function pushAudit(action,entity,detail={}){
  const supabase=await getSupabase();
  if(!supabase) return;
  await supabase.rpc("atlas_write_audit",{p_action:action,p_entity:entity,p_detail:detail});
}

export async function healthCheck(){
  const supabase=await getSupabase();
  if(!supabase) return {ok:false,message:"Supabase no configurado"};
  const started=performance.now();
  const {data,error}=await supabase.rpc("atlas_healthcheck");
  return error
    ? {ok:false,message:error.message}
    : {ok:true,message:data||"Conexión correcta",ms:Math.round(performance.now()-started)};
}
