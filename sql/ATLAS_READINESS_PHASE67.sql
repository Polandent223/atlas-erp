-- ATLAS Fase 67 — Readiness operacional completo
create or replace function public.atlas_operational_readiness()
returns jsonb language plpgsql security definer set search_path=public
as $$
declare cid uuid:=public.current_company_id(); missing text[]:='{}'; n int; cur text;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 select upper(base_currency) into cur from public.companies where id=cid;
 if cur is null or btrim(cur)='' then missing:=array_append(missing,'base_currency'); end if;
 select count(*) into n from public.company_settings where company_id=cid;
 if n=0 then missing:=array_append(missing,'company_settings'); end if;
 select count(*) into n from public.branches where company_id=cid and active=true;
 if n=0 then missing:=array_append(missing,'active_branch'); end if;
 select count(*) into n from public.cash_accounts where company_id=cid and active=true;
 if n=0 then missing:=array_append(missing,'active_cash_account'); end if;
 select count(*) into n from public.accounting_accounts where company_id=cid and active=true
 and code in ('1.1.01','1.1.02','1.1.03','1.1.04','2.1.01','2.1.02','4.1.01','5.1.01','5.2.01');
 if n<9 then missing:=array_append(missing,'chart_of_accounts'); end if;
 return jsonb_build_object('ready',cardinality(missing)=0,'missing',to_jsonb(missing),'company_id',cid,
 'checks',jsonb_build_object('base_currency',not ('base_currency'=any(missing)),'company_settings',not ('company_settings'=any(missing)),
 'active_branch',not ('active_branch'=any(missing)),'active_cash_account',not ('active_cash_account'=any(missing)),
 'chart_of_accounts',not ('chart_of_accounts'=any(missing))));
end $$;
revoke all on function public.atlas_operational_readiness() from public, anon;
grant execute on function public.atlas_operational_readiness() to authenticated;
