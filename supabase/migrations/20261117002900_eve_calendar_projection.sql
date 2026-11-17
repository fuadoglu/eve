-- EVE-013.2: authenticated, bounded, read-only calendar projection.
-- The API contract uses [check_in, check_out) and property.read is checked
-- for every requested property before any data is returned.
grant create on schema api to app_executor;

-- UI05 requires a recognizable owner name in multi-owner property filters.
-- Allow profile display-name reads only when the actor can read one of that
-- owner's properties; profile rows remain otherwise self-only.
create policy owner_accounts_visible_property_read on app_private.owner_accounts
  for select to app_executor
  using (
    owner_user_id=(select app_private.current_actor_id())
    or exists (
      select 1 from app_private.property_memberships m
      where m.owner_account_id=owner_accounts.id
        and m.user_id=(select app_private.current_actor_id())
        and m.revoked_at is null
    )
  );

create policy profiles_visible_property_owner_read on app_private.profiles
  for select to app_executor
  using (
    user_id=(select app_private.current_actor_id())
    or exists (
      select 1
      from app_private.owner_accounts oa
      join app_private.properties p on p.owner_account_id=oa.id
      where oa.owner_user_id=profiles.user_id
        and app_private.has_property_capability(p.id,p.owner_account_id,'property.read')
    )
  );

create function api.list_calendar_property_options(
  p_after_id uuid default null,
  p_page_size integer default 50
)
returns table (
  property_id uuid,
  owner_account_id uuid,
  owner_display_name varchar(100),
  name text,
  area text
)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not api.is_my_session_active() then
    raise exception using errcode='28000', message='active_session_required';
  end if;

  return query
  select p.id, p.owner_account_id,
         left(coalesce(nullif(btrim(pr.display_name),''),'Sahib'),100)::varchar(100),
         p.name::text, p.area::text
  from app_private.properties p
  join app_private.owner_accounts oa on oa.id=p.owner_account_id
  left join app_private.profiles pr on pr.user_id=oa.owner_user_id
  where p_page_size between 1 and 100
    and (p_after_id is null or p.id>p_after_id)
    and app_private.has_property_capability(p.id,p.owner_account_id,'property.read')
  order by p.id
  limit case when p_page_size between 1 and 100 then p_page_size else 0 end;
end;
$$;
revoke all on function api.list_calendar_property_options(uuid,integer)
  from public, anon, authenticated;
grant execute on function api.list_calendar_property_options(uuid,integer) to authenticated;
grant app_executor to current_user with set true, inherit false;
alter function api.list_calendar_property_options(uuid,integer) owner to app_executor;
revoke app_executor from current_user;

create function api.get_calendar(
  p_from date,
  p_to date,
  p_property_ids uuid[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_reservation_count integer;
  v_block_count integer;
  v_reservations jsonb;
  v_blocks jsonb;
begin
  if not api.is_my_session_active() then
    raise exception using errcode='28000', message='active_session_required';
  end if;

  if p_from is null or p_to is null or p_to <= p_from or p_to - p_from > 93
     or p_property_ids is null or cardinality(p_property_ids) not between 1 and 100
     or array_position(p_property_ids, null) is not null then
    raise exception using errcode='22023', message='invalid_calendar_range_or_scope';
  end if;

  -- Fail the complete selection when one ID is unauthorized; never return a
  -- partial result that could conceal an invalid/cross-owner filter.
  if exists (
    select 1
    from unnest(p_property_ids) requested(property_id)
    where not exists (
      select 1 from app_private.properties p
      where p.id=requested.property_id
        and app_private.has_property_capability(p.id,p.owner_account_id,'property.read')
    )
  ) then
    raise exception using errcode='P0002', message='calendar_property_not_found';
  end if;

  select count(*) into v_reservation_count
  from app_private.reservations r
  join app_private.reservation_placements rp
    on rp.id=r.current_placement_id and rp.reservation_id=r.id
   and rp.property_id=r.property_id and rp.owner_account_id=r.owner_account_id
   and rp.effective_to is null
  where r.property_id=any(p_property_ids)
    and r.state not in ('cancelled','no_show')
    and r.check_in<p_to and r.check_out>p_from
    and app_private.has_property_capability(r.property_id,r.owner_account_id,'reservation.read');

  select count(*) into v_block_count
  from app_private.manual_blocks b
  where b.property_id=any(p_property_ids) and b.released_at is null
    and b.check_in<p_to and b.check_out>p_from
    and app_private.has_property_capability(b.property_id,b.owner_account_id,'property.read');

  if v_reservation_count>1000 or v_block_count>1000 then
    raise exception using errcode='22023', message='calendar_result_too_large';
  end if;

  select coalesce(jsonb_agg(api.get_reservation(r.id) order by r.check_in,r.id),'[]'::jsonb)
    into v_reservations
  from app_private.reservations r
  join app_private.reservation_placements rp
    on rp.id=r.current_placement_id and rp.reservation_id=r.id
   and rp.property_id=r.property_id and rp.owner_account_id=r.owner_account_id
   and rp.effective_to is null
  where r.property_id=any(p_property_ids)
    and r.state not in ('cancelled','no_show')
    and r.check_in<p_to and r.check_out>p_from
    and app_private.has_property_capability(r.property_id,r.owner_account_id,'reservation.read');

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'id',b.id,'property_id',b.property_id,'check_in',b.check_in,'check_out',b.check_out,
    'reason',b.reason,'version',b.version,'created_at',b.created_at,'updated_at',b.updated_at
  )) order by b.check_in,b.id),'[]'::jsonb)
    into v_blocks
  from app_private.manual_blocks b
  where b.property_id=any(p_property_ids) and b.released_at is null
    and b.check_in<p_to and b.check_out>p_from
    and app_private.has_property_capability(b.property_id,b.owner_account_id,'property.read');

  return jsonb_build_object(
    'reservations',v_reservations,'blocks',v_blocks,'from',p_from,'to',p_to
  );
end;
$$;

revoke all on function api.get_calendar(date,date,uuid[]) from public,anon,authenticated;
grant execute on function api.get_calendar(date,date,uuid[]) to authenticated;
grant app_executor to current_user with set true, inherit false;
alter function api.get_calendar(date,date,uuid[]) owner to app_executor;
revoke app_executor from current_user;
revoke create on schema api from app_executor;
