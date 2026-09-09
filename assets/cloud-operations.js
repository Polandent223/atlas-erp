import {getSupabaseClient} from "./supabase.js";
const client=()=>{const c=getSupabaseClient?.();if(!c)throw new Error("Supabase no está configurado.");return c};
const rpc=async(name,args)=>{const {data,error}=await client().rpc(name,args);if(error)throw error;return data};
export const cloudCreateSale=p=>rpc("atlas_create_sale",p);
export const cloudCreatePurchase=p=>rpc("atlas_create_purchase",p);
export const cloudCollectReceivable=(id,amount,account)=>rpc("atlas_collect_receivable",{p_receivable:id,p_amount:amount,p_cash_account:account});
export const cloudPayPayable=(id,amount,account)=>rpc("atlas_pay_payable",{p_payable:id,p_amount:amount,p_cash_account:account});
