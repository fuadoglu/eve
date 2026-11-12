-- EVE-006.2 private calendar block read; public availability uses a different
-- safe projection and never receives a block reason from this function.
grant select on app_private.manual_blocks to app_executor;
create policy manual_blocks_property_read on app_private.manual_blocks
  for select to app_executor
  using (app_private.has_property_capability(
    property_id,owner_account_id,'property.read'));

grant create on schema api to app_executor;
create function api.list_current_manual_blocks(
  p_property_id uuid,
  p_from date,
  p_to date,
  p_after_id uuid default null,
  p_page_size integer default 100
)
returns table (
  block_id uuid,
  property_id uuid,
  check_in date,
  check_out date,
  reason text,
  version integer,
  created_at timestamptz,
  updated_at timestamptz
)
language sql stable security definer set search_path = ''
as $$
  select b.id,b.property_id,b.check_in,b.check_out,b.reason::text,
         b.version,b.created_at,b.updated_at
  from app_private.manual_blocks b
  where p_property_id is not null
    and (select app_private.current_actor_id()) is not null
    and p_from is not null and p_to is not null
    and p_to-p_from between 1 and 93
    and p_page_size between 1 and 100
    and b.property_id=p_property_id
    and b.released_at is null
    and b.check_in<p_to and b.check_out>p_from
    and (p_after_id is null or b.id>p_after_id)
    and app_private.has_property_capability(
      b.property_id,b.owner_account_id,'property.read')
  order by b.id
  limit case when p_page_size between 1 and 100 then p_page_size else 0 end;
$$;
revoke all on function api.list_current_manual_blocks(uuid,date,date,uuid,integer)
  from public,anon,authenticated;
grant execute on function api.list_current_manual_blocks(uuid,date,date,uuid,integer)
  to authenticated;
grant app_executor to current_user with set true, inherit false;
alter function api.list_current_manual_blocks(uuid,date,date,uuid,integer)
  owner to app_executor;
revoke app_executor from current_user;
revoke create on schema api from app_executor;
