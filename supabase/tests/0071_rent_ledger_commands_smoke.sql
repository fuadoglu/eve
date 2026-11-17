-- PostgreSQL 17 smoke: immutable rent/deposit commands, limits and replay.
begin;
set constraints all deferred;

do $$
begin
  if not exists(select 1 from pg_proc p where p.oid='api.create_rent_entry(uuid,jsonb,text)'::regprocedure
    and p.proowner='app_executor'::regrole and p.prosecdef and p.provolatile='v'
    and p.proconfig @> array['search_path=""']::text[])
    or has_function_privilege('anon','api.create_rent_entry(uuid,jsonb,text)','EXECUTE')
    or not has_function_privilege('authenticated','api.create_rent_entry(uuid,jsonb,text)','EXECUTE') then
    raise exception 'rent ledger command security boundary mismatch';
  end if;
  if has_table_privilege('authenticated','app_private.rent_entries','INSERT')
    or has_table_privilege('authenticated','app_private.rent_entries','UPDATE')
    or has_table_privilege('authenticated','app_private.rent_entries','DELETE')
    or has_table_privilege('app_executor','app_private.rent_entries','UPDATE')
    or has_table_privilege('app_executor','app_private.rent_entries','DELETE') then
    raise exception 'authenticated role received direct rent ledger mutation privilege';
  end if;
end $$;

insert into auth.users(id) values
  ('f9000000-0000-0000-0000-000000000021'),
  ('f9000000-0000-0000-0000-000000000022');
insert into auth.sessions(id,user_id,created_at) values
  ('f9100000-0000-0000-0000-000000000021','f9000000-0000-0000-0000-000000000021',now()-interval '1 hour'),
  ('f9100000-0000-0000-0000-000000000022','f9000000-0000-0000-0000-000000000022',now()-interval '1 hour');
insert into app_private.owner_accounts(id,owner_user_id)
values ('f9200000-0000-0000-0000-000000000021','f9000000-0000-0000-0000-000000000021');
insert into app_private.properties(id,owner_account_id,name,area)
values ('f9300000-0000-4000-8000-000000000021','f9200000-0000-0000-0000-000000000021','Ledger smoke home','Baku');
insert into app_private.subscriptions(owner_account_id,property_id,state,current_end)
values ('f9200000-0000-0000-0000-000000000021','f9300000-0000-4000-8000-000000000021','trialing',now()+interval '7 days');
insert into app_private.property_memberships(owner_account_id,property_id,user_id,permission,granted_by)
values ('f9200000-0000-0000-0000-000000000021','f9300000-0000-4000-8000-000000000021',
  'f9000000-0000-0000-0000-000000000022','daily','f9000000-0000-0000-0000-000000000021');
insert into app_private.reservations(
  id,owner_account_id,property_id,current_placement_id,guest_name,check_in,check_out,
  check_in_time,check_out_time,guest_count,state,total_minor
) values (
  'f9400000-0000-4000-8000-000000000021','f9200000-0000-0000-0000-000000000021',
  'f9300000-0000-4000-8000-000000000021','f9500000-0000-0000-0000-000000000021',
  'Ledger smoke guest','2099-02-01','2099-02-04','15:00','11:00',2,'confirmed',30000
);
insert into app_private.reservation_placements(
  id,owner_account_id,property_id,reservation_id,placement_no,check_in_snapshot,check_out_snapshot,effective_from,created_by
) values (
  'f9500000-0000-0000-0000-000000000021','f9200000-0000-0000-0000-000000000021',
  'f9300000-0000-4000-8000-000000000021','f9400000-0000-4000-8000-000000000021',1,
  '2099-02-01','2099-02-04',now(),'f9000000-0000-0000-0000-000000000021'
);
insert into app_private.inspection_days(id,owner_account_id,property_id,local_date)
values ('f9600000-0000-0000-0000-000000000021','f9200000-0000-0000-0000-000000000021',
  'f9300000-0000-4000-8000-000000000021','2099-02-04');
insert into app_private.rooms(id,owner_account_id,property_id,name)
values ('f9640000-0000-0000-0000-000000000021','f9200000-0000-0000-0000-000000000021',
  'f9300000-0000-4000-8000-000000000021','Smoke room');
insert into app_private.inventory_items(id,owner_account_id,property_id,room_id,name,state)
values ('f9650000-0000-0000-0000-000000000021','f9200000-0000-0000-0000-000000000021',
  'f9300000-0000-4000-8000-000000000021','f9640000-0000-0000-0000-000000000021','Smoke item','damaged');
insert into app_private.inspection_events(id,owner_account_id,property_id,day_id,handover_key,reservation_id,placement_id,event_kind,due_at)
values ('f9610000-0000-0000-0000-000000000021','f9200000-0000-0000-0000-000000000021',
  'f9300000-0000-4000-8000-000000000021','f9600000-0000-0000-0000-000000000021','rent-smoke-damage-inspection',
  'f9400000-0000-4000-8000-000000000021','f9500000-0000-0000-0000-000000000021','manual',now());
insert into app_private.inspection_snapshots(id,owner_account_id,property_id,event_id,inventory_version,manifest,content_hash)
values ('f9620000-0000-0000-0000-000000000021','f9200000-0000-0000-0000-000000000021',
  'f9300000-0000-4000-8000-000000000021','f9610000-0000-0000-0000-000000000021',1,'{}',repeat('a',64));
insert into app_private.inspection_snapshot_rooms(id,owner_account_id,property_id,snapshot_id,source_room_id,name)
values ('f9660000-0000-0000-0000-000000000021','f9200000-0000-0000-0000-000000000021',
  'f9300000-0000-4000-8000-000000000021','f9620000-0000-0000-0000-000000000021',
  'f9640000-0000-0000-0000-000000000021','Smoke room');
insert into app_private.inspection_snapshot_items(id,owner_account_id,property_id,snapshot_id,snapshot_room_id,source_item_id,name,quantity,unit,state)
values ('f9670000-0000-0000-0000-000000000021','f9200000-0000-0000-0000-000000000021',
  'f9300000-0000-4000-8000-000000000021','f9620000-0000-0000-0000-000000000021',
  'f9660000-0000-0000-0000-000000000021','f9650000-0000-0000-0000-000000000021','Smoke item',1,'ədəd','damaged');
insert into app_private.inspection_submissions(id,owner_account_id,property_id,event_id,snapshot_id,side,actor_user_id,state,completed_at)
values ('f9630000-0000-0000-0000-000000000021','f9200000-0000-0000-0000-000000000021',
  'f9300000-0000-4000-8000-000000000021','f9610000-0000-0000-0000-000000000021',
  'f9620000-0000-0000-0000-000000000021','giver','f9000000-0000-0000-0000-000000000021','completed',now());
insert into app_private.inspection_answers(id,owner_account_id,property_id,submission_id,snapshot_item_id,condition,actual_quantity,note)
values ('f9680000-0000-0000-0000-000000000021','f9200000-0000-0000-0000-000000000021',
  'f9300000-0000-4000-8000-000000000021','f9630000-0000-0000-0000-000000000021',
  'f9670000-0000-0000-0000-000000000021','damaged',1,'Damage recorded for acceptance smoke');

set local role authenticated;
set local request.jwt.claims = '{"sub":"f9000000-0000-0000-0000-000000000021","session_id":"f9100000-0000-0000-0000-000000000021","iat":1800000000}';
do $$
declare
  v_receipt jsonb;
  v_replay jsonb;
  v_extra_receipt jsonb;
  v_refund jsonb;
  v_refund_replay jsonb;
  v_deposit jsonb;
  v_allocation jsonb;
  v_page record;
  v_failed boolean := false;
begin
  v_receipt := api.create_rent_entry('f9400000-0000-4000-8000-000000000021',
    '{"kind":"rent_receipt","amount_minor":10000,"custodian":"owner"}', 'ledger-receipt-key-0001');
  v_replay := api.create_rent_entry('f9400000-0000-4000-8000-000000000021',
    '{"kind":"rent_receipt","amount_minor":10000,"custodian":"owner"}', 'ledger-receipt-key-0001');
  if v_receipt->>'id' is distinct from v_replay->>'id' or v_receipt->>'version'<>'1'
    or v_receipt->>'currency'<>'AZN' or v_receipt->>'updated_at' is distinct from v_receipt->>'created_at' then
    raise exception 'rent receipt replay or immutable DTO mismatch: % %',v_receipt,v_replay;
  end if;
  v_failed := false;
  begin
    perform api.create_rent_entry('f9400000-0000-4000-8000-000000000021',
      '{"kind":"rent_receipt","amount_minor":10001,"custodian":"owner"}', 'ledger-receipt-key-0001');
  exception when unique_violation then v_failed := true;
  end;
  if not v_failed then raise exception 'changed payload reused a durable rent ledger operation key'; end if;
  v_extra_receipt := api.create_rent_entry('f9400000-0000-4000-8000-000000000021',
    '{"kind":"rent_receipt","amount_minor":25000,"custodian":"owner"}', 'ledger-extra-receipt-key-001');
  if (api.get_reservation('f9400000-0000-4000-8000-000000000021')#>>'{balance,overpaid_minor}')::bigint<>5000 then
    raise exception 'AT11 overpayment was not visible after receipts exceeded the reservation quote';
  end if;
  v_refund := api.create_rent_entry('f9400000-0000-4000-8000-000000000021',
    jsonb_build_object('kind','rent_refund','amount_minor',6000,'custodian','owner','original_id',v_extra_receipt->>'id'),
    'ledger-rent-refund-key-001');
  v_refund_replay := api.create_rent_entry('f9400000-0000-4000-8000-000000000021',
    jsonb_build_object('kind','rent_refund','amount_minor',6000,'custodian','owner','original_id',v_extra_receipt->>'id'),
    'ledger-rent-refund-key-001');
  if v_refund->>'id' is distinct from v_refund_replay->>'id'
    or (select count(*) from app_private.rent_entries e where e.original_entry_id=(v_extra_receipt->>'id')::uuid and e.kind='rent_refund')<>1 then
    raise exception 'AT11 refund retry was not idempotent';
  end if;
  v_failed := false;
  begin
    perform api.create_rent_entry('f9400000-0000-4000-8000-000000000021',
      jsonb_build_object('kind','rent_refund','amount_minor',19001,'custodian','owner','original_id',v_extra_receipt->>'id'),
      'ledger-rent-refund-excess-key');
  exception when sqlstate '22023' then v_failed := true;
  end;
  if not v_failed then raise exception 'AT11 refund exceeded its original receipt remainder'; end if;
  v_failed := false;
  begin
    perform api.create_rent_entry('f9400000-0000-4000-8000-000000000021',
      '{"kind":"rent_receipt","amount_minor":1.5,"custodian":"owner"}', 'ledger-fractional-amount-key');
  exception when sqlstate '22023' then v_failed := true;
  end;
  if not v_failed then raise exception 'fractional qəpik amount was accepted'; end if;
  v_deposit := api.create_rent_entry('f9400000-0000-4000-8000-000000000021',
    '{"kind":"deposit_receipt","amount_minor":5000,"custodian":"owner"}', 'ledger-deposit-key-0001');
  if (api.get_reservation('f9400000-0000-4000-8000-000000000021')#>>'{balance,deposit_held_minor}')::bigint<>5000
    or exists(select 1 from app_private.rent_entries e where e.original_entry_id=(v_deposit->>'id')::uuid
      and e.kind in ('deposit_return','deposit_to_rent','deposit_to_damage')) then
    raise exception 'AT12 completed inspection did not remain financially separate from the deposit';
  end if;
  v_allocation := api.create_rent_entry('f9400000-0000-4000-8000-000000000021',
    jsonb_build_object('kind','deposit_to_damage','amount_minor',1200,'custodian','owner','original_id',v_deposit->>'id','note','Zədə üzrə razılaşma'),
    'ledger-allocation-key-0001');
  if v_allocation->>'kind'<>'deposit_to_damage' or v_allocation->>'amount_minor'<>'1200' then
    raise exception 'deposit allocation was not recorded separately from rent income';
  end if;
  begin
    perform api.create_rent_entry('f9400000-0000-4000-8000-000000000021',
      jsonb_build_object('kind','deposit_return','amount_minor',4000,'custodian','owner','original_id',v_deposit->>'id'),
      'ledger-excess-key-0001');
  exception when sqlstate '22023' then v_failed := true;
  end;
  if not v_failed then raise exception 'deposit return exceeded unallocated source balance'; end if;

  select * into v_page from api.list_reservation_rent_entries('f9400000-0000-4000-8000-000000000021',null,null,10) limit 1;
  if not found or v_page.currency<>'AZN' or v_page.version<>1 then raise exception 'rent ledger DTO page missing'; end if;
  if (api.get_reservation('f9400000-0000-4000-8000-000000000021')#>>'{balance,rent_received_minor}')::bigint<>29000
    or (api.get_reservation('f9400000-0000-4000-8000-000000000021')#>>'{balance,rent_refunded_minor}')::bigint<>6000
    or (api.get_reservation('f9400000-0000-4000-8000-000000000021')#>>'{balance,remaining_minor}')::bigint<>1000
    or (api.get_reservation('f9400000-0000-4000-8000-000000000021')#>>'{balance,overpaid_minor}')::bigint<>0
    or (api.get_reservation('f9400000-0000-4000-8000-000000000021')#>>'{balance,deposit_held_minor}')::bigint<>3800 then
    raise exception 'AT11 rent balance/refund or AT12 deposit isolation mismatch';
  end if;
end $$;

set local request.jwt.claims = '{"sub":"f9000000-0000-0000-0000-000000000022","session_id":"f9100000-0000-0000-0000-000000000022","iat":1800000000}';
do $$
declare v_failed boolean := false; v_source_id uuid;
begin
  perform api.create_rent_entry('f9400000-0000-4000-8000-000000000021',
    '{"kind":"rent_receipt","amount_minor":200,"custodian":"manager"}', 'ledger-daily-receipt-001');
  begin
    perform api.create_rent_entry('f9400000-0000-4000-8000-000000000021',
      '{"kind":"rent_receipt","amount_minor":200,"custodian":"owner"}', 'ledger-daily-owner-001');
  exception when insufficient_privilege then v_failed := true;
  end;
  if not v_failed then raise exception 'daily manager impersonated the owner custodian'; end if;
  perform api.create_rent_entry('f9400000-0000-4000-8000-000000000021',
    '{"kind":"deposit_receipt","amount_minor":200,"custodian":"manager"}', 'ledger-daily-deposit-001');
  select e.id into v_source_id from api.list_reservation_rent_entries(
    'f9400000-0000-4000-8000-000000000021',null,null,20) e where e.kind='deposit_receipt' and e.custodian='manager';
  if v_source_id is null then raise exception 'daily manager cannot read the current deposit source'; end if;
  v_failed := false;
  begin
    perform api.create_rent_entry('f9400000-0000-4000-8000-000000000021',
      jsonb_build_object('kind','deposit_to_damage','amount_minor',100,'custodian','manager','original_id',v_source_id,'note','test'),
      'ledger-daily-allocation-001');
  exception when insufficient_privilege then v_failed := true;
  end;
  if not v_failed then raise exception 'daily manager allocated deposit without finance.manage'; end if;
end $$;
rollback;
