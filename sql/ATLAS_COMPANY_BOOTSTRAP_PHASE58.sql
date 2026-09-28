-- ATLAS Fase 58 — Bootstrap seguro de empresa
create unique index if not exists atlas_branches_company_code_uq on public.branches(company_id,code);

create or replace function public.atlas_bootstrap_company()
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); bid uuid; cur text; readiness jsonb;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 select upper(base_currency) into cur from public.companies where id=cid;
 if cur is null then raise exception 'Empresa inválida'; end if;
 insert into public.company_settings(company_id) values(cid) on conflict(company_id) do nothing;
 select id into bid from public.branches where company_id=cid and code='MAIN' limit 1;
 if bid is null then
   insert into public.branches(company_id,name,code,active) values(cid,'Sede Principal','MAIN',true) returning id into bid;
 end if;
 if not exists(select 1 from public.cash_accounts where company_id=cid and branch_id=bid and name='Caja Principal' and currency=cur) then
   insert into public.cash_accounts(company_id,branch_id,name,currency,balance,active) values(cid,bid,'Caja Principal',cur,0,true);
 end if;
 perform public.atlas_seed_chart_of_accounts();
 readiness:=public.atlas_operational_readiness();
 return jsonb_build_object('ok',true,'branch_id',bid,'base_currency',cur,'readiness',readiness);
end $$;
revoke all on function public.atlas_bootstrap_company() from public;
grant execute on function public.atlas_bootstrap_company() to authenticated;
create index if not exists atlas_cash_accounts_company_branch_idx on public.cash_accounts(company_id,branch_id,active);
