-- EVE-006.2 internal current-placement list projection for AT04/AT05.
-- The full OpenAPI ReservationPage balance/commission DTO remains unimplemented.
grant create on schema api to app_executor;
create function api.list_current_reservation_summaries(
  p_property_id uuid,
  p_status text default null,
  p_after_id uuid default null,
  p_page_size integer default 30
)
returns table (
  reservation_id uuid,
  placement_id uuid,
  guest_name text,
  check_in date,
  check_out date,
  state text,
  total_minor bigint,
  version integer
)
language sql stable security definer set search_path = ''
as $$
  select r.id, r.current_placement_id, r.guest_name::text,
         r.check_in, r.check_out, r.state::text, r.total_minor, r.version
  from app_private.reservations r
  join app_private.reservation_placements rp
    on rp.id = r.current_placement_id
   and rp.reservation_id = r.id
   and rp.property_id = r.property_id
   and rp.owner_account_id = r.owner_account_id
  where p_property_id is not null
    and (select app_private.current_actor_id()) is not null
    and p_page_size between 1 and 100
    and (p_status is null or p_status in
      ('hold','confirmed','checked_in','completed','cancelled','no_show'))
    and r.property_id = p_property_id
    and (p_status is null or r.state::text = p_status)
    and (p_after_id is null or r.id > p_after_id)
    and app_private.has_property_capability(r.property_id,r.owner_account_id,'reservation.read')
  order by r.id
  limit case when p_page_size between 1 and 100 then p_page_size else 0 end;
$$;
revoke all on function api.list_current_reservation_summaries(uuid,text,uuid,integer)
  from public, anon, authenticated;
grant app_executor to current_user with set true, inherit false;
alter function api.list_current_reservation_summaries(uuid,text,uuid,integer)
  owner to app_executor;
revoke app_executor from current_user;
revoke create on schema api from app_executor;
grant execute on function api.list_current_reservation_summaries(uuid,text,uuid,integer)
  to authenticated;
