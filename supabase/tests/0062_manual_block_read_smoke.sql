-- Private calendar read fixture; this is not public availability proof.
do $$
begin
  if has_function_privilege('anon',
       'api.list_current_manual_blocks(uuid,date,date,uuid,integer)','EXECUTE')
     or has_table_privilege('authenticated','app_private.manual_blocks','SELECT')
     or not exists (
       select 1 from pg_proc p
       where p.oid='api.list_current_manual_blocks(uuid,date,date,uuid,integer)'::regprocedure
         and p.proowner='app_executor'::regrole and p.prosecdef
         and p.proconfig @> array['search_path=""']::text[]
     ) then
    raise exception 'private block read grant/owner/search_path mismatch';
  end if;
end $$;

-- A1 membership was revoked by the property-list smoke. Restore it for M.
update app_private.property_memberships set revoked_at=null
where property_id='33333333-3333-3333-3333-333333333333'
  and user_id='cccccccc-cccc-cccc-cccc-cccccccccccc';
insert into app_private.manual_blocks
  (id,owner_account_id,property_id,check_in,check_out,reason,released_at)
values
 ('70000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111',
  '33333333-3333-3333-3333-333333333333','2027-07-01','2027-07-04','A1 private reason',null),
 ('71000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111',
  '33333333-3333-3333-3333-333333333333','2027-07-10','2027-07-12','A1 second reason',null),
 ('72000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111',
  '33333333-3333-3333-3333-333333333333','2027-07-06','2027-07-08','Released',now()),
 ('80000000-0000-0000-0000-000000000001','22222222-2222-2222-2222-222222222222',
  '44444444-4444-4444-4444-444444444444','2027-07-02','2027-07-05','B1 private reason',null),
 ('90000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111',
  '55555555-5555-5555-5555-555555555555','2027-07-03','2027-07-06','A2 private reason',null),
 ('a0000000-0000-0000-0000-000000000001','22222222-2222-2222-2222-222222222222',
  '66666666-6666-6666-6666-666666666666','2027-07-04','2027-07-07','B2 private reason',null);

begin;
set local role authenticated;
set local request.jwt.claim.sub='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
do $$ begin
  if (select count(*) from api.list_current_manual_blocks(
       '33333333-3333-3333-3333-333333333333','2027-07-01','2027-07-13')) <> 2
     or (select count(*) from api.list_current_manual_blocks(
       '55555555-5555-5555-5555-555555555555','2027-07-01','2027-07-13')) <> 1
     or exists (select 1 from api.list_current_manual_blocks(
       '44444444-4444-4444-4444-444444444444','2027-07-01','2027-07-13')) then
    raise exception 'owner A private block scope mismatch';
  end if;
end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
do $$ begin
  if (select count(*) from api.list_current_manual_blocks(
       '44444444-4444-4444-4444-444444444444','2027-07-01','2027-07-13')) <> 1
     or (select count(*) from api.list_current_manual_blocks(
       '66666666-6666-6666-6666-666666666666','2027-07-01','2027-07-13')) <> 1
     or exists (select 1 from api.list_current_manual_blocks(
       '33333333-3333-3333-3333-333333333333','2027-07-01','2027-07-13')) then
    raise exception 'owner B private block scope mismatch';
  end if;
end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub='cccccccc-cccc-cccc-cccc-cccccccccccc';
do $$
declare seen uuid[];
begin
  select coalesce(array_agg(block_id order by block_id),array[]::uuid[])
    into seen from api.list_current_manual_blocks(
      '33333333-3333-3333-3333-333333333333','2027-07-01','2027-07-13',null,1);
  if seen <> array['70000000-0000-0000-0000-000000000001'::uuid] then
    raise exception 'private block first page mismatch: %',seen;
  end if;
  select coalesce(array_agg(block_id order by block_id),array[]::uuid[])
    into seen from api.list_current_manual_blocks(
      '33333333-3333-3333-3333-333333333333','2027-07-01','2027-07-13',
      '70000000-0000-0000-0000-000000000001',1);
  if seen <> array['71000000-0000-0000-0000-000000000001'::uuid] then
    raise exception 'private block second page mismatch: %',seen;
  end if;
  if exists (select 1 from api.list_current_manual_blocks(
       '33333333-3333-3333-3333-333333333333','2027-07-04','2027-07-05'))
     or exists (select 1 from api.list_current_manual_blocks(
       '33333333-3333-3333-3333-333333333333','2027-07-07','2027-07-08'))
     or (select count(*) from api.list_current_manual_blocks(
       '44444444-4444-4444-4444-444444444444','2027-07-04','2027-07-05')) <> 1
     or exists (select 1 from api.list_current_manual_blocks(
       '55555555-5555-5555-5555-555555555555','2027-07-01','2027-07-13')) then
    raise exception 'half-open date/released/manager scope mismatch';
  end if;
  if exists (select 1 from api.list_current_manual_blocks(
       '33333333-3333-3333-3333-333333333333','2027-07-01','2027-10-04'))
     or exists (select 1 from api.list_current_manual_blocks(
       '33333333-3333-3333-3333-333333333333','2027-07-01','2027-07-13',null,101))
     or exists (select 1 from api.list_current_manual_blocks(
       '33333333-3333-3333-3333-333333333333','2027-07-13','2027-07-01')) then
    raise exception 'invalid date/page window accepted';
  end if;
  begin
    execute 'select reason from app_private.manual_blocks limit 1';
    raise exception 'authenticated raw block read unexpectedly worked';
  exception when insufficient_privilege then null;
  end;
end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub='';
set local request.jwt.claims='';
do $$ begin
  if exists (select 1 from api.list_current_manual_blocks(
    '33333333-3333-3333-3333-333333333333','2027-07-01','2027-07-13')) then
    raise exception 'missing actor saw private block reason';
  end if;
end $$;
rollback;

update app_private.property_memberships set revoked_at=now()
where property_id='33333333-3333-3333-3333-333333333333'
  and user_id='cccccccc-cccc-cccc-cccc-cccccccccccc';
begin;
set local role authenticated;
set local request.jwt.claim.sub='cccccccc-cccc-cccc-cccc-cccccccccccc';
do $$ begin
  if exists (select 1 from api.list_current_manual_blocks(
       '33333333-3333-3333-3333-333333333333','2027-07-01','2027-07-13'))
     or (select count(*) from api.list_current_manual_blocks(
       '44444444-4444-4444-4444-444444444444','2027-07-01','2027-07-13')) <> 1 then
    raise exception 'A1 revoke failed or unrelated B1 access lost';
  end if;
end $$;
rollback;
