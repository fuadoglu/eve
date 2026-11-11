-- Local role-switched SQL harness. auth.users and request JWT settings are stubs, not JWT proof.
do $$
begin
  if not exists (
    select 1 from pg_roles where rolname='app_executor'
      and not rolcanlogin and not rolbypassrls and not rolsuper
      and not rolcreatedb and not rolcreaterole and not rolreplication and not rolinherit
  ) then
    raise exception 'executor role must be low privilege';
  end if;
  if exists (
    select 1 from pg_auth_members m
    where m.member='app_executor'::regrole
      or (m.roleid='app_executor'::regrole and
          (m.inherit_option or m.set_option or
           m.member not in (current_user::regrole, coalesce(to_regrole('postgres'),current_user::regrole))))
  ) then raise exception 'unsafe executor role membership leaked after migration'; end if;
  if exists (
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='app_private' and c.relkind='r' and c.relowner='app_executor'::regrole
  ) then raise exception 'executor owns a base table'; end if;
  if has_schema_privilege('authenticated','app_private','USAGE')
     or has_table_privilege('authenticated','app_private.properties','SELECT')
     or has_schema_privilege('anon','api','USAGE')
     or has_schema_privilege('app_executor','auth','USAGE')
     or has_function_privilege('anon','api.has_property_capability(uuid,text)','EXECUTE') then
    raise exception 'client base access or anon RPC leaked';
  end if;
  if not exists (
    select 1 from pg_proc p
    where p.oid='api.has_property_capability(uuid,text)'::regprocedure
      and p.proowner='app_executor'::regrole and p.prosecdef
      and p.proconfig @> array['search_path=""']::text[]
  ) then raise exception 'RPC owner/definer/search_path mismatch'; end if;
end $$;

insert into auth.users(id) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
 ('cccccccc-cccc-cccc-cccc-cccccccccccc');
insert into app_private.owner_accounts(id,owner_user_id) values
 ('11111111-1111-1111-1111-111111111111','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
 ('22222222-2222-2222-2222-222222222222','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
insert into app_private.properties(id,owner_account_id,name,area) values
 ('33333333-3333-3333-3333-333333333333','11111111-1111-1111-1111-111111111111','A1','Bakı'),
 ('44444444-4444-4444-4444-444444444444','22222222-2222-2222-2222-222222222222','B1','Bakı');
insert into app_private.property_memberships(owner_account_id,property_id,user_id,permission,granted_by) values
 ('11111111-1111-1111-1111-111111111111','33333333-3333-3333-3333-333333333333','cccccccc-cccc-cccc-cccc-cccccccccccc','daily','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
 ('22222222-2222-2222-2222-222222222222','44444444-4444-4444-4444-444444444444','cccccccc-cccc-cccc-cccc-cccccccccccc','full','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

begin;
set local role authenticated;
do $$ begin
  if api.has_property_capability('33333333-3333-3333-3333-333333333333','property.read') is distinct from false then
    raise exception 'missing JWT actor unexpectedly accepted';
  end if;
end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}';
do $$ begin
  if not api.has_property_capability('33333333-3333-3333-3333-333333333333','property.read') then
    raise exception 'verified claims fallback did not resolve owner';
  end if;
end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
do $$ begin
  if not api.has_property_capability('33333333-3333-3333-3333-333333333333','property.read')
     or api.has_property_capability('44444444-4444-4444-4444-444444444444','property.read') then
    raise exception 'owner tenant access mismatch';
  end if;
  begin
    execute 'select id from app_private.properties limit 1';
    raise exception 'authenticated raw table select unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
do $$ begin
  if not api.has_property_capability('33333333-3333-3333-3333-333333333333','reservation.read')
     or api.has_property_capability('33333333-3333-3333-3333-333333333333','finance.read')
     or not api.has_property_capability('44444444-4444-4444-4444-444444444444','finance.read')
     or api.has_property_capability('33333333-3333-3333-3333-333333333333','owner') then
    raise exception 'daily/full capability mismatch';
  end if;
  if api.has_property_capability('33333333-3333-3333-3333-333333333333',null) is distinct from false
     or api.has_property_capability('33333333-3333-3333-3333-333333333333','unknown') is distinct from false then
    raise exception 'null/unknown capability accepted';
  end if;
end $$;
rollback;

update app_private.property_memberships set revoked_at=now()
where property_id='33333333-3333-3333-3333-333333333333';
begin;
set local role authenticated;
set local request.jwt.claim.sub = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
do $$ begin
  if api.has_property_capability('33333333-3333-3333-3333-333333333333','property.read')
     or not api.has_property_capability('44444444-4444-4444-4444-444444444444','property.read') then
    raise exception 'revocation did not apply on next request';
  end if;
end $$;
rollback;
