-- Local synthetic DB behavior proof, not hosted Supabase history or HTTP/RPC proof.
do $$
declare
  owner_a uuid := gen_random_uuid();
  owner_b uuid := gen_random_uuid();
  account_a uuid;
  account_b uuid;
  property_a uuid;
  expired_reservation uuid := gen_random_uuid();
  expired_placement uuid := gen_random_uuid();
  future_reservation uuid := gen_random_uuid();
  future_placement uuid := gen_random_uuid();
  confirmed_reservation uuid := gen_random_uuid();
  confirmed_placement uuid := gen_random_uuid();
  block_id uuid;
  expired_count integer;
begin
  insert into auth.users(id) values (owner_a),(owner_b);
  insert into app_private.owner_accounts(owner_user_id) values (owner_a) returning id into account_a;
  insert into app_private.owner_accounts(owner_user_id) values (owner_b) returning id into account_b;
  insert into app_private.properties(owner_account_id,name,area)
    values (account_a,'Catch-up fixture','Bakı') returning id into property_a;
  insert into app_private.manual_blocks(owner_account_id,property_id,check_in,check_out)
    values (account_a,property_a,'2027-05-01','2027-05-03') returning id into block_id;
  insert into app_private.occupancy(owner_account_id,property_id,manual_block_id,date_range)
    values (account_a,property_a,block_id,daterange('2027-05-01','2027-05-03','[)'));

  set constraints all deferred;
  insert into app_private.reservations(
    id,owner_account_id,property_id,current_placement_id,guest_name,
    check_in,check_out,check_in_time,check_out_time,state,hold_expires_at,total_minor
  ) values
    (expired_reservation,account_a,property_a,expired_placement,'Expired hold',
      '2027-03-01','2027-03-03','14:00','12:00','hold',statement_timestamp()-interval '1 hour',100),
    (future_reservation,account_a,property_a,future_placement,'Future hold',
      '2027-04-01','2027-04-03','14:00','12:00','hold',statement_timestamp()+interval '1 hour',100),
    (confirmed_reservation,account_a,property_a,confirmed_placement,'Confirmed',
      '2027-06-01','2027-06-03','14:00','12:00','confirmed',null,100);
  insert into app_private.reservation_placements(
    id,owner_account_id,property_id,reservation_id,placement_no,
    check_in_snapshot,check_out_snapshot,effective_from,created_by
  ) values
    (expired_placement,account_a,property_a,expired_reservation,1,'2027-03-01','2027-03-03',now(),owner_a),
    (future_placement,account_a,property_a,future_reservation,1,'2027-04-01','2027-04-03',now(),owner_a),
    (confirmed_placement,account_a,property_a,confirmed_reservation,1,'2027-06-01','2027-06-03',now(),owner_a);
  insert into app_private.occupancy(owner_account_id,property_id,placement_id,date_range,expires_at)
  values
    (account_a,property_a,expired_placement,daterange('2027-03-01','2027-03-03','[)'),statement_timestamp()-interval '1 hour'),
    (account_a,property_a,future_placement,daterange('2027-04-01','2027-04-03','[)'),statement_timestamp()+interval '1 hour'),
    (account_a,property_a,confirmed_placement,daterange('2027-06-01','2027-06-03','[)'),null);
  set constraints all immediate;

  perform set_config('request.jwt.claim.sub',owner_a::text,true);
  expired_count := app_private.expire_property_holds(property_a);
  if expired_count <> 1 then
    raise exception 'expected one due hold to expire, got %',expired_count;
  end if;
  if (select state from app_private.reservations where id=expired_reservation) <> 'cancelled'
     or (select hold_expires_at from app_private.reservations where id=expired_reservation) is not null
     or (select version from app_private.reservations where id=expired_reservation) <> 2
     or (select active from app_private.occupancy where placement_id=expired_placement)
     or not (select active from app_private.occupancy where placement_id=future_placement)
     or (select state from app_private.reservations where id=confirmed_reservation) <> 'confirmed'
     or not (select active from app_private.occupancy where placement_id=confirmed_placement)
     or not (select active from app_private.occupancy where manual_block_id=block_id) then
    raise exception 'catch-up changed a future hold, confirmed booking or manual block';
  end if;
  if not exists (select 1 from app_private.audit_events
      where resource_id=expired_reservation and reason='hold_expired'
        and redacted_diff->>'reason'='hold_expired') then
    raise exception 'expired hold audit reason missing';
  end if;
  if app_private.expire_property_holds(property_a) <> 0 then
    raise exception 'repeated catch-up was not idempotent';
  end if;
  perform set_config('request.jwt.claim.sub',owner_b::text,true);
  begin
    perform app_private.expire_property_holds(property_a);
    raise exception 'cross-owner catch-up unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
  perform set_config('request.jwt.claim.sub','',true);
  begin
    perform app_private.expire_property_holds(property_a);
    raise exception 'anonymous catch-up unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;

do $$
begin
  if has_function_privilege('authenticated','app_private.expire_property_holds(uuid)','EXECUTE')
     or has_function_privilege('anon','app_private.expire_property_holds(uuid)','EXECUTE')
     or not has_function_privilege('app_executor','app_private.expire_property_holds(uuid)','EXECUTE')
     or not exists (
       select 1 from pg_proc p
       where p.oid='app_private.expire_property_holds(uuid)'::regprocedure
         and p.prosecdef
         and p.proconfig @> array['search_path=""']::text[]
     ) then
    raise exception 'hold expiry helper grant boundary mismatch';
  end if;
end $$;
