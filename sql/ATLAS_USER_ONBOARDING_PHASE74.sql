-- ATLAS Fase 74 — Alta segura de perfiles para usuarios Auth existentes
-- Esta RPC NO crea contraseñas ni usuarios en Supabase Auth.
-- El usuario debe existir primero en auth.users. El administrador de ATLAS
-- únicamente lo vincula a su empresa, rol y sucursales sin exponer service_role.

create or replace function public.atlas_link_auth_user(
 p_user_id uuid,
 p_full_name text,
 p_role_id uuid,
 p_branch_ids uuid[],
 p_active boolean default true
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
 cid uuid:=public.current_company_id();
 b uuid;
 all_branches boolean:=false;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('settings.manage') or public.has_permission('*')) then
   raise exception 'Permiso insuficiente';
 end if;
 if p_user_id is null then raise exception 'UUID de Auth requerido'; end if;
 if nullif(btrim(coalesce(p_full_name,'')),'') is null then raise exception 'Nombre requerido'; end if;
 if not exists(select 1 from auth.users where id=p_user_id) then
   raise exception 'El usuario no existe en Supabase Authentication';
 end if;
 if exists(select 1 from public.profiles where id=p_user_id and company_id<>cid) then
   raise exception 'El usuario ya pertenece a otra empresa';
 end if;
 if not exists(select 1 from public.roles where id=p_role_id and company_id=cid) then
   raise exception 'Rol inválido';
 end if;
 select permissions ? 'branches.all' into all_branches
 from public.roles where id=p_role_id and company_id=cid;
 foreach b in array coalesce(p_branch_ids,array[]::uuid[]) loop
   if not exists(select 1 from public.branches where id=b and company_id=cid and active=true) then
     raise exception 'Sucursal inválida';
   end if;
 end loop;
 if not all_branches and cardinality(coalesce(p_branch_ids,array[]::uuid[]))=0 then
   raise exception 'Selecciona al menos una sucursal';
 end if;

 insert into public.profiles(id,company_id,full_name,status)
 values(p_user_id,cid,btrim(p_full_name),case when p_active then 'ACTIVE' else 'INACTIVE' end)
 on conflict(id) do update set
   full_name=excluded.full_name,
   status=excluded.status
 where public.profiles.company_id=cid;

 insert into public.user_roles(user_id,role_id) values(p_user_id,p_role_id)
 on conflict(user_id) do update set role_id=excluded.role_id;
 delete from public.user_branches where user_id=p_user_id;
 if not all_branches then
   insert into public.user_branches(user_id,branch_id)
   select p_user_id,x from unnest(coalesce(p_branch_ids,array[]::uuid[])) x;
 end if;

 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'CREATE','USER_PROFILE',p_user_id::text,
   jsonb_build_object('full_name',btrim(p_full_name),'role_id',p_role_id,
     'branch_ids',coalesce(p_branch_ids,array[]::uuid[]),'active',p_active));
 return jsonb_build_object('id',p_user_id,'active',p_active);
end $$;

revoke all on function public.atlas_link_auth_user(uuid,text,uuid,uuid[],boolean) from public;
grant execute on function public.atlas_link_auth_user(uuid,text,uuid,uuid[],boolean) to authenticated;
