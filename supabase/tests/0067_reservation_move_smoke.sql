-- PostgreSQL 17: real API move command, RLS/capability, placement, ledger, task and link effects.
begin;
set constraints all deferred;

insert into auth.users(id) values
  ('f7000000-0000-0000-0000-000000000001'),
  ('f7000000-0000-0000-0000-000000000002'),
  ('f7000000-0000-0000-0000-000000000003'),
  ('f7000000-0000-0000-0000-000000000004');
insert into app_private.owner_accounts(id,owner_user_id) values
  ('f7100000-0000-0000-0000-000000000001','f7000000-0000-0000-0000-000000000001'),
  ('f7100000-0000-0000-0000-000000000002','f7000000-0000-0000-0000-000000000004');
insert into app_private.properties(id,owner_account_id,name,area) values
  ('f7200000-0000-4000-8000-000000000001','f7100000-0000-0000-0000-000000000001','Source','Bakı'),
  ('f7200000-0000-4000-8000-000000000002','f7100000-0000-0000-0000-000000000001','Target','Bakı'),
  ('f7200000-0000-4000-8000-000000000003','f7100000-0000-0000-0000-000000000002','Other owner','Bakı');
insert into app_private.subscriptions(owner_account_id,property_id,state,current_end) values
  ('f7100000-0000-0000-0000-000000000001','f7200000-0000-4000-8000-000000000001','active',now()+interval '30 days'),
  ('f7100000-0000-0000-0000-000000000001','f7200000-0000-4000-8000-000000000002','trialing',now()+interval '30 days'),
  ('f7100000-0000-0000-0000-000000000002','f7200000-0000-4000-8000-000000000003','active',now()+interval '30 days');
insert into app_private.property_memberships(owner_account_id,property_id,user_id,permission,granted_by) values
  ('f7100000-0000-0000-0000-000000000001','f7200000-0000-4000-8000-000000000001','f7000000-0000-0000-0000-000000000002','daily','f7000000-0000-0000-0000-000000000001'),
  ('f7100000-0000-0000-0000-000000000001','f7200000-0000-4000-8000-000000000002','f7000000-0000-0000-0000-000000000003','full','f7000000-0000-0000-0000-000000000001');

insert into app_private.reservations(
  id,owner_account_id,property_id,current_placement_id,guest_name,check_in,check_out,
  check_in_time,check_out_time,total_minor
) values (
  'f7300000-0000-0000-0000-000000000001','f7100000-0000-0000-0000-000000000001',
  'f7200000-0000-4000-8000-000000000001','f7400000-0000-0000-0000-000000000001',
  'Move guest','2027-07-01','2027-07-04','15:00','11:00',30000
);
insert into app_private.reservation_placements(
  id,owner_account_id,property_id,reservation_id,placement_no,
  check_in_snapshot,check_out_snapshot,effective_from,created_by
) values (
  'f7400000-0000-0000-0000-000000000001','f7100000-0000-0000-0000-000000000001',
  'f7200000-0000-4000-8000-000000000001','f7300000-0000-0000-0000-000000000001',
  1,'2027-07-01','2027-07-04',now()-interval '1 day','f7000000-0000-0000-0000-000000000001'
);
insert into app_private.occupancy(owner_account_id,property_id,placement_id,date_range)
values ('f7100000-0000-0000-0000-000000000001','f7200000-0000-4000-8000-000000000001',
  'f7400000-0000-0000-0000-000000000001',daterange('2027-07-01','2027-07-04','[)'));
insert into app_private.rent_entries(
  owner_account_id,property_id,reservation_id,placement_id,kind,amount_minor,
  custodian,custodian_user_id,actor_id,occurred_at,operation_key
) values
  ('f7100000-0000-0000-0000-000000000001','f7200000-0000-4000-8000-000000000001',
   'f7300000-0000-0000-0000-000000000001','f7400000-0000-0000-0000-000000000001',
   'rent_receipt',10000,'owner','f7000000-0000-0000-0000-000000000001',
   'f7000000-0000-0000-0000-000000000001',now(),'move-smoke-rent-receipt'),
  ('f7100000-0000-0000-0000-000000000001','f7200000-0000-4000-8000-000000000001',
   'f7300000-0000-0000-0000-000000000001','f7400000-0000-0000-0000-000000000001',
   'deposit_receipt',5000,'owner','f7000000-0000-0000-0000-000000000001',
   'f7000000-0000-0000-0000-000000000001',now(),'move-smoke-deposit-receipt');

insert into app_private.tasks(
  id,owner_account_id,property_id,reservation_id,placement_id,kind,title,due_at,state,
  required_for_readiness,version
) values
  ('f7500000-0000-0000-0000-000000000001','f7100000-0000-0000-0000-000000000001',
   'f7200000-0000-4000-8000-000000000001','f7300000-0000-0000-0000-000000000001',
   'f7400000-0000-0000-0000-000000000001','cleaning','Private source-specific title',
   now()+interval '2 days','accepted',true,4),
  ('f7500000-0000-0000-0000-000000000002','f7100000-0000-0000-0000-000000000001',
   'f7200000-0000-4000-8000-000000000001','f7300000-0000-0000-0000-000000000001',
   'f7400000-0000-0000-0000-000000000001','other','Completed task',
   now()-interval '2 hours','completed',false,7);
update app_private.tasks set confirmed_at=now(),confirmed_by='f7000000-0000-0000-0000-000000000001'
where id='f7500000-0000-0000-0000-000000000002';
insert into app_private.access_links(
  owner_account_id,property_id,token_hash,kind,task_id,reservation_id,placement_id,
  scopes,expires_at,created_by
) values
  ('f7100000-0000-0000-0000-000000000001','f7200000-0000-4000-8000-000000000001',
   repeat('a',64),'guest_guide',null,'f7300000-0000-0000-0000-000000000001',
   'f7400000-0000-0000-0000-000000000001','["guest_guide.read"]',now()+interval '1 day',
   'f7000000-0000-0000-0000-000000000001'),
  ('f7100000-0000-0000-0000-000000000001','f7200000-0000-4000-8000-000000000001',
   repeat('b',64),'task','f7500000-0000-0000-0000-000000000001',null,null,
   '["task.read"]',now()+interval '1 day','f7000000-0000-0000-0000-000000000001');
insert into app_private.inspection_days(id,owner_account_id,property_id,local_date)
values ('f7600000-0000-0000-0000-000000000001','f7100000-0000-0000-0000-000000000001',
  'f7200000-0000-4000-8000-000000000001','2027-07-04');
insert into app_private.inspection_events(
  id,owner_account_id,property_id,day_id,handover_key,reservation_id,placement_id,event_kind,due_at
) values ('f7700000-0000-0000-0000-000000000001','f7100000-0000-0000-0000-000000000001',
  'f7200000-0000-4000-8000-000000000001','f7600000-0000-0000-0000-000000000001',
  'move-smoke-checkout','f7300000-0000-0000-0000-000000000001',
  'f7400000-0000-0000-0000-000000000001','check_out',now()+interval '3 days');
insert into app_private.manual_blocks(owner_account_id,property_id,check_in,check_out,reason)
values ('f7100000-0000-0000-0000-000000000001','f7200000-0000-4000-8000-000000000002',
  '2027-07-02','2027-07-03','synthetic move conflict');
insert into app_private.occupancy(owner_account_id,property_id,manual_block_id,date_range)
values ('f7100000-0000-0000-0000-000000000001','f7200000-0000-4000-8000-000000000002',
  (select id from app_private.manual_blocks where reason='synthetic move conflict'),
  daterange('2027-07-02','2027-07-03','[)'));

set constraints all immediate;
set local role authenticated;
set local request.jwt.claim.sub='f7000000-0000-0000-0000-000000000002';
do $$ begin
  begin
    perform api.move_reservation('f7300000-0000-0000-0000-000000000001'::uuid,
      '{"expected_version":1,"to_property_id":"f7200000-0000-4000-8000-000000000002","new_total_minor":28000}'::jsonb,
      'reservation-move-source-only-key-01');
    raise exception 'source-only manager moved reservation without target capability';
  exception when no_data_found or insufficient_privilege then null;
  end;
end $$;
reset role;

set local role authenticated;
set local request.jwt.claim.sub='f7000000-0000-0000-0000-000000000001';
do $$ declare v_result jsonb;
begin
  begin
    perform api.move_reservation('f7300000-0000-0000-0000-000000000001'::uuid,
      '{"expected_version":1,"to_property_id":"f7200000-0000-4000-8000-000000000003","new_total_minor":28000}'::jsonb,
      'reservation-move-cross-owner-key-01');
    raise exception 'cross-owner property move was accepted';
  exception when no_data_found or insufficient_privilege then null;
  end;
  begin
    perform api.move_reservation('f7300000-0000-0000-0000-000000000001'::uuid,
      '{"expected_version":2,"to_property_id":"f7200000-0000-4000-8000-000000000002","new_total_minor":28000}'::jsonb,
      'reservation-move-stale-version-key-01');
    raise exception 'stale reservation version was accepted';
  exception when serialization_failure then null;
  end;
  begin
    perform api.move_reservation('f7300000-0000-0000-0000-000000000001'::uuid,
      '{"expected_version":1,"to_property_id":"f7200000-0000-4000-8000-000000000002","new_total_minor":28000}'::jsonb,
      'reservation-move-overlap-key-01');
    raise exception 'target occupancy conflict was accepted';
  exception when exclusion_violation then null;
  end;
end $$;
reset role;

do $$ begin
  if not exists(select 1 from app_private.reservations where id='f7300000-0000-0000-0000-000000000001'
       and property_id='f7200000-0000-4000-8000-000000000001'
       and current_placement_id='f7400000-0000-0000-0000-000000000001' and version=1)
     or exists(select 1 from app_private.reservation_placements where reservation_id='f7300000-0000-0000-0000-000000000001' and placement_no=2)
     or exists(select 1 from app_private.idempotency_keys where key='reservation-move-overlap-key-01') then
    raise exception 'failed overlap move was not atomic';
  end if;
  delete from app_private.occupancy where manual_block_id=(select id from app_private.manual_blocks where reason='synthetic move conflict');
  delete from app_private.manual_blocks where reason='synthetic move conflict';
end $$;

set local role authenticated;
set local request.jwt.claim.sub='f7000000-0000-0000-0000-000000000001';
do $$ declare v_result jsonb;
begin
  v_result := api.move_reservation('f7300000-0000-0000-0000-000000000001'::uuid,
    '{"expected_version":1,"to_property_id":"f7200000-0000-4000-8000-000000000002","new_total_minor":28000,"reason":"owner approved move"}'::jsonb,
    'reservation-move-owner-key-01');
  if v_result->>'reservation_id' <> 'f7300000-0000-0000-0000-000000000001'
     or v_result->>'placement_id' is null or v_result->>'replayed' <> 'false' then
    raise exception 'move command returned an invalid acknowledgement: %',v_result;
  end if;
  if api.move_reservation('f7300000-0000-0000-0000-000000000001'::uuid,
      '{"expected_version":1,"to_property_id":"f7200000-0000-4000-8000-000000000002","new_total_minor":28000,"reason":"owner approved move"}'::jsonb,
      'reservation-move-owner-key-01')->>'placement_id' <> v_result->>'placement_id' then
    raise exception 'same-key move retry produced a different placement';
  end if;
  begin
    perform api.move_reservation('f7300000-0000-0000-0000-000000000001'::uuid,
      '{"expected_version":1,"to_property_id":"f7200000-0000-4000-8000-000000000002","new_total_minor":28001,"reason":"owner approved move"}'::jsonb,
      'reservation-move-owner-key-01');
    raise exception 'same move key accepted a different payload';
  exception when unique_violation then null;
  end;
end $$;
reset role;
savepoint source_manager_after_move;

do $$ declare v_current uuid; v_task_event_count integer;
begin
  select current_placement_id into v_current from app_private.reservations
    where id='f7300000-0000-0000-0000-000000000001'
      and property_id='f7200000-0000-4000-8000-000000000002'
      and total_minor=28000 and version=2;
  if v_current is null then raise exception 'reservation pointer, property, price or version did not move'; end if;
  if (select count(*) from app_private.reservation_placements where reservation_id='f7300000-0000-0000-0000-000000000001')<>2
     or not exists(select 1 from app_private.reservation_placements where id='f7400000-0000-0000-0000-000000000001'
       and property_id='f7200000-0000-4000-8000-000000000001'
       and check_in_snapshot='2027-07-01' and check_out_snapshot='2027-07-04' and effective_to is not null)
     or not exists(select 1 from app_private.reservation_placements where id=v_current
       and property_id='f7200000-0000-4000-8000-000000000002'
       and check_in_snapshot='2027-07-01' and check_out_snapshot='2027-07-04' and effective_to is null) then
    raise exception 'placement history or immutable dates are incorrect';
  end if;
  if (select count(*) from app_private.occupancy where placement_id='f7400000-0000-0000-0000-000000000001' and not active)<>1
     or (select count(*) from app_private.occupancy where placement_id=v_current and property_id='f7200000-0000-4000-8000-000000000002' and active)<>1 then
    raise exception 'source and target occupancy were not transferred';
  end if;
  if (select count(*) from app_private.rent_entries where reservation_id='f7300000-0000-0000-0000-000000000001')<>2
     or not exists(select 1 from app_private.reservation_attribution_transfers where reservation_id='f7300000-0000-0000-0000-000000000001'
       and from_placement_id='f7400000-0000-0000-0000-000000000001' and to_placement_id=v_current
       and rent_net_snapshot_minor=10000 and deposit_net_snapshot_minor=5000) then
    raise exception 'move changed ledger rows or net attribution snapshot';
  end if;
  if not exists(select 1 from app_private.tasks where id='f7500000-0000-0000-0000-000000000001'
       and state='cancelled' and version=5)
     or not exists(select 1 from app_private.task_transition_events where task_id='f7500000-0000-0000-0000-000000000001'
       and action='cancel' and from_state='accepted' and to_state='cancelled'
       and expected_version=4 and resulting_version=5)
     or not exists(select 1 from app_private.tasks where reservation_id='f7300000-0000-0000-0000-000000000001'
       and placement_id=v_current and kind='cleaning' and title='Təmizlik'
       and state='open' and due_at>now() and required_for_readiness and assignee_contact_id is null
       and description is null and inspection_event_id is null)
     or not exists(select 1 from app_private.tasks where id='f7500000-0000-0000-0000-000000000002'
       and kind='other' and state='completed' and version=7) then
    raise exception 'source/target cleaning tasks or completed task preservation is incorrect';
  end if;
  if (select count(*) from app_private.access_links where token_hash=repeat('a',64) and revoked_at is not null)<>1
     or (select count(*) from app_private.access_links where token_hash=repeat('b',64) and revoked_at is not null)<>1
     or not exists(select 1 from app_private.inspection_events where id='f7700000-0000-0000-0000-000000000001'
       and placement_id='f7400000-0000-0000-0000-000000000001') then
    raise exception 'old placement links were not revoked or inspection history changed';
  end if;
  select count(*) into v_task_event_count from app_private.task_transition_events
    where task_id='f7500000-0000-0000-0000-000000000001';
  if v_task_event_count<>1 then raise exception 'move task cancellation event count mismatch'; end if;
  if not exists(select 1 from app_private.audit_events where resource_id='f7300000-0000-0000-0000-000000000001'
       and capability='reservation.write' and reason='owner approved move')
     or not exists(select 1 from app_private.outbox where event_kind='reservation.moved'
       and payload->>'reservation_id'='f7300000-0000-0000-0000-000000000001') then
    raise exception 'move audit/outbox records are missing';
  end if;
end $$;

set local role authenticated;
set local request.jwt.claim.sub='f7000000-0000-0000-0000-000000000002';
do $$ begin
  if (select count(*) from api.read_current_reservation('f7300000-0000-0000-0000-000000000001'))<>0 then
    raise exception 'source-only manager can still read current guest after move';
  end if;
end $$;
rollback to savepoint source_manager_after_move;
release savepoint source_manager_after_move;

savepoint target_manager_after_move;
set local role authenticated;
set local request.jwt.claim.sub='f7000000-0000-0000-0000-000000000003';
do $$ begin
  if (select count(*) from api.read_current_reservation('f7300000-0000-0000-0000-000000000001'))<>1 then
    raise exception 'target manager cannot read moved current reservation';
  end if;
  begin
    perform api.move_reservation('f7300000-0000-0000-0000-000000000001'::uuid,
      '{"expected_version":2,"to_property_id":"f7200000-0000-4000-8000-000000000001","new_total_minor":28000}'::jsonb,
      'reservation-move-target-only-key-01');
    raise exception 'target-only manager moved reservation without source capability';
  exception when no_data_found or insufficient_privilege then null;
  end;
end $$;
rollback to savepoint target_manager_after_move;
release savepoint target_manager_after_move;
rollback;
