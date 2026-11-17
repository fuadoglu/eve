-- PostgreSQL 17 smoke: calendar range boundaries, capability and tenant scope.
begin;
set constraints all deferred;

do $$
begin
  if not exists (
    select 1 from pg_proc p
    where p.oid='api.list_calendar_property_options(uuid,integer)'::regprocedure
      and p.proowner='app_executor'::regrole and p.prosecdef and p.provolatile='s'
      and p.proconfig @> array['search_path=""']::text[]
  ) or has_function_privilege('anon','api.list_calendar_property_options(uuid,integer)','EXECUTE')
    or not has_function_privilege('authenticated','api.list_calendar_property_options(uuid,integer)','EXECUTE') then
    raise exception 'calendar property option RPC owner or grant boundary is unsafe';
  end if;
end $$;

insert into auth.users(id) values
  ('f9000000-0000-0000-0000-000000000001'),
  ('f9000000-0000-0000-0000-000000000002');
insert into auth.sessions(id,user_id,created_at) values
  ('f9100000-0000-0000-0000-000000000001','f9000000-0000-0000-0000-000000000001',now()-interval '1 hour'),
  ('f9100000-0000-0000-0000-000000000002','f9000000-0000-0000-0000-000000000002',now()-interval '1 hour');
insert into app_private.profiles(user_id,display_name) values
  ('f9000000-0000-0000-0000-000000000001','Calendar owner A'),
  ('f9000000-0000-0000-0000-000000000002','Calendar owner B');
insert into app_private.owner_accounts(id,owner_user_id) values
  ('f9200000-0000-0000-0000-000000000001','f9000000-0000-0000-0000-000000000001'),
  ('f9200000-0000-0000-0000-000000000002','f9000000-0000-0000-0000-000000000002');
insert into app_private.properties(id,owner_account_id,name,area) values
  ('f9300000-0000-4000-8000-000000000001','f9200000-0000-0000-0000-000000000001','Calendar A','Baku'),
  ('f9300000-0000-4000-8000-000000000002','f9200000-0000-0000-0000-000000000002','Calendar B','Baku');
insert into app_private.property_memberships(owner_account_id,property_id,user_id,permission,granted_by) values
  ('f9200000-0000-0000-0000-000000000001','f9300000-0000-4000-8000-000000000001',
   'f9000000-0000-0000-0000-000000000002','daily','f9000000-0000-0000-0000-000000000001');
insert into app_private.reservations(
  id,owner_account_id,property_id,current_placement_id,guest_name,check_in,check_out,
  check_in_time,check_out_time,guest_count,state,total_minor
) values (
  'f9400000-0000-4000-8000-000000000001','f9200000-0000-0000-0000-000000000001',
  'f9300000-0000-4000-8000-000000000001','f9500000-0000-0000-0000-000000000001',
  'Calendar guest','2099-01-01','2099-01-03','15:00','11:00',2,'confirmed',30000
);
insert into app_private.reservation_placements(
  id,owner_account_id,property_id,reservation_id,placement_no,check_in_snapshot,check_out_snapshot,effective_from,created_by
) values (
  'f9500000-0000-0000-0000-000000000001','f9200000-0000-0000-0000-000000000001',
  'f9300000-0000-4000-8000-000000000001','f9400000-0000-4000-8000-000000000001',1,
  '2099-01-01','2099-01-03',now(),'f9000000-0000-0000-0000-000000000001'
);
insert into app_private.reservations(
  id,owner_account_id,property_id,current_placement_id,guest_name,check_in,check_out,
  check_in_time,check_out_time,guest_count,state,total_minor,hold_expires_at
) values (
  'f9400000-0000-4000-8000-000000000002','f9200000-0000-0000-0000-000000000001',
  'f9300000-0000-4000-8000-000000000001','f9500000-0000-0000-0000-000000000002',
  'Expired calendar hold','2099-01-15','2099-01-17','15:00','11:00',1,'hold',10000,now()-interval '1 hour'
);
insert into app_private.reservation_placements(
  id,owner_account_id,property_id,reservation_id,placement_no,check_in_snapshot,check_out_snapshot,effective_from,created_by
) values (
  'f9500000-0000-0000-0000-000000000002','f9200000-0000-0000-0000-000000000001',
  'f9300000-0000-4000-8000-000000000001','f9400000-0000-4000-8000-000000000002',1,
  '2099-01-15','2099-01-17',now(),'f9000000-0000-0000-0000-000000000001'
);
insert into app_private.occupancy(owner_account_id,property_id,placement_id,date_range,expires_at)
values ('f9200000-0000-0000-0000-000000000001','f9300000-0000-4000-8000-000000000001',
  'f9500000-0000-0000-0000-000000000002',daterange('2099-01-15','2099-01-17','[)'),now()-interval '1 hour');
insert into app_private.manual_blocks(
  id,owner_account_id,property_id,check_in,check_out,reason
) values (
  'f9600000-0000-4000-8000-000000000001','f9200000-0000-0000-0000-000000000001',
  'f9300000-0000-4000-8000-000000000001','2099-01-10','2099-01-12','Synthetic private maintenance reason'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"f9000000-0000-0000-0000-000000000002","session_id":"f9100000-0000-0000-0000-000000000002","iat":1800000000}';
do $$
declare
  v_calendar jsonb;
  v_options record;
  v_reservation_before jsonb;
  v_expired_hold_before jsonb;
  v_blocks_before jsonb;
  v_failed boolean;
begin
  select * into v_options from api.list_calendar_property_options(null,100)
  where property_id='f9300000-0000-4000-8000-000000000001';
  if v_options.owner_display_name<>'Calendar owner A'
     or v_options.name<>'Calendar A' or v_options.area<>'Baku'
     or exists(select 1 from api.list_calendar_property_options(null,100)
       where property_id='f9300000-0000-4000-8000-000000000002') then
    raise exception 'owner option projection leaked or omitted scoped display name';
  end if;

  v_reservation_before := api.get_reservation('f9400000-0000-4000-8000-000000000001');
  v_expired_hold_before := api.get_reservation('f9400000-0000-4000-8000-000000000002');
  v_blocks_before := api.get_calendar('2099-01-01','2099-02-01',
       array['f9300000-0000-4000-8000-000000000001']::uuid[])->'blocks';
  v_calendar := api.get_calendar('2099-01-01','2099-02-01',array['f9300000-0000-4000-8000-000000000001']::uuid[]);
  if v_calendar->>'from'<>'2099-01-01' or v_calendar->>'to'<>'2099-02-01'
     or jsonb_array_length(v_calendar->'reservations')<>2
     or jsonb_array_length(v_calendar->'blocks')<>1
     or v_calendar#>>'{reservations,0,guest_name}'<>'Calendar guest'
     or v_calendar#>>'{reservations,0,status}'<>'confirmed'
     or v_calendar#>>'{reservations,1,guest_name}'<>'Expired calendar hold'
     or v_calendar#>>'{reservations,1,status}'<>'hold'
     or (v_calendar#>>'{reservations,1,hold_expires_at}')::timestamptz>=now()
     or v_calendar#>>'{blocks,0,property_id}'<>'f9300000-0000-4000-8000-000000000001' then
    raise exception 'authorized calendar projection omits or mislabels an expired hold: %',v_calendar;
  end if;

  if jsonb_array_length(api.get_calendar('2099-01-03','2099-01-04',
       array['f9300000-0000-4000-8000-000000000001']::uuid[])->'reservations')<>0
     or jsonb_array_length(api.get_calendar('2098-12-31','2099-01-01',
       array['f9300000-0000-4000-8000-000000000001']::uuid[])->'reservations')<>0 then
    raise exception 'calendar interval is not half-open at checkout/check-in';
  end if;

  v_failed:=false;
  begin
    perform api.get_calendar('2099-01-01','2099-04-05',array['f9300000-0000-4000-8000-000000000001']::uuid[]);
  exception when sqlstate '22023' then v_failed:=true;
  end;
  if not v_failed then raise exception 'calendar accepted a range above 93 days'; end if;

  v_failed:=false;
  begin
    perform api.get_calendar('2099-01-01','2099-02-01',array['f9300000-0000-4000-8000-000000000002']::uuid[]);
  exception when sqlstate 'P0002' then v_failed:=true;
  end;
  if not v_failed then raise exception 'calendar returned another owner property'; end if;

  v_failed:=false;
  begin
    perform api.get_calendar('2099-01-01','2099-02-01',array[
      'f9300000-0000-4000-8000-000000000001',
      'f9300000-0000-4000-8000-000000000002']::uuid[]);
  exception when sqlstate 'P0002' then v_failed:=true;
  end;
  if not v_failed then raise exception 'calendar accepted mixed authorized and foreign property IDs'; end if;

  if api.get_reservation('f9400000-0000-4000-8000-000000000001') is distinct from v_reservation_before
     or api.get_reservation('f9400000-0000-4000-8000-000000000002') is distinct from v_expired_hold_before
     or api.get_calendar('2099-01-01','2099-02-01',
       array['f9300000-0000-4000-8000-000000000001']::uuid[])->'blocks' is distinct from v_blocks_before then
    raise exception 'calendar GET mutated a domain row';
  end if;

  if api.revoke_my_sessions() is distinct from true then
    raise exception 'calendar smoke could not revoke the active test session';
  end if;
  v_failed:=false;
  begin
    perform * from api.list_calendar_property_options(null,100);
  exception when sqlstate '28000' then v_failed:=true;
  end;
  if not v_failed then
    raise exception 'calendar property options remained callable after session revocation';
  end if;
end $$;

rollback;
