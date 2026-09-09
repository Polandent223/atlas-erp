-- ATLAS ERP - PATCH DE CONEXION FASE 47
create or replace function public.current_user_scope()
returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object(
  'user_id',p.id,'company_id',p.company_id,'full_name',p.full_name,'status',p.status,
  'role_id',(select ur.role_id from public.user_roles ur where ur.user_id=p.id limit 1),
  'branch_ids',coalesce((select jsonb_agg(ub.branch_id) from public.user_branches ub where ub.user_id=p.id),'[]'::jsonb)
 )
 from public.profiles p where p.id=auth.uid() and p.status='ACTIVE'
$$;

create or replace function public.atlas_healthcheck()
returns text language sql stable security definer set search_path=public as $$
 select case when auth.uid() is null then 'ATLAS conectado; sesión no iniciada'
 when public.current_company_id() is null then 'ATLAS autenticado; perfil sin empresa'
 else 'ATLAS conectado y autenticado' end
$$;

create or replace function public.atlas_write_audit(p_action text,p_entity text,p_detail jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id();
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 insert into public.audit_log(company_id,user_id,action,entity,detail)
 values(cid,auth.uid(),p_action,p_entity,coalesce(p_detail,'{}'::jsonb));
end $$;

create or replace function public.atlas_workspace_snapshot()
returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object(
  'company',(select to_jsonb(c) from public.companies c where c.id=public.current_company_id()),
  'profile',(select to_jsonb(p) from public.profiles p where p.id=auth.uid()),
  'role',(select to_jsonb(r) from public.roles r join public.user_roles ur on ur.role_id=r.id where ur.user_id=auth.uid() limit 1),
  'branches',(select coalesce(jsonb_agg(to_jsonb(b)),'[]'::jsonb) from public.branches b
              where b.company_id=public.current_company_id() and public.can_access_branch(b.id))
 )
$$;

revoke all on function public.current_user_scope() from public;
revoke all on function public.atlas_healthcheck() from public;
revoke all on function public.atlas_write_audit(text,text,jsonb) from public;
revoke all on function public.atlas_workspace_snapshot() from public;
grant execute on function public.current_user_scope() to authenticated;
grant execute on function public.atlas_healthcheck() to authenticated;
grant execute on function public.atlas_write_audit(text,text,jsonb) to authenticated;
grant execute on function public.atlas_workspace_snapshot() to authenticated;

select 'ATLAS CONNECTION PATCH READY' as estado,
 (select count(*) from public.companies) as empresas,
 (select count(*) from public.profiles) as perfiles,
 (select count(*) from public.branches) as sucursales;
