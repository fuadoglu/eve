-- EVE-012.3: same-owner reservation move with immutable placement history.
-- The command keeps the same half-open date interval and never moves ledger rows.
grant select on app_private.occupancy, app_private.rent_entries, app_private.idempotency_keys,
  app_private.reservation_attribution_transfers to app_executor;
grant update on app_private.reservations, app_private.reservation_placements,
  app_private.occupancy to app_executor;
grant insert on app_private.reservation_attribution_transfers to app_executor;
grant update on app_private.idempotency_keys to app_executor;
grant insert on app_private.tasks to app_executor;

create policy reservations_move_update on app_private.reservations
  for update to app_executor
  using (app_private.can_write_reservation(property_id, owner_account_id))
  with check (app_private.can_write_reservation(property_id, owner_account_id));

create policy reservation_placements_move_update on app_private.reservation_placements
  for update to app_executor
  using (app_private.can_write_reservation(property_id, owner_account_id))
  with check (app_private.can_write_reservation(property_id, owner_account_id));

create policy occupancy_move_internal_read on app_private.occupancy
  for select to app_executor using (
    placement_id is not null
    and app_private.can_write_reservation(property_id, owner_account_id)
  );
create policy occupancy_move_update on app_private.occupancy
  for update to app_executor
  using (placement_id is not null
    and app_private.can_write_reservation(property_id, owner_account_id))
  with check (placement_id is not null
    and app_private.can_write_reservation(property_id, owner_account_id));
create policy tasks_move_insert on app_private.tasks
  for insert to app_executor with check (
    reservation_id is not null and placement_id is not null
    and kind='cleaning'
    and app_private.can_manage_task(property_id,owner_account_id)
  );

create policy reservation_attribution_move_insert on app_private.reservation_attribution_transfers
  for insert to app_executor with check (
    actor_id=(select app_private.current_actor_id())
    and exists (
      select 1 from app_private.reservation_placements src
      join app_private.reservation_placements dst
        on dst.id=to_placement_id and dst.reservation_id=src.reservation_id
        and dst.owner_account_id=src.owner_account_id
      where src.id=from_placement_id
        and src.reservation_id=reservation_attribution_transfers.reservation_id
        and src.owner_account_id=reservation_attribution_transfers.owner_account_id
        and app_private.can_write_reservation(src.property_id,src.owner_account_id)
        and app_private.can_write_reservation(dst.property_id,dst.owner_account_id)
    )
  );
create policy reservation_attribution_move_read on app_private.reservation_attribution_transfers
  for select to app_executor using (
    actor_id=(select app_private.current_actor_id())
    and exists (
      select 1 from app_private.reservation_placements src
      join app_private.reservation_placements dst
        on dst.id=to_placement_id and dst.reservation_id=src.reservation_id
        and dst.owner_account_id=src.owner_account_id
      where src.id=from_placement_id
        and src.reservation_id=reservation_attribution_transfers.reservation_id
        and src.owner_account_id=reservation_attribution_transfers.owner_account_id
        and app_private.can_write_reservation(src.property_id,src.owner_account_id)
        and app_private.can_write_reservation(dst.property_id,dst.owner_account_id)
    )
  );
create policy idempotency_keys_move_read on app_private.idempotency_keys
  for select to app_executor using (
    actor_scope=(select app_private.current_actor_id())::text||':moveReservation'
  );
create policy idempotency_keys_move_create on app_private.idempotency_keys
  for insert to app_executor with check (
    actor_scope=(select app_private.current_actor_id())::text||':moveReservation'
  );
create policy idempotency_keys_move_update on app_private.idempotency_keys
  for update to app_executor
  using (actor_scope=(select app_private.current_actor_id())::text||':moveReservation')
  with check (actor_scope=(select app_private.current_actor_id())::text||':moveReservation');

grant create on schema api to app_executor;

create function api.move_reservation(
  p_reservation_id uuid,
  p_input jsonb,
  p_idempotency_key text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor uuid := app_private.current_actor_id();
  v_reservation app_private.reservations%rowtype;
  v_source_owner uuid;
  v_source_property uuid;
  v_target_owner uuid;
  v_target_archived timestamptz;
  v_now timestamptz;
  v_expected_version integer;
  v_new_total_minor bigint;
  v_free_stay boolean := false;
  v_reason text;
  v_target_property uuid;
  v_new_placement uuid := gen_random_uuid();
  v_next_placement_no integer;
  v_prior app_private.idempotency_keys%rowtype;
  v_request_hash text;
  v_actor_scope text;
  v_rent_net bigint;
  v_deposit_net bigint;
  v_closed_occupancies integer;
  v_hold_expiry timestamptz;
  v_source_task app_private.tasks%rowtype;
  v_task_key text;
  v_task_hash text;
  v_request_id text;
begin
  if v_actor is null then
    raise exception using errcode='28000', message='authentication_required';
  end if;
  if p_reservation_id is null or jsonb_typeof(p_input) is distinct from 'object'
     or p_input - array['expected_version','to_property_id','new_total_minor','free_stay','reason'] <> '{}'::jsonb
     or jsonb_typeof(p_input->'expected_version') is distinct from 'number'
     or (p_input->>'expected_version') !~ '^[1-9][0-9]*$'
     or (p_input->>'expected_version')::numeric > 2147483647
     or jsonb_typeof(p_input->'to_property_id') is distinct from 'string'
     or (p_input->>'to_property_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     or jsonb_typeof(p_input->'new_total_minor') is distinct from 'number'
     or (p_input->>'new_total_minor') !~ '^(0|[1-9][0-9]*)$'
     or (p_input->>'new_total_minor')::numeric > 9007199254740991
     or (p_input ? 'free_stay' and jsonb_typeof(p_input->'free_stay') is distinct from 'boolean')
     or (p_input ? 'reason' and (jsonb_typeof(p_input->'reason') is distinct from 'string'
       or length(p_input->>'reason') > 1000))
     or p_idempotency_key is null or p_idempotency_key !~ '^[A-Za-z0-9_-]{16,128}$' then
    raise exception using errcode='22023', message='invalid_reservation_move_input';
  end if;
  v_expected_version := (p_input->>'expected_version')::integer;
  v_target_property := (p_input->>'to_property_id')::uuid;
  v_new_total_minor := (p_input->>'new_total_minor')::bigint;
  v_free_stay := coalesce((p_input->>'free_stay')::boolean, false);
  v_reason := nullif(btrim(p_input->>'reason'),'');
  v_request_id := 'move_'||md5(v_actor::text||':'||p_idempotency_key);
  if v_new_total_minor=0 and not v_free_stay then
    raise exception using errcode='22023', message='zero_price_requires_free_stay_confirmation';
  end if;

  v_actor_scope := v_actor::text||':moveReservation';
  v_request_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'reservation_id',p_reservation_id,'expected_version',v_expected_version,
    'to_property_id',v_target_property,'new_total_minor',v_new_total_minor,
    'free_stay',v_free_stay,'reason',v_reason)::text,'UTF8'),'sha256'),'hex');
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_actor_scope||':'||p_idempotency_key,0));
  select * into v_prior from app_private.idempotency_keys i
    where i.actor_scope=v_actor_scope and i.key=p_idempotency_key for update;
  if found and v_prior.expires_at>statement_timestamp() then
    if v_prior.operation_id<>'moveReservation' or v_prior.request_hash<>v_request_hash then
      raise exception using errcode='23505',message='idempotency_key_payload_conflict';
    end if;
    if v_prior.result_id is null then
      raise exception using errcode='P0002',message='reservation_move_result_unavailable';
    end if;
    select * into v_reservation from app_private.reservations r
      where r.id=p_reservation_id
        and app_private.can_write_reservation(r.property_id,r.owner_account_id);
    if not found then raise exception using errcode='P0002',message='reservation_not_found'; end if;
    select src.property_id,dst.property_id into v_source_property,v_target_property
      from app_private.reservation_attribution_transfers t
      join app_private.reservation_placements src on src.id=t.from_placement_id
        and src.reservation_id=t.reservation_id and src.owner_account_id=t.owner_account_id
      join app_private.reservation_placements dst on dst.id=t.to_placement_id
        and dst.reservation_id=t.reservation_id and dst.owner_account_id=t.owner_account_id
      where t.reservation_id=p_reservation_id and t.to_placement_id=v_prior.result_id
        and t.owner_account_id=v_reservation.owner_account_id;
    if not found
       or not app_private.can_write_reservation(v_source_property,v_reservation.owner_account_id)
       or not app_private.can_write_reservation(v_target_property,v_reservation.owner_account_id)
       or not exists (select 1 from app_private.subscriptions s where s.property_id=v_source_property
         and s.owner_account_id=v_reservation.owner_account_id and s.state in ('trialing','active')
         and s.current_end>statement_timestamp())
       or not exists (select 1 from app_private.subscriptions s where s.property_id=v_target_property
         and s.owner_account_id=v_reservation.owner_account_id and s.state in ('trialing','active')
         and s.current_end>statement_timestamp()) then
      raise exception using errcode='42501',message='reservation_move_replay_forbidden';
    end if;
    return jsonb_build_object('reservation_id',p_reservation_id,
      'placement_id',v_prior.result_id,'replayed',true);
  elsif found then
    update app_private.idempotency_keys set request_hash=v_request_hash,
      operation_id='moveReservation',response_status=null,result_id=null,
      created_at=statement_timestamp(),expires_at=statement_timestamp()+interval '24 hours'
      where id=v_prior.id;
  else
    insert into app_private.idempotency_keys(actor_scope,key,request_hash,operation_id,
      created_at,expires_at)
      values(v_actor_scope,p_idempotency_key,v_request_hash,'moveReservation',
        statement_timestamp(),statement_timestamp()+interval '24 hours');
  end if;

  select * into v_reservation from app_private.reservations r
    where r.id=p_reservation_id and app_private.can_write_reservation(r.property_id,r.owner_account_id);
  if not found then raise exception using errcode='P0002',message='reservation_not_found'; end if;
  v_source_owner := v_reservation.owner_account_id;
  v_source_property := v_reservation.property_id;
  if v_target_property=v_source_property then
    raise exception using errcode='22023',message='reservation_move_target_must_differ';
  end if;

  -- The existing hold catch-up primitive takes a property row lock. Acquire
  -- both locks in deterministic UUID order and keep them until this transaction ends.
  if v_source_property<v_target_property then
    perform app_private.expire_property_holds(v_source_property);
    perform app_private.expire_property_holds(v_target_property);
  else
    perform app_private.expire_property_holds(v_target_property);
    perform app_private.expire_property_holds(v_source_property);
  end if;
  select * into v_reservation from app_private.reservations r
    where r.id=p_reservation_id and r.property_id=v_source_property
      and r.owner_account_id=v_source_owner
      and app_private.can_write_reservation(r.property_id,r.owner_account_id)
    for update;
  if not found then raise exception using errcode='40001',message='reservation_changed_during_move'; end if;
  if v_reservation.state not in ('hold','confirmed','checked_in') then
    raise exception using errcode='22023',message='reservation_state_not_movable';
  end if;
  if v_reservation.version<>v_expected_version then
    raise exception using errcode='40001',message='reservation_version_conflict';
  end if;
  if v_reservation.property_id<>v_source_property or v_reservation.owner_account_id<>v_source_owner then
    raise exception using errcode='40001',message='reservation_changed_during_move';
  end if;

  select p.owner_account_id,p.archived_at
    into v_target_owner,v_target_archived
    from app_private.properties p where p.id=v_target_property
      and app_private.can_write_reservation(p.id,p.owner_account_id);
  if not found or v_target_owner<>v_source_owner or v_target_archived is not null then
    raise exception using errcode='42501',message='reservation_move_target_forbidden';
  end if;
  v_now := clock_timestamp();
  if not exists (select 1 from app_private.subscriptions s
      where s.property_id=v_source_property and s.owner_account_id=v_source_owner
        and s.state in ('trialing','active') and s.current_end>v_now)
     or not exists (select 1 from app_private.subscriptions s
      where s.property_id=v_target_property and s.owner_account_id=v_source_owner
        and s.state in ('trialing','active') and s.current_end>v_now) then
    raise exception using errcode='42501',message='active_entitlement_required';
  end if;

  v_hold_expiry := case when v_reservation.state='hold' then v_reservation.hold_expires_at else null end;
  if v_reservation.state='hold' and (v_hold_expiry is null or v_hold_expiry<=v_now) then
    raise exception using errcode='22023',message='reservation_hold_expired';
  end if;
  select count(*) into v_closed_occupancies from app_private.occupancy o
    where o.placement_id=v_reservation.current_placement_id and o.owner_account_id=v_source_owner
      and o.property_id=v_source_property and o.active;
  if v_closed_occupancies<>1 then
    raise exception using errcode='23514',message='reservation_active_occupancy_invariant';
  end if;

  select coalesce(sum(case
      when e.kind in ('rent_receipt','deposit_to_rent') then e.amount_minor
      when e.kind='rent_refund' then -e.amount_minor
      when e.kind='reversal' and original.kind in ('rent_receipt','deposit_to_rent') then -e.amount_minor
      when e.kind='reversal' and original.kind='rent_refund' then e.amount_minor
      else 0 end),0)::bigint,
    coalesce(sum(case
      when e.kind='deposit_receipt' then e.amount_minor
      when e.kind in ('deposit_return','deposit_to_rent','deposit_to_damage') then -e.amount_minor
      when e.kind='reversal' and original.kind='deposit_receipt' then -e.amount_minor
      when e.kind='reversal' and original.kind in ('deposit_return','deposit_to_rent','deposit_to_damage') then e.amount_minor
      else 0 end),0)::bigint
    into v_rent_net,v_deposit_net
    from app_private.rent_entries e
    left join app_private.rent_entries original on original.id=e.original_entry_id
      and original.owner_account_id=e.owner_account_id
    where e.reservation_id=p_reservation_id and e.owner_account_id=v_source_owner;
  if v_rent_net<0 or v_deposit_net<0 then
    raise exception using errcode='23514',message='reservation_net_balance_invariant';
  end if;

  set constraints all deferred;
  select coalesce(max(p.placement_no),0)+1 into v_next_placement_no
    from app_private.reservation_placements p where p.reservation_id=p_reservation_id;
  insert into app_private.reservation_placements(
    id,owner_account_id,property_id,reservation_id,placement_no,
    check_in_snapshot,check_out_snapshot,effective_from,created_by
  ) values (
    v_new_placement,v_source_owner,v_target_property,p_reservation_id,v_next_placement_no,
    v_reservation.check_in,v_reservation.check_out,v_now,v_actor
  );
  update app_private.reservation_placements set effective_to=v_now
    where id=v_reservation.current_placement_id and effective_to is null;
  if not found then raise exception using errcode='23514',message='current_placement_not_open'; end if;

  update app_private.occupancy set active=false
    where placement_id=v_reservation.current_placement_id and property_id=v_source_property
      and owner_account_id=v_source_owner and active;
  if not found then raise exception using errcode='23514',message='source_occupancy_close_failed'; end if;
  insert into app_private.occupancy(owner_account_id,property_id,placement_id,date_range,expires_at)
    values(v_source_owner,v_target_property,v_new_placement,
      daterange(v_reservation.check_in,v_reservation.check_out,'[)'),v_hold_expiry);
  insert into app_private.reservation_attribution_transfers(
    owner_account_id,reservation_id,from_placement_id,to_placement_id,
    rent_net_snapshot_minor,deposit_net_snapshot_minor,actor_id,created_at
  ) values(v_source_owner,p_reservation_id,v_reservation.current_placement_id,v_new_placement,
      v_rent_net,v_deposit_net,v_actor,v_now);

  -- Preserve task history, cancel only future unfinished source cleaning work,
  -- and create a privacy-minimal target task for each cancelled task.
  for v_source_task in
    select t.* from app_private.tasks t
    where t.reservation_id=p_reservation_id
      and t.placement_id=v_reservation.current_placement_id
      and t.property_id=v_source_property and t.owner_account_id=v_source_owner
      and t.kind='cleaning' and t.due_at>v_now
      and t.state in ('open','accepted','reported_done')
    order by t.id for update
  loop
    v_task_key := 'move_'||md5(v_new_placement::text||':'||v_source_task.id::text);
    v_task_hash := encode(extensions.digest(convert_to(jsonb_build_object(
      'reservation_id',p_reservation_id,'task_id',v_source_task.id,
      'target_placement_id',v_new_placement,'action','cancel',
      'expected_version',v_source_task.version)::text,'UTF8'),'sha256'),'hex');
    insert into app_private.task_transition_events(
      owner_account_id,property_id,task_id,action,from_state,to_state,actor_user_id,
      note,idempotency_scope,idempotency_key,request_hash,expected_version,
      resulting_version,created_at
    ) values(v_source_owner,v_source_property,v_source_task.id,'cancel',v_source_task.state,
      'cancelled',v_actor,'reservation_moved','user:'||v_actor::text||':cancel',v_task_key,
      v_task_hash,v_source_task.version,v_source_task.version+1,v_now);
    update app_private.tasks set state='cancelled',version=version+1,updated_at=v_now
      where id=v_source_task.id and version=v_source_task.version;
    if not found then raise exception using errcode='40001',message='source_task_version_conflict'; end if;
    update app_private.access_links set revoked_at=v_now,updated_at=v_now,version=version+1
      where kind='task' and task_id=v_source_task.id and revoked_at is null;
    insert into app_private.tasks(
      owner_account_id,property_id,reservation_id,placement_id,kind,title,due_at,
      required_for_readiness
    ) values(v_source_owner,v_target_property,p_reservation_id,v_new_placement,
      'cleaning','Təmizlik',v_source_task.due_at,v_source_task.required_for_readiness);
  end loop;

  update app_private.access_links set revoked_at=v_now,updated_at=v_now,version=version+1
    where kind='guest_guide' and reservation_id=p_reservation_id
      and placement_id=v_reservation.current_placement_id and revoked_at is null;
  update app_private.reservations set property_id=v_target_property,
      current_placement_id=v_new_placement,total_minor=v_new_total_minor,
      zero_price_confirmed=(v_new_total_minor=0),updated_at=v_now,version=version+1
    where id=p_reservation_id and version=v_expected_version;
  if not found then raise exception using errcode='40001',message='reservation_version_conflict'; end if;

  insert into app_private.audit_events(
    owner_account_id,property_id,actor_user_id,capability,resource_type,resource_id,
    request_id,redacted_diff,reason,created_at
  ) values(v_source_owner,v_target_property,v_actor,'reservation.write','reservation',p_reservation_id,
    v_request_id,jsonb_build_object('action','move_property','version',v_expected_version+1,
      'source_property_id',v_source_property,'target_property_id',v_target_property,
      'from_placement_id',v_reservation.current_placement_id,'to_placement_id',v_new_placement,
      'price_changed',(v_reservation.total_minor<>v_new_total_minor)),
    coalesce(v_reason,'reservation_move'),v_now);
  insert into app_private.outbox(
    event_kind,dedupe_key,property_id,owner_account_id,payload,state,next_attempt_at
  ) values('reservation.moved','reservation.moved:'||p_reservation_id::text||':'||v_new_placement::text,
    v_target_property,v_source_owner,jsonb_build_object('reservation_id',p_reservation_id,
      'placement_id',v_new_placement,'source_property_id',v_source_property),
    'pending',v_now);
  update app_private.idempotency_keys set response_status=200,result_id=v_new_placement
    where actor_scope=v_actor_scope and key=p_idempotency_key;
  return jsonb_build_object('reservation_id',p_reservation_id,'placement_id',v_new_placement,
    'replayed',false);
end;
$$;
revoke all on function api.move_reservation(uuid,jsonb,text) from public,anon,authenticated;
grant execute on function api.move_reservation(uuid,jsonb,text) to authenticated;
grant app_executor to current_user with set true, inherit false;
alter function api.move_reservation(uuid,jsonb,text) owner to app_executor;
revoke app_executor from current_user;
revoke create on schema api from app_executor;
