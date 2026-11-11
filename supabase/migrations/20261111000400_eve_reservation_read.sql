-- EVE-006.2 read projection: reservation access follows its current placement.
-- The composite FK in migration 001 ties the current placement to this property.
-- Historical placement/finance projections and all writes remain closed.
grant select on app_private.reservations, app_private.reservation_placements to app_executor;

create policy reservations_current_property_read on app_private.reservations
  for select to app_executor
  using (app_private.has_property_capability(property_id, owner_account_id, 'reservation.read'));

create policy reservation_placements_current_read on app_private.reservation_placements
  for select to app_executor
  using (
    app_private.has_property_capability(property_id, owner_account_id, 'reservation.read')
    and exists (
      select 1 from app_private.reservations r
      where r.id = reservation_id
        and r.current_placement_id = reservation_placements.id
        and r.property_id = reservation_placements.property_id
        and r.owner_account_id = reservation_placements.owner_account_id
    )
  );

-- Internal explicit-column projection for the server reservation route. It is
-- deliberately narrower than the final OpenAPI Reservation DTO; no ledger or
-- commission projection is asserted by this function.
grant create on schema api to app_executor;
create function api.read_current_reservation(p_reservation_id uuid)
returns table (
  reservation_id uuid,
  property_id uuid,
  placement_id uuid,
  guest_name text,
  guest_phone text,
  check_in date,
  check_out date,
  state text,
  total_minor bigint,
  version integer,
  created_at timestamptz,
  updated_at timestamptz
)
language sql stable security definer set search_path = ''
as $$
  select r.id, r.property_id, r.current_placement_id,
         r.guest_name::text, r.guest_phone::text,
         r.check_in, r.check_out, r.state::text, r.total_minor,
         r.version, r.created_at, r.updated_at
  from app_private.reservations r
  join app_private.reservation_placements rp
    on rp.id = r.current_placement_id
   and rp.reservation_id = r.id
   and rp.property_id = r.property_id
   and rp.owner_account_id = r.owner_account_id
  where p_reservation_id is not null and (select auth.uid()) is not null
    and r.id = p_reservation_id
    and app_private.has_property_capability(r.property_id,r.owner_account_id,'reservation.read');
$$;
revoke all on function api.read_current_reservation(uuid)
  from public, anon, authenticated;
alter function api.read_current_reservation(uuid) owner to app_executor;
revoke create on schema api from app_executor;
grant execute on function api.read_current_reservation(uuid) to authenticated;
