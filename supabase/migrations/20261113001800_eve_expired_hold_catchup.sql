-- EVE-010.2: transaction-local catch-up for a property's expired reservation holds.
-- The caller's booking transaction must invoke this only after taking the
-- property lock; the function acquires the same lock itself for safe standalone
-- use and to serialize concurrent catch-up attempts.
create function app_private.expire_property_holds(p_property_id uuid)
returns integer
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_actor uuid := app_private.current_actor_id();
  v_owner_account_id uuid;
  v_now timestamptz;
  v_reservation record;
  v_changed integer := 0;
  v_occupancy_changed integer;
begin
  if v_actor is null or p_property_id is null then
    raise insufficient_privilege using message = 'property hold expiry is not authorized';
  end if;

  select p.owner_account_id into v_owner_account_id
  from app_private.properties p
  join app_private.owner_accounts a
    on a.id = p.owner_account_id and a.owner_user_id = v_actor
  where p.id = p_property_id
  for update of p;

  if not found then
    raise insufficient_privilege using message = 'property hold expiry is not authorized';
  end if;

  -- Read the actual time after the property lock is acquired. A hold may expire
  -- while this transaction waits behind another property write.
  v_now := clock_timestamp();

  for v_reservation in
    select r.id, r.current_placement_id, r.owner_account_id, r.version
    from app_private.reservations r
    where r.property_id = p_property_id
      and r.owner_account_id = v_owner_account_id
      and r.state = 'hold'
      and r.hold_expires_at <= v_now
    order by r.id
    for update
  loop
    update app_private.reservations r
    set state = 'cancelled',
        hold_expires_at = null,
        updated_at = v_now,
        version = r.version + 1
    where r.id = v_reservation.id
      and r.state = 'hold'
      and r.hold_expires_at <= v_now;

    if not found then
      continue;
    end if;

    update app_private.occupancy o
    set active = false
    where o.placement_id = v_reservation.current_placement_id
      and o.property_id = p_property_id
      and o.owner_account_id = v_owner_account_id
      and o.active;
    get diagnostics v_occupancy_changed = row_count;
    if v_occupancy_changed <> 1 then
      raise exception 'expired hold must own exactly one active occupancy'
        using errcode = 'integrity_constraint_violation';
    end if;

    insert into app_private.audit_events(
      owner_account_id, property_id, actor_user_id, capability,
      resource_type, resource_id, request_id, redacted_diff, reason, created_at
    ) values (
      v_owner_account_id, p_property_id, v_actor, 'reservation.write',
      'reservation', v_reservation.id, 'hold-expiry:' || v_reservation.id::text,
      jsonb_build_object('state_from','hold','state_to','cancelled',
        'reason','hold_expired','version',v_reservation.version + 1),
      'hold_expired', v_now
    );
    v_changed := v_changed + 1;
  end loop;

  return v_changed;
end;
$$;
revoke all on function app_private.expire_property_holds(uuid) from public, anon, authenticated;
grant execute on function app_private.expire_property_holds(uuid) to app_executor;
