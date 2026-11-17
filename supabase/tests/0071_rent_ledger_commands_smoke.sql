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

set local role authenticated;
set local request.jwt.claims = '{"sub":"f9000000-0000-0000-0000-000000000021","session_id":"f9100000-0000-0000-0000-000000000021","iat":1800000000}';
do $$
declare
  v_receipt jsonb;
  v_replay jsonb;
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
  v_deposit := api.create_rent_entry('f9400000-0000-4000-8000-000000000021',
    '{"kind":"deposit_receipt","amount_minor":5000,"custodian":"owner"}', 'ledger-deposit-key-0001');
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
  if (api.get_reservation('f9400000-0000-4000-8000-000000000021')#>>'{balance,rent_received_minor}')::bigint<>10000
    or (api.get_reservation('f9400000-0000-4000-8000-000000000021')#>>'{balance,deposit_held_minor}')::bigint<>3800 then
    raise exception 'deposit entered rent income or allocation balance is incorrect';
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
    'f9400000-0000-4000-8000-000000000021',null,null,20) e where e.kind='deposit_receipt';
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
