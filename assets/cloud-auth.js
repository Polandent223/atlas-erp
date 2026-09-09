import {getSupabase} from "./supabase.js";
async function client(){const c=await getSupabase();if(!c)throw new Error("Supabase todavía no está conectado.");return c;}
export function cloudAuthAvailable(){return true;}
export async function cloudSignIn(email,password){if(!email||!password)throw new Error("Correo y contraseña son obligatorios.");const c=await client();const {data,error}=await c.auth.signInWithPassword({email:String(email).trim(),password:String(password)});if(error)throw new Error(error.message||"No se pudo iniciar sesión.");return data;}
export async function cloudSignOut(){const c=await client();const {error}=await c.auth.signOut();if(error)throw new Error(error.message||"No se pudo cerrar sesión.");return true;}
export async function cloudSession(){const c=await client();const {data,error}=await c.auth.getSession();if(error)throw new Error(error.message||"No se pudo leer la sesión.");return data?.session||null;}
export async function cloudProfile(){const s=await cloudSession();if(!s?.user?.id)return null;const c=await client();const {data,error}=await c.from("profiles").select("id,company_id,full_name,status").eq("id",s.user.id).single();if(error)throw new Error(error.message||"No se pudo cargar el perfil.");return data;}
