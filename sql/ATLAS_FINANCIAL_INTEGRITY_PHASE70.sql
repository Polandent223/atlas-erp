-- ATLAS Fase 70 — Diagnóstico financiero integral
-- Valida invariantes críticas sin modificar datos. Útil antes de liberar una migración a producción.

create or replace function public.atlas_financial_integrity_check()
returns jsonb
language plpgsql security definer set search_path=public as $$
declare
 cid uuid:=public.current_company_id();
 issues jsonb:='[]'::jsonb;
 r record;
 n integer:=0;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('audit.view') or public.has_permission('settings.manage') or public.has_permission('*')) then
   raise exception 'Permiso insuficiente';
 end if;

 -- 1. Asientos descuadrados.
 for r in
   select je.id,je.reference,
          round(coalesce(sum(jl.debit),0),4) debit,
          round(coalesce(sum(jl.credit),0),4) credit
   from public.journal_entries je
   left join public.journal_lines jl on jl.entry_id=je.id
   where je.company_id=cid
   group by je.id,je.reference
   having abs(coalesce(sum(jl.debit),0)-coalesce(sum(jl.credit),0))>0.009
 loop
   issues:=issues||jsonb_build_array(jsonb_build_object('severity','ERROR','code','JOURNAL_UNBALANCED','reference',r.reference,'debit',r.debit,'credit',r.credit));
 end loop;

 -- 2. Movimientos de caja cuya moneda no coincide con la cuenta.
 for r in
   select cm.id,cm.reference,cm.currency movement_currency,ca.currency account_currency
   from public.cash_movements cm
   join public.cash_accounts ca on ca.id=cm.account_id and ca.company_id=cm.company_id
   where cm.company_id=cid and upper(coalesce(cm.currency,''))<>upper(coalesce(ca.currency,''))
 loop
   issues:=issues||jsonb_build_array(jsonb_build_object('severity','ERROR','code','CASH_CURRENCY_MISMATCH','reference',r.reference,'movement_currency',r.movement_currency,'account_currency',r.account_currency));
 end loop;

 -- 3. Saldos de caja negativos: se consideran error mientras ATLAS no tenga sobregiro explícito.
 for r in select id,name,currency,balance from public.cash_accounts where company_id=cid and active=true and balance<0 loop
   issues:=issues||jsonb_build_array(jsonb_build_object('severity','ERROR','code','NEGATIVE_CASH','account',r.name,'currency',r.currency,'balance',r.balance));
 end loop;

 -- 4. Transferencias financieras: verifica que ambos lados representen el mismo valor USD.
 if to_regclass('public.cash_transfers') is not null then
  for r in
    select id,reference,from_amount,from_currency,to_amount,to_currency,base_amount_usd,from_rate,to_rate
    from public.cash_transfers where company_id=cid
  loop
    if r.base_amount_usd<=0 or r.from_rate<=0 or r.to_rate<=0
       or abs((case when upper(r.from_currency)='USD' then r.from_amount else r.from_amount/r.from_rate end)-r.base_amount_usd)>greatest(0.01,abs(r.base_amount_usd)*0.0005)
       or abs((case when upper(r.to_currency)='USD' then r.to_amount else r.to_amount/r.to_rate end)-r.base_amount_usd)>greatest(0.01,abs(r.base_amount_usd)*0.0005)
    then
      issues:=issues||jsonb_build_array(jsonb_build_object('severity','ERROR','code','TRANSFER_FX_MISMATCH','reference',r.reference));
    end if;
  end loop;
 end if;

 -- 5. Gastos con snapshot FX incoherente.
 for r in
   select id,reference,amount,currency,base_amount_usd,exchange_rate
   from public.expenses
   where company_id=cid and base_amount_usd is not null
 loop
   if r.base_amount_usd<=0 or coalesce(r.exchange_rate,0)<=0
      or abs((case when upper(r.currency)='USD' then r.amount else r.amount/r.exchange_rate end)-r.base_amount_usd)>greatest(0.01,abs(r.base_amount_usd)*0.0005)
   then
     issues:=issues||jsonb_build_array(jsonb_build_object('severity','ERROR','code','EXPENSE_FX_MISMATCH','reference',r.reference));
   end if;
 end loop;

 -- 6. Créditos o cuentas por cobrar/pagar nunca pueden quedar negativos.
 select count(*) into n from public.receivables where company_id=cid and balance<0;
 if n>0 then issues:=issues||jsonb_build_array(jsonb_build_object('severity','ERROR','code','NEGATIVE_RECEIVABLES','count',n)); end if;
 select count(*) into n from public.payables where company_id=cid and balance<0;
 if n>0 then issues:=issues||jsonb_build_array(jsonb_build_object('severity','ERROR','code','NEGATIVE_PAYABLES','count',n)); end if;
 select count(*) into n from public.customer_credits where company_id=cid and balance<0;
 if n>0 then issues:=issues||jsonb_build_array(jsonb_build_object('severity','ERROR','code','NEGATIVE_CUSTOMER_CREDITS','count',n)); end if;
 select count(*) into n from public.supplier_credits where company_id=cid and balance<0;
 if n>0 then issues:=issues||jsonb_build_array(jsonb_build_object('severity','ERROR','code','NEGATIVE_SUPPLIER_CREDITS','count',n)); end if;

 return jsonb_build_object(
   'ok',jsonb_array_length(issues)=0,
   'checked_at',now(),
   'company_id',cid,
   'issue_count',jsonb_array_length(issues),
   'issues',issues
 );
end $$;

revoke all on function public.atlas_financial_integrity_check() from public;
grant execute on function public.atlas_financial_integrity_check() to authenticated;
