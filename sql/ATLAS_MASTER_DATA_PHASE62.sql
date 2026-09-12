-- ATLAS Fase 62 — Maestros remotos coherentes con la UI
-- Añade los campos que la interfaz ya maneja y centraliza altas/ediciones en RPCs seguros.

alter table public.customers add column if not exists code text;
alter table public.suppliers add column if not exists code text;
alter table public.products add column if not exists category text not null default 'General';
alter table public.products add column if not exists tax numeric(9,4) not null default 0 check(tax>=0 and tax<=100);

create unique index if not exists customers_company_code_uq on public.customers(company_id,code) where code is not null and code<>'';
create unique index if not exists suppliers_company_code_uq on public.suppliers(company_id,code) where code is not null and code<>'';

create or replace function public.atlas_create_master(p_entity text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); rid uuid:=gen_random_uuid(); e text:=lower(trim(p_entity));
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if e='customer' then
   if not (public.has_permission('customers.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
   if nullif(trim(p_payload->>'name'),'') is null then raise exception 'Nombre requerido'; end if;
   insert into public.customers(id,company_id,code,name,tax_id,phone,email,address,active)
   values(rid,cid,nullif(trim(p_payload->>'code'),''),trim(p_payload->>'name'),nullif(trim(p_payload->>'tax_id'),''),nullif(trim(p_payload->>'phone'),''),nullif(trim(p_payload->>'email'),''),nullif(trim(p_payload->>'address'),''),true);
 elsif e='supplier' then
   if not (public.has_permission('suppliers.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
   if nullif(trim(p_payload->>'name'),'') is null then raise exception 'Nombre requerido'; end if;
   insert into public.suppliers(id,company_id,code,name,tax_id,phone,email,address,active)
   values(rid,cid,nullif(trim(p_payload->>'code'),''),trim(p_payload->>'name'),nullif(trim(p_payload->>'tax_id'),''),nullif(trim(p_payload->>'phone'),''),nullif(trim(p_payload->>'email'),''),nullif(trim(p_payload->>'address'),''),true);
 elsif e='product' then
   if not (public.has_permission('products.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
   if nullif(trim(p_payload->>'sku'),'') is null or nullif(trim(p_payload->>'name'),'') is null then raise exception 'SKU y nombre requeridos'; end if;
   insert into public.products(id,company_id,sku,name,category,cost,price,tax,min_stock,active)
   values(rid,cid,trim(p_payload->>'sku'),trim(p_payload->>'name'),coalesce(nullif(trim(p_payload->>'category'),''),'General'),coalesce((p_payload->>'cost')::numeric,0),coalesce((p_payload->>'price')::numeric,0),coalesce((p_payload->>'tax')::numeric,0),coalesce((p_payload->>'min_stock')::numeric,0),true);
   insert into public.inventory(company_id,branch_id,product_id,stock,reserved)
   select cid,b.id,rid,0,0 from public.branches b where b.company_id=cid and b.active=true
   on conflict(branch_id,product_id) do nothing;
 else raise exception 'Entidad no permitida'; end if;
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'CREATE',upper(e),rid::text,p_payload);
 return jsonb_build_object('id',rid,'entity',e);
end $$;

create or replace function public.atlas_update_master(p_entity text,p_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); e text:=lower(trim(p_entity));
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if e='customer' then
   if not (public.has_permission('customers.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
   update public.customers set
    code=coalesce(nullif(trim(p_payload->>'code'),''),code),name=coalesce(nullif(trim(p_payload->>'name'),''),name),
    tax_id=case when p_payload ? 'tax_id' then nullif(trim(p_payload->>'tax_id'),'') else tax_id end,
    phone=case when p_payload ? 'phone' then nullif(trim(p_payload->>'phone'),'') else phone end,
    email=case when p_payload ? 'email' then nullif(trim(p_payload->>'email'),'') else email end,
    address=case when p_payload ? 'address' then nullif(trim(p_payload->>'address'),'') else address end
   where id=p_id and company_id=cid;
 elsif e='supplier' then
   if not (public.has_permission('suppliers.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
   update public.suppliers set
    code=coalesce(nullif(trim(p_payload->>'code'),''),code),name=coalesce(nullif(trim(p_payload->>'name'),''),name),
    tax_id=case when p_payload ? 'tax_id' then nullif(trim(p_payload->>'tax_id'),'') else tax_id end,
    phone=case when p_payload ? 'phone' then nullif(trim(p_payload->>'phone'),'') else phone end,
    email=case when p_payload ? 'email' then nullif(trim(p_payload->>'email'),'') else email end,
    address=case when p_payload ? 'address' then nullif(trim(p_payload->>'address'),'') else address end
   where id=p_id and company_id=cid;
 elsif e='product' then
   if not (public.has_permission('products.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
   update public.products set
    sku=coalesce(nullif(trim(p_payload->>'sku'),''),sku),name=coalesce(nullif(trim(p_payload->>'name'),''),name),
    category=coalesce(nullif(trim(p_payload->>'category'),''),category),
    cost=case when p_payload ? 'cost' then (p_payload->>'cost')::numeric else cost end,
    price=case when p_payload ? 'price' then (p_payload->>'price')::numeric else price end,
    tax=case when p_payload ? 'tax' then (p_payload->>'tax')::numeric else tax end,
    min_stock=case when p_payload ? 'min_stock' then (p_payload->>'min_stock')::numeric else min_stock end
   where id=p_id and company_id=cid;
 else raise exception 'Entidad no permitida'; end if;
 if not found then raise exception 'Registro no encontrado'; end if;
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'UPDATE',upper(e),p_id::text,p_payload);
 return jsonb_build_object('id',p_id,'entity',e);
end $$;

revoke all on function public.atlas_create_master(text,jsonb) from public;
revoke all on function public.atlas_update_master(text,uuid,jsonb) from public;
grant execute on function public.atlas_create_master(text,jsonb) to authenticated;
grant execute on function public.atlas_update_master(text,uuid,jsonb) to authenticated;
