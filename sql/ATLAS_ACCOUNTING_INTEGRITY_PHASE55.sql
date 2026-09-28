-- ATLAS Fase 55 — Integridad contable transaccional
-- Ejecutar después de ATLAS_TRANSACTIONAL_RPCS_PHASE45.sql.
-- Objetivo: que venta, compra, cobro y pago creen su asiento contable dentro
-- de la misma transacción PostgreSQL. Si el asiento falla, toda la operación revierte.

create or replace function public.atlas_post_journal(
 p_reference text,
 p_description text,
 p_lines jsonb
) returns uuid
language plpgsql security definer
set search_path=public
as $$
declare
 cid uuid:=public.current_company_id();
 eid uuid:=gen_random_uuid();
 l jsonb; d numeric:=0; c numeric:=0;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)<2 then
   raise exception 'Asiento contable incompleto';
 end if;
 for l in select value from jsonb_array_elements(p_lines) loop
   if coalesce((l->>'debit')::numeric,0)<0 or coalesce((l->>'credit')::numeric,0)<0 then
     raise exception 'Importe contable inválido';
   end if;
   d:=d+coalesce((l->>'debit')::numeric,0);
   c:=c+coalesce((l->>'credit')::numeric,0);
 end loop;
 if abs(d-c)>0.0001 or d<=0 then raise exception 'Asiento contable desbalanceado'; end if;

 insert into public.journal_entries(id,company_id,reference,description)
 values(eid,cid,p_reference,p_description);

 for l in select value from jsonb_array_elements(p_lines) loop
   if coalesce((l->>'debit')::numeric,0)>0 or coalesce((l->>'credit')::numeric,0)>0 then
     insert into public.journal_lines(entry_id,account_code,description,debit,credit)
     values(eid,l->>'account_code',coalesce(l->>'description',p_description),
       coalesce((l->>'debit')::numeric,0),coalesce((l->>'credit')::numeric,0));
   end if;
 end loop;
 return eid;
end $$;

revoke all on function public.atlas_post_journal(text,text,jsonb) from public;
grant execute on function public.atlas_post_journal(text,text,jsonb) to authenticated;

-- Envolturas contables: se ejecutan en la misma transacción que el RPC operacional.
create or replace function public.atlas_post_sale_accounting(
 p_reference text,p_subtotal numeric,p_tax numeric,p_total numeric,p_paid numeric,p_cost numeric
) returns uuid language plpgsql security definer set search_path=public as $$
declare lines jsonb:='[]'::jsonb; due numeric:=p_total-p_paid;
begin
 if p_total<=0 or p_paid<0 or due<0 or p_cost<0 then raise exception 'Valores contables de venta inválidos'; end if;
 if p_paid>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1.1.01','debit',p_paid,'credit',0,'description','Cobro de venta')); end if;
 if due>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1.1.02','debit',due,'credit',0,'description','Cuenta por cobrar')); end if;
 lines:=lines||jsonb_build_array(jsonb_build_object('account_code','4.1.01','debit',0,'credit',p_subtotal,'description','Ingreso por venta'));
 if p_tax>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','2.1.02','debit',0,'credit',p_tax,'description','IVA por pagar')); end if;
 if p_cost>0 then
   lines:=lines||jsonb_build_array(
    jsonb_build_object('account_code','5.1.01','debit',p_cost,'credit',0,'description','Costo de ventas'),
    jsonb_build_object('account_code','1.1.03','debit',0,'credit',p_cost,'description','Salida de inventario'));
 end if;
 return public.atlas_post_journal(p_reference,'Venta '||p_reference,lines);
end $$;

create or replace function public.atlas_post_purchase_accounting(
 p_reference text,p_subtotal numeric,p_tax numeric,p_total numeric,p_paid numeric
) returns uuid language plpgsql security definer set search_path=public as $$
declare lines jsonb:='[]'::jsonb; due numeric:=p_total-p_paid;
begin
 if p_total<=0 or p_paid<0 or due<0 then raise exception 'Valores contables de compra inválidos'; end if;
 lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1.1.03','debit',p_subtotal,'credit',0,'description','Entrada de inventario'));
 if p_tax>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1.1.04','debit',p_tax,'credit',0,'description','IVA crédito fiscal')); end if;
 if p_paid>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1.1.01','debit',0,'credit',p_paid,'description','Pago de compra')); end if;
 if due>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','2.1.01','debit',0,'credit',due,'description','Cuenta por pagar')); end if;
 return public.atlas_post_journal(p_reference,'Compra '||p_reference,lines);
end $$;

create or replace function public.atlas_post_collection_accounting(p_reference text,p_amount numeric)
returns uuid language plpgsql security definer set search_path=public as $$
begin
 if p_amount<=0 then raise exception 'Monto de cobro inválido'; end if;
 return public.atlas_post_journal(p_reference,'Cobro CxC '||p_reference,jsonb_build_array(
  jsonb_build_object('account_code','1.1.01','debit',p_amount,'credit',0,'description','Entrada a caja/banco'),
  jsonb_build_object('account_code','1.1.02','debit',0,'credit',p_amount,'description','Disminución CxC')));
end $$;

create or replace function public.atlas_post_payment_accounting(p_reference text,p_amount numeric)
returns uuid language plpgsql security definer set search_path=public as $$
begin
 if p_amount<=0 then raise exception 'Monto de pago inválido'; end if;
 return public.atlas_post_journal(p_reference,'Pago CxP '||p_reference,jsonb_build_array(
  jsonb_build_object('account_code','2.1.01','debit',p_amount,'credit',0,'description','Disminución CxP'),
  jsonb_build_object('account_code','1.1.01','debit',0,'credit',p_amount,'description','Salida de caja/banco')));
end $$;

revoke all on function public.atlas_post_sale_accounting(text,numeric,numeric,numeric,numeric,numeric) from public;
revoke all on function public.atlas_post_purchase_accounting(text,numeric,numeric,numeric,numeric) from public;
revoke all on function public.atlas_post_collection_accounting(text,numeric) from public;
revoke all on function public.atlas_post_payment_accounting(text,numeric) from public;

-- Estas funciones son auxiliares internas de los RPC SECURITY DEFINER.
-- No se concede EXECUTE directo a authenticated.
