-- ATLAS Fase 56 — Contrato multi-moneda seguro
-- Complementa F55. No reemplaza importes contables base; evita mezclar importes USD con saldos de caja en otra moneda.

create or replace function public.atlas_fx_amount(
 p_base_amount numeric,
 p_account_currency text,
 p_document_currency text,
 p_exchange_rate numeric
) returns numeric
language plpgsql immutable
as $$
declare ac text:=upper(coalesce(p_account_currency,'USD')); dc text:=upper(coalesce(p_document_currency,'USD'));
begin
 if p_base_amount is null or p_base_amount<0 then raise exception 'Importe base inválido'; end if;
 if p_exchange_rate is null or p_exchange_rate<=0 then raise exception 'Tasa inválida'; end if;
 -- ATLAS F53/F55 usa USD como importe de referencia contable.
 -- Si la cuenta está en USD, el movimiento es exactamente el importe base.
 if ac='USD' then return round(p_base_amount,4); end if;
 -- Si la cuenta está en la misma moneda documental no-USD, convierte el importe base con el snapshot de tasa.
 if ac=dc and dc<>'USD' then return round(p_base_amount*p_exchange_rate,4); end if;
 -- No se permite inferir cruces (ej. EUR documento -> VES cuenta) con una sola tasa.
 raise exception 'Conversión no soportada: documento %, cuenta %. Se requiere tasa cruzada explícita.',dc,ac;
end $$;

revoke all on function public.atlas_fx_amount(numeric,text,text,numeric) from public;
grant execute on function public.atlas_fx_amount(numeric,text,text,numeric) to authenticated;

-- Verificador de integridad de configuración monetaria para diagnóstico previo a operación.
create or replace function public.atlas_currency_healthcheck()
returns jsonb
language plpgsql stable security definer set search_path=public
as $$
declare cid uuid:=public.current_company_id(); invalid_accounts int; invalid_rates int;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 select count(*) into invalid_accounts from public.cash_accounts
 where company_id=cid and active=true and (currency is null or btrim(currency)='');
 select count(*) into invalid_rates from public.exchange_rates
 where company_id=cid and (currency is null or btrim(currency)='' or rate<=0);
 return jsonb_build_object(
   'ok',invalid_accounts=0 and invalid_rates=0,
   'invalid_cash_accounts',invalid_accounts,
   'invalid_exchange_rates',invalid_rates,
   'reference_currency','USD',
   'rule','No cross-currency inference without explicit rate'
 );
end $$;
revoke all on function public.atlas_currency_healthcheck() from public;
grant execute on function public.atlas_currency_healthcheck() to authenticated;
