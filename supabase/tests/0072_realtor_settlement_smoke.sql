-- PostgreSQL 17 smoke for EVE-015.2 / D44. Synthetic users and records only.
begin;
set constraints all deferred;

do $$ begin
  if has_function_privilege('anon','api.get_realtor_balance(uuid)','EXECUTE')
     or has_function_privilege('anon','api.record_realtor_settlement(uuid,jsonb,text)','EXECUTE')
     or not has_function_privilege('authenticated','api.get_realtor_balance(uuid)','EXECUTE')
     or not has_function_privilege('authenticated','api.record_realtor_settlement(uuid,jsonb,text)','EXECUTE')
     or has_table_privilege('authenticated','app_private.realtor_settlements','INSERT')
     or has_table_privilege('authenticated','app_private.realtor_accounts','UPDATE')
     or has_table_privilege('app_executor','app_private.realtor_settlements','UPDATE')
     or has_table_privilege('app_executor','app_private.realtor_settlements','DELETE') then
    raise exception 'realtor settlement grant boundary mismatch';
  end if;
end $$;

insert into auth.users(id) values
 ('fa000000-0000-0000-0000-000000000001'),
 ('fa000000-0000-0000-0000-000000000002'),
 ('fa000000-0000-0000-0000-000000000003'),
 ('fa000000-0000-0000-0000-000000000004');
insert into auth.sessions(id,user_id,created_at) values
 ('fa100000-0000-0000-0000-000000000001','fa000000-0000-0000-0000-000000000001',now()-interval '1 hour'),
 ('fa100000-0000-0000-0000-000000000002','fa000000-0000-0000-0000-000000000002',now()-interval '1 hour'),
 ('fa100000-0000-0000-0000-000000000003','fa000000-0000-0000-0000-000000000003',now()-interval '1 hour'),
 ('fa100000-0000-0000-0000-000000000004','fa000000-0000-0000-0000-000000000004',now()-interval '1 hour');
insert into app_private.owner_accounts(id,owner_user_id)
values ('fa200000-0000-0000-0000-000000000001','fa000000-0000-0000-0000-000000000001');
insert into app_private.properties(id,owner_account_id,name,area)
values ('fa300000-0000-4000-8000-000000000001','fa200000-0000-0000-0000-000000000001','Settlement smoke','Baku');
insert into app_private.subscriptions(owner_account_id,property_id,state,current_end)
values ('fa200000-0000-0000-0000-000000000001','fa300000-0000-4000-8000-000000000001','trialing',now()+interval '7 days');
insert into app_private.property_memberships(owner_account_id,property_id,user_id,permission,granted_by)
values
 ('fa200000-0000-0000-0000-000000000001','fa300000-0000-4000-8000-000000000001','fa000000-0000-0000-0000-000000000002','full','fa000000-0000-0000-0000-000000000001'),
 ('fa200000-0000-0000-0000-000000000001','fa300000-0000-4000-8000-000000000001','fa000000-0000-0000-0000-000000000003','daily','fa000000-0000-0000-0000-000000000001');
insert into app_private.contacts(id,owner_account_id,name,phone,service_type)
values ('fa400000-0000-0000-0000-000000000001','fa200000-0000-0000-0000-000000000001','Synthetic realtor','+994501112233','realtor');
insert into app_private.contact_properties(owner_account_id,property_id,contact_id)
values ('fa200000-0000-0000-0000-000000000001','fa300000-0000-4000-8000-000000000001','fa400000-0000-0000-0000-000000000001');
insert into app_private.reservations(id,owner_account_id,property_id,current_placement_id,guest_name,check_in,check_out,
  check_in_time,check_out_time,guest_count,state,total_minor)
values ('fa500000-0000-4000-8000-000000000001','fa200000-0000-0000-0000-000000000001',
  'fa300000-0000-4000-8000-000000000001','fa600000-0000-0000-0000-000000000001','Synthetic guest',
  '2099-03-01','2099-03-04','15:00','11:00',1,'confirmed',10000);
insert into app_private.reservation_placements(id,owner_account_id,property_id,reservation_id,placement_no,
  check_in_snapshot,check_out_snapshot,effective_from,created_by)
values ('fa600000-0000-0000-0000-000000000001','fa200000-0000-0000-0000-000000000001',
  'fa300000-0000-4000-8000-000000000001','fa500000-0000-4000-8000-000000000001',1,
  '2099-03-01','2099-03-04',now(),'fa000000-0000-0000-0000-000000000001');
insert into app_private.realtor_accounts(owner_account_id,reservation_id,contact_id,commission_kind,
  fixed_minor,percentage_basis_points,basis_minor,earned_minor)
values ('fa200000-0000-0000-0000-000000000001','fa500000-0000-4000-8000-000000000001',
  'fa400000-0000-0000-0000-000000000001','fixed',3000,null,10000,3000);

set local role authenticated;
set local request.jwt.claims='{"sub":"fa000000-0000-0000-0000-000000000001","session_id":"fa100000-0000-0000-0000-000000000001","iat":1800000000}';
do $$
declare b jsonb; receipt jsonb; refund jsonb; settlement jsonb; replay jsonb; failed boolean;
  before_receipts bigint; after_receipts bigint;
begin
  b:=api.get_realtor_balance('fa500000-0000-4000-8000-000000000001');
  if (b->>'version')::int<>1 or (b->>'owner_due_minor')::bigint<>0 then raise exception 'empty balance mismatch: %',b; end if;
  failed:=false;
  begin
    perform api.record_realtor_settlement('fa500000-0000-4000-8000-000000000001',
      '{"expected_version":1,"contact_id":"fa400000-0000-0000-0000-000000000001","kind":"owner_to_realtor","amount_minor":1}',
      'settlement-prepay-key-0001');
  exception when sqlstate '22023' then failed:=true; end;
  if not failed then raise exception 'commission prepayment accepted'; end if;
  receipt:=api.create_rent_entry('fa500000-0000-4000-8000-000000000001',
    '{"kind":"rent_receipt","amount_minor":10000,"custodian":"realtor","contact_id":"fa400000-0000-0000-0000-000000000001"}',
    'settlement-rent-receipt-0001');
  if (api.get_realtor_balance('fa500000-0000-4000-8000-000000000001')->>'version')::int<>2 then
    raise exception 'realtor receipt did not increment aggregate version'; end if;
  refund:=api.create_rent_entry('fa500000-0000-4000-8000-000000000001',jsonb_build_object(
    'kind','rent_refund','amount_minor',1,'custodian','realtor','contact_id','fa400000-0000-0000-0000-000000000001',
    'original_id',receipt->>'id'),'settlement-rent-refund-0001');
  b:=api.get_realtor_balance('fa500000-0000-4000-8000-000000000001');
  if (b->>'version')::int<>3 or (b->>'collected_minor')::bigint<>9999
    or (b->>'commission_minor')::bigint<>3000 or (b->>'owner_due_minor')::bigint<>6999 then
    raise exception 'C/E or refund balance mismatch: %',b; end if;
  select count(*) into before_receipts from app_private.rent_entries where reservation_id='fa500000-0000-4000-8000-000000000001';
  settlement:=api.record_realtor_settlement('fa500000-0000-4000-8000-000000000001',
    '{"expected_version":3,"contact_id":"fa400000-0000-0000-0000-000000000001","kind":"realtor_to_owner","amount_minor":6999}',
    'settlement-transfer-key-001');
  if settlement->>'balance_version'<>'4' then raise exception 'settlement version not advanced: %',settlement; end if;
  failed:=false;
  begin
    perform api.record_realtor_settlement('fa500000-0000-4000-8000-000000000001',
      '{"expected_version":4,"contact_id":"fa400000-0000-0000-0000-000000000001","kind":"commission_offset","amount_minor":3001}',
      'settlement-excess-offset-01');
  exception when sqlstate '22023' then failed:=true; end;
  if not failed then raise exception 'offset exceeding both due amounts was accepted'; end if;
  perform api.record_realtor_settlement('fa500000-0000-4000-8000-000000000001',
    '{"expected_version":4,"contact_id":"fa400000-0000-0000-0000-000000000001","kind":"commission_offset","amount_minor":3000}',
    'settlement-offset-key-001');
  b:=api.get_realtor_balance('fa500000-0000-4000-8000-000000000001');
  if (b->>'version')::int<>5 or (b->>'owner_due_minor')::bigint<>0 or (b->>'realtor_due_minor')::bigint<>0
    or (b->>'commission_paid_minor')::bigint<>3000 then raise exception 'D44 offset net mismatch: %',b; end if;
  replay:=api.record_realtor_settlement('fa500000-0000-4000-8000-000000000001',
    '{"expected_version":3,"contact_id":"fa400000-0000-0000-0000-000000000001","kind":"realtor_to_owner","amount_minor":6999}',
    'settlement-transfer-key-001');
  if replay->>'id' is distinct from settlement->>'id' or replay->>'balance_version'<>'4' then
    raise exception 'identical payload did not replay the original event after the balance became stale'; end if;
  failed:=false;
  begin
    perform api.record_realtor_settlement('fa500000-0000-4000-8000-000000000001',
      '{"expected_version":3,"contact_id":"fa400000-0000-0000-0000-000000000001","kind":"realtor_to_owner","amount_minor":6998}',
      'settlement-transfer-key-001');
  exception when unique_violation then failed:=true; end;
  if not failed then raise exception 'changed settlement payload replay was accepted'; end if;
  failed:=false;
  begin
    perform api.record_realtor_settlement('fa500000-0000-4000-8000-000000000001',
      '{"expected_version":4,"contact_id":"fa400000-0000-0000-0000-000000000001","kind":"realtor_to_owner","amount_minor":1}',
      'settlement-stale-version-001');
  exception when serialization_failure then failed:=true; end;
  if not failed then raise exception 'stale balance version was accepted'; end if;
  select count(*) into after_receipts from app_private.rent_entries where reservation_id='fa500000-0000-4000-8000-000000000001';
  if before_receipts<>after_receipts then raise exception 'settlement created a rent entry'; end if;
end $$;

set local request.jwt.claims='{"sub":"fa000000-0000-0000-0000-000000000002","session_id":"fa100000-0000-0000-0000-000000000002","iat":1800000000}';
do $$ begin
  if api.get_realtor_balance('fa500000-0000-4000-8000-000000000001')->>'contact_id'<>'fa400000-0000-0000-0000-000000000001' then
    raise exception 'full manager could not read financial balance'; end if;
end $$;

set local request.jwt.claims='{"sub":"fa000000-0000-0000-0000-000000000003","session_id":"fa100000-0000-0000-0000-000000000003","iat":1800000000}';
do $$ declare denied boolean:=false; begin
  begin perform api.get_realtor_balance('fa500000-0000-4000-8000-000000000001');
  exception when sqlstate 'P0002' or insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'daily manager read financial balance'; end if;
end $$;

set local request.jwt.claims='{"sub":"fa000000-0000-0000-0000-000000000004","session_id":"fa100000-0000-0000-0000-000000000004","iat":1800000000}';
do $$ declare denied boolean:=false; begin
  begin perform api.get_realtor_balance('fa500000-0000-4000-8000-000000000001');
  exception when sqlstate 'P0002' or insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'cross-tenant balance read accepted'; end if;
end $$;

rollback;
