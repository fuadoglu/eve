-- EVE-011.3 synthetic database proof for reservation response DTO and property context.
do $$
begin
  if (select p.proowner<>'app_executor'::regrole or not p.prosecdef
      or not (coalesce(p.proconfig,array[]::text[]) @> array['search_path=""']::text[])
      from pg_proc p where p.oid='api.get_reservation(uuid)'::regprocedure)
     or (select p.proowner<>'app_executor'::regrole or not p.prosecdef
      from pg_proc p where p.oid='api.list_reservable_property_contexts()'::regprocedure)
     or has_function_privilege('anon','api.get_reservation(uuid)','EXECUTE')
     or not has_function_privilege('authenticated','api.get_reservation(uuid)','EXECUTE')
     or has_table_privilege('authenticated','app_private.reservations','SELECT')
     or not has_function_privilege('app_executor','api.is_my_session_active()','EXECUTE')
     or not has_function_privilege('app_executor','app_private.create_reservation_unchecked(jsonb,text)','EXECUTE')
     or has_function_privilege('authenticated','app_private.create_reservation_unchecked(jsonb,text)','EXECUTE') then
    raise exception 'reservation safe DTO RPC grants or ownership are unsafe';
  end if;
end $$;

begin;
insert into auth.users(id) values ('f0000000-0000-0000-0000-000000000025') on conflict (id) do nothing;
insert into auth.sessions(id,user_id,created_at)
values ('f0100000-0000-0000-0000-000000000025','f0000000-0000-0000-0000-000000000025',clock_timestamp());
insert into app_private.owner_accounts(id,owner_user_id)
values ('f1000000-0000-0000-0000-000000000025','f0000000-0000-0000-0000-000000000025');
insert into app_private.properties(id,owner_account_id,name,area,max_guests,default_check_in,default_check_out)
values ('f2000000-0000-0000-0000-000000000025','f1000000-0000-0000-0000-000000000025','Reservation test','Bakı',4,'15:00','11:00');
insert into app_private.subscriptions(owner_account_id,property_id,state,current_end)
values ('f1000000-0000-0000-0000-000000000025','f2000000-0000-0000-0000-000000000025','trialing',now()+interval '7 days');
set local role authenticated;
set local request.jwt.claim.sub='f0000000-0000-0000-0000-000000000025';
set local request.jwt.claims='{"sub":"f0000000-0000-0000-0000-000000000025","session_id":"f0100000-0000-0000-0000-000000000025"}';
do $$
declare
  v_first jsonb;
  v_retry jsonb;
  v_dto jsonb;
  v_context record;
begin
  select * into v_context from api.list_reservable_property_contexts();
  if v_context.id<>'f2000000-0000-0000-0000-000000000025'::uuid
     or v_context.default_check_in<>'15:00' or v_context.default_check_out<>'11:00'
     or v_context.default_custodian<>'owner' then
    raise exception 'reservable property context differs from authoritative property settings';
  end if;
  v_first := api.create_reservation(
    '{"property_id":"f2000000-0000-0000-0000-000000000025","guest_name":"DTO guest","check_in":"2027-05-01","check_out":"2027-05-04","total_minor":30000,"initial_receipt":{"amount_minor":10000,"kind":"rent_receipt","custodian":"owner"}}'::jsonb,
    'reservation-create-read-key-025');
  v_retry := api.create_reservation(
    '{"property_id":"f2000000-0000-0000-0000-000000000025","guest_name":"DTO guest","check_in":"2027-05-01","check_out":"2027-05-04","total_minor":30000,"initial_receipt":{"amount_minor":10000,"kind":"rent_receipt","custodian":"owner"}}'::jsonb,
    'reservation-create-read-key-025');
  if v_first->>'reservation_id' is distinct from v_retry->>'reservation_id' then
    raise exception 'retry returned a different reservation';
  end if;
  v_dto := api.get_reservation((v_first->>'reservation_id')::uuid);
  if v_dto->>'guest_name'<>'DTO guest' or v_dto->>'currency'<>'AZN'
     or v_dto#>>'{balance,rent_received_minor}'<>'10000'
     or v_dto#>>'{balance,remaining_minor}'<>'20000'
     or v_dto#>>'{balance,overpaid_minor}'<>'0' then
    raise exception 'safe reservation DTO or idempotent initial receipt balance differs';
  end if;
  perform set_config('test.reservation_id',v_first->>'reservation_id',true);
  begin
    perform api.get_reservation('f2000000-0000-0000-0000-000000000025'::uuid);
    raise exception 'property id was accepted as reservation id';
  exception when sqlstate 'P0002' then null;
  end;
end $$;
reset role;
do $$
declare
  v_reservation uuid;
  v_owner uuid;
  v_property uuid;
  v_placement uuid;
  v_receipt uuid;
  v_refund uuid;
  v_deposit uuid;
  v_allocation uuid;
  v_actor uuid := 'f0000000-0000-0000-0000-000000000025';
begin
  select r.id, r.owner_account_id, r.property_id, r.current_placement_id, e.id
    into v_reservation, v_owner, v_property, v_placement, v_receipt
  from app_private.idempotency_keys i
  join app_private.reservations r on r.id=i.result_id
  join app_private.rent_entries e on e.reservation_id=r.id and e.kind='rent_receipt'
  where i.key='reservation-create-read-key-025';
  insert into app_private.rent_entries(owner_account_id,property_id,reservation_id,placement_id,kind,amount_minor,
      custodian,custodian_user_id,original_entry_id,actor_id,occurred_at,operation_key)
    values (v_owner,v_property,v_reservation,v_placement,'rent_refund',1000,'owner',v_actor,v_receipt,v_actor,now(),'test-rent-refund-025') returning id into v_refund;
  insert into app_private.rent_entries(owner_account_id,property_id,reservation_id,placement_id,kind,amount_minor,
      custodian,custodian_user_id,original_entry_id,actor_id,occurred_at,operation_key)
    values (v_owner,v_property,v_reservation,v_placement,'reversal',1000,'owner',v_actor,v_refund,v_actor,now(),'test-rent-refund-reversal-025');
  insert into app_private.rent_entries(owner_account_id,property_id,reservation_id,placement_id,kind,amount_minor,
      custodian,custodian_user_id,actor_id,occurred_at,operation_key)
    values (v_owner,v_property,v_reservation,v_placement,'deposit_receipt',5000,'owner',v_actor,v_actor,now(),'test-deposit-receipt-025') returning id into v_deposit;
  insert into app_private.rent_entries(owner_account_id,property_id,reservation_id,placement_id,kind,amount_minor,
      custodian,custodian_user_id,original_entry_id,actor_id,occurred_at,operation_key)
    values (v_owner,v_property,v_reservation,v_placement,'deposit_to_damage',1000,'owner',v_actor,v_deposit,v_actor,now(),'test-deposit-allocation-025') returning id into v_allocation;
  insert into app_private.rent_entries(owner_account_id,property_id,reservation_id,placement_id,kind,amount_minor,
      custodian,custodian_user_id,original_entry_id,actor_id,occurred_at,operation_key)
    values (v_owner,v_property,v_reservation,v_placement,'reversal',1000,'owner',v_actor,v_allocation,v_actor,now(),'test-deposit-allocation-reversal-025');
end $$;
set local role authenticated;
do $$
declare v_reservation uuid; v_dto jsonb;
begin
  v_reservation := current_setting('test.reservation_id')::uuid;
  v_dto := api.get_reservation(v_reservation);
  if v_dto#>>'{balance,rent_received_minor}'<>'10000'
     or v_dto#>>'{balance,rent_refunded_minor}'<>'0'
     or v_dto#>>'{balance,remaining_minor}'<>'20000'
     or v_dto#>>'{balance,deposit_held_minor}'<>'5000' then
    raise exception 'reversals did not restore receipt or deposit balances';
  end if;
  if api.revoke_my_sessions() is distinct from true or api.is_my_session_active() is distinct from false then
    raise exception 'logout-all did not revoke the active test session';
  end if;
  begin
    perform 1 from api.list_reservable_property_contexts();
    raise exception 'revoked session unexpectedly listed reservation property contexts';
  exception when sqlstate '28000' then null;
  end;
  begin
    perform api.get_reservation(v_reservation);
    raise exception 'revoked session unexpectedly read reservation DTO';
  exception when sqlstate '28000' then null;
  end;
  begin
    perform api.create_reservation(
      '{"property_id":"f2000000-0000-0000-0000-000000000025","guest_name":"Revoked guest","check_in":"2027-06-01","check_out":"2027-06-02","total_minor":10000}'::jsonb,
      'revoked-reservation-key-025');
    raise exception 'revoked session unexpectedly created a reservation';
  exception when sqlstate '28000' then null;
  end;
end $$;
rollback;
