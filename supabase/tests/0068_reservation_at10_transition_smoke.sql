-- PostgreSQL 17: AT10 date/price, lifecycle, idempotency and financial decisions.
begin;
set constraints all deferred;

insert into auth.users(id,email,email_confirmed_at) values
  ('f8000000-0000-0000-0000-000000000001','at10-owner@example.test',now()),
  ('f8000000-0000-0000-0000-000000000002','at10-daily@example.test',now()),
  ('f8000000-0000-0000-0000-000000000003','at10-full@example.test',now()),
  ('f8000000-0000-0000-0000-000000000004','at10-other@example.test',now()),
  ('f8000000-0000-0000-0000-000000000005','at10-source-only@example.test',now()),
  ('f8000000-0000-0000-0000-000000000006','at10-target-only@example.test',now());
insert into auth.sessions(id,user_id,created_at) values
  ('f8800000-0000-0000-0000-000000000001','f8000000-0000-0000-0000-000000000001',now()),
  ('f8800000-0000-0000-0000-000000000002','f8000000-0000-0000-0000-000000000002',now()),
  ('f8800000-0000-0000-0000-000000000003','f8000000-0000-0000-0000-000000000003',now()),
  ('f8800000-0000-0000-0000-000000000004','f8000000-0000-0000-0000-000000000004',now()),
  ('f8800000-0000-0000-0000-000000000005','f8000000-0000-0000-0000-000000000005',now()),
  ('f8800000-0000-0000-0000-000000000006','f8000000-0000-0000-0000-000000000006',now());
insert into app_private.owner_accounts(id,owner_user_id) values
  ('f8100000-0000-0000-0000-000000000001','f8000000-0000-0000-0000-000000000001'),
  ('f8100000-0000-0000-0000-000000000002','f8000000-0000-0000-0000-000000000004');
insert into app_private.properties(id,owner_account_id,name,area,max_guests) values
  ('f8200000-0000-4000-8000-000000000001','f8100000-0000-0000-0000-000000000001','AT10 source','Bakı',4),
  ('f8200000-0000-4000-8000-000000000002','f8100000-0000-0000-0000-000000000001','AT10 target','Bakı',4),
  ('f8200000-0000-4000-8000-000000000003','f8100000-0000-0000-0000-000000000002','AT10 other','Bakı',4);
insert into app_private.subscriptions(owner_account_id,property_id,state,current_end) values
  ('f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000001','active',now()+interval '30 days'),
  ('f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000002','trialing',now()+interval '30 days'),
  ('f8100000-0000-0000-0000-000000000002','f8200000-0000-4000-8000-000000000003','active',now()+interval '30 days');
insert into app_private.property_memberships(owner_account_id,property_id,user_id,permission,granted_by) values
  ('f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000001','f8000000-0000-0000-0000-000000000002','daily','f8000000-0000-0000-0000-000000000001'),
  ('f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000001','f8000000-0000-0000-0000-000000000003','full','f8000000-0000-0000-0000-000000000001'),
  ('f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000002','f8000000-0000-0000-0000-000000000002','daily','f8000000-0000-0000-0000-000000000001'),
  ('f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000002','f8000000-0000-0000-0000-000000000003','full','f8000000-0000-0000-0000-000000000001'),
  ('f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000001','f8000000-0000-0000-0000-000000000005','daily','f8000000-0000-0000-0000-000000000001'),
  ('f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000001','f8000000-0000-0000-0000-000000000006','full','f8000000-0000-0000-0000-000000000001');

insert into app_private.reservations(id,owner_account_id,property_id,current_placement_id,guest_name,guest_phone,
  check_in,check_out,check_in_time,check_out_time,guest_count,state,total_minor)
values ('f8300000-0000-0000-0000-000000000001','f8100000-0000-0000-0000-000000000001',
  'f8200000-0000-4000-8000-000000000001','f8400000-0000-0000-0000-000000000001','AT10 guest',null,
  (now() at time zone 'Asia/Baku')::date-1,(now() at time zone 'Asia/Baku')::date+4,'14:00','12:00',2,'confirmed',30000),
 ('f8300000-0000-0000-0000-000000000002','f8100000-0000-0000-0000-000000000001',
  'f8200000-0000-4000-8000-000000000002','f8400000-0000-0000-0000-000000000002','Cancel guest',null,
  (now() at time zone 'Asia/Baku')::date-3,(now() at time zone 'Asia/Baku')::date-1,'14:00','12:00',1,'confirmed',10000),
 ('f8300000-0000-0000-0000-000000000003','f8100000-0000-0000-0000-000000000001',
  'f8200000-0000-4000-8000-000000000002','f8400000-0000-0000-0000-000000000003','Adjust guest',null,
  (now() at time zone 'Asia/Baku')::date-5,(now() at time zone 'Asia/Baku')::date-3,'14:00','12:00',1,'confirmed',10000),
 ('f8300000-0000-0000-0000-000000000004','f8100000-0000-0000-0000-000000000001',
  'f8200000-0000-4000-8000-000000000002','f8400000-0000-0000-0000-000000000004','No commission guest',null,
  (now() at time zone 'Asia/Baku')::date-7,(now() at time zone 'Asia/Baku')::date-6,'14:00','12:00',1,'confirmed',5000),
 ('f8300000-0000-0000-0000-000000000005','f8100000-0000-0000-0000-000000000001',
  'f8200000-0000-4000-8000-000000000002','f8400000-0000-0000-0000-000000000005','No-show guest',null,
  (now() at time zone 'Asia/Baku')::date-9,(now() at time zone 'Asia/Baku')::date-8,'14:00','12:00',1,'confirmed',5000);
insert into app_private.reservation_placements(id,owner_account_id,property_id,reservation_id,placement_no,
  check_in_snapshot,check_out_snapshot,effective_from,created_by) values
  ('f8400000-0000-0000-0000-000000000001','f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000001',
    'f8300000-0000-0000-0000-000000000001',1,(now() at time zone 'Asia/Baku')::date-1,(now() at time zone 'Asia/Baku')::date+4,now()-interval '2 days','f8000000-0000-0000-0000-000000000001'),
  ('f8400000-0000-0000-0000-000000000002','f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000002',
    'f8300000-0000-0000-0000-000000000002',1,(now() at time zone 'Asia/Baku')::date-3,(now() at time zone 'Asia/Baku')::date-1,now()-interval '2 days','f8000000-0000-0000-0000-000000000001'),
  ('f8400000-0000-0000-0000-000000000003','f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000002',
    'f8300000-0000-0000-0000-000000000003',1,(now() at time zone 'Asia/Baku')::date-5,(now() at time zone 'Asia/Baku')::date-3,now()-interval '2 days','f8000000-0000-0000-0000-000000000001'),
  ('f8400000-0000-0000-0000-000000000004','f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000002',
    'f8300000-0000-0000-0000-000000000004',1,(now() at time zone 'Asia/Baku')::date-7,(now() at time zone 'Asia/Baku')::date-6,now()-interval '2 days','f8000000-0000-0000-0000-000000000001'),
  ('f8400000-0000-0000-0000-000000000005','f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000002',
    'f8300000-0000-0000-0000-000000000005',1,(now() at time zone 'Asia/Baku')::date-9,(now() at time zone 'Asia/Baku')::date-8,now()-interval '2 days','f8000000-0000-0000-0000-000000000001');
insert into app_private.occupancy(owner_account_id,property_id,placement_id,date_range) values
  ('f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000001','f8400000-0000-0000-0000-000000000001',
    daterange((now() at time zone 'Asia/Baku')::date-1,(now() at time zone 'Asia/Baku')::date+4,'[)')),
  ('f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000002','f8400000-0000-0000-0000-000000000002',
    daterange((now() at time zone 'Asia/Baku')::date-3,(now() at time zone 'Asia/Baku')::date-1,'[)')),
  ('f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000002','f8400000-0000-0000-0000-000000000003',
    daterange((now() at time zone 'Asia/Baku')::date-5,(now() at time zone 'Asia/Baku')::date-3,'[)')),
  ('f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000002','f8400000-0000-0000-0000-000000000004',
    daterange((now() at time zone 'Asia/Baku')::date-7,(now() at time zone 'Asia/Baku')::date-6,'[)')),
  ('f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000002','f8400000-0000-0000-0000-000000000005',
    daterange((now() at time zone 'Asia/Baku')::date-9,(now() at time zone 'Asia/Baku')::date-8,'[)'));
insert into app_private.tasks(owner_account_id,property_id,reservation_id,placement_id,kind,title,due_at,state,
  required_for_readiness,version) values
  ('f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000001','f8300000-0000-0000-0000-000000000001',
    'f8400000-0000-0000-0000-000000000001','cleaning','Private task description',now()+interval '3 days','open',true,4),
  ('f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000001','f8300000-0000-0000-0000-000000000001',
    'f8400000-0000-0000-0000-000000000001','other','Completed task',now()-interval '1 day','completed',false,7);
insert into app_private.tasks(owner_account_id,property_id,reservation_id,placement_id,kind,title,due_at,state,
  required_for_readiness,version) values
  ('f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000002','f8300000-0000-0000-0000-000000000005',
    'f8400000-0000-0000-0000-000000000005','cleaning','No-show cleaning',now()+interval '2 days','open',true,1);
insert into app_private.access_links(owner_account_id,property_id,token_hash,kind,reservation_id,placement_id,
  scopes,expires_at,created_by) values
  ('f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000001',repeat('a',64),'guest_guide',
    'f8300000-0000-0000-0000-000000000001','f8400000-0000-0000-0000-000000000001','[]',now()+interval '7 days','f8000000-0000-0000-0000-000000000001'),
  ('f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000002',repeat('b',64),'guest_guide',
    'f8300000-0000-0000-0000-000000000002','f8400000-0000-0000-0000-000000000002','[]',now()+interval '7 days','f8000000-0000-0000-0000-000000000001'),
  ('f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000002',repeat('d',64),'guest_guide',
    'f8300000-0000-0000-0000-000000000005','f8400000-0000-0000-0000-000000000005','[]',now()+interval '7 days','f8000000-0000-0000-0000-000000000001');
insert into app_private.rent_entries(id,owner_account_id,property_id,reservation_id,placement_id,kind,amount_minor,
  custodian,custodian_user_id,actor_id,occurred_at,operation_key) values
  ('f8600000-0000-0000-0000-000000000001','f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000002','f8300000-0000-0000-0000-000000000002',
    'f8400000-0000-0000-0000-000000000002','rent_receipt',5000,'owner','f8000000-0000-0000-0000-000000000001',
    'f8000000-0000-0000-0000-000000000001',now(),'at10-receipt-00000000000001'),
  ('f8600000-0000-0000-0000-000000000002','f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000002','f8300000-0000-0000-0000-000000000003',
    'f8400000-0000-0000-0000-000000000003','rent_receipt',5000,'owner','f8000000-0000-0000-0000-000000000001',
    'f8000000-0000-0000-0000-000000000001',now(),'at10-receipt-00000000000002'),
  ('f8600000-0000-0000-0000-000000000003','f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000002','f8300000-0000-0000-0000-000000000004',
    'f8400000-0000-0000-0000-000000000004','rent_receipt',1000,'owner','f8000000-0000-0000-0000-000000000001',
    'f8000000-0000-0000-0000-000000000001',now(),'at10-receipt-00000000000003');
insert into app_private.contacts(id,owner_account_id,name,phone,service_type)
  values('f8700000-0000-0000-0000-000000000001','f8100000-0000-0000-0000-000000000001','AT10 realtor','+994501234567','realtor');
insert into app_private.realtor_accounts(id,owner_account_id,reservation_id,contact_id,commission_kind,
  fixed_minor,basis_minor,earned_minor)
  values('f8900000-0000-0000-0000-000000000001','f8100000-0000-0000-0000-000000000001',
    'f8300000-0000-0000-0000-000000000003','f8700000-0000-0000-0000-000000000001','fixed',1000,10000,1000);
insert into app_private.realtor_settlements(owner_account_id,property_id,realtor_account_id,kind,amount_minor,
  occurred_at,actor_id,reservation_id,placement_id,operation_key)
  values('f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000002',
    'f8900000-0000-0000-0000-000000000001','owner_to_realtor',1000,now(),
    'f8000000-0000-0000-0000-000000000001','f8300000-0000-0000-0000-000000000003',
    'f8400000-0000-0000-0000-000000000003','at10-settlement-000000001');

set constraints all immediate;

-- Owner updates the interval; placement/occupancy/link/task effects are atomic and idempotent.
set local role authenticated;
set local request.jwt.claim.sub='f8000000-0000-0000-0000-000000000001';
set local request.jwt.claims='{"sub":"f8000000-0000-0000-0000-000000000001","session_id":"f8800000-0000-0000-0000-000000000001"}';
do $$ declare v_result jsonb; v_retry jsonb; v_reservation uuid:='f8300000-0000-0000-0000-000000000001';
  v_new_out date:=(now() at time zone 'Asia/Baku')::date+5; v_stale boolean:=false;
begin
  v_result:=api.patch_reservation(v_reservation,
    jsonb_build_object('expected_version',1,'check_out',v_new_out::text,'total_minor',32000),
    'at10-patch-dates-key-000000001');
  if v_result->>'reservation_id'<>v_reservation::text or (v_result->>'version')::int<>2 or v_result->>'replayed'<>'false' then
    raise exception 'invalid patch acknowledgement %',v_result; end if;
  v_retry:=api.patch_reservation(v_reservation,
    jsonb_build_object('expected_version',1,'check_out',v_new_out::text,'total_minor',32000),
    'at10-patch-dates-key-000000001');
  if v_retry->>'replayed'<>'true' then raise exception 'same-key patch did not replay'; end if;
  begin
    perform api.patch_reservation(v_reservation,jsonb_build_object('expected_version',1,'total_minor',31000),
      'at10-patch-stale-key-000000001');
  exception when serialization_failure then v_stale:=true; end;
  if not v_stale then raise exception 'stale reservation version was accepted'; end if;
end $$;
reset role;
do $$ declare v_new_placement uuid;
begin
  select current_placement_id into v_new_placement from app_private.reservations where id='f8300000-0000-0000-0000-000000000001'
    and version=2 and total_minor=32000 and check_out=(now() at time zone 'Asia/Baku')::date+5;
  if v_new_placement is null then raise exception 'date/price update did not persist'; end if;
  if (select count(*) from app_private.reservation_placements where reservation_id='f8300000-0000-0000-0000-000000000001')<>2
    or not exists(select 1 from app_private.reservation_placements where id='f8400000-0000-0000-0000-000000000001'
      and effective_to is not null and check_out_snapshot=(now() at time zone 'Asia/Baku')::date+4)
    or not exists(select 1 from app_private.reservation_placements where id=v_new_placement
      and effective_to is null and check_out_snapshot=(now() at time zone 'Asia/Baku')::date+5)
    or exists(select 1 from app_private.occupancy where placement_id='f8400000-0000-0000-0000-000000000001' and active)
    or not exists(select 1 from app_private.occupancy where placement_id=v_new_placement and active
      and date_range=daterange((now() at time zone 'Asia/Baku')::date-1,(now() at time zone 'Asia/Baku')::date+5,'[)')) then
    raise exception 'placement history or occupancy interval is incorrect'; end if;
  if (select count(*) from app_private.access_links where token_hash=repeat('a',64) and revoked_at is not null)<>1 then
    raise exception 'date change did not revoke old placement guest link'; end if;
  if not exists(select 1 from app_private.tasks where reservation_id='f8300000-0000-0000-0000-000000000001'
      and kind='cleaning' and state='open' and version=5 and title='Private task description'
      and placement_id=(select current_placement_id from app_private.reservations where id='f8300000-0000-0000-0000-000000000001')
      and due_at=(((select check_out from app_private.reservations where id='f8300000-0000-0000-0000-000000000001')+'12:00'::time) at time zone 'Asia/Baku'))
    or not exists(select 1 from app_private.tasks where reservation_id='f8300000-0000-0000-0000-000000000001'
      and kind='other' and state='completed' and version=7) then
    raise exception 'future cleaning task was not rescheduled or completed task changed'; end if;
end $$;

-- A date extension overlapping a manual block is rejected and leaves no partial placement/idempotency record.
insert into app_private.manual_blocks(owner_account_id,property_id,check_in,check_out,reason)
  values('f8100000-0000-0000-0000-000000000001','f8200000-0000-4000-8000-000000000001',
    (now() at time zone 'Asia/Baku')::date+5,(now() at time zone 'Asia/Baku')::date+6,'at10 conflict');
insert into app_private.occupancy(owner_account_id,property_id,manual_block_id,date_range)
  select owner_account_id,property_id,id,daterange(check_in,check_out,'[)') from app_private.manual_blocks where reason='at10 conflict';
set local role authenticated;
set local request.jwt.claim.sub='f8000000-0000-0000-0000-000000000001';
set local request.jwt.claims='{"sub":"f8000000-0000-0000-0000-000000000001","session_id":"f8800000-0000-0000-0000-000000000001"}';
do $$ declare v_conflict boolean:=false;
begin
  begin
    perform api.patch_reservation('f8300000-0000-0000-0000-000000000001'::uuid,
      jsonb_build_object('expected_version',2,'check_out',((now() at time zone 'Asia/Baku')::date+6)::text,'total_minor',33000),
      'at10-date-conflict-key-0000001');
  exception when exclusion_violation then v_conflict:=true; end;
  if not v_conflict then raise exception 'overlapping date change was accepted'; end if;
end $$;
reset role;
do $$ begin
  if not exists(select 1 from app_private.reservations where id='f8300000-0000-0000-0000-000000000001'
      and version=2 and total_minor=32000 and check_out=(now() at time zone 'Asia/Baku')::date+5)
    or (select count(*) from app_private.reservation_placements where reservation_id='f8300000-0000-0000-0000-000000000001')<>2
    or exists(select 1 from app_private.idempotency_keys where key='at10-date-conflict-key-0000001') then
    raise exception 'overlap failure was not atomic'; end if;
  delete from app_private.occupancy where manual_block_id=(select id from app_private.manual_blocks where reason='at10 conflict');
  delete from app_private.manual_blocks where reason='at10 conflict';
end $$;

-- Move the updated reservation to the same owner's second property, keep history,
-- revoke the prior placement link, and deny the former source-only manager.
insert into app_private.access_links(owner_account_id,property_id,token_hash,kind,reservation_id,placement_id,
  scopes,expires_at,created_by)
select owner_account_id,property_id,repeat('c',64),'guest_guide',id,current_placement_id,'[]',
  now()+interval '7 days','f8000000-0000-0000-0000-000000000001'
  from app_private.reservations where id='f8300000-0000-0000-0000-000000000001';
set local role authenticated;
set local request.jwt.claim.sub='f8000000-0000-0000-0000-000000000001';
set local request.jwt.claims='{"sub":"f8000000-0000-0000-0000-000000000001","session_id":"f8800000-0000-0000-0000-000000000001"}';
do $$ declare v_result jsonb;
begin
  v_result:=api.move_reservation('f8300000-0000-0000-0000-000000000001'::uuid,
    jsonb_build_object('expected_version',2,'to_property_id','f8200000-0000-4000-8000-000000000002',
      'new_total_minor',32000), 'at10-move-key-000000000000001');
  if v_result->>'replayed'<>'false' or v_result->>'placement_id' is null then raise exception 'reservation move failed'; end if;
end $$;
reset role;
do $$ declare v_target_placement uuid;
begin
  select current_placement_id into v_target_placement from app_private.reservations
    where id='f8300000-0000-0000-0000-000000000001';
  if not exists(select 1 from app_private.reservations where id='f8300000-0000-0000-0000-000000000001'
      and version=3 and property_id='f8200000-0000-4000-8000-000000000002' and current_placement_id=v_target_placement)
    or not exists(select 1 from app_private.reservation_placements where id='f8400000-0000-0000-0000-000000000001'
      and effective_to is not null)
    or exists(select 1 from app_private.occupancy where placement_id='f8400000-0000-0000-0000-000000000001' and active)
    or not exists(select 1 from app_private.occupancy where placement_id=v_target_placement and active)
    or not exists(select 1 from app_private.access_links where token_hash=repeat('c',64) and revoked_at is not null)
    or not exists(select 1 from app_private.tasks where placement_id=(select id from app_private.reservation_placements
      where reservation_id='f8300000-0000-0000-0000-000000000001' and placement_no=2)
      and kind='cleaning' and state='cancelled')
    or not exists(select 1 from app_private.tasks where placement_id=v_target_placement
      and kind='cleaning' and state='open' and description is null)
    or not exists(select 1 from app_private.tasks where reservation_id='f8300000-0000-0000-0000-000000000001'
      and kind='other' and state='completed' and version=7) then
    raise exception 'move failed to preserve placement/task privacy invariants'; end if;
end $$;
reset role;
set local role authenticated;
set local request.jwt.claim.sub='f8000000-0000-0000-0000-000000000005';
set local request.jwt.claims='{"sub":"f8000000-0000-0000-0000-000000000005","session_id":"f8800000-0000-0000-0000-000000000005"}';
do $$ declare v_denied boolean:=false;
begin
  begin
    perform api.get_reservation('f8300000-0000-0000-0000-000000000001'::uuid);
  exception when no_data_found then v_denied:=true; end;
  if not v_denied then raise exception 'source-only manager read current guest data after move'; end if;
end $$;
reset role;

-- Check-in, checkout, cleaning and completed-release keep state completed and never reopen occupancy.
set local role authenticated;
set local request.jwt.claim.sub='f8000000-0000-0000-0000-000000000001';
set local request.jwt.claims='{"sub":"f8000000-0000-0000-0000-000000000001","session_id":"f8800000-0000-0000-0000-000000000001"}';
do $$ declare v_result jsonb; v_before timestamptz; v_after timestamptz; v_dto jsonb;
  v_new_out date:=(now() at time zone 'Asia/Baku')::date;
begin
  v_result:=api.transition_reservation('f8300000-0000-0000-0000-000000000001'::uuid,
    '{"expected_version":3,"action":"check_in"}'::jsonb,'at10-checkin-key-000000000001');
  if (v_result->>'version')::int<>4 then raise exception 'check-in did not bump version'; end if;
  v_result:=api.transition_reservation('f8300000-0000-0000-0000-000000000001'::uuid,
    '{"expected_version":4,"action":"check_out"}'::jsonb,'at10-checkout-key-00000000001');
  if (v_result->>'version')::int<>5 then raise exception 'check-out did not bump version'; end if;
  v_dto:=api.get_reservation('f8300000-0000-0000-0000-000000000001'::uuid);
  v_before:=(v_dto->>'actual_check_out_at')::timestamptz;
  v_result:=api.transition_reservation('f8300000-0000-0000-0000-000000000001'::uuid,
    jsonb_build_object('expected_version',5,'action','release_remaining_days','new_check_out',v_new_out::text,'new_total_minor',25000),
    'at10-release-key-000000000000001');
  if (v_result->>'version')::int<>6 then raise exception 'release remaining days did not bump version'; end if;
  v_dto:=api.get_reservation('f8300000-0000-0000-0000-000000000001'::uuid);
  v_after:=(v_dto->>'actual_check_out_at')::timestamptz;
  if v_dto->>'status'<>'completed' or (v_dto->>'version')::int<>6
     or v_dto->>'check_out'<>v_new_out::text or (v_dto->>'total_minor')::int<>25000
     or v_before is null or v_after is distinct from v_before then
    raise exception 'early release changed status/quote incorrectly or overwrote actual checkout'; end if;
end $$;
reset role;
do $$ begin
  if exists(select 1 from app_private.occupancy where placement_id=(select current_placement_id from app_private.reservations
      where id='f8300000-0000-0000-0000-000000000001') and active)
    or (select count(*) from app_private.reservation_placements where reservation_id='f8300000-0000-0000-0000-000000000001')<>4
    or not exists(select 1 from app_private.tasks where reservation_id='f8300000-0000-0000-0000-000000000001'
      and kind='cleaning' and state='open' and inspection_event_id is not null) then
    raise exception 'early release reopened occupancy or lost checkout cleaning/history'; end if;
end $$;

-- A rent ledger makes a cancel decision mandatory. keep_as_is adds no refund record.
set local role authenticated;
set local request.jwt.claim.sub='f8000000-0000-0000-0000-000000000002';
set local request.jwt.claims='{"sub":"f8000000-0000-0000-0000-000000000002","session_id":"f8800000-0000-0000-0000-000000000002"}';
do $$ declare v_missing boolean:=false; v_result jsonb;
begin
  begin
    perform api.transition_reservation('f8300000-0000-0000-0000-000000000002'::uuid,
      '{"expected_version":1,"action":"cancel"}'::jsonb,'at10-cancel-missing-key-000001');
  exception when invalid_parameter_value then v_missing:=true; end;
  if not v_missing then raise exception 'cancel without required financial decision was accepted'; end if;
end $$;
reset role;
set local role authenticated;
set local request.jwt.claim.sub='f8000000-0000-0000-0000-000000000001';
set local request.jwt.claims='{"sub":"f8000000-0000-0000-0000-000000000001","session_id":"f8800000-0000-0000-0000-000000000001"}';
do $$ declare v_result jsonb;
begin
  v_result:=api.transition_reservation('f8300000-0000-0000-0000-000000000002'::uuid,
    '{"expected_version":1,"action":"cancel","financial_decision":{"mode":"keep_as_is"}}'::jsonb,
    'at10-cancel-keep-key-000000001');
  if v_result->>'reservation_id'<>'f8300000-0000-0000-0000-000000000002' then raise exception 'cancel acknowledgement mismatch'; end if;
end $$;
reset role;
do $$ begin
  if (select count(*) from app_private.rent_entries where reservation_id='f8300000-0000-0000-0000-000000000002')<>1
    or not exists(select 1 from app_private.reservations where id='f8300000-0000-0000-0000-000000000002'
      and state='cancelled' and version=2)
    or exists(select 1 from app_private.occupancy where placement_id='f8400000-0000-0000-0000-000000000002' and active)
    or not exists(select 1 from app_private.access_links where token_hash=repeat('b',64) and revoked_at is not null) then
    raise exception 'keep_as_is cancellation changed money or failed to release/revoke'; end if;
end $$;

-- Settlement RLS must prevent commission replacement once settled. Receipt-linked adjustments
-- remain bounded and must stay attached to the source property/placement after a move.
set local role authenticated;
set local request.jwt.claim.sub='f8000000-0000-0000-0000-000000000001';
set local request.jwt.claims='{"sub":"f8000000-0000-0000-0000-000000000001","session_id":"f8800000-0000-0000-0000-000000000001"}';
do $$ declare v_settled boolean:=false;
begin
  begin
    perform api.patch_reservation('f8300000-0000-0000-0000-000000000003'::uuid,
      '{"expected_version":1,"commission":{"contact_id":"f8700000-0000-0000-0000-000000000001","kind":"fixed","fixed_minor":2000,"basis_minor":10000}}'::jsonb,
      'at10-commission-settled-key-001');
  exception when unique_violation then v_settled:=true; end;
  if not v_settled then raise exception 'settled commission was modified'; end if;
end $$;
reset role;
set local role authenticated;
set local request.jwt.claim.sub='f8000000-0000-0000-0000-000000000001';
set local request.jwt.claims='{"sub":"f8000000-0000-0000-0000-000000000001","session_id":"f8800000-0000-0000-0000-000000000001"}';
do $$ declare v_result jsonb;
begin
  v_result:=api.move_reservation('f8300000-0000-0000-0000-000000000003'::uuid,
    jsonb_build_object('expected_version',1,'to_property_id','f8200000-0000-4000-8000-000000000001',
      'new_total_minor',10000), 'at10-refund-source-move-000001');
  if v_result->>'replayed'<>'false' then raise exception 'receipt source move failed'; end if;
end $$;
reset role;
set local role authenticated;
set local request.jwt.claim.sub='f8000000-0000-0000-0000-000000000006';
set local request.jwt.claims='{"sub":"f8000000-0000-0000-0000-000000000006","session_id":"f8800000-0000-0000-0000-000000000006"}';
do $$ declare v_settled boolean:=false;
begin
  begin
    perform api.patch_reservation('f8300000-0000-0000-0000-000000000003'::uuid,
      '{"expected_version":2,"commission":{"contact_id":"f8700000-0000-0000-0000-000000000001","kind":"fixed","fixed_minor":2000,"basis_minor":10000}}'::jsonb,
      'at10-target-only-settlement-001');
  exception when unique_violation then v_settled:=true; end;
  if not v_settled then raise exception 'destination-only finance manager changed a settled commission'; end if;
end $$;
reset role;
set local role authenticated;
set local request.jwt.claim.sub='f8000000-0000-0000-0000-000000000001';
set local request.jwt.claims='{"sub":"f8000000-0000-0000-0000-000000000001","session_id":"f8800000-0000-0000-0000-000000000001"}';
do $$ declare v_below boolean:=false;
begin
  begin
    perform api.transition_reservation('f8300000-0000-0000-0000-000000000003'::uuid,
      '{"expected_version":2,"action":"cancel","financial_decision":{"mode":"adjust","rent_refunds":[{"original_id":"f8600000-0000-0000-0000-000000000002","amount_minor":500}],"commission_keep_minor":0}}'::jsonb,
      'at10-commission-below-settled-001');
  exception when invalid_parameter_value then v_below:=true; end;
  if not v_below then raise exception 'commission was reduced below immutable settlements'; end if;
end $$;
reset role;

set local role authenticated;
set local request.jwt.claim.sub='f8000000-0000-0000-0000-000000000002';
set local request.jwt.claims='{"sub":"f8000000-0000-0000-0000-000000000002","session_id":"f8800000-0000-0000-0000-000000000002"}';
do $$ declare v_denied boolean:=false;
begin
  begin
    perform api.transition_reservation('f8300000-0000-0000-0000-000000000003'::uuid,
      '{"expected_version":2,"action":"cancel","financial_decision":{"mode":"adjust","rent_refunds":[{"original_id":"f8600000-0000-0000-0000-000000000002","amount_minor":2000}]}}'::jsonb,
      'at10-cancel-adjust-daily-00001');
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'daily manager adjusted financial ledger'; end if;
end $$;
reset role;
set local role authenticated;
set local request.jwt.claim.sub='f8000000-0000-0000-0000-000000000001';
set local request.jwt.claims='{"sub":"f8000000-0000-0000-0000-000000000001","session_id":"f8800000-0000-0000-0000-000000000001"}';
do $$ declare v_receipt uuid; v_result jsonb; v_bounded boolean:=false;
begin
  v_receipt:='f8600000-0000-0000-0000-000000000002';
  begin
    perform api.transition_reservation('f8300000-0000-0000-0000-000000000003'::uuid,
      jsonb_build_object('expected_version',2,'action','cancel','financial_decision',
        jsonb_build_object('mode','adjust','rent_refunds',jsonb_build_array(jsonb_build_object('original_id',v_receipt,'amount_minor',5001)))),
      'at10-cancel-adjust-over-key-0001');
  exception when invalid_parameter_value then v_bounded:=true; end;
  if not v_bounded then raise exception 'refund exceeding original receipt was accepted'; end if;
  v_result:=api.transition_reservation('f8300000-0000-0000-0000-000000000003'::uuid,
    jsonb_build_object('expected_version',2,'action','cancel','financial_decision',
      jsonb_build_object('mode','adjust','rent_refunds',jsonb_build_array(jsonb_build_object('original_id',v_receipt,'amount_minor',2000)))),
    'at10-cancel-adjust-valid-key-001');
  if v_result->>'replayed'<>'false' then raise exception 'valid refund adjustment unexpectedly replayed'; end if;
end $$;
reset role;
do $$ begin
  if (select count(*) from app_private.rent_entries where reservation_id='f8300000-0000-0000-0000-000000000003'
      and kind='rent_refund' and amount_minor=2000 and original_entry_id='f8600000-0000-0000-0000-000000000002'
      and property_id='f8200000-0000-4000-8000-000000000002'
      and placement_id='f8400000-0000-0000-0000-000000000003')<>1 then
    raise exception 'receipt-linked refund lost its source property or placement'; end if;
  if (select sum(amount_minor) from app_private.rent_entries where reservation_id='f8300000-0000-0000-0000-000000000003'
      and kind in ('rent_receipt','rent_refund'))<>7000 then raise exception 'rent refund ledger total is incorrect'; end if;
end $$;

-- Zero commission keep may accompany a rent refund when this reservation has no realtor account.
set local role authenticated;
set local request.jwt.claim.sub='f8000000-0000-0000-0000-000000000001';
set local request.jwt.claims='{"sub":"f8000000-0000-0000-0000-000000000001","session_id":"f8800000-0000-0000-0000-000000000001"}';
do $$ declare v_missing boolean:=false;
begin
  begin
    perform api.transition_reservation('f8300000-0000-0000-0000-000000000004'::uuid,
      '{"expected_version":1,"action":"cancel","financial_decision":{"mode":"adjust","commission_keep_minor":1}}'::jsonb,
      'at10-positive-commission-without-account');
  exception when invalid_parameter_value then v_missing:=true; end;
  if not v_missing then raise exception 'positive commission keep was accepted without a realtor account'; end if;
end $$;
do $$ declare v_result jsonb;
begin
  v_result:=api.transition_reservation('f8300000-0000-0000-0000-000000000004'::uuid,
    '{"expected_version":1,"action":"cancel","financial_decision":{"mode":"adjust","rent_refunds":[{"original_id":"f8600000-0000-0000-0000-000000000003","amount_minor":500}],"commission_keep_minor":0}}'::jsonb,
    'at10-refund-zero-commission-key');
  if v_result->>'replayed'<>'false' then raise exception 'zero commission adjustment did not execute'; end if;
end $$;
reset role;
do $$ begin
  if not exists(select 1 from app_private.reservations where id='f8300000-0000-0000-0000-000000000004'
      and state='cancelled' and version=2)
    or not exists(select 1 from app_private.rent_entries where original_entry_id='f8600000-0000-0000-0000-000000000003'
      and kind='rent_refund' and amount_minor=500) then
    raise exception 'zero commission keep with a rent refund was not applied'; end if;
end $$;

-- A confirmed past reservation may be marked no-show; future work and guest access close atomically.
set local role authenticated;
set local request.jwt.claim.sub='f8000000-0000-0000-0000-000000000001';
set local request.jwt.claims='{"sub":"f8000000-0000-0000-0000-000000000001","session_id":"f8800000-0000-0000-0000-000000000001"}';
do $$ declare v_result jsonb;
begin
  v_result:=api.transition_reservation('f8300000-0000-0000-0000-000000000005'::uuid,
    '{"expected_version":1,"action":"no_show"}'::jsonb,'at10-no-show-key-00000000001');
  if v_result->>'reservation_id'<>'f8300000-0000-0000-0000-000000000005'
     or (v_result->>'version')::int<>2 or v_result->>'replayed'<>'false' then
    raise exception 'no-show transition acknowledgement mismatch: %',v_result; end if;
end $$;
reset role;
do $$ begin
  if not exists(select 1 from app_private.reservations where id='f8300000-0000-0000-0000-000000000005'
      and state='no_show' and version=2)
    or exists(select 1 from app_private.occupancy where placement_id='f8400000-0000-0000-0000-000000000005' and active)
    or not exists(select 1 from app_private.access_links where token_hash=repeat('d',64) and revoked_at is not null)
    or not exists(select 1 from app_private.tasks where reservation_id='f8300000-0000-0000-0000-000000000005'
      and kind='cleaning' and state='cancelled' and version=2)
    or not exists(select 1 from app_private.task_transition_events where task_id=(select id from app_private.tasks
      where reservation_id='f8300000-0000-0000-0000-000000000005' and kind='cleaning')
      and action='cancel' and note='reservation_no_show' and resulting_version=2) then
    raise exception 'no-show transition did not atomically release occupancy, revoke guest access, and cancel future work'; end if;
end $$;
rollback;
