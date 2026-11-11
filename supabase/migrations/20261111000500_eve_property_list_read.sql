-- EVE-006.2 internal property-list projection for AT04/AT05 DB scope.
-- This is intentionally smaller than the OpenAPI PropertyPage DTO.
grant create on schema api to app_executor;
create function api.list_visible_property_summaries(
  p_after_id uuid default null,
  p_page_size integer default 50
)
returns table (
  property_id uuid,
  owner_account_id uuid,
  name text,
  area text,
  readiness text,
  version integer
)
language sql stable security definer set search_path = ''
as $$
  select p.id, p.owner_account_id, p.name::text, p.area::text,
         p.readiness::text, p.version
  from app_private.properties p
  where (select app_private.current_actor_id()) is not null
    and p_page_size between 1 and 100
    and (p_after_id is null or p.id > p_after_id)
    and app_private.has_property_capability(p.id,p.owner_account_id,'property.read')
  order by p.id
  limit case when p_page_size between 1 and 100 then p_page_size else 0 end;
$$;
revoke all on function api.list_visible_property_summaries(uuid,integer)
  from public, anon, authenticated;
grant app_executor to current_user with set true, inherit false;
alter function api.list_visible_property_summaries(uuid,integer) owner to app_executor;
revoke app_executor from current_user;
revoke create on schema api from app_executor;
grant execute on function api.list_visible_property_summaries(uuid,integer) to authenticated;
