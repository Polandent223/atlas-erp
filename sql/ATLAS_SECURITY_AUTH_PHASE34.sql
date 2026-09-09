create or replace function public.current_user_scope()
returns jsonb language sql stable security definer set search_path=public as $$
select jsonb_build_object('user_id',p.id,'company_id',p.company_id,'full_name',p.full_name,'status',p.status,'role',r.name,'permissions',coalesce(r.permissions,'[]'::jsonb),'branches',coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'name',b.name,'code',b.code)) from public.user_branches ub join public.branches b on b.id=ub.branch_id where ub.user_id=p.id and b.active=true),'[]'::jsonb))
from public.profiles p left join public.user_roles ur on ur.user_id=p.id left join public.roles r on r.id=ur.role_id where p.id=auth.uid() and p.status='ACTIVE' $$;
revoke all on function public.current_user_scope() from public;
grant execute on function public.current_user_scope() to authenticated;
drop policy if exists atlas_profile_self on public.profiles;
create policy atlas_profile_self on public.profiles for select to authenticated using(id=auth.uid() and company_id=public.current_company_id());
