import {cloudAuthAvailable,cloudSession,cloudProfile} from "./cloud-auth.js";
import {verifyCloudTarget} from "./cloud-import-executor.js";
const KEY="atlas_cloud_activation_v1";
export function cloudActivationState(){try{return JSON.parse(localStorage.getItem(KEY)||'{"enabled":false,"verified":false}')}catch{return {enabled:false,verified:false}}}
export async function verifyCloudActivation(){
 if(!cloudAuthAvailable())return {ok:false,reason:"Supabase no configurado"};
 const session=await cloudSession();if(!session?.user)return {ok:false,reason:"Sin sesión cloud"};
 const profile=await cloudProfile();if(!profile?.company_id)return {ok:false,reason:"Perfil sin empresa"};
 const target=await verifyCloudTarget();
 const state={enabled:false,verified:true,companyId:target.company_id,userId:session.user.id,verifiedAt:new Date().toISOString()};
 localStorage.setItem(KEY,JSON.stringify(state));return {ok:true,state,target};
}
export function enableCloudMode(){
 const s=cloudActivationState();if(!s.verified||!s.companyId)throw new Error("Primero debes verificar sesión, empresa y alcance cloud.");
 s.enabled=true;s.enabledAt=new Date().toISOString();localStorage.setItem(KEY,JSON.stringify(s));return s;
}
export function disableCloudMode(){const s=cloudActivationState();s.enabled=false;localStorage.setItem(KEY,JSON.stringify(s));return s}
export function isCloudMode(){const s=cloudActivationState();return s.enabled===true&&s.verified===true&&!!s.companyId}
