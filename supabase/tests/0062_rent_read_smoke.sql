-- EVE-006.2 AT04-06 local role-switched fixture. Synthetic move only; not
-- a move transaction, hosted Supabase JWT/Data API, or full RentEntryPage.
do $$ begin
  if has_table_privilege('anon','app_private.rent_entries','SELECT')
     or has_table_privilege('authenticated','app_private.rent_entries','SELECT')
     or has_function_privilege('anon',
       'api.list_reservation_rent_summaries(uuid,timestamptz,uuid,integer)','EXECUTE')
     or not has_table_privilege('app_executor','app_private.rent_entries','SELECT')
     or not exists (
       select 1 from pg_proc p
       where p.oid='api.list_reservation_rent_summaries(uuid,timestamptz,uuid,integer)'::regprocedure
         and p.proowner='app_executor'::regrole and p.prosecdef
         and p.proconfig @> array['search_path=""']::text[]
     ) then raise exception 'rent read grant/owner/search_path boundary failed'; end if;
  if pg_get_function_result(
       'api.list_reservation_rent_summaries(uuid,timestamptz,uuid,integer)'::regprocedure)
       ~ '(guest|note|actor|contact|operation_key|target)' then
    raise exception 'sensitive ledger field exposed in RPC signature';
  end if;
end $$;

insert into auth.users(id) values
 ('e1000000-0000-0000-0000-000000000001'), -- A owner
 ('e1000000-0000-0000-0000-000000000002'), -- B owner
 ('e1000000-0000-0000-0000-000000000003'), -- M A1 daily/B1 full
 ('e1000000-0000-0000-0000-000000000004'), -- source full
 ('e1000000-0000-0000-0000-000000000005'), -- target daily
 ('e1000000-0000-0000-0000-000000000006'); -- stranger
insert into app_private.owner_accounts(id,owner_user_id) values
 ('e1100000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001'),
 ('e1100000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000002');
insert into app_private.properties(id,owner_account_id,name,area) values
 ('e2100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000001','A1 finance','Bakı'),
 ('e2100000-0000-0000-0000-000000000002','e1100000-0000-0000-0000-000000000001','A2 finance','Bakı'),
 ('e2100000-0000-0000-0000-000000000003','e1100000-0000-0000-0000-000000000002','B1 finance','Bakı');
insert into app_private.property_memberships
 (owner_account_id,property_id,user_id,permission,granted_by) values
 ('e1100000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000001',
  'e1000000-0000-0000-0000-000000000003','daily','e1000000-0000-0000-0000-000000000001'),
 ('e1100000-0000-0000-0000-000000000002','e2100000-0000-0000-0000-000000000003',
  'e1000000-0000-0000-0000-000000000003','full','e1000000-0000-0000-0000-000000000002'),
 ('e1100000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000001',
  'e1000000-0000-0000-0000-000000000004','full','e1000000-0000-0000-0000-000000000001'),
 ('e1100000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000002',
  'e1000000-0000-0000-0000-000000000005','daily','e1000000-0000-0000-0000-000000000001');

begin;
set constraints all deferred;
insert into app_private.reservations
 (id,owner_account_id,property_id,current_placement_id,guest_name,guest_phone,
  check_in,check_out,check_in_time,check_out_time,total_minor) values
 ('e3100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000001',
  'e2100000-0000-0000-0000-000000000001','e4100000-0000-0000-0000-000000000001',
  'Synthetic A guest','+994501234567','2027-06-01','2027-06-04','14:00','12:00',30000),
 ('e3100000-0000-0000-0000-000000000002','e1100000-0000-0000-0000-000000000002',
  'e2100000-0000-0000-0000-000000000003','e4100000-0000-0000-0000-000000000002',
  'Synthetic B guest','+994501234567','2027-07-01','2027-07-04','14:00','12:00',20000);
insert into app_private.reservation_placements
 (id,owner_account_id,property_id,reservation_id,placement_no,
  check_in_snapshot,check_out_snapshot,effective_from,created_by) values
 ('e4100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000001',
  'e2100000-0000-0000-0000-000000000001','e3100000-0000-0000-0000-000000000001',
  1,'2027-06-01','2027-06-04',now(),'e1000000-0000-0000-0000-000000000001'),
 ('e4100000-0000-0000-0000-000000000002','e1100000-0000-0000-0000-000000000002',
  'e2100000-0000-0000-0000-000000000003','e3100000-0000-0000-0000-000000000002',
  1,'2027-07-01','2027-07-04',now(),'e1000000-0000-0000-0000-000000000002');
commit;
insert into app_private.rent_entries
 (id,owner_account_id,property_id,reservation_id,placement_id,kind,amount_minor,
  custodian,custodian_user_id,actor_id,occurred_at,note,operation_key) values
 ('e5100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000001',
  'e2100000-0000-0000-0000-000000000001','e3100000-0000-0000-0000-000000000001',
  'e4100000-0000-0000-0000-000000000001','rent_receipt',10000,'owner',
  'e1000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',
  '2027-05-01T09:00:00Z','Synthetic sensitive note A','rent-test-a-1'),
 ('e5100000-0000-0000-0000-000000000002','e1100000-0000-0000-0000-000000000001',
  'e2100000-0000-0000-0000-000000000001','e3100000-0000-0000-0000-000000000001',
  'e4100000-0000-0000-0000-000000000001','deposit_receipt',5000,'owner',
  'e1000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',
  '2027-05-01T09:00:00Z','Synthetic sensitive note B','rent-test-a-2'),
 ('e5100000-0000-0000-0000-000000000003','e1100000-0000-0000-0000-000000000002',
  'e2100000-0000-0000-0000-000000000003','e3100000-0000-0000-0000-000000000002',
  'e4100000-0000-0000-0000-000000000002','rent_receipt',7000,'owner',
  'e1000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000002',
  '2027-05-02T09:00:00Z','Synthetic B note','rent-test-b-1');

begin;
set local role authenticated;
set local request.jwt.claim.sub='e1000000-0000-0000-0000-000000000003';
do $$ begin
  if (select count(*) from api.list_reservation_rent_summaries(
      'e3100000-0000-0000-0000-000000000001')) <> 2
     or (select count(*) from api.list_reservation_rent_summaries(
      'e3100000-0000-0000-0000-000000000002')) <> 1
     or (select amount_minor from api.list_reservation_rent_summaries(
      'e3100000-0000-0000-0000-000000000001',null,null,1)) <> 10000
     or (select entry_id from api.list_reservation_rent_summaries(
      'e3100000-0000-0000-0000-000000000001',
      '2027-05-01T09:00:00Z','e5100000-0000-0000-0000-000000000001',1))
       is distinct from 'e5100000-0000-0000-0000-000000000002'::uuid then
    raise exception 'daily current/full B1 or stable keyset read failed';
  end if;
  begin
    execute 'select id from app_private.rent_entries limit 1';
    raise exception 'authenticated direct ledger read succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;
rollback;

-- Revocation is checked against the current membership on the next request;
-- the independently assigned B1 full scope remains available.
update app_private.property_memberships set revoked_at=now()
where property_id='e2100000-0000-0000-0000-000000000001'
  and user_id='e1000000-0000-0000-0000-000000000003';
begin;
set local role authenticated;
set local request.jwt.claim.sub='e1000000-0000-0000-0000-000000000003';
do $$ begin
  if exists (select 1 from api.list_reservation_rent_summaries(
       'e3100000-0000-0000-0000-000000000001'))
     or (select count(*) from api.list_reservation_rent_summaries(
       'e3100000-0000-0000-0000-000000000002')) <> 1 then
    raise exception 'A1 revoke or B1 independent access failed';
  end if;
end $$;
rollback;
update app_private.property_memberships set revoked_at=null
where property_id='e2100000-0000-0000-0000-000000000001'
  and user_id='e1000000-0000-0000-0000-000000000003';

begin;
set constraints all deferred;
insert into app_private.reservation_placements
 (id,owner_account_id,property_id,reservation_id,placement_no,
  check_in_snapshot,check_out_snapshot,effective_from,created_by) values
 ('e4100000-0000-0000-0000-000000000003','e1100000-0000-0000-0000-000000000001',
  'e2100000-0000-0000-0000-000000000002','e3100000-0000-0000-0000-000000000001',
  2,'2027-06-01','2027-06-04',now(),'e1000000-0000-0000-0000-000000000001');
update app_private.reservation_placements set effective_to=now()
where id='e4100000-0000-0000-0000-000000000001';
update app_private.reservations
set property_id='e2100000-0000-0000-0000-000000000002',
    current_placement_id='e4100000-0000-0000-0000-000000000003',version=version+1
where id='e3100000-0000-0000-0000-000000000001';
commit;
insert into app_private.rent_entries
 (id,owner_account_id,property_id,reservation_id,placement_id,kind,amount_minor,
  custodian,custodian_user_id,actor_id,occurred_at,note,operation_key) values
 ('e5100000-0000-0000-0000-000000000004','e1100000-0000-0000-0000-000000000001',
  'e2100000-0000-0000-0000-000000000002','e3100000-0000-0000-0000-000000000001',
  'e4100000-0000-0000-0000-000000000003','rent_receipt',4000,'owner',
  'e1000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',
  '2027-05-03T09:00:00Z','Synthetic destination note','rent-test-a-3');

begin;
set local role authenticated;
set local request.jwt.claim.sub='e1000000-0000-0000-0000-000000000003';
do $$ begin
  if exists (select 1 from api.list_reservation_rent_summaries(
      'e3100000-0000-0000-0000-000000000001'))
     or (select count(*) from api.list_reservation_rent_summaries(
      'e3100000-0000-0000-0000-000000000002')) <> 1 then
    raise exception 'source-only daily saw moved money or lost B1';
  end if;
end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub='e1000000-0000-0000-0000-000000000004';
do $$ begin
  if (select count(*) from api.list_reservation_rent_summaries(
      'e3100000-0000-0000-0000-000000000001')) <> 2
     or exists (select 1 from api.list_reservation_rent_summaries(
      'e3100000-0000-0000-0000-000000000002')) then
    raise exception 'source-full historical finance scope failed';
  end if;
end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub='e1000000-0000-0000-0000-000000000005';
do $$ begin
  if (select count(*) from api.list_reservation_rent_summaries(
      'e3100000-0000-0000-0000-000000000001')) <> 1
     or (select entry_id from api.list_reservation_rent_summaries(
      'e3100000-0000-0000-0000-000000000001'))
       is distinct from 'e5100000-0000-0000-0000-000000000004'::uuid then
    raise exception 'target-only daily saw source history or missed current money';
  end if;
end $$;
rollback;

begin;
set local role app_executor;
set local request.jwt.claim.sub='e1000000-0000-0000-0000-000000000003';
do $$ begin
  if exists (select 1 from app_private.rent_entries
      where reservation_id='e3100000-0000-0000-0000-000000000001')
     or (select count(*) from app_private.rent_entries
      where reservation_id='e3100000-0000-0000-0000-000000000002') <> 1 then
    raise exception 'executor row policy exposed moved source or hid B1';
  end if;
end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub='e1000000-0000-0000-0000-000000000001';
do $$ begin
  if (select count(*) from api.list_reservation_rent_summaries(
      'e3100000-0000-0000-0000-000000000001')) <> 3
     or exists (select 1 from api.list_reservation_rent_summaries(
      'e3100000-0000-0000-0000-000000000002')) then
    raise exception 'owner A history or cross-tenant isolation failed';
  end if;
end $$;
rollback;
begin;
set local role authenticated;
set local request.jwt.claim.sub='e1000000-0000-0000-0000-000000000002';
do $$ begin
  if exists (select 1 from api.list_reservation_rent_summaries(
      'e3100000-0000-0000-0000-000000000001'))
     or (select count(*) from api.list_reservation_rent_summaries(
      'e3100000-0000-0000-0000-000000000002')) <> 1 then
    raise exception 'owner B history or cross-tenant isolation failed';
  end if;
end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub='e1000000-0000-0000-0000-000000000006';
do $$ begin
  if exists (select 1 from api.list_reservation_rent_summaries(
      'e3100000-0000-0000-0000-000000000001'))
     or exists (select 1 from api.list_reservation_rent_summaries(
      'e3100000-0000-0000-0000-000000000002'))
     or exists (select 1 from api.list_reservation_rent_summaries(
      'e9100000-0000-0000-0000-000000000001')) then
    raise exception 'stranger or unknown ID exposed ledger rows';
  end if;
end $$;
rollback;
begin;
set local role authenticated;
set local request.jwt.claim.sub='e1000000-0000-0000-0000-000000000001';
do $$ begin
  if exists (select 1 from api.list_reservation_rent_summaries(
       'e3100000-0000-0000-0000-000000000001',null,null,0))
     or exists (select 1 from api.list_reservation_rent_summaries(
       'e3100000-0000-0000-0000-000000000001',null,null,101))
     or exists (select 1 from api.list_reservation_rent_summaries(
       'e3100000-0000-0000-0000-000000000001',now(),null,30))
     or exists (select 1 from api.list_reservation_rent_summaries(
       'e3100000-0000-0000-0000-000000000001',null,
       'e5100000-0000-0000-0000-000000000001',30)) then
    raise exception 'invalid page size or partial cursor returned data';
  end if;
end $$;
rollback;
begin;
set local role authenticated;
set local request.jwt.claim.sub='';
set local request.jwt.claims='';
do $$ begin
  if exists (select 1 from api.list_reservation_rent_summaries(
       'e3100000-0000-0000-0000-000000000001'))
     or exists (select 1 from api.list_reservation_rent_summaries(null)) then
    raise exception 'missing actor returned data';
  end if;
end $$;
rollback;
