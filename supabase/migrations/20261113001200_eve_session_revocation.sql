-- EVE-007.2: scoped application session revocation for logout-all.
-- session_id is stable across access-token refresh. The active guard also
-- checks auth.sessions so provider-revoked JWTs fail closed before expiring.
do $$
begin
  if not exists (select 1 from pg_roles where rolname='app_executor') then
    raise exception 'app_executor must exist before session revocation migration';
  end if;
  if not exists (select 1 from pg_roles where rolname='app_session_reader') then
    create role app_session_reader nologin nobypassrls noinherit;
  end if;
  if exists (
    select 1 from pg_roles r where r.rolname='app_session_reader'
      and (r.rolcanlogin or r.rolbypassrls or r.rolsuper or r.rolcreatedb
           or r.rolcreaterole or r.rolreplication or r.rolinherit)
  ) or exists (
    select 1 from pg_auth_members m
    where m.member='app_session_reader'::regrole
      or (m.roleid='app_session_reader'::regrole and
          (m.inherit_option or m.set_option or
           m.member not in (current_user::regrole, coalesce(to_regrole('postgres'),current_user::regrole))))
  ) then
    raise exception 'app_session_reader has an unsafe role attribute or membership';
  end if;
end $$;

grant usage on schema app_private, auth to app_session_reader;
grant select (user_id, session_revoked_before) on app_private.profiles to app_session_reader;
grant execute on function app_private.current_actor_id() to app_session_reader;
grant select (id, user_id, created_at) on auth.sessions to app_session_reader;

create policy profiles_session_reader_self on app_private.profiles
  for select to app_session_reader
  using (user_id = (select app_private.current_actor_id()));

grant insert (user_id), update (session_revoked_before, updated_at, version)
  on app_private.profiles to app_executor;

create policy profiles_self_session_insert on app_private.profiles
  for insert to app_executor
  with check (user_id = (select app_private.current_actor_id()));

create policy profiles_self_session_update on app_private.profiles
  for update to app_executor
  using (user_id = (select app_private.current_actor_id()))
  with check (user_id = (select app_private.current_actor_id()));

create function api.is_my_session_active()
returns boolean
language plpgsql stable security definer set search_path = ''
as $$
declare
  actor_id uuid := app_private.current_actor_id();
  session_id uuid;
  session_created_at timestamptz;
  revoked_before timestamptz;
  claims jsonb;
begin
  if actor_id is null then return false; end if;
  begin
    claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
    session_id := nullif(claims ->> 'session_id', '')::uuid;
  exception when others then
    return false;
  end;
  if session_id is null then return false; end if;

  select s.created_at into session_created_at
  from auth.sessions s
  where s.id = session_id and s.user_id = actor_id;
  if not found then return false; end if;

  select p.session_revoked_before into revoked_before
  from app_private.profiles p where p.user_id = actor_id;
  if not found then return true; end if;
  return coalesce(revoked_before is null or session_created_at > revoked_before, false);
end;
$$;
revoke all on function api.is_my_session_active() from public, anon, authenticated;
grant execute on function api.is_my_session_active() to authenticated;

create function api.revoke_my_sessions()
returns boolean
language plpgsql volatile security definer set search_path = ''
as $$
declare
  actor_id uuid := app_private.current_actor_id();
  revoked_at timestamptz := clock_timestamp();
begin
  if actor_id is null then
    raise exception using errcode = '42501', message = 'authenticated user required';
  end if;

  insert into app_private.profiles(user_id, session_revoked_before, updated_at)
    values (actor_id, revoked_at, revoked_at)
  on conflict (user_id) do update
    set session_revoked_before = greatest(
          coalesce(app_private.profiles.session_revoked_before, '-infinity'::timestamptz),
          excluded.session_revoked_before
        ),
        updated_at = excluded.updated_at,
        version = app_private.profiles.version + 1;
  return true;
end;
$$;
revoke all on function api.revoke_my_sessions() from public, anon, authenticated;
grant execute on function api.revoke_my_sessions() to authenticated;

-- Transfer only reviewed RPC ownership to narrowly privileged roles.
grant create on schema api to app_session_reader;
grant app_session_reader to current_user with set true, inherit false;
alter function api.is_my_session_active() owner to app_session_reader;
revoke app_session_reader from current_user;
revoke create on schema api from app_session_reader;
grant app_executor to current_user with set true, inherit false;
alter function api.revoke_my_sessions() owner to app_executor;
revoke app_executor from current_user;
