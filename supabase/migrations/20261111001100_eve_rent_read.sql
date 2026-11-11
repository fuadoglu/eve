-- EVE-006.2 / AT04-06: property-scoped rent history read.
-- Current reservation staff see only entries on the current placement.
-- Historical entries require finance.read on the entry's own property.
-- The full OpenAPI RentEntryPage and all ledger writes remain separate work.
grant select on app_private.rent_entries to app_executor;

create policy rent_entries_current_or_finance_read on app_private.rent_entries
  for select to app_executor
  using (
    app_private.has_property_capability(property_id,owner_account_id,'finance.read')
    or (
      app_private.has_property_capability(property_id,owner_account_id,'reservation.read')
      and exists (
        select 1 from app_private.reservations r
        where r.id=reservation_id
          and r.owner_account_id=rent_entries.owner_account_id
          and r.property_id=rent_entries.property_id
          and r.current_placement_id=rent_entries.placement_id
      )
    )
  );

-- Internal allowlist projection. Historical rows do not expose guest details,
-- target property, note, actor, operation key, or contact identity.
grant create on schema api to app_executor;
create function api.list_reservation_rent_summaries(
  p_reservation_id uuid,
  p_after_at timestamptz default null,
  p_after_id uuid default null,
  p_page_size integer default 30
)
returns table (
  entry_id uuid,
  reservation_id uuid,
  property_id uuid,
  placement_id uuid,
  kind text,
  amount_minor bigint,
  custodian text,
  occurred_at timestamptz,
  created_at timestamptz
)
language sql stable security definer set search_path = ''
as $$
  select e.id,e.reservation_id,e.property_id,e.placement_id,
         e.kind::text,e.amount_minor,e.custodian::text,
         e.occurred_at,e.created_at
  from app_private.rent_entries e
  where p_reservation_id is not null
    and (select app_private.current_actor_id()) is not null
    and p_page_size between 1 and 100
    and ((p_after_at is null and p_after_id is null)
      or (p_after_at is not null and p_after_id is not null))
    and e.reservation_id=p_reservation_id
    and (p_after_at is null or (e.occurred_at,e.id)>(p_after_at,p_after_id))
    and (
      app_private.has_property_capability(e.property_id,e.owner_account_id,'finance.read')
      or (
        app_private.has_property_capability(e.property_id,e.owner_account_id,'reservation.read')
        and exists (
          select 1 from app_private.reservations r
          where r.id=e.reservation_id
            and r.owner_account_id=e.owner_account_id
            and r.property_id=e.property_id
            and r.current_placement_id=e.placement_id
        )
      )
    )
  order by e.occurred_at,e.id
  limit case when p_page_size between 1 and 100 then p_page_size else 0 end;
$$;
revoke all on function api.list_reservation_rent_summaries(uuid,timestamptz,uuid,integer)
  from public,anon,authenticated;
grant app_executor to current_user with set true, inherit false;
alter function api.list_reservation_rent_summaries(uuid,timestamptz,uuid,integer)
  owner to app_executor;
revoke app_executor from current_user;
revoke create on schema api from app_executor;
grant execute on function api.list_reservation_rent_summaries(uuid,timestamptz,uuid,integer)
  to authenticated;
