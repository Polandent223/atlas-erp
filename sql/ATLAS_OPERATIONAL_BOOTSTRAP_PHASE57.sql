-- ATLAS Fase 57 — Bootstrap operativo y diagnóstico de preparación

create or replace function public.atlas_seed_chart_of_accounts()
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); inserted_count int;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 insert into public.accounting_accounts(company_id,code,name,type,active) values
 (cid,'1.1.01','Caja y bancos','ASSET',true),(cid,'1.1.02','Cuentas por cobrar','ASSET',true),(cid,'1.1.03','Inventario','ASSET',true),(cid,'1.1.04','IVA crédito fiscal','ASSET',true),(cid,'2.1.01','Cuentas por pagar','LIABILITY',true),(cid,'2.1.02','IVA por pagar','LIABILITY',true),(cid,'4.1.01','Ventas','INCOME',true),(cid,'5.1.01','Costo de ventas','COST',true),(cid,'5.2.01','Compras / Gastos','EXPENSE',true)
 on conflict(company_id,code) do update set name=excluded.name,type=excluded.type,active=true;
 get diagnostics inserted_count=row_count;
 return jsonb_build_object('ok',true,'accounts_ready',inserted_count);
end $$;
revoke all on function public.atlas_seed_chart_of_accounts() from public;
grant execute on function public.atlas_seed_chart_of_accounts() to authenticated;

create or replace function public.atlas_operational_readiness()
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); missing text[]:='{}'; n int;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 select count(*) into n from public.branches where company_id=cid and active=true;
 if n=0 then missing:=array_append(missing,'active_branch'); end if;
 select count(*) into n from public.accounting_accounts where company_id=cid and active=true and code in ('1.1.01','1.1.02','1.1.03','1.1.04','2.1.01','2.1.02','4.1.01','5.1.01','5.2.01');
 if n<9 then missing:=array_append(missing,'chart_of_accounts'); end if;
 return jsonb_build_object('ready',cardinality(missing)=0,'missing',to_jsonb(missing),'company_id',cid,'checks',jsonb_build_object('active_branch',not ('active_branch'=any(missing)),'chart_of_accounts',not ('chart_of_accounts'=any(missing))));
end $$;
revoke all on function public.atlas_operational_readiness() from public;
grant execute on function public.atlas_operational_readiness() to authenticated;
$$;