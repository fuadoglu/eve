-- Local SQL role-switch fixture for the internal property list, not Data API proof.
do $$
begin
  if not exists (
    select 1 from pg_proc p
    where p.oid='api.list_visible_property_summaries(uuid,integer)'::regprocedure
      and p.proowner='app_executor'::regrole and p.prosecdef
      and p.proconfig @> array['search_path=""']::text[]
  ) or has_function_privilege('anon',
       'api.list_visible_property_summaries(uuid,integer)','EXECUTE')
    or has_table_privilege('authenticated','app_private.properties','SELECT') then
    raise exception 'property list function owner or grant boundary is unsafe';
  end if;
end $$;

-- The earlier access smoke created A1/B1 and revoked M's A1 membership.
insert into app_private.properties(id,owner_account_id,name,area) values
 ('55555555-5555-5555-5555-555555555555','11111111-1111-1111-1111-111111111111','A2','Bakı'),
 ('66666666-6666-6666-6666-666666666666','22222222-2222-2222-2222-222222222222','B2','Bakı');
update app_private.property_memberships set revoked_at=null
where property_id='33333333-3333-3333-3333-333333333333'
  and user_id='cccccccc-cccc-cccc-cccc-cccccccccccc';
-- Owner A also manages B2: owner and manager identities coexist.
insert into app_private.property_memberships
  (owner_account_id,property_id,user_id,permission,granted_by) values
  ('22222222-2222-2222-2222-222222222222',
   '66666666-6666-6666-6666-666666666666',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','daily',
   'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

begin;
set local role authenticated;
set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
do $$
declare seen uuid[];
begin
  select coalesce(array_agg(property_id order by property_id),array[]::uuid[])
    into seen from api.list_visible_property_summaries();
  if seen <> array[
    '33333333-3333-3333-3333-333333333333'::uuid,
    '55555555-5555-5555-5555-555555555555'::uuid,
    '66666666-6666-6666-6666-666666666666'::uuid] then
    raise exception 'owner A or manager-on-B2 list mismatch: %',seen;
  end if;
end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
do $$
declare seen uuid[];
begin
  select coalesce(array_agg(property_id order by property_id),array[]::uuid[])
    into seen from api.list_visible_property_summaries();
  if seen <> array[
    '44444444-4444-4444-4444-444444444444'::uuid,
    '66666666-6666-6666-6666-666666666666'::uuid] then
    raise exception 'owner B list mismatch: %',seen;
  end if;
end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
do $$
declare seen uuid[];
begin
  select coalesce(array_agg(property_id order by property_id),array[]::uuid[])
    into seen from api.list_visible_property_summaries();
  if seen <> array[
    '33333333-3333-3333-3333-333333333333'::uuid,
    '44444444-4444-4444-4444-444444444444'::uuid] then
    raise exception 'manager M list mismatch: %',seen;
  end if;
  select coalesce(array_agg(property_id order by property_id),array[]::uuid[])
    into seen from api.list_visible_property_summaries(null,1);
  if seen <> array['33333333-3333-3333-3333-333333333333'::uuid] then
    raise exception 'first page mismatch: %',seen;
  end if;
  select coalesce(array_agg(property_id order by property_id),array[]::uuid[])
    into seen from api.list_visible_property_summaries(
      '33333333-3333-3333-3333-333333333333',1);
  if seen <> array['44444444-4444-4444-4444-444444444444'::uuid] then
    raise exception 'second page mismatch: %',seen;
  end if;
  if exists (select 1 from api.list_visible_property_summaries(null,101))
     or exists (select 1 from api.list_visible_property_summaries(null,0))
     or exists (select 1 from api.list_visible_property_summaries(null,null)) then
    raise exception 'invalid page size accepted';
  end if;
  begin
    execute 'select id from app_private.properties limit 1';
    raise exception 'authenticated direct base read unexpectedly worked';
  exception when insufficient_privilege then null;
  end;
end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '';
do $$ begin
  if exists (select 1 from api.list_visible_property_summaries()) then
    raise exception 'missing JWT actor returned a property';
  end if;
end $$;
rollback;

update app_private.property_memberships set revoked_at=now()
where property_id='33333333-3333-3333-3333-333333333333'
  and user_id='cccccccc-cccc-cccc-cccc-cccccccccccc';
begin;
set local role authenticated;
set local request.jwt.claim.sub = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
do $$
declare seen uuid[];
begin
  select coalesce(array_agg(property_id order by property_id),array[]::uuid[])
    into seen from api.list_visible_property_summaries();
  if seen <> array['44444444-4444-4444-4444-444444444444'::uuid] then
    raise exception 'revoked A1 remained visible or B1 disappeared: %',seen;
  end if;
end $$;
rollback;
