-- Local role-switched list proof. The earlier fixture already moved reservation
-- 400... from Source to Target; this is not a production move transaction.
do $$
begin
  if has_function_privilege('anon',
       'api.list_current_reservation_summaries(uuid,text,uuid,integer)','EXECUTE')
     or has_table_privilege('authenticated','app_private.reservations','SELECT')
     or not exists (
       select 1 from pg_proc p
       where p.oid='api.list_current_reservation_summaries(uuid,text,uuid,integer)'::regprocedure
         and p.proowner='app_executor'::regrole and p.prosecdef
         and p.proconfig @> array['search_path=""']::text[]
     ) then
    raise exception 'reservation list grant/owner/search_path boundary mismatch';
  end if;
end $$;

-- C retains Source access after its Target membership is later revoked.
insert into app_private.property_memberships
  (owner_account_id,property_id,user_id,permission,granted_by) values
 ('10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  'c0000000-0000-0000-0000-000000000001','daily',
  'a0000000-0000-0000-0000-000000000001');
begin;
set constraints all deferred;
insert into app_private.reservations
  (id,owner_account_id,property_id,current_placement_id,guest_name,guest_phone,
   check_in,check_out,check_in_time,check_out_time,state,hold_expires_at,total_minor)
values
 ('41000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001','51000000-0000-0000-0000-000000000001',
  'Source Guest','+994501234567','2027-06-01','2027-06-03','14:00','12:00',
  'hold','2027-05-30',10000),
 ('42000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001','62000000-0000-0000-0000-000000000001',
  'Target Guest','+994501234567','2027-06-04','2027-06-06','14:00','12:00',
  'hold','2027-05-30',10000);
insert into app_private.reservation_placements
  (id,owner_account_id,property_id,reservation_id,placement_no,
   check_in_snapshot,check_out_snapshot,effective_from,created_by)
values
 ('51000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001','41000000-0000-0000-0000-000000000001',
  1,'2027-06-01','2027-06-03',now(),'a0000000-0000-0000-0000-000000000001'),
 ('62000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001','42000000-0000-0000-0000-000000000001',
  1,'2027-06-04','2027-06-06',now(),'a0000000-0000-0000-0000-000000000001');
commit;

begin;
set local role authenticated;
set local request.jwt.claim.sub='b0000000-0000-0000-0000-000000000001';
do $$
declare seen uuid[];
begin
  select coalesce(array_agg(reservation_id order by reservation_id),array[]::uuid[])
    into seen from api.list_current_reservation_summaries(
      '20000000-0000-0000-0000-000000000001');
  if seen <> array['41000000-0000-0000-0000-000000000001'::uuid]
     or exists (select 1 from api.list_current_reservation_summaries(
       '30000000-0000-0000-0000-000000000001')) then
    raise exception 'source-only manager saw moved or target reservation: %',seen;
  end if;
end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub='c0000000-0000-0000-0000-000000000001';
do $$
declare seen uuid[];
begin
  select coalesce(array_agg(reservation_id order by reservation_id),array[]::uuid[])
    into seen from api.list_current_reservation_summaries(
      '30000000-0000-0000-0000-000000000001');
  if seen <> array[
    '40000000-0000-0000-0000-000000000001'::uuid,
    '42000000-0000-0000-0000-000000000001'::uuid] then
    raise exception 'target manager list mismatch: %',seen;
  end if;
  select coalesce(array_agg(reservation_id order by reservation_id),array[]::uuid[])
    into seen from api.list_current_reservation_summaries(
      '30000000-0000-0000-0000-000000000001','confirmed');
  if seen <> array['40000000-0000-0000-0000-000000000001'::uuid] then
    raise exception 'status filter mismatch: %',seen;
  end if;
  select coalesce(array_agg(reservation_id order by reservation_id),array[]::uuid[])
    into seen from api.list_current_reservation_summaries(
      '30000000-0000-0000-0000-000000000001',null,null,1);
  if seen <> array['40000000-0000-0000-0000-000000000001'::uuid] then
    raise exception 'first page mismatch: %',seen;
  end if;
  select coalesce(array_agg(reservation_id order by reservation_id),array[]::uuid[])
    into seen from api.list_current_reservation_summaries(
      '30000000-0000-0000-0000-000000000001',null,
      '40000000-0000-0000-0000-000000000001',1);
  if seen <> array['42000000-0000-0000-0000-000000000001'::uuid] then
    raise exception 'second page mismatch: %',seen;
  end if;
  if exists (select 1 from api.list_current_reservation_summaries(
       '30000000-0000-0000-0000-000000000001','not_a_state'))
     or exists (select 1 from api.list_current_reservation_summaries(
       '30000000-0000-0000-0000-000000000001',null,null,101))
     or exists (select 1 from api.list_current_reservation_summaries(null)) then
    raise exception 'invalid filter/page/property accepted';
  end if;
end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub='';
set local request.jwt.claims='';
do $$ begin
  if exists (select 1 from api.list_current_reservation_summaries(
    '30000000-0000-0000-0000-000000000001')) then
    raise exception 'missing actor returned reservations';
  end if;
end $$;
rollback;

update app_private.property_memberships set revoked_at=now()
where property_id='30000000-0000-0000-0000-000000000001'
  and user_id='c0000000-0000-0000-0000-000000000001';
begin;
set local role authenticated;
set local request.jwt.claim.sub='c0000000-0000-0000-0000-000000000001';
do $$ begin
  if exists (select 1 from api.list_current_reservation_summaries(
       '30000000-0000-0000-0000-000000000001'))
     or (select count(*) from api.list_current_reservation_summaries(
       '20000000-0000-0000-0000-000000000001')) <> 1 then
    raise exception 'revoke did not remove Target or wrongly removed Source';
  end if;
end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
do $$ begin
  if exists (select 1 from api.list_current_reservation_summaries(
    '30000000-0000-0000-0000-000000000001')) then
    raise exception 'other owner saw tenant reservation';
  end if;
end $$;
rollback;
