-- EVE-011.3: safe context and DTO projections for the authenticated create flow.
grant select on app_private.owner_accounts, app_private.property_memberships,
  app_private.subscriptions, app_private.contacts, app_private.realtor_accounts,
  app_private.rent_entries, app_private.reservations, app_private.properties,
  app_private.reservation_placements to app_executor;
grant execute on function api.is_my_session_active() to app_executor;
grant create on schema api to app_executor;
grant app_executor to current_user with set true, inherit false;

create policy realtor_accounts_current_reservation_read on app_private.realtor_accounts
  for select to app_executor
  using (exists (select 1 from app_private.reservations r
    where r.id=realtor_accounts.reservation_id
      and r.owner_account_id=realtor_accounts.owner_account_id
      and r.current_placement_id is not null
      and app_private.has_property_capability(r.property_id,r.owner_account_id,'reservation.read')));

create function api.list_reservable_property_contexts()
returns table (
  id uuid,
  name text,
  max_guests integer,
  default_check_in text,
  default_check_out text,
  default_custodian text
)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not api.is_my_session_active() then
    raise exception using errcode='28000', message='active_session_required';
  end if;
  return query
    select p.id, p.name::text, p.max_guests,
           to_char(p.default_check_in, 'HH24:MI'), to_char(p.default_check_out, 'HH24:MI'),
           case when exists (select 1 from app_private.owner_accounts oa
             where oa.id=p.owner_account_id and oa.owner_user_id=app_private.current_actor_id())
             then 'owner' else 'manager' end
    from app_private.properties p
    where p.archived_at is null
      and app_private.can_write_reservation(p.id,p.owner_account_id)
      and exists (select 1 from app_private.subscriptions s
        where s.property_id=p.id and s.owner_account_id=p.owner_account_id
          and s.state in ('trialing','active') and s.current_end>statement_timestamp())
    order by p.name, p.id;
end;
$$;
revoke all on function api.list_reservable_property_contexts() from public, anon, authenticated;
grant execute on function api.list_reservable_property_contexts() to authenticated;
alter function api.list_reservable_property_contexts() owner to app_executor;

create function api.get_reservation(p_reservation_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if not api.is_my_session_active() then
    raise exception using errcode='28000', message='active_session_required';
  end if;

  select jsonb_strip_nulls(jsonb_build_object(
    'id', r.id,
    'property_id', r.property_id,
    'current_placement_id', r.current_placement_id,
    'guest_name', r.guest_name,
    'guest_phone', r.guest_phone,
    'guest_count', r.guest_count,
    'check_in', r.check_in,
    'check_out', r.check_out,
    'check_in_time', to_char(r.check_in_time, 'HH24:MI'),
    'check_out_time', to_char(r.check_out_time, 'HH24:MI'),
    'actual_check_in_at', r.actual_check_in_at,
    'actual_check_out_at', r.actual_check_out_at,
    'status', r.state::text,
    'hold_expires_at', r.hold_expires_at,
    'total_minor', r.total_minor,
    'currency', 'AZN',
    'note', r.private_note,
    'commission', case when ra.id is null then null else jsonb_strip_nulls(jsonb_build_object(
      'contact_id', ra.contact_id, 'kind', ra.commission_kind::text,
      'fixed_minor', ra.fixed_minor, 'basis_minor', ra.basis_minor,
      'percentage_basis_points', ra.percentage_basis_points)) end,
    'balance', jsonb_build_object(
      'rent_received_minor', money.rent_received_minor,
      'rent_refunded_minor', money.rent_refunded_minor,
      'remaining_minor', greatest(0::numeric, r.total_minor::numeric-money.rent_received_minor)::bigint,
      'overpaid_minor', greatest(0::numeric, money.rent_received_minor-r.total_minor::numeric)::bigint,
      'deposit_held_minor', money.deposit_held_minor),
    'version', r.version,
    'created_at', r.created_at,
    'updated_at', r.updated_at
  )) into v_result
  from app_private.reservations r
  join app_private.reservation_placements rp
    on rp.id=r.current_placement_id and rp.reservation_id=r.id
   and rp.property_id=r.property_id and rp.owner_account_id=r.owner_account_id
  left join app_private.realtor_accounts ra
    on ra.reservation_id=r.id and ra.owner_account_id=r.owner_account_id
  cross join lateral (
    select
      greatest(0::numeric,
        coalesce(sum(case when e.kind in ('rent_receipt','deposit_to_rent') then e.amount_minor else 0 end),0)
        - coalesce(sum(case when e.kind='rent_refund' then e.amount_minor else 0 end),0)
        - coalesce(sum(case when e.kind='reversal' and original.kind in ('rent_receipt','deposit_to_rent') then e.amount_minor else 0 end),0)
        + coalesce(sum(case when e.kind='reversal' and original.kind='rent_refund' then e.amount_minor else 0 end),0)
      )::bigint as rent_received_minor,
      greatest(0::numeric, coalesce(sum(case when e.kind='rent_refund' then e.amount_minor else 0 end),0)
        - coalesce(sum(case when e.kind='reversal' and original.kind='rent_refund' then e.amount_minor else 0 end),0))::bigint as rent_refunded_minor,
      greatest(0::numeric,
        coalesce(sum(case when e.kind='deposit_receipt' then e.amount_minor else 0 end),0)
        - coalesce(sum(case when e.kind in ('deposit_return','deposit_to_rent','deposit_to_damage') then e.amount_minor else 0 end),0)
        - coalesce(sum(case when e.kind='reversal' and original.kind='deposit_receipt' then e.amount_minor else 0 end),0)
        + coalesce(sum(case when e.kind='reversal' and original.kind in ('deposit_return','deposit_to_rent','deposit_to_damage') then e.amount_minor else 0 end),0)
      )::bigint as deposit_held_minor
    from app_private.rent_entries e
    left join app_private.rent_entries original
      on original.id=e.original_entry_id and original.owner_account_id=e.owner_account_id
    where e.reservation_id=r.id and e.owner_account_id=r.owner_account_id
  ) money
  where r.id=p_reservation_id
    and app_private.has_property_capability(r.property_id,r.owner_account_id,'reservation.read');

  if v_result is null then
    raise exception using errcode='P0002', message='reservation_not_found';
  end if;
  return v_result;
end;
$$;
revoke all on function api.get_reservation(uuid) from public, anon, authenticated;
grant execute on function api.get_reservation(uuid) to authenticated;
alter function api.get_reservation(uuid) owner to app_executor;

-- Keep the public create RPC name and contract, but route calls through a
-- session-guarded wrapper. Authenticated callers cannot bypass revocation by
-- invoking the former implementation directly through PostgREST.
grant create on schema app_private to app_executor;
set role app_executor;
alter function api.create_reservation(jsonb,text) set schema app_private;
alter function app_private.create_reservation(jsonb,text) rename to create_reservation_unchecked;
revoke all on function app_private.create_reservation_unchecked(jsonb,text) from public, anon, authenticated;
grant execute on function app_private.create_reservation_unchecked(jsonb,text) to app_executor;

create function api.create_reservation(p_input jsonb, p_idempotency_key text)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
begin
  if not api.is_my_session_active() then
    raise exception using errcode='28000', message='active_session_required';
  end if;
  return app_private.create_reservation_unchecked(p_input,p_idempotency_key);
end;
$$;
revoke all on function api.create_reservation(jsonb,text) from public, anon, authenticated;
grant execute on function api.create_reservation(jsonb,text) to authenticated;
reset role;
grant execute on function api.is_my_session_active() to app_executor;
revoke create on schema app_private from app_executor;

revoke app_executor from current_user;
revoke create on schema api from app_executor;
