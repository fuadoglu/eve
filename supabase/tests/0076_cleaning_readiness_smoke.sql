-- EVE-018.1 synthetic DB component: required task/inspection/readiness projection.
do $$ begin
  if has_function_privilege('authenticated',
       'app_private.recompute_property_readiness(uuid,uuid)','EXECUTE')
     or has_function_privilege('service_role',
       'app_private.recompute_property_readiness(uuid,uuid)','EXECUTE')
     or has_function_privilege('app_executor',
       'app_private.recompute_property_readiness(uuid,uuid)','EXECUTE') then
    raise exception 'readiness recompute helper is directly callable';
  end if;
end $$;
begin;
set constraints all deferred;
insert into auth.users(id,email) values
  ('a1810000-0000-0000-0000-000000000001','eve0181-owner@example.test');
insert into app_private.owner_accounts(id,owner_user_id) values
  ('a1811000-0000-0000-0000-000000000001','a1810000-0000-0000-0000-000000000001');
insert into app_private.properties(id,owner_account_id,name,area) values
  ('a1812000-0000-0000-0000-000000000001','a1811000-0000-0000-0000-000000000001','Cleaning A','Bakı'),
  ('a1812000-0000-0000-0000-000000000002','a1811000-0000-0000-0000-000000000001','Cleaning B','Bakı'),
  ('a1812000-0000-0000-0000-000000000003','a1811000-0000-0000-0000-000000000001','Cleaning C','Bakı');
insert into app_private.reservations(id,owner_account_id,property_id,current_placement_id,
  guest_name,check_in,check_out,check_in_time,check_out_time,guest_count,state,total_minor,
  actual_check_in_at) values
  ('a181a000-0000-0000-0000-000000000001','a1811000-0000-0000-0000-000000000001',
   'a1812000-0000-0000-0000-000000000002','a181b000-0000-0000-0000-000000000001',
   'Guest',current_date-1,current_date+1,'14:00','12:00',1,'checked_in',10000,now());
insert into app_private.reservation_placements(id,owner_account_id,property_id,reservation_id,
  placement_no,check_in_snapshot,check_out_snapshot,effective_from,created_by) values
  ('a181b000-0000-0000-0000-000000000001','a1811000-0000-0000-0000-000000000001',
   'a1812000-0000-0000-0000-000000000002','a181a000-0000-0000-0000-000000000001',
   1,current_date-1,current_date+1,now(),'a1810000-0000-0000-0000-000000000001');
insert into app_private.tasks(id,owner_account_id,property_id,reservation_id,placement_id,
  kind,title,due_at,required_for_readiness) values
  ('a181c000-0000-0000-0000-000000000001','a1811000-0000-0000-0000-000000000001',
   'a1812000-0000-0000-0000-000000000002','a181a000-0000-0000-0000-000000000001',
   'a181b000-0000-0000-0000-000000000001','cleaning','Future cleaning',now()+interval '1 day',false);
do $$ begin
  begin
    insert into app_private.tasks(owner_account_id,property_id,reservation_id,placement_id,
      kind,title,due_at,required_for_readiness) values
      ('a1811000-0000-0000-0000-000000000001','a1812000-0000-0000-0000-000000000002',
       'a181a000-0000-0000-0000-000000000001','a181b000-0000-0000-0000-000000000001',
       'cleaning','Duplicate',now(),true);
    raise exception 'duplicate active reservation cleaning task accepted';
  exception when unique_violation then null;
  end;
end $$;
insert into app_private.inspection_days(id,owner_account_id,property_id,local_date)
  values ('a1813000-0000-0000-0000-000000000002','a1811000-0000-0000-0000-000000000001',
   'a1812000-0000-0000-0000-000000000002',current_date);
insert into app_private.inspection_events(id,owner_account_id,property_id,day_id,handover_key,
  reservation_id,placement_id,event_kind,due_at) values
  ('a1814000-0000-0000-0000-000000000002','a1811000-0000-0000-0000-000000000001',
   'a1812000-0000-0000-0000-000000000002','a1813000-0000-0000-0000-000000000002',
   'reservation:a181a000-0000-0000-0000-000000000001:checkout:a181b000-0000-0000-0000-000000000001',
   'a181a000-0000-0000-0000-000000000001','a181b000-0000-0000-0000-000000000001','check_out',now());
update app_private.reservations set state='completed',actual_check_out_at=now()
  where id='a181a000-0000-0000-0000-000000000001';
do $$ begin
  if not (select required_for_readiness from app_private.tasks
      where id='a181c000-0000-0000-0000-000000000001')
     or (select readiness from app_private.properties
      where id='a1812000-0000-0000-0000-000000000002')<>'cleaning_pending' then
    raise exception 'checkout did not promote reused cleaning task to required/pending';
  end if;
end $$;

-- A cleaning task completed before checkout remains immutable history, but it
-- must still be tied to the new checkout inspection before readiness can pass.
insert into app_private.reservations(id,owner_account_id,property_id,current_placement_id,
  guest_name,check_in,check_out,check_in_time,check_out_time,guest_count,state,total_minor,
  actual_check_in_at) values
  ('a181a000-0000-0000-0000-000000000002','a1811000-0000-0000-0000-000000000001',
   'a1812000-0000-0000-0000-000000000003','a181b000-0000-0000-0000-000000000002',
   'Guest 2',current_date-1,current_date+1,'14:00','12:00',1,'checked_in',10000,now());
insert into app_private.reservation_placements(id,owner_account_id,property_id,reservation_id,
  placement_no,check_in_snapshot,check_out_snapshot,effective_from,created_by) values
  ('a181b000-0000-0000-0000-000000000002','a1811000-0000-0000-0000-000000000001',
   'a1812000-0000-0000-0000-000000000003','a181a000-0000-0000-0000-000000000002',
   1,current_date-1,current_date+1,now(),'a1810000-0000-0000-0000-000000000001');
insert into app_private.contacts(id,owner_account_id,name,phone,service_type)
  values ('a181d000-0000-0000-0000-000000000002','a1811000-0000-0000-0000-000000000001',
   'Cleaner','+994501112233','cleaner');
insert into app_private.tasks(id,owner_account_id,property_id,reservation_id,placement_id,
  kind,title,description,due_at,assignee_contact_id,state,reported_done_at,confirmed_at,confirmed_by,
  required_for_readiness,version) values
  ('a181c000-0000-0000-0000-000000000002','a1811000-0000-0000-0000-000000000001',
   'a1812000-0000-0000-0000-000000000003','a181a000-0000-0000-0000-000000000002',
   'a181b000-0000-0000-0000-000000000002','cleaning','Prior cleaning','Keep this instruction',
   now()-interval '2 days','a181d000-0000-0000-0000-000000000002','completed',now()-interval '1 day',now()-interval '1 day',
   'a1810000-0000-0000-0000-000000000001',false,2);
insert into app_private.task_transition_events(owner_account_id,property_id,task_id,action,
  from_state,to_state,actor_user_id,note,idempotency_scope,idempotency_key,request_hash,
  expected_version,resulting_version) values
  ('a1811000-0000-0000-0000-000000000001','a1812000-0000-0000-0000-000000000003',
   'a181c000-0000-0000-0000-000000000002','confirm','reported_done','completed',
   'a1810000-0000-0000-0000-000000000001',null,
   'user:a1810000-0000-0000-0000-000000000001:confirm','eve0181_completed_task_1',repeat('b',64),1,2);
insert into app_private.inspection_days(owner_account_id,property_id,local_date)
  values ('a1811000-0000-0000-0000-000000000001','a1812000-0000-0000-0000-000000000003',current_date);
insert into app_private.inspection_events(owner_account_id,property_id,day_id,handover_key,
  reservation_id,placement_id,event_kind,due_at)
select 'a1811000-0000-0000-0000-000000000001','a1812000-0000-0000-0000-000000000003',d.id,
  'reservation:a181a000-0000-0000-0000-000000000002:checkout:a181b000-0000-0000-0000-000000000002',
  'a181a000-0000-0000-0000-000000000002','a181b000-0000-0000-0000-000000000002','check_out',now()
from app_private.inspection_days d
where d.property_id='a1812000-0000-0000-0000-000000000003' and d.local_date=current_date;
update app_private.reservations set state='completed',actual_check_out_at=now()
  where id='a181a000-0000-0000-0000-000000000002';
do $$ begin
  if (select state from app_private.tasks where id='a181c000-0000-0000-0000-000000000002')<>'completed'
     or (select required_for_readiness from app_private.tasks where id='a181c000-0000-0000-0000-000000000002') is not true
     or (select title from app_private.tasks where id='a181c000-0000-0000-0000-000000000002')<>'Prior cleaning'
     or (select description from app_private.tasks where id='a181c000-0000-0000-0000-000000000002')<>'Keep this instruction'
     or (select assignee_contact_id from app_private.tasks where id='a181c000-0000-0000-0000-000000000002')<>'a181d000-0000-0000-0000-000000000002'
     or (select version from app_private.tasks where id='a181c000-0000-0000-0000-000000000002')<>3
     or (select inspection_event_id from app_private.tasks where id='a181c000-0000-0000-0000-000000000002')<>
       (select e.id from app_private.inspection_events e where e.reservation_id='a181a000-0000-0000-0000-000000000002')
     or (select readiness from app_private.properties where id='a1812000-0000-0000-0000-000000000003')<>'cleaning_pending'
     or (select count(*) from app_private.task_transition_events where task_id='a181c000-0000-0000-0000-000000000002')<>1
     or (select resulting_version from app_private.task_transition_events where task_id='a181c000-0000-0000-0000-000000000002')<>2 then
    raise exception 'pre-checkout completion escaped readiness or history/instruction changed';
  end if;
end $$;
insert into app_private.inspection_snapshots(id,owner_account_id,property_id,event_id,inventory_version,manifest,content_hash)
select 'a1815000-0000-0000-0000-000000000002','a1811000-0000-0000-0000-000000000001',
  'a1812000-0000-0000-0000-000000000003',e.id,1,'{}',repeat('c',64)
from app_private.inspection_events e where e.reservation_id='a181a000-0000-0000-0000-000000000002';
insert into app_private.rooms(id,owner_account_id,property_id,name) values
  ('a1817000-0000-0000-0000-000000000002','a1811000-0000-0000-0000-000000000001',
   'a1812000-0000-0000-0000-000000000003','Room C');
insert into app_private.inspection_snapshot_rooms(id,owner_account_id,property_id,snapshot_id,source_room_id,name) values
  ('a1816000-0000-0000-0000-000000000002','a1811000-0000-0000-0000-000000000001',
   'a1812000-0000-0000-0000-000000000003','a1815000-0000-0000-0000-000000000002',
   'a1817000-0000-0000-0000-000000000002','Room C');
insert into app_private.inspection_submissions(id,owner_account_id,property_id,event_id,snapshot_id,side,
  actor_user_id,state,completed_at)
select 'a1819000-0000-0000-0000-000000000002','a1811000-0000-0000-0000-000000000001',
  'a1812000-0000-0000-0000-000000000003',e.id,'a1815000-0000-0000-0000-000000000002',
  'giver','a1810000-0000-0000-0000-000000000001','completed',now()
from app_private.inspection_events e where e.reservation_id='a181a000-0000-0000-0000-000000000002';
insert into app_private.inspection_room_answers(owner_account_id,property_id,submission_id,snapshot_room_id,result,confirmed_at)
  values ('a1811000-0000-0000-0000-000000000001','a1812000-0000-0000-0000-000000000003',
   'a1819000-0000-0000-0000-000000000002','a1816000-0000-0000-0000-000000000002','ok',now());
do $$ begin
  if (select readiness from app_private.properties where id='a1812000-0000-0000-0000-000000000003')<>'ready' then
    raise exception 'post-checkout inspection did not release preserved completed task';
  end if;
end $$;
insert into app_private.inspection_days(id,owner_account_id,property_id,local_date) values
  ('a1813000-0000-0000-0000-000000000001','a1811000-0000-0000-0000-000000000001',
   'a1812000-0000-0000-0000-000000000001',current_date);
insert into app_private.inspection_events(id,owner_account_id,property_id,day_id,handover_key,event_kind,due_at) values
  ('a1814000-0000-0000-0000-000000000001','a1811000-0000-0000-0000-000000000001',
   'a1812000-0000-0000-0000-000000000001','a1813000-0000-0000-0000-000000000001',
   'eve0181-cleaning-a','manual',now());
insert into app_private.inspection_snapshots(id,owner_account_id,property_id,event_id,inventory_version,manifest,content_hash) values
  ('a1815000-0000-0000-0000-000000000001','a1811000-0000-0000-0000-000000000001',
   'a1812000-0000-0000-0000-000000000001','a1814000-0000-0000-0000-000000000001',1,'{}',repeat('a',64));
insert into app_private.rooms(id,owner_account_id,property_id,name) values
  ('a1817000-0000-0000-0000-000000000001','a1811000-0000-0000-0000-000000000001',
   'a1812000-0000-0000-0000-000000000001','Room');
insert into app_private.inspection_snapshot_rooms(id,owner_account_id,property_id,snapshot_id,source_room_id,name) values
  ('a1816000-0000-0000-0000-000000000001','a1811000-0000-0000-0000-000000000001',
   'a1812000-0000-0000-0000-000000000001','a1815000-0000-0000-0000-000000000001',
   'a1817000-0000-0000-0000-000000000001','Room');
insert into app_private.tasks(id,owner_account_id,property_id,kind,title,due_at,required_for_readiness,inspection_event_id) values
  ('a1818000-0000-0000-0000-000000000001','a1811000-0000-0000-0000-000000000001',
   'a1812000-0000-0000-0000-000000000001','cleaning','Cleaning A',now(),true,
   'a1814000-0000-0000-0000-000000000001'),
  ('a1818000-0000-0000-0000-000000000002','a1811000-0000-0000-0000-000000000001',
   'a1812000-0000-0000-0000-000000000001','repair','Safety check',now(),true,
   'a1814000-0000-0000-0000-000000000001');
do $$ begin
  if (select readiness from app_private.properties where id='a1812000-0000-0000-0000-000000000001')<>'cleaning_pending'
    or (select readiness from app_private.properties where id='a1812000-0000-0000-0000-000000000002')<>'cleaning_pending' then
    raise exception 'required task did not keep both properties independently pending';
  end if;
end $$;

-- A completed task cannot clear readiness before its linked inspection is complete.
update app_private.tasks set state='completed' where id='a1818000-0000-0000-0000-000000000001';
do $$ begin
  if (select readiness from app_private.properties where id='a1812000-0000-0000-0000-000000000001')<>'cleaning_pending' then
    raise exception 'first completion cleared another required task';
  end if;
end $$;
update app_private.tasks set state='completed' where id='a1818000-0000-0000-0000-000000000002';
do $$ begin
  if (select readiness from app_private.properties where id='a1812000-0000-0000-0000-000000000001')<>'cleaning_pending' then
    raise exception 'completion without linked inspection cleared pending readiness';
  end if;
end $$;
insert into app_private.inspection_submissions(id,owner_account_id,property_id,event_id,snapshot_id,side,
  actor_user_id,state,completed_at) values
  ('a1819000-0000-0000-0000-000000000001','a1811000-0000-0000-0000-000000000001',
   'a1812000-0000-0000-0000-000000000001','a1814000-0000-0000-0000-000000000001',
   'a1815000-0000-0000-0000-000000000001','giver','a1810000-0000-0000-0000-000000000001',
   'completed',now());
do $$ begin
  if (select readiness from app_private.properties where id='a1812000-0000-0000-0000-000000000001')<>'cleaning_pending' then
    raise exception 'missing room answer allowed ready state';
  end if;
end $$;
insert into app_private.inspection_room_answers(owner_account_id,property_id,submission_id,snapshot_room_id,result,confirmed_at)
 values ('a1811000-0000-0000-0000-000000000001','a1812000-0000-0000-0000-000000000001',
   'a1819000-0000-0000-0000-000000000001','a1816000-0000-0000-0000-000000000001','ok',now());
do $$ begin
  if (select readiness from app_private.properties where id='a1812000-0000-0000-0000-000000000001')<>'ready' then
    raise exception 'completed inspection and all required tasks did not mark ready';
  end if;
end $$;

-- Removing an answer after completion must reopen the readiness gate; adding
-- it back must clear the gate without an explicit helper call.
delete from app_private.inspection_room_answers
  where submission_id='a1819000-0000-0000-0000-000000000001';
do $$ begin
  if (select readiness from app_private.properties
      where id='a1812000-0000-0000-0000-000000000001')<>'cleaning_pending' then
    raise exception 'answer deletion failed to reopen readiness';
  end if;
end $$;
insert into app_private.inspection_room_answers(owner_account_id,property_id,submission_id,snapshot_room_id,result,confirmed_at)
 values ('a1811000-0000-0000-0000-000000000001','a1812000-0000-0000-0000-000000000001',
   'a1819000-0000-0000-0000-000000000001','a1816000-0000-0000-0000-000000000001','ok',now());
do $$ begin
  if (select readiness from app_private.properties
      where id='a1812000-0000-0000-0000-000000000001')<>'ready' then
    raise exception 'answer restoration failed to clear readiness';
  end if;
end $$;

-- An ordinary task state write recomputes readiness in the same transaction.
insert into app_private.tasks(id,owner_account_id,property_id,kind,title,due_at,required_for_readiness,inspection_event_id) values
  ('a1818000-0000-0000-0000-000000000004','a1811000-0000-0000-0000-000000000001',
   'a1812000-0000-0000-0000-000000000001','repair','Required repair',now(),true,
   'a1814000-0000-0000-0000-000000000001');
update app_private.tasks set state='completed'
  where id='a1818000-0000-0000-0000-000000000004';
do $$ begin
  if (select readiness from app_private.properties where id='a1812000-0000-0000-0000-000000000001')<>'ready' then
    raise exception 'task completion did not synchronously recompute readiness';
  end if;
end $$;

-- A new required task reopens cleaning; an explicit attention state is preserved.
insert into app_private.tasks(id,owner_account_id,property_id,kind,title,due_at,required_for_readiness) values
  ('a1818000-0000-0000-0000-000000000003','a1811000-0000-0000-0000-000000000001',
   'a1812000-0000-0000-0000-000000000001','cleaning','Second turnover',now(),true);
update app_private.properties set readiness='attention_required'
  where id='a1812000-0000-0000-0000-000000000001';
update app_private.tasks set state='cancelled'
  where id='a1818000-0000-0000-0000-000000000003';
do $$ begin
  if (select readiness from app_private.properties where id='a1812000-0000-0000-0000-000000000001')<>'attention_required' then
    raise exception 'task cancellation silently cleared explicit attention state';
  end if;
end $$;
rollback;
