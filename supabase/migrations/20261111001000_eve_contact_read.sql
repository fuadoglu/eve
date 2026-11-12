-- EVE-006.2 private contact read. Current assigned-property membership gives
-- contact.read/task.manage; write transitions remain closed.
grant select on app_private.contacts, app_private.contact_properties to app_executor;

create function app_private.has_property_assignment_capability(
  p_property_id uuid, p_owner_account_id uuid, p_capability text
)
returns boolean
language sql stable security invoker set search_path = ''
as $$
  select case
    when (select app_private.current_actor_id()) is null
      or p_property_id is null or p_owner_account_id is null
      or p_capability is null
      or p_capability not in ('contact.read','task.manage') then false
    when app_private.is_owner(p_owner_account_id) then true
    else exists (
      select 1 from app_private.property_memberships m
      where m.property_id=p_property_id
        and m.owner_account_id=p_owner_account_id
        and m.user_id=(select app_private.current_actor_id())
        and m.revoked_at is null
    )
  end;
$$;
revoke all on function app_private.has_property_assignment_capability(uuid,uuid,text)
  from public,anon,authenticated;
grant execute on function app_private.has_property_assignment_capability(uuid,uuid,text)
  to app_executor;

create policy contact_properties_assigned_read on app_private.contact_properties
  for select to app_executor
  using (app_private.is_owner(owner_account_id)
    or app_private.has_property_assignment_capability(
      property_id,owner_account_id,'task.manage'));
create policy contacts_linked_or_owner_read on app_private.contacts
  for select to app_executor
  using (app_private.is_owner(owner_account_id) or exists (
    select 1 from app_private.contact_properties cp
    where cp.contact_id=contacts.id
      and cp.owner_account_id=contacts.owner_account_id
      and app_private.has_property_assignment_capability(
        cp.property_id,cp.owner_account_id,'contact.read')
  ));

grant create on schema api to app_executor;
create function api.list_property_contact_summaries(
  p_property_id uuid,
  p_after_id uuid default null,
  p_page_size integer default 30
)
returns table (
  contact_id uuid,
  property_id uuid,
  name text,
  phone text,
  service_type text,
  private_note text,
  version integer,
  created_at timestamptz,
  updated_at timestamptz
)
language sql stable security definer set search_path = ''
as $$
  select c.id,cp.property_id,c.name::text,c.phone::text,c.service_type::text,
    case when app_private.is_owner(c.owner_account_id) or exists (
      select 1 from app_private.property_memberships m
      where m.property_id=cp.property_id
        and m.owner_account_id=cp.owner_account_id
        and m.user_id=(select app_private.current_actor_id())
        and m.permission='full' and m.revoked_at is null
    ) then c.private_note::text else null end,
    c.version,c.created_at,c.updated_at
  from app_private.contact_properties cp
  join app_private.contacts c
    on c.id=cp.contact_id and c.owner_account_id=cp.owner_account_id
  where p_property_id is not null
    and (select app_private.current_actor_id()) is not null
    and p_page_size between 1 and 100
    and cp.property_id=p_property_id
    and c.archived_at is null
    and (p_after_id is null or c.id>p_after_id)
    and app_private.has_property_assignment_capability(
      cp.property_id,cp.owner_account_id,'contact.read')
  order by c.id
  limit case when p_page_size between 1 and 100 then p_page_size else 0 end;
$$;
revoke all on function api.list_property_contact_summaries(uuid,uuid,integer)
  from public,anon,authenticated;
grant execute on function api.list_property_contact_summaries(uuid,uuid,integer)
  to authenticated;
grant app_executor to current_user with set true, inherit false;
alter function api.list_property_contact_summaries(uuid,uuid,integer)
  owner to app_executor;
revoke app_executor from current_user;
revoke create on schema api from app_executor;
