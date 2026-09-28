-- ATLAS Fase 65 — Endurecimiento de RPC SECURITY DEFINER
revoke all on function public.atlas_post_journal(text,text,jsonb) from public, anon, authenticated;
revoke all on function public.atlas_write_audit(text,text,jsonb) from public, anon, authenticated;
revoke all on function public.atlas_post_sale_accounting(text,numeric,numeric,numeric,numeric,numeric) from public, anon, authenticated;
revoke all on function public.atlas_post_purchase_accounting(text,numeric,numeric,numeric,numeric) from public, anon, authenticated;
revoke all on function public.atlas_post_collection_accounting(text,numeric) from public, anon, authenticated;
revoke all on function public.atlas_post_payment_accounting(text,numeric) from public, anon, authenticated;
