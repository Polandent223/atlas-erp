-- ATLAS Fase 33 — Bootstrap inicial
-- Reemplazar los 4 valores indicados DESPUÉS de crear el primer usuario en Supabase Authentication.
begin;
with c as (
 insert into public.companies(name,tax_id,country,base_currency)
 values ('REEMPLAZAR_EMPRESA','REEMPLAZAR_RIF','VE','USD')
 returning id
), p as (
 insert into public.profiles(id,company_id,full_name,status)
 select 'REEMPLAZAR_AUTH_USER_UUID'::uuid,c.id,'Administrador','ACTIVE' from c
 returning id,company_id
), r as (
 insert into public.roles(company_id,name,permissions)
 select p.company_id,'Administrador','["*"]'::jsonb from p
 returning id,company_id
), ur as (
 insert into public.user_roles(user_id,role_id)
 select p.id,r.id from p cross join r
), b as (
 insert into public.branches(company_id,name,code)
 select p.company_id,'Tienda Principal','PRINCIPAL' from p
 returning id
)
insert into public.user_branches(user_id,branch_id)
select p.id,b.id from p cross join b;
commit;
