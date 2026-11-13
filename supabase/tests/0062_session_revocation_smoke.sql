-- Local PostgreSQL smoke; auth.sessions and JWT claims are synthetic fixtures.
do $$
declare mismatch_count integer;
begin
  select count(*) into mismatch_count
  from pg_proc p
  where p.oid in ('api.is_my_session_active()'::regprocedure,'api.revoke_my_sessions()'::regprocedure)
    and (not p.prosecdef
      or not (coalesce(p.proconfig,array[]::text[]) @> array['search_path=""']::text[])
      or has_function_privilege('anon',p.oid,'EXECUTE')
      or not has_function_privilege('authenticated',p.oid,'EXECUTE'));
  if mismatch_count <> 0 then raise exception 'session RPC security configuration mismatch'; end if;
  if (select proowner from pg_proc where oid='api.is_my_session_active()'::regprocedure) <> 'app_session_reader'::regrole
    or (select proowner from pg_proc where oid='api.revoke_my_sessions()'::regprocedure) <> 'app_executor'::regrole then
    raise exception 'session RPC must use the scoped owner roles';
  end if;
  if (select rolbypassrls or rolsuper or rolcanlogin
      from pg_roles where rolname='app_session_reader')
     or not (select relrowsecurity from pg_class where oid='auth.sessions'::regclass)
     or not exists (
       select 1 from pg_policy p
       where p.polrelid='auth.sessions'::regclass
         and p.polname='sessions_session_reader_self'
         and p.polcmd='r'
         and p.polroles=array['app_session_reader'::regrole::oid]
     ) then
    raise exception 'Auth session reader must be non-bypass and actor-scoped';
  end if;
  if has_table_privilege('authenticated','app_private.profiles','UPDATE')
     or has_table_privilege('authenticated','app_private.profiles','INSERT')
     or has_table_privilege('app_session_reader','auth.sessions','DELETE')
     or has_table_privilege('app_session_reader','auth.sessions','UPDATE') then
    raise exception 'session roles have excessive privileges';
  end if;
  if not has_schema_privilege('app_session_reader','auth','USAGE')
     or not has_column_privilege('app_session_reader','auth.sessions','id','SELECT')
     or not has_column_privilege('app_session_reader','auth.sessions','user_id','SELECT')
     or not has_column_privilege('app_session_reader','auth.sessions','created_at','SELECT') then
    raise exception 'session reader Auth schema/column grants missing';
  end if;
end $$;

begin;
insert into auth.users(id) values
 ('f7000000-0000-0000-0000-000000000001'),
 ('f7000000-0000-0000-0000-000000000002');
insert into auth.sessions(id,user_id,created_at) values
 ('f7100000-0000-0000-0000-000000000001','f7000000-0000-0000-0000-000000000001',clock_timestamp()),
 ('f7100000-0000-0000-0000-000000000002','f7000000-0000-0000-0000-000000000002',clock_timestamp());

set local role authenticated;
set local request.jwt.claims = '{"sub":"f7000000-0000-0000-0000-000000000001","session_id":"f7100000-0000-0000-0000-000000000001","iat":1800000000}';
do $$ begin
  if not api.is_my_session_active() then raise exception 'new session without profile must be eligible'; end if;
  if api.revoke_my_sessions() is distinct from true then raise exception 'logout-all cutoff was not recorded'; end if;
  if api.is_my_session_active() is distinct from false then raise exception 'pre-cutoff session remained active'; end if;
  begin
    execute 'update app_private.profiles set session_revoked_before = null';
    raise exception 'authenticated direct profile write unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;

-- A refreshed JWT retains session_id; changing iat cannot resurrect it.
set local request.jwt.claims = '{"sub":"f7000000-0000-0000-0000-000000000001","session_id":"f7100000-0000-0000-0000-000000000001","iat":1999999999}';
do $$ begin
  if api.is_my_session_active() is distinct from false then
    raise exception 'refresh of a pre-cutoff session bypassed revocation';
  end if;
end $$;

-- Create the provider fixture outside the API role, then query it as authenticated.
reset role;
insert into auth.sessions(id,user_id,created_at) values
 ('f7100000-0000-0000-0000-000000000003','f7000000-0000-0000-0000-000000000001',clock_timestamp() + interval '1 second');
set local role authenticated;
set local request.jwt.claims = '{"sub":"f7000000-0000-0000-0000-000000000001","session_id":"f7100000-0000-0000-0000-000000000003","iat":1800000000}';
do $$ begin
  if not api.is_my_session_active() then raise exception 'new post-cutoff session was rejected'; end if;
end $$;

set local request.jwt.claims = '{"sub":"f7000000-0000-0000-0000-000000000002","session_id":"f7100000-0000-0000-0000-000000000002","iat":1800000000}';
do $$ begin
  if not api.is_my_session_active() then raise exception 'one user logout-all affected another user'; end if;
end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"f7000000-0000-0000-0000-000000000001","iat":1800000000}';
do $$ begin
  if api.is_my_session_active() is distinct from false then raise exception 'session without session_id was accepted'; end if;
end $$;
rollback;

begin;
set local role anon;
do $$ begin
  begin
    perform api.is_my_session_active();
    raise exception 'anonymous session RPC execution unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;
rollback;
