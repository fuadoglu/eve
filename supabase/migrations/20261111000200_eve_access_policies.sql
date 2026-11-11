-- EVE-006.2 foundation: client roles have no app_private base access.
-- This migration only exposes read-only property scope checks; domain writes remain closed.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'app_executor') then
    create role app_executor nologin nobypassrls noinherit;
  end if;
end $$;
do $$
begin
  if exists (
    select 1 from pg_roles r where r.rolname='app_executor'
      and (r.rolcanlogin or r.rolbypassrls or r.rolsuper or r.rolcreatedb
           or r.rolcreaterole or r.rolreplication or r.rolinherit)
  ) or exists (
    select 1 from pg_auth_members m
    where m.member='app_executor'::regrole
      or (m.roleid='app_executor'::regrole and
          (m.inherit_option or m.set_option or
           m.member not in (current_user::regrole, coalesce(to_regrole('postgres'),current_user::regrole))))
  ) then
    raise exception 'app_executor has an unsafe role attribute or membership';
  end if;
end $$;

grant usage on schema app_private to app_executor;
grant select on app_private.profiles, app_private.owner_accounts,
  app_private.properties, app_private.property_memberships to app_executor;

-- Hosted Supabase does not grant custom roles USAGE on the auth schema.
-- Read only the JWT settings supplied by the verified Data API request.
create function app_private.current_actor_id()
returns uuid
language sql stable security invoker set search_path = ''
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
  )::uuid;
$$;
revoke all on function app_private.current_actor_id() from public, anon, authenticated;
grant execute on function app_private.current_actor_id() to app_executor;

create policy profiles_self_read on app_private.profiles
  for select to app_executor using (user_id = (select app_private.current_actor_id()));
create policy owner_accounts_self_read on app_private.owner_accounts
  for select to app_executor using (owner_user_id = (select app_private.current_actor_id()));

create function app_private.is_owner(p_owner_account_id uuid)
returns boolean
language sql stable security invoker set search_path = ''
as $$
  select (select app_private.current_actor_id()) is not null and exists (
    select 1 from app_private.owner_accounts a
    where a.id = p_owner_account_id and a.owner_user_id = (select app_private.current_actor_id())
  );
$$;
revoke all on function app_private.is_owner(uuid) from public, anon, authenticated;
grant execute on function app_private.is_owner(uuid) to app_executor;

create policy property_memberships_self_or_owner_read on app_private.property_memberships
  for select to app_executor
  using (user_id = (select app_private.current_actor_id()) or app_private.is_owner(owner_account_id));

create function app_private.has_property_capability(
  p_property_id uuid, p_owner_account_id uuid, p_capability text
)
returns boolean
language sql stable security invoker set search_path = ''
as $$
  select case
    when (select app_private.current_actor_id()) is null or p_property_id is null or p_owner_account_id is null then false
    when p_capability is null
      or p_capability not in ('property.read', 'reservation.read', 'finance.read') then false
    when app_private.is_owner(p_owner_account_id) then true
    else exists (
      select 1 from app_private.property_memberships m
      where m.property_id = p_property_id
        and m.owner_account_id = p_owner_account_id
        and m.user_id = (select app_private.current_actor_id())
        and m.revoked_at is null
        and (p_capability <> 'finance.read' or m.permission = 'full')
    )
  end;
$$;
revoke all on function app_private.has_property_capability(uuid,uuid,text)
  from public, anon, authenticated;
grant execute on function app_private.has_property_capability(uuid,uuid,text)
  to app_executor;

create policy properties_scoped_read on app_private.properties
  for select to app_executor
  using (app_private.has_property_capability(id,owner_account_id,'property.read'));

-- Narrow RPC: caller supplies only property id/capability; owner is derived from the row.
-- The exposed function owner is neither table owner nor BYPASSRLS.
grant usage, create on schema api to app_executor;
create function api.has_property_capability(p_property_id uuid, p_capability text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select coalesce((
    select app_private.has_property_capability(p.id,p.owner_account_id,p_capability)
    from app_private.properties p where p.id=p_property_id
  ),false);
$$;
revoke all on function api.has_property_capability(uuid,text)
  from public, anon, authenticated;
-- Supabase's migration role must be able to SET ROLE to the new function owner.
-- Revoke this temporary membership in the same migration transaction.
grant app_executor to current_user with set true, inherit false;
alter function api.has_property_capability(uuid,text) owner to app_executor;
revoke app_executor from current_user;
revoke create on schema api from app_executor;
grant usage on schema api to authenticated;
grant execute on function api.has_property_capability(uuid,text) to authenticated;
