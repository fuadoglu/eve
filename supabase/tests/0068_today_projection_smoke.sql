-- PostgreSQL 17 smoke: Today projection ordering, ledger-safe balance and tenant scope.
begin;
set constraints all deferred;

insert into auth.users(id) values
 ('f8000000-0000-0000-0000-000000000001'),
 ('f8000000-0000-0000-0000-000000000002'),
 ('f8000000-0000-0000-0000-000000000003');
insert into auth.sessions(id,user_id,created_at) values
 ('f8100000-0000-0000-0000-000000000001','f8000000-0000-0000-0000-000000000001',now()-interval '1 hour'),
 ('f8100000-0000-0000-0000-000000000002','f8000000-0000-0000-0000-000000000002',now()-interval '1 hour'),
 ('f8100000-0000-0000-0000-000000000003','f8000000-0000-0000-0000-000000000003',now()-interval '1 hour');
insert into app_private.owner_accounts(id,owner_user_id) values
 ('f8200000-0000-0000-0000-000000000001','f8000000-0000-0000-0000-000000000001'),
 ('f8200000-0000-0000-0000-000000000002','f8000000-0000-0000-0000-000000000002');
insert into app_private.properties(id,owner_account_id,name,area) values
 ('f8300000-0000-4000-8000-000000000001','f8200000-0000-0000-0000-000000000001','Today A home','Baku'),
 ('f8300000-0000-4000-8000-000000000002','f8200000-0000-0000-0000-000000000002','Today B private home','Baku');
insert into app_private.property_memberships(owner_account_id,property_id,user_id,permission,granted_by) values
 ('f8200000-0000-0000-0000-000000000001','f8300000-0000-4000-8000-000000000001',
  'f8000000-0000-0000-0000-000000000003','daily','f8000000-0000-0000-0000-000000000001');

do $$ declare v_today date := (statement_timestamp() at time zone 'Asia/Baku')::date;
begin
  insert into app_private.subscriptions(owner_account_id,property_id,state,current_end) values
    ('f8200000-0000-0000-0000-000000000001','f8300000-0000-4000-8000-000000000001','active',
     (v_today::timestamp at time zone 'Asia/Baku')),
    ('f8200000-0000-0000-0000-000000000002','f8300000-0000-4000-8000-000000000002','active',
     (v_today::timestamp at time zone 'Asia/Baku'));
  insert into app_private.reservations(
    id,owner_account_id,property_id,current_placement_id,guest_name,check_in,check_out,
    check_in_time,check_out_time,total_minor
  ) values
   ('f8400000-0000-0000-0000-000000000001','f8200000-0000-0000-0000-000000000001',
    'f8300000-0000-4000-8000-000000000001','f8500000-0000-0000-0000-000000000001',
    'Synthetic A guest',v_today,v_today+1,'15:00','12:00',30000),
   ('f8400000-0000-0000-0000-000000000002','f8200000-0000-0000-0000-000000000002',
    'f8300000-0000-4000-8000-000000000002','f8500000-0000-0000-0000-000000000002',
    'Synthetic B private guest',v_today,v_today+1,'15:00','12:00',30000),
   ('f8400000-0000-0000-0000-000000000003','f8200000-0000-0000-0000-000000000001',
    'f8300000-0000-4000-8000-000000000001','f8500000-0000-0000-0000-000000000003',
    'Synthetic departure guest',v_today-1,v_today,'15:00','12:00',30000),
   ('f8400000-0000-0000-0000-000000000004','f8200000-0000-0000-0000-000000000001',
    'f8300000-0000-4000-8000-000000000001','f8500000-0000-0000-0000-000000000005',
    'Synthetic moved guest',v_today+1,v_today+2,'15:00','12:00',30000);
  insert into app_private.reservation_placements(
    id,owner_account_id,property_id,reservation_id,placement_no,check_in_snapshot,check_out_snapshot,effective_from,created_by
  ) values
   ('f8500000-0000-0000-0000-000000000001','f8200000-0000-0000-0000-000000000001',
    'f8300000-0000-4000-8000-000000000001','f8400000-0000-0000-0000-000000000001',1,
    v_today,v_today+1,now()-interval '1 day','f8000000-0000-0000-0000-000000000001'),
   ('f8500000-0000-0000-0000-000000000002','f8200000-0000-0000-0000-000000000002',
    'f8300000-0000-4000-8000-000000000002','f8400000-0000-0000-0000-000000000002',1,
    v_today,v_today+1,now()-interval '1 day','f8000000-0000-0000-0000-000000000002'),
   ('f8500000-0000-0000-0000-000000000003','f8200000-0000-0000-0000-000000000001',
    'f8300000-0000-4000-8000-000000000001','f8400000-0000-0000-0000-000000000003',1,
    v_today-1,v_today,now()-interval '2 days','f8000000-0000-0000-0000-000000000001'),
   ('f8500000-0000-0000-0000-000000000004','f8200000-0000-0000-0000-000000000001',
    'f8300000-0000-4000-8000-000000000001','f8400000-0000-0000-0000-000000000004',1,
    v_today,v_today+1,now()-interval '1 day','f8000000-0000-0000-0000-000000000001',now()-interval '1 hour'),
   ('f8500000-0000-0000-0000-000000000005','f8200000-0000-0000-0000-000000000001',
    'f8300000-0000-4000-8000-000000000001','f8400000-0000-0000-0000-000000000004',2,
    v_today+1,v_today+2,now(),'f8000000-0000-0000-0000-000000000001');
  insert into app_private.occupancy(owner_account_id,property_id,placement_id,date_range) values
   ('f8200000-0000-0000-0000-000000000001','f8300000-0000-4000-8000-000000000001',
    'f8500000-0000-0000-0000-000000000001',daterange(v_today,v_today+1,'[)')),
   ('f8200000-0000-0000-0000-000000000002','f8300000-0000-4000-8000-000000000002',
    'f8500000-0000-0000-0000-000000000002',daterange(v_today,v_today+1,'[)')),
   ('f8200000-0000-0000-0000-000000000001','f8300000-0000-4000-8000-000000000001',
    'f8500000-0000-0000-0000-000000000003',daterange(v_today-1,v_today,'[)')),
   ('f8200000-0000-0000-0000-000000000001','f8300000-0000-4000-8000-000000000001',
    'f8500000-0000-0000-0000-000000000005',daterange(v_today+1,v_today+2,'[)'));
  insert into app_private.rent_entries(
    id,owner_account_id,property_id,reservation_id,placement_id,kind,amount_minor,
    custodian,custodian_user_id,actor_id,occurred_at,operation_key
  ) values
   ('f8600000-0000-0000-0000-000000000001','f8200000-0000-0000-0000-000000000001',
    'f8300000-0000-4000-8000-000000000001','f8400000-0000-0000-0000-000000000001',
    'f8500000-0000-0000-0000-000000000001','rent_receipt',10000,'owner',
    'f8000000-0000-0000-0000-000000000001','f8000000-0000-0000-0000-000000000001',now(),'today-rent-a'),
   ('f8600000-0000-0000-0000-000000000002','f8200000-0000-0000-0000-000000000001',
    'f8300000-0000-4000-8000-000000000001','f8400000-0000-0000-0000-000000000001',
    'f8500000-0000-0000-0000-000000000001','deposit_receipt',5000,'owner',
    'f8000000-0000-0000-0000-000000000001','f8000000-0000-0000-0000-000000000001',now(),'today-deposit-a');
  insert into app_private.tasks(
    id,owner_account_id,property_id,reservation_id,placement_id,kind,title,due_at,state
  ) values
   ('f8700000-0000-0000-0000-000000000001','f8200000-0000-0000-0000-000000000001',
    'f8300000-0000-4000-8000-000000000001','f8400000-0000-0000-0000-000000000001',
    'f8500000-0000-0000-0000-000000000001','cleaning','Synthetic overdue cleaning',
    ((v_today-1)::timestamp at time zone 'Asia/Baku'),'open'),
   ('f8700000-0000-0000-0000-000000000002','f8200000-0000-0000-0000-000000000002',
    'f8300000-0000-4000-8000-000000000002','f8400000-0000-0000-0000-000000000002',
    'f8500000-0000-0000-0000-000000000002','cleaning','Synthetic private cleaning',
    ((v_today-1)::timestamp at time zone 'Asia/Baku'),'open'),
   ('f8700000-0000-0000-0000-000000000003','f8200000-0000-0000-0000-000000000001',
    'f8300000-0000-4000-8000-000000000001','f8400000-0000-0000-0000-000000000003',
    'f8500000-0000-0000-0000-000000000003','cleaning','Synthetic due-today reported task',
    ((v_today::timestamp at time zone 'Asia/Baku')+interval '13 hours'),'reported_done'),
   ('f8700000-0000-0000-0000-000000000004','f8200000-0000-0000-0000-000000000001',
    'f8300000-0000-4000-8000-000000000001','f8400000-0000-0000-0000-000000000004',
    'f8500000-0000-0000-0000-000000000004','cleaning','Synthetic stale placement task',
    ((v_today::timestamp at time zone 'Asia/Baku')+interval '12 hours'),'open');
end $$;

set local role authenticated;
set local request.jwt.claims = '{"sub":"f8000000-0000-0000-0000-000000000003","session_id":"f8100000-0000-0000-0000-000000000003","iat":1800000000}';
do $$ declare v_projection jsonb; v_date date := (statement_timestamp() at time zone 'Asia/Baku')::date;
begin
  v_projection := api.get_today(v_date,'f8200000-0000-0000-0000-000000000001');
  if v_projection->>'local_date'<>v_date::text or v_projection->>'timezone'<>'Asia/Baku'
     or (select count(*) from jsonb_array_elements(v_projection->'cards') c
         where c->>'property_id'='f8300000-0000-4000-8000-000000000001')<>6
     or exists (select 1 from jsonb_array_elements(v_projection->'cards') c
         where c->>'id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
            or c->>'target_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
     or exists (select 1 from jsonb_array_elements(v_projection->'cards') c
         where c->>'property_id'<>'f8300000-0000-4000-8000-000000000001'
            or c::text like '%private%') then
    raise exception 'daily manager received an invalid or cross-property Today projection: %',v_projection;
  end if;
  if (select count(*) from jsonb_array_elements(v_projection->'cards') c where c->>'kind'='arrival')<>1
     or (select count(*) from jsonb_array_elements(v_projection->'cards') c where c->>'kind'='departure')<>1
     or (select count(*) from jsonb_array_elements(v_projection->'cards') c where c->>'kind'='task')<>2
     or (select count(*) from jsonb_array_elements(v_projection->'cards') c where c->>'kind'='subscription')<>1
     or (select amount_minor::bigint from jsonb_array_elements(v_projection->'cards') c
         where c->>'kind'='rent_due')<>20000 then
    raise exception 'arrival, overdue task, subscription or rent balance projection failed: %',v_projection;
  end if;
  if not exists (select 1 from jsonb_array_elements(v_projection->'cards') c
       where c->>'kind'='task' and c->>'action'='open_task'
         and c->>'title'='Synthetic overdue cleaning')
     or (select c->>'action' from jsonb_array_elements(v_projection->'cards') c
         where c->>'kind'='arrival')<>'check_in' then
    raise exception 'Today action mapping failed: %',v_projection;
  end if;
  if not exists (select 1 from jsonb_array_elements(v_projection->'cards') c
       where c->>'kind'='departure' and c->>'action'='check_out')
     or not exists (select 1 from jsonb_array_elements(v_projection->'cards') c
       where c->>'kind'='task' and c->>'action'='confirm_task'
         and c->>'title'='Synthetic due-today reported task')
     or exists (select 1 from jsonb_array_elements(v_projection->'cards') c
       where c->>'title'='Synthetic stale placement task') then
    raise exception 'departure, reported task or stale placement filtering failed: %',v_projection;
  end if;
  if v_projection->'cards'->0->>'kind'<>'task'
     or v_projection->'cards'->1->>'kind'<>'departure'
     or v_projection->'cards'->2->>'kind'<>'arrival'
     or v_projection->'cards'->3->>'kind'<>'task'
     or v_projection->'cards'->4->>'kind'<>'rent_due'
     or v_projection->'cards'->5->>'kind'<>'subscription' then
    raise exception 'Today priority order changed: %',v_projection;
  end if;
  v_projection := api.get_today(v_date,null);
  if (select count(*) from jsonb_array_elements(v_projection->'cards') c)<>6
     or exists (select 1 from jsonb_array_elements(v_projection->'cards') c
         where c->>'property_id'<>'f8300000-0000-4000-8000-000000000001'
            or c::text like '%private%') then
    raise exception 'unfiltered Today projection crossed membership scope: %',v_projection;
  end if;
  begin
    perform api.get_today(v_date,'f8200000-0000-0000-0000-000000000002');
    raise exception 'daily manager selected an unauthorized owner scope';
  exception when no_data_found then null;
  end;
  begin
    execute 'select id from app_private.tasks limit 1';
    raise exception 'authenticated user directly read task base table';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

set local role anon;
do $$ begin
  if has_function_privilege(current_user,'api.get_today(date,uuid)','EXECUTE') then
    raise exception 'anon role can execute Today RPC';
  end if;
end $$;
reset role;
rollback;
