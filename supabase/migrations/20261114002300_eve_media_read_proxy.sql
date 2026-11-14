-- EVE-022.2: private media reads are resolved from a live resource binding.
-- All bridge functions are server-only; the browser never receives Storage keys.

grant select on app_private.media_assets, app_private.media_bindings,
  app_private.properties, app_private.property_memberships,
  app_private.tasks, app_private.task_transition_events,
  app_private.task_transition_media, app_private.expenses, app_private.expense_allocations,
  app_private.inspection_answers, app_private.inspection_submissions,
  app_private.inspection_events, app_private.access_links,
  app_private.reservations, app_private.reservation_placements,
  app_private.guides, app_private.guide_versions to app_executor;

-- Internal SECURITY DEFINER RPCs own the capability decision; no browser role
-- receives a base-table grant or a direct Storage path.
create policy media_assets_proxy_internal_read on app_private.media_assets
  for select to app_executor using (
    state='validated' and deleted_at is null and classification in
      ('private_guest','private_receipt','private_inspection','private_task','private_inventory')
  );
create policy media_bindings_proxy_internal_read on app_private.media_bindings
  for select to app_executor using (true);
create policy access_links_media_internal_read on app_private.access_links
  for select to app_executor using (true);
create policy tasks_media_internal_read on app_private.tasks
  for select to app_executor using (true);
create policy task_transition_events_media_internal_read on app_private.task_transition_events
  for select to app_executor using (true);
create policy task_transition_media_proxy_internal_read on app_private.task_transition_media
  for select to app_executor using (true);
create policy expenses_media_internal_read on app_private.expenses
  for select to app_executor using (true);
create policy expense_allocations_media_internal_read on app_private.expense_allocations
  for select to app_executor using (true);
create policy inspection_answers_media_internal_read on app_private.inspection_answers
  for select to app_executor using (true);
create policy inspection_submissions_media_internal_read on app_private.inspection_submissions
  for select to app_executor using (true);
create policy inspection_events_media_internal_read on app_private.inspection_events
  for select to app_executor using (true);
create policy reservations_media_internal_read on app_private.reservations
  for select to app_executor using (true);
create policy reservation_placements_media_internal_read on app_private.reservation_placements
  for select to app_executor using (true);
create policy guides_media_internal_read on app_private.guides
  for select to app_executor using (true);
create policy guide_versions_media_internal_read on app_private.guide_versions
  for select to app_executor using (true);

create table app_private.link_session_rate_limits (
  token_hash varchar(64) primary key references app_private.access_links(token_hash) on delete cascade,
  window_started_at timestamptz not null,
  attempts integer not null check (attempts>=1),
  updated_at timestamptz not null default statement_timestamp(),
  check (token_hash ~ '^[0-9a-f]{64}$')
);
alter table app_private.link_session_rate_limits enable row level security;
alter table app_private.link_session_rate_limits force row level security;
grant select,insert,update on app_private.link_session_rate_limits to app_executor;
create policy link_session_rate_limits_internal on app_private.link_session_rate_limits
  for all to app_executor using (true) with check (true);

-- D34 inventory media are readable by inventory.read; writes remain inventory.manage.
drop policy media_assets_inventory_read on app_private.media_assets;
create policy media_assets_inventory_read on app_private.media_assets
  for select to app_executor using (
    app_private.has_property_capability(property_id,owner_account_id,'inventory.read')
    and classification='private_inventory' and state='validated' and deleted_at is null
  );

create function app_private.media_actor_can_read(p_media_id uuid)
returns boolean
language plpgsql stable security definer set search_path = ''
as $$
declare v_media app_private.media_assets%rowtype;
begin
  select * into v_media from app_private.media_assets a
  where a.id=p_media_id and a.state='validated' and a.deleted_at is null;
  if not found or (select app_private.current_actor_id()) is null then return false; end if;

  if v_media.classification='private_receipt' then
    return app_private.has_property_capability(v_media.property_id,v_media.owner_account_id,'finance.read')
      and exists (select 1 from app_private.media_bindings b
        join app_private.expenses e on e.id=b.expense_id and e.owner_account_id=b.owner_account_id
        join app_private.expense_allocations al on al.expense_id=e.id
          and al.owner_account_id=e.owner_account_id and al.property_id=b.property_id
        where b.media_asset_id=v_media.id and b.property_id=v_media.property_id
          and b.owner_account_id=v_media.owner_account_id and b.expense_id is not null);
  elsif v_media.classification='private_inventory' then
    return app_private.has_property_capability(v_media.property_id,v_media.owner_account_id,'inventory.read')
      and exists (select 1 from app_private.media_bindings b
        where b.media_asset_id=v_media.id and b.property_id=v_media.property_id
          and b.owner_account_id=v_media.owner_account_id and b.inventory_item_id is not null);
  elsif v_media.classification='private_task' then
    return app_private.has_property_capability(v_media.property_id,v_media.owner_account_id,'property.read')
      and (exists (select 1 from app_private.media_bindings b
          where b.media_asset_id=v_media.id and b.property_id=v_media.property_id
            and b.owner_account_id=v_media.owner_account_id and b.task_id is not null)
        or exists (select 1 from app_private.task_transition_media tm
          where tm.media_asset_id=v_media.id and tm.property_id=v_media.property_id
            and tm.owner_account_id=v_media.owner_account_id));
  elsif v_media.classification='private_inspection' then
    return app_private.has_property_capability(v_media.property_id,v_media.owner_account_id,'property.read')
      and exists (select 1 from app_private.media_bindings b
        join app_private.inspection_answers a on a.id=b.inspection_answer_id
          and a.property_id=b.property_id and a.owner_account_id=b.owner_account_id
        where b.media_asset_id=v_media.id and b.property_id=v_media.property_id
          and b.owner_account_id=v_media.owner_account_id);
  end if;
  -- private_guest is bearer-link only; public classifications use a different safe projection.
  return false;
end;
$$;
revoke all on function app_private.media_actor_can_read(uuid) from public,anon,authenticated,service_role;
grant execute on function app_private.media_actor_can_read(uuid) to app_executor;
alter function app_private.media_actor_can_read(uuid) owner to app_executor;

create function app_private.get_media_actor_source(p_media_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare v_media app_private.media_assets%rowtype;
begin
  if not app_private.media_actor_can_read(p_media_id) then
    raise exception using errcode='P0002',message='media_not_found';
  end if;
  select * into v_media from app_private.media_assets a
    where a.id=p_media_id and a.state='validated' and a.deleted_at is null;
  return jsonb_build_object('id',v_media.id,'classification',v_media.classification::text,
    'bucket',v_media.bucket,'object_key',v_media.object_key,'mime',v_media.mime,
    'size_bytes',v_media.size_bytes);
end;
$$;
revoke all on function app_private.get_media_actor_source(uuid) from public,anon,authenticated,service_role;
grant execute on function app_private.get_media_actor_source(uuid) to app_executor;
alter function app_private.get_media_actor_source(uuid) owner to app_executor;

create function app_private.get_media_scoped_source(p_link_token_hash text,p_media_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare v_media app_private.media_assets%rowtype; v_link app_private.access_links%rowtype; v_allowed boolean := false;
begin
  if p_link_token_hash is null or p_link_token_hash !~ '^[0-9a-f]{64}$' or p_media_id is null then
    raise exception using errcode='P0002',message='media_not_found';
  end if;
  select * into v_link from app_private.access_links l where l.token_hash=p_link_token_hash;
  if not found then raise exception using errcode='P0002',message='media_not_found'; end if;
  if v_link.revoked_at is not null or v_link.expires_at<=statement_timestamp() then
    raise exception using errcode='P4100',message='link_expired';
  end if;
  if v_link.kind='task' and not exists (select 1 from app_private.tasks t
      where t.id=v_link.task_id and t.property_id=v_link.property_id
        and t.owner_account_id=v_link.owner_account_id and t.state<>'cancelled') then
    raise exception using errcode='P4100',message='link_expired';
  end if;
  if v_link.kind='inspection' and not exists (select 1 from app_private.inspection_events e
      where e.id=v_link.inspection_event_id and e.property_id=v_link.property_id
        and e.owner_account_id=v_link.owner_account_id
        and (e.reservation_id is null or exists (select 1 from app_private.reservations r
          where r.id=e.reservation_id and r.property_id=e.property_id
            and r.owner_account_id=e.owner_account_id and r.current_placement_id=e.placement_id
            and r.state::text not in ('cancelled','no_show')))) then
    raise exception using errcode='P4100',message='link_expired';
  end if;
  if v_link.kind='guest_guide' and not exists (select 1 from app_private.reservations r
      where r.id=v_link.reservation_id and r.property_id=v_link.property_id
        and r.owner_account_id=v_link.owner_account_id and r.current_placement_id=v_link.placement_id
        and r.state::text not in ('cancelled','no_show')) then
    raise exception using errcode='P4100',message='link_expired';
  end if;
  select * into v_media from app_private.media_assets a
  where a.id=p_media_id and a.state='validated' and a.deleted_at is null
    and a.property_id=v_link.property_id and a.owner_account_id=v_link.owner_account_id;
  if not found then raise exception using errcode='P0002',message='media_not_found'; end if;

  if v_link.kind='task' and v_media.classification='private_task'
     and v_link.scopes ? 'task.read' then
    v_allowed := exists (select 1 from app_private.media_bindings b
      where b.media_asset_id=v_media.id and b.task_id=v_link.task_id
        and b.property_id=v_link.property_id and b.owner_account_id=v_link.owner_account_id)
      or exists (select 1 from app_private.task_transition_media tm
        join app_private.task_transition_events e on e.id=tm.transition_event_id
          and e.property_id=tm.property_id and e.owner_account_id=tm.owner_account_id
        where tm.media_asset_id=v_media.id and e.task_id=v_link.task_id and e.access_link_id=v_link.id);
  elsif v_link.kind='inspection' and v_media.classification='private_inspection'
        and v_link.scopes ? 'inspection.read' then
    v_allowed := exists (select 1 from app_private.media_bindings b
      join app_private.inspection_answers a on a.id=b.inspection_answer_id
        and a.property_id=b.property_id and a.owner_account_id=b.owner_account_id
      join app_private.inspection_submissions s on s.id=a.submission_id
        and s.property_id=a.property_id and s.owner_account_id=a.owner_account_id
      join app_private.inspection_events e on e.id=s.event_id
        and e.property_id=s.property_id and e.owner_account_id=s.owner_account_id
      where b.media_asset_id=v_media.id and e.id=v_link.inspection_event_id
        and s.side=v_link.side and b.property_id=v_link.property_id
        and b.owner_account_id=v_link.owner_account_id
        and (e.reservation_id is null or exists (select 1 from app_private.reservations r
          where r.id=e.reservation_id and r.property_id=e.property_id
            and r.owner_account_id=e.owner_account_id
            and r.current_placement_id=e.placement_id and r.state::text not in ('cancelled','no_show'))));
  elsif v_link.kind='guest_guide' and v_media.classification='private_guest'
        and v_link.scopes ? 'guest_guide.read' then
    v_allowed := exists (select 1 from app_private.reservations r
      join app_private.reservation_placements p on p.id=r.current_placement_id
        and p.reservation_id=r.id and p.property_id=r.property_id and p.owner_account_id=r.owner_account_id
      join app_private.guides g on g.property_id=r.property_id and g.owner_account_id=r.owner_account_id
        and g.classification='guest_private' and g.archived_at is null
      join app_private.guide_versions gv on gv.guide_id=g.id and gv.published_at is not null
      join app_private.media_bindings b on b.guide_version_id=gv.id
        and b.property_id=gv.property_id and b.owner_account_id=gv.owner_account_id
      where r.id=v_link.reservation_id and r.property_id=v_link.property_id
        and r.owner_account_id=v_link.owner_account_id and r.current_placement_id=v_link.placement_id
        and r.state::text not in ('cancelled','no_show') and b.media_asset_id=v_media.id);
  end if;
  if not v_allowed then raise exception using errcode='P0002',message='media_not_found'; end if;
  return jsonb_build_object('id',v_media.id,'classification',v_media.classification::text,
    'bucket',v_media.bucket,'object_key',v_media.object_key,'mime',v_media.mime,
    'size_bytes',v_media.size_bytes,'link_expires_at',v_link.expires_at);
end;
$$;
revoke all on function app_private.get_media_scoped_source(text,uuid) from public,anon,authenticated,service_role;
grant execute on function app_private.get_media_scoped_source(text,uuid) to app_executor;
alter function app_private.get_media_scoped_source(text,uuid) owner to app_executor;

create function app_private.exchange_scoped_link(p_link_token_hash text)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare v_link app_private.access_links%rowtype; v_resource text; v_scope text;
  v_window timestamptz; v_attempts integer;
begin
  if p_link_token_hash is null or p_link_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode='P0002',message='link_not_found';
  end if;
  select * into v_link from app_private.access_links l where l.token_hash=p_link_token_hash;
  if not found then raise exception using errcode='P0002',message='link_not_found'; end if;
  if v_link.revoked_at is not null or v_link.expires_at<=statement_timestamp() then
    raise exception using errcode='P4100',message='link_expired';
  end if;
  v_resource := v_link.kind::text;
  v_scope := case v_link.kind when 'task' then 'task.read'
    when 'inspection' then 'inspection.read' else 'guest_guide.read' end;
  if not (v_link.scopes ? v_scope) then
    raise exception using errcode='P0002',message='link_not_found';
  end if;
  if v_link.kind='task' and not exists (select 1 from app_private.tasks t
      where t.id=v_link.task_id and t.property_id=v_link.property_id
        and t.owner_account_id=v_link.owner_account_id and t.state<>'cancelled') then
    raise exception using errcode='P4100',message='link_expired';
  end if;
  if v_link.kind='inspection' and not exists (select 1 from app_private.inspection_events e
      where e.id=v_link.inspection_event_id and e.property_id=v_link.property_id
        and e.owner_account_id=v_link.owner_account_id
        and (e.reservation_id is null or exists (select 1 from app_private.reservations r
          where r.id=e.reservation_id and r.property_id=e.property_id
            and r.owner_account_id=e.owner_account_id and r.current_placement_id=e.placement_id
            and r.state::text not in ('cancelled','no_show')))) then
    raise exception using errcode='P4100',message='link_expired';
  end if;
  if v_link.kind='guest_guide' and not exists (select 1 from app_private.reservations r
    where r.id=v_link.reservation_id and r.property_id=v_link.property_id
      and r.owner_account_id=v_link.owner_account_id and r.current_placement_id=v_link.placement_id
      and r.state::text not in ('cancelled','no_show')) then
    raise exception using errcode='P4100',message='link_expired';
  end if;
  insert into app_private.link_session_rate_limits(token_hash,window_started_at,attempts,updated_at)
    values(p_link_token_hash,statement_timestamp(),1,statement_timestamp())
  on conflict (token_hash) do update set
    window_started_at=case when app_private.link_session_rate_limits.window_started_at+interval '1 minute'<=statement_timestamp()
      then statement_timestamp() else app_private.link_session_rate_limits.window_started_at end,
    attempts=case when app_private.link_session_rate_limits.window_started_at+interval '1 minute'<=statement_timestamp()
      then 1 else app_private.link_session_rate_limits.attempts+1 end,
    updated_at=statement_timestamp()
  returning window_started_at,attempts into v_window,v_attempts;
  if v_attempts>10 then raise exception using errcode='PGR01',message='link_exchange_rate_limited'; end if;
  return jsonb_build_object('resource_type',v_resource,'expires_at',v_link.expires_at);
end;
$$;
revoke all on function app_private.exchange_scoped_link(text) from public,anon,authenticated,service_role;
grant execute on function app_private.exchange_scoped_link(text) to app_executor;
alter function app_private.exchange_scoped_link(text) owner to app_executor;

grant usage,create on schema api to app_executor;
create function api.get_media_actor_source_for_server(p_actor_user_id uuid,p_media_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
begin
  if current_setting('request.jwt.claim.role',true) is distinct from 'service_role'
     or p_actor_user_id is null then raise exception using errcode='42501',message='server_adapter_required'; end if;
  perform pg_catalog.set_config('request.jwt.claim.sub',p_actor_user_id::text,true);
  return app_private.get_media_actor_source(p_media_id);
end; $$;
revoke all on function api.get_media_actor_source_for_server(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function api.get_media_actor_source_for_server(uuid,uuid) to service_role;
alter function api.get_media_actor_source_for_server(uuid,uuid) owner to app_executor;

create function api.get_media_scoped_source_for_server(p_link_token_hash text,p_media_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if current_setting('request.jwt.claim.role',true) is distinct from 'service_role' then
    raise exception using errcode='42501',message='server_adapter_required'; end if;
  return app_private.get_media_scoped_source(p_link_token_hash,p_media_id);
end; $$;
revoke all on function api.get_media_scoped_source_for_server(text,uuid) from public,anon,authenticated,service_role;
grant execute on function api.get_media_scoped_source_for_server(text,uuid) to service_role;
alter function api.get_media_scoped_source_for_server(text,uuid) owner to app_executor;

create function api.exchange_scoped_link_for_server(p_link_token_hash text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
begin
  if current_setting('request.jwt.claim.role',true) is distinct from 'service_role' then
    raise exception using errcode='42501',message='server_adapter_required'; end if;
  return app_private.exchange_scoped_link(p_link_token_hash);
end; $$;
revoke all on function api.exchange_scoped_link_for_server(text) from public,anon,authenticated,service_role;
grant execute on function api.exchange_scoped_link_for_server(text) to service_role;
alter function api.exchange_scoped_link_for_server(text) owner to app_executor;

-- app_executor is the sole function owner; API exposure is server-role only.
