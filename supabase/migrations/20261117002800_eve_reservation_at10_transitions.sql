-- EVE-012.3: atomic reservation date/price and lifecycle operations.
-- Public HTTP routes expose only the reservation DTO after this internal acknowledgement.
create extension if not exists pgcrypto with schema extensions;
grant usage on schema extensions to app_executor;

grant select on app_private.properties, app_private.reservations,
  app_private.reservation_placements, app_private.occupancy,
  app_private.subscriptions, app_private.property_memberships,
  app_private.owner_accounts, app_private.idempotency_keys,
  app_private.rent_entries, app_private.realtor_accounts,
  app_private.realtor_settlements, app_private.tasks,
  app_private.task_transition_events, app_private.access_links,
  app_private.inspection_days, app_private.inspection_events,
  app_private.realtor_settlements to app_executor;
grant insert on app_private.reservation_placements, app_private.occupancy,
  app_private.task_transition_events, app_private.inspection_days,
  app_private.inspection_events, app_private.outbox,
  app_private.audit_events to app_executor;
grant update on app_private.reservations, app_private.reservation_placements,
  app_private.occupancy, app_private.tasks, app_private.access_links,
  app_private.realtor_accounts, app_private.idempotency_keys to app_executor;
grant delete on app_private.realtor_accounts to app_executor;
grant insert on app_private.rent_entries to app_executor;

create policy reservations_at10_read on app_private.reservations
  for select to app_executor using (app_private.can_write_reservation(property_id,owner_account_id));
create policy reservations_at10_update on app_private.reservations
  for update to app_executor
  using (app_private.can_write_reservation(property_id,owner_account_id))
  with check (app_private.can_write_reservation(property_id,owner_account_id));
create policy placements_at10_read on app_private.reservation_placements
  for select to app_executor using (app_private.can_write_reservation(property_id,owner_account_id));
create policy placements_at10_update on app_private.reservation_placements
  for update to app_executor
  using (app_private.can_write_reservation(property_id,owner_account_id))
  with check (app_private.can_write_reservation(property_id,owner_account_id));
create policy placements_at10_insert on app_private.reservation_placements
  for insert to app_executor with check (
    created_by=(select app_private.current_actor_id())
    and app_private.can_write_reservation(property_id,owner_account_id));
create policy occupancy_at10_read on app_private.occupancy
  for select to app_executor using (placement_id is not null
    and app_private.can_write_reservation(property_id,owner_account_id));
create policy occupancy_at10_update on app_private.occupancy
  for update to app_executor using (placement_id is not null
    and app_private.can_write_reservation(property_id,owner_account_id))
  with check (placement_id is not null
    and app_private.can_write_reservation(property_id,owner_account_id));
create policy occupancy_at10_insert on app_private.occupancy
  for insert to app_executor with check (placement_id is not null and manual_block_id is null
    and app_private.can_write_reservation(property_id,owner_account_id));
create policy at10_idempotency_read on app_private.idempotency_keys
  for select to app_executor using (actor_scope in (
    (select app_private.current_actor_id())::text||':patchReservation',
    (select app_private.current_actor_id())::text||':transitionReservation'));
create policy at10_idempotency_insert on app_private.idempotency_keys
  for insert to app_executor with check (actor_scope in (
    (select app_private.current_actor_id())::text||':patchReservation',
    (select app_private.current_actor_id())::text||':transitionReservation'));
create policy at10_idempotency_update on app_private.idempotency_keys
  for update to app_executor using (actor_scope in (
    (select app_private.current_actor_id())::text||':patchReservation',
    (select app_private.current_actor_id())::text||':transitionReservation'))
  with check (actor_scope in (
    (select app_private.current_actor_id())::text||':patchReservation',
    (select app_private.current_actor_id())::text||':transitionReservation'));
create policy at10_task_read on app_private.tasks
  for select to app_executor using (app_private.can_write_reservation(property_id,owner_account_id));
create policy at10_task_update on app_private.tasks
  for update to app_executor using (app_private.can_write_reservation(property_id,owner_account_id))
  with check (app_private.can_write_reservation(property_id,owner_account_id));
create policy at10_task_event_read on app_private.task_transition_events
  for select to app_executor using (app_private.can_write_reservation(property_id,owner_account_id));
create policy at10_task_event_insert on app_private.task_transition_events
  for insert to app_executor with check (actor_user_id=(select app_private.current_actor_id())
    and access_link_id is null
    and app_private.can_write_reservation(property_id,owner_account_id));
create policy at10_access_link_read on app_private.access_links
  for select to app_executor using (app_private.can_write_reservation(property_id,owner_account_id));
create policy at10_access_link_update on app_private.access_links
  for update to app_executor using (app_private.can_write_reservation(property_id,owner_account_id))
  with check (app_private.can_write_reservation(property_id,owner_account_id));
create policy at10_rent_insert on app_private.rent_entries
  for insert to app_executor with check (actor_id=(select app_private.current_actor_id())
    and app_private.can_write_reservation(property_id,owner_account_id));
create policy at10_realtor_read on app_private.realtor_accounts
  for select to app_executor using (exists(select 1 from app_private.reservations r
    where r.id=realtor_accounts.reservation_id and r.owner_account_id=realtor_accounts.owner_account_id
      and app_private.can_write_reservation(r.property_id,r.owner_account_id)));
-- Commission replacement must observe every settlement for the account; forced RLS
-- otherwise makes the existence check silently see zero rows.
create policy at10_settlement_read on app_private.realtor_settlements
  for select to app_executor using (
    app_private.has_property_capability(property_id,owner_account_id,'finance.read')
    or exists(select 1 from app_private.reservations r
      where r.id=realtor_settlements.reservation_id
        and r.owner_account_id=realtor_settlements.owner_account_id
        and app_private.has_property_capability(r.property_id,r.owner_account_id,'finance.read'))
  );
create policy at10_realtor_update on app_private.realtor_accounts
  for update to app_executor using (exists(select 1 from app_private.reservations r
    where r.id=realtor_accounts.reservation_id and r.owner_account_id=realtor_accounts.owner_account_id
      and app_private.can_write_reservation(r.property_id,r.owner_account_id)))
  with check (exists(select 1 from app_private.reservations r
    where r.id=realtor_accounts.reservation_id and r.owner_account_id=realtor_accounts.owner_account_id
      and app_private.can_write_reservation(r.property_id,r.owner_account_id)));
create policy at10_realtor_delete on app_private.realtor_accounts
  for delete to app_executor using (exists(select 1 from app_private.reservations r
    where r.id=realtor_accounts.reservation_id and r.owner_account_id=realtor_accounts.owner_account_id
      and app_private.can_write_reservation(r.property_id,r.owner_account_id)));
create policy at10_audit_insert on app_private.audit_events
  for insert to app_executor with check (actor_user_id=(select app_private.current_actor_id())
    and capability='reservation.write'
    and app_private.can_write_reservation(property_id,owner_account_id));
create policy at10_outbox_insert on app_private.outbox
  for insert to app_executor with check (event_kind like 'reservation.%'
    and property_id is not null and owner_account_id is not null
    and app_private.can_write_reservation(property_id,owner_account_id));
create policy at10_inspection_day_read on app_private.inspection_days
  for select to app_executor using (app_private.can_write_reservation(property_id,owner_account_id));
create policy at10_inspection_day_insert on app_private.inspection_days
  for insert to app_executor with check (app_private.can_write_reservation(property_id,owner_account_id));
create policy at10_inspection_event_read on app_private.inspection_events
  for select to app_executor using (app_private.can_write_reservation(property_id,owner_account_id));
create policy at10_inspection_event_insert on app_private.inspection_events
  for insert to app_executor with check (app_private.can_write_reservation(property_id,owner_account_id));

create function api.patch_reservation(p_reservation_id uuid,p_input jsonb,p_idempotency_key text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_actor uuid := app_private.current_actor_id();
  v_r app_private.reservations%rowtype;
  v_prior app_private.idempotency_keys%rowtype;
  v_key text;
  v_hash text;
  v_expected integer;
  v_check_in date;
  v_check_out date;
  v_check_in_time time;
  v_check_out_time time;
  v_total bigint;
  v_guest_name text;
  v_guest_phone text;
  v_guest_count integer;
  v_note text;
  v_capacity integer;
  v_archived timestamptz;
  v_entitlement boolean;
  v_now timestamptz := statement_timestamp();
  v_placement uuid;
  v_placement_no integer;
  v_dates_changed boolean;
  v_changed_count integer;
  v_task app_private.tasks%rowtype;
  v_event_key text;
  v_commission jsonb;
  v_commission_contact uuid;
  v_commission_kind app_private.commission_kind;
  v_commission_fixed bigint;
  v_commission_basis bigint;
  v_commission_bps integer;
  v_commission_earned bigint;
  v_existing_commission app_private.realtor_accounts%rowtype;
begin
  if not api.is_my_session_active() then raise exception using errcode='28000',message='active_session_required'; end if;
  if v_actor is null then raise exception using errcode='28000',message='authentication_required'; end if;
  if p_reservation_id is null or jsonb_typeof(p_input) is distinct from 'object'
    or p_input - array['expected_version','guest_name','guest_phone','guest_count','check_in','check_out',
      'check_in_time','check_out_time','total_minor','capacity_override_confirmed','commission','note','free_stay'] <> '{}'::jsonb
    or jsonb_typeof(p_input->'expected_version') is distinct from 'number'
    or (p_input->>'expected_version') !~ '^[1-9][0-9]*$'
    or (p_input->>'expected_version')::numeric > 2147483647
    or (select count(*) from jsonb_object_keys(p_input)) < 2
    or (p_input ? 'guest_name' and (jsonb_typeof(p_input->'guest_name') is distinct from 'string'
      or length(btrim(p_input->>'guest_name')) not between 1 and 150))
    or (p_input ? 'guest_phone' and p_input->'guest_phone' <> 'null'::jsonb
      and (jsonb_typeof(p_input->'guest_phone') is distinct from 'string'
        or (p_input->>'guest_phone') !~ '^\+[1-9][0-9]{7,14}$'))
    or (p_input ? 'guest_count' and (jsonb_typeof(p_input->'guest_count') is distinct from 'number'
      or (p_input->>'guest_count') !~ '^[1-9][0-9]*$' or (p_input->>'guest_count')::numeric > 1000))
    or (p_input ? 'check_in' and (jsonb_typeof(p_input->'check_in') is distinct from 'string'
      or (p_input->>'check_in') !~ '^\d{4}-\d{2}-\d{2}$'))
    or (p_input ? 'check_out' and (jsonb_typeof(p_input->'check_out') is distinct from 'string'
      or (p_input->>'check_out') !~ '^\d{4}-\d{2}-\d{2}$'))
    or (p_input ? 'check_in_time' and (jsonb_typeof(p_input->'check_in_time') is distinct from 'string'
      or (p_input->>'check_in_time') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'))
    or (p_input ? 'check_out_time' and (jsonb_typeof(p_input->'check_out_time') is distinct from 'string'
      or (p_input->>'check_out_time') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'))
    or (p_input ? 'total_minor' and (jsonb_typeof(p_input->'total_minor') is distinct from 'number'
      or (p_input->>'total_minor') !~ '^(0|[1-9][0-9]*)$' or (p_input->>'total_minor')::numeric > 9007199254740991))
    or (p_input ? 'capacity_override_confirmed' and jsonb_typeof(p_input->'capacity_override_confirmed') is distinct from 'boolean')
    or (p_input ? 'free_stay' and jsonb_typeof(p_input->'free_stay') is distinct from 'boolean')
    or (p_input ? 'note' and (jsonb_typeof(p_input->'note') is distinct from 'string' or length(p_input->>'note')>2000))
    or (p_input ? 'commission' and p_input->'commission'<>'null'::jsonb and jsonb_typeof(p_input->'commission') is distinct from 'object')
    or p_idempotency_key is null or p_idempotency_key !~ '^[A-Za-z0-9_-]{16,128}$' then
    raise exception using errcode='22023',message='invalid_reservation_patch_input';
  end if;
  v_expected := (p_input->>'expected_version')::integer;
  if p_input ? 'check_in' then v_check_in := (p_input->>'check_in')::date; end if;
  if p_input ? 'check_out' then v_check_out := (p_input->>'check_out')::date; end if;
  if p_input ? 'check_in_time' then v_check_in_time := (p_input->>'check_in_time')::time; end if;
  if p_input ? 'check_out_time' then v_check_out_time := (p_input->>'check_out_time')::time; end if;
  if p_input ? 'total_minor' then v_total := (p_input->>'total_minor')::bigint; end if;
  if v_total=0 and coalesce((p_input->>'free_stay')::boolean,false) is not true then
    raise exception using errcode='22023',message='zero_price_requires_free_stay_confirmation';
  end if;
  v_key := v_actor::text||':patchReservation';
  v_hash := encode(extensions.digest(convert_to(jsonb_build_object('reservation_id',p_reservation_id,'input',p_input)::text,'UTF8'),'sha256'),'hex');
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_key||':'||p_idempotency_key,0));
  select * into v_prior from app_private.idempotency_keys i where i.actor_scope=v_key and i.key=p_idempotency_key for update;
  if found and v_prior.expires_at>v_now then
    if v_prior.operation_id<>'patchReservation' or v_prior.request_hash<>v_hash then
      raise exception using errcode='23505',message='idempotency_key_payload_conflict'; end if;
    select * into v_r from app_private.reservations r where r.id=p_reservation_id
      and app_private.can_write_reservation(r.property_id,r.owner_account_id);
    if not found then raise exception using errcode='P0002',message='reservation_not_found'; end if;
    if not exists(select 1 from app_private.subscriptions s where s.property_id=v_r.property_id
      and s.owner_account_id=v_r.owner_account_id and s.state in ('trialing','active') and s.current_end>v_now) then
      raise exception using errcode='42501',message='active_entitlement_required'; end if;
    return jsonb_build_object('reservation_id',v_r.id,'version',v_r.version,'replayed',true);
  elsif found then
    update app_private.idempotency_keys set request_hash=v_hash,operation_id='patchReservation',
      response_status=null,result_id=null,created_at=v_now,expires_at=v_now+interval '24 hours' where id=v_prior.id;
  else
    insert into app_private.idempotency_keys(actor_scope,key,request_hash,operation_id,created_at,expires_at)
      values(v_key,p_idempotency_key,v_hash,'patchReservation',v_now,v_now+interval '24 hours');
  end if;
  select * into v_r from app_private.reservations r where r.id=p_reservation_id
    and app_private.can_write_reservation(r.property_id,r.owner_account_id);
  if not found then raise exception using errcode='P0002',message='reservation_not_found'; end if;
  if p_input ? 'check_in' or p_input ? 'check_out' then
    perform app_private.expire_property_holds(v_r.property_id);
  end if;
  select * into v_r from app_private.reservations r where r.id=p_reservation_id
    and app_private.can_write_reservation(r.property_id,r.owner_account_id) for update;
  if not found then raise exception using errcode='P0002',message='reservation_not_found'; end if;
  if v_r.version<>v_expected then raise exception using errcode='40001',message='reservation_version_conflict'; end if;
  if v_r.state not in ('hold','confirmed','checked_in') then raise exception using errcode='22023',message='reservation_state_not_editable'; end if;
  if not exists(select 1 from app_private.subscriptions s where s.property_id=v_r.property_id
    and s.owner_account_id=v_r.owner_account_id and s.state in ('trialing','active') and s.current_end>v_now) then
    raise exception using errcode='42501',message='active_entitlement_required'; end if;
  select p.max_guests,p.archived_at into v_capacity,v_archived from app_private.properties p
    where p.id=v_r.property_id and p.owner_account_id=v_r.owner_account_id
      and app_private.can_write_reservation(p.id,p.owner_account_id);
  if not found or v_archived is not null then raise exception using errcode='P0002',message='property_not_found'; end if;
  v_guest_name := coalesce(p_input->>'guest_name',v_r.guest_name);
  v_guest_phone := case when p_input ? 'guest_phone' then nullif(p_input->>'guest_phone','null') else v_r.guest_phone end;
  v_guest_count := coalesce((p_input->>'guest_count')::integer,v_r.guest_count);
  if v_guest_count>v_capacity and coalesce((p_input->>'capacity_override_confirmed')::boolean,false) is not true then
    raise exception using errcode='22023',message='capacity_override_confirmation_required'; end if;
  v_check_in := coalesce(v_check_in,v_r.check_in);
  v_check_out := coalesce(v_check_out,v_r.check_out);
  v_check_in_time := coalesce(v_check_in_time,v_r.check_in_time);
  v_check_out_time := coalesce(v_check_out_time,v_r.check_out_time);
  v_total := coalesce(v_total,v_r.total_minor);
  if v_check_out<=v_check_in then raise exception using errcode='22023',message='invalid_reservation_interval'; end if;
  if v_total=0 and not (coalesce((p_input->>'free_stay')::boolean,v_r.zero_price_confirmed)) then
    raise exception using errcode='22023',message='zero_price_requires_free_stay_confirmation'; end if;
  v_dates_changed := v_check_in is distinct from v_r.check_in or v_check_out is distinct from v_r.check_out;
  if p_input ? 'commission' then
    v_commission := p_input->'commission';
    if v_commission<>'null'::jsonb then
      if exists(select 1 from jsonb_object_keys(v_commission) k where k not in
        ('contact_id','kind','fixed_minor','basis_minor','percentage_basis_points'))
        or jsonb_typeof(v_commission->'contact_id') is distinct from 'string'
        or (v_commission->>'contact_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        or v_commission->>'kind' is null or v_commission->>'kind' not in ('fixed','percentage')
        or (v_commission ? 'basis_minor' and (jsonb_typeof(v_commission->'basis_minor') is distinct from 'number'
          or (v_commission->>'basis_minor') !~ '^(0|[1-9][0-9]*)$'
          or (v_commission->>'basis_minor')::numeric>9007199254740991)) then
        raise exception using errcode='22023',message='invalid_reservation_commission';
      end if;
      v_commission_contact := (v_commission->>'contact_id')::uuid;
      v_commission_kind := (v_commission->>'kind')::app_private.commission_kind;
      if v_commission_kind='fixed' then
        if jsonb_typeof(v_commission->'fixed_minor') is distinct from 'number'
          or (v_commission->>'fixed_minor') !~ '^[1-9][0-9]*$'
          or (v_commission->>'fixed_minor')::numeric>9007199254740991
          or v_commission ? 'percentage_basis_points' then
          raise exception using errcode='22023',message='invalid_reservation_commission';
        end if;
        v_commission_fixed := (v_commission->>'fixed_minor')::bigint;
        v_commission_bps := null;
        v_commission_earned := v_commission_fixed;
      else
        if jsonb_typeof(v_commission->'percentage_basis_points') is distinct from 'number'
          or (v_commission->>'percentage_basis_points') !~ '^[1-9][0-9]*$'
          or (v_commission->>'percentage_basis_points')::numeric>10000
          or v_commission ? 'fixed_minor' then
          raise exception using errcode='22023',message='invalid_reservation_commission';
        end if;
        v_commission_fixed := null;
        v_commission_bps := (v_commission->>'percentage_basis_points')::integer;
        v_commission_earned := floor((v_total::numeric*v_commission_bps::numeric/10000)+0.5)::bigint;
      end if;
      v_commission_basis := coalesce((v_commission->>'basis_minor')::bigint,v_total);
      if v_commission_basis<>v_total then
        raise exception using errcode='22023',message='commission_basis_must_match_reservation_total';
      end if;
      if not app_private.is_owner(v_r.owner_account_id)
        and not exists(select 1 from app_private.property_memberships m where m.property_id=v_r.property_id
          and m.owner_account_id=v_r.owner_account_id and m.user_id=v_actor and m.revoked_at is null and m.permission='full') then
        raise exception using errcode='42501',message='finance_manage_required';
      end if;
      if not exists(select 1 from app_private.contacts c where c.id=v_commission_contact
        and c.owner_account_id=v_r.owner_account_id and c.archived_at is null) then
        raise exception using errcode='22023',message='commission_contact_not_available';
      end if;
      select * into v_existing_commission from app_private.realtor_accounts a
        where a.reservation_id=v_r.id and a.owner_account_id=v_r.owner_account_id for update;
      if found and exists(select 1 from app_private.realtor_settlements s
        where s.realtor_account_id=v_existing_commission.id and s.owner_account_id=v_r.owner_account_id) then
        raise exception using errcode='23505',message='commission_has_settlement';
      end if;
      if found then
        update app_private.realtor_accounts set contact_id=v_commission_contact,commission_kind=v_commission_kind,
          fixed_minor=v_commission_fixed,percentage_basis_points=v_commission_bps,
          basis_minor=v_commission_basis,earned_minor=v_commission_earned,updated_at=v_now,version=version+1
          where id=v_existing_commission.id;
      else
        insert into app_private.realtor_accounts(owner_account_id,reservation_id,contact_id,commission_kind,
          fixed_minor,percentage_basis_points,basis_minor,earned_minor)
          values(v_r.owner_account_id,v_r.id,v_commission_contact,v_commission_kind,
            v_commission_fixed,v_commission_bps,v_commission_basis,v_commission_earned);
      end if;
    else
      select * into v_existing_commission from app_private.realtor_accounts a
        where a.reservation_id=v_r.id and a.owner_account_id=v_r.owner_account_id for update;
      if found then
        if not app_private.is_owner(v_r.owner_account_id)
          and not exists(select 1 from app_private.property_memberships m where m.property_id=v_r.property_id
            and m.owner_account_id=v_r.owner_account_id and m.user_id=v_actor and m.revoked_at is null and m.permission='full') then
          raise exception using errcode='42501',message='finance_manage_required';
        end if;
        if exists(select 1 from app_private.realtor_settlements s
          where s.realtor_account_id=v_existing_commission.id and s.owner_account_id=v_r.owner_account_id) then
          raise exception using errcode='23505',message='commission_has_settlement';
        end if;
        delete from app_private.realtor_accounts where id=v_existing_commission.id;
      end if;
    end if;
  end if;
  v_placement := v_r.current_placement_id;
  if v_dates_changed then
    select count(*) into v_changed_count from app_private.occupancy o
      where o.placement_id=v_r.current_placement_id and o.property_id=v_r.property_id
        and o.owner_account_id=v_r.owner_account_id and o.active;
    if v_changed_count<>1 then raise exception using errcode='23514',message='reservation_active_occupancy_invariant'; end if;
    set constraints all deferred;
    select coalesce(max(p.placement_no),0)+1 into v_placement_no from app_private.reservation_placements p where p.reservation_id=p_reservation_id;
    v_placement := gen_random_uuid();
    insert into app_private.reservation_placements(id,owner_account_id,property_id,reservation_id,placement_no,
      check_in_snapshot,check_out_snapshot,effective_from,created_by)
      values(v_placement,v_r.owner_account_id,v_r.property_id,v_r.id,v_placement_no,v_check_in,v_check_out,v_now,v_actor);
    update app_private.reservation_placements set effective_to=v_now where id=v_r.current_placement_id and effective_to is null;
    if not found then raise exception using errcode='23514',message='current_placement_not_open'; end if;
    update app_private.occupancy set active=false where placement_id=v_r.current_placement_id
      and property_id=v_r.property_id and owner_account_id=v_r.owner_account_id and active;
    if not found then raise exception using errcode='23514',message='source_occupancy_close_failed'; end if;
    insert into app_private.occupancy(owner_account_id,property_id,placement_id,date_range,expires_at)
      values(v_r.owner_account_id,v_r.property_id,v_placement,daterange(v_check_in,v_check_out,'[)'),
        case when v_r.state='hold' then v_r.hold_expires_at else null end);
    update app_private.access_links set revoked_at=v_now,updated_at=v_now,version=version+1
      where kind='guest_guide' and reservation_id=v_r.id and placement_id=v_r.current_placement_id and revoked_at is null;
    for v_task in select * from app_private.tasks t where t.reservation_id=v_r.id
      and t.placement_id=v_r.current_placement_id and t.property_id=v_r.property_id
      and t.owner_account_id=v_r.owner_account_id and t.kind='cleaning'
      and t.state in ('open','accepted','reported_done') and t.due_at>v_now for update
    loop
      update app_private.tasks set placement_id=v_placement,
        due_at=((v_check_out+v_check_out_time) at time zone 'Asia/Baku'),
        version=version+1,updated_at=v_now
        where id=v_task.id and version=v_task.version;
      if not found then raise exception using errcode='40001',message='reservation_task_version_conflict'; end if;
    end loop;
  end if;
  update app_private.reservations set guest_name=v_guest_name,guest_phone=v_guest_phone,guest_count=v_guest_count,
    check_in=v_check_in,check_out=v_check_out,check_in_time=v_check_in_time,check_out_time=v_check_out_time,
    current_placement_id=v_placement,total_minor=v_total,zero_price_confirmed=(v_total=0),
    private_note=case when p_input ? 'note' then p_input->>'note' else private_note end,
    updated_at=v_now,version=version+1 where id=v_r.id and version=v_expected;
  if not found then raise exception using errcode='40001',message='reservation_version_conflict'; end if;
  insert into app_private.audit_events(owner_account_id,property_id,actor_user_id,capability,resource_type,resource_id,
    request_id,redacted_diff,reason,created_at)
    values(v_r.owner_account_id,v_r.property_id,v_actor,'reservation.write','reservation',v_r.id,
      'reservation-patch:'||md5(v_actor::text||':'||p_idempotency_key),
      jsonb_build_object('version',v_expected+1,'dates_changed',v_dates_changed,
        'check_in_from',v_r.check_in,'check_in_to',v_check_in,
        'check_out_from',v_r.check_out,'check_out_to',v_check_out,
        'total_minor_from',v_r.total_minor,'total_minor_to',v_total,
        'commission_changed',p_input ? 'commission',
        'guest_changed',v_guest_name<>v_r.guest_name or v_guest_phone is distinct from v_r.guest_phone
          or v_guest_count<>v_r.guest_count,'placement_id',v_placement),
      'reservation_patch',v_now);
  insert into app_private.outbox(event_kind,dedupe_key,property_id,owner_account_id,payload,state,next_attempt_at)
    values('reservation.updated','reservation.updated:'||v_r.id::text||':'||(v_expected+1)::text,v_r.property_id,v_r.owner_account_id,
      jsonb_build_object('reservation_id',v_r.id,'version',v_expected+1,'placement_id',v_placement),'pending',v_now);
  update app_private.idempotency_keys set response_status=200,result_id=v_r.id where actor_scope=v_key and key=p_idempotency_key;
  return jsonb_build_object('reservation_id',v_r.id,'version',v_expected+1,'replayed',false);
end; $$;

create function api.transition_reservation(p_reservation_id uuid,p_input jsonb,p_idempotency_key text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_actor uuid := app_private.current_actor_id();
  v_r app_private.reservations%rowtype;
  v_prior app_private.idempotency_keys%rowtype;
  v_key text;
  v_hash text;
  v_expected integer;
  v_action text;
  v_now timestamptz := statement_timestamp();
  v_new_state app_private.reservation_state;
  v_changed integer;
  v_task app_private.tasks%rowtype;
  v_event_key text;
  v_day uuid;
  v_check_out date;
  v_total bigint;
  v_next_placement uuid;
  v_next_number integer;
  v_decision jsonb;
  v_has_financial boolean;
  v_has_manager_full boolean;
  v_item jsonb;
  v_original app_private.rent_entries%rowtype;
  v_already numeric;
  v_amount numeric;
  v_operation text;
  v_commission app_private.realtor_accounts%rowtype;
  v_settled_commission numeric := 0;
  v_rent_refund_total numeric := 0;
  v_deposit_return_total numeric := 0;
  v_commission_keep_minor numeric;
begin
  if not api.is_my_session_active() then raise exception using errcode='28000',message='active_session_required'; end if;
  if v_actor is null then raise exception using errcode='28000',message='authentication_required'; end if;
  if p_reservation_id is null or jsonb_typeof(p_input) is distinct from 'object'
    or p_input - array['expected_version','action','reason','new_check_out','new_total_minor','financial_decision','free_stay'] <> '{}'::jsonb
    or jsonb_typeof(p_input->'expected_version') is distinct from 'number'
    or (p_input->>'expected_version') !~ '^[1-9][0-9]*$'
    or (p_input->>'expected_version')::numeric>2147483647
    or jsonb_typeof(p_input->'action') is distinct from 'string'
    or p_input->>'action' not in ('confirm','cancel','no_show','check_in','check_out','release_remaining_days')
    or (p_input ? 'reason' and (jsonb_typeof(p_input->'reason') is distinct from 'string' or length(p_input->>'reason')>2000))
    or (p_input ? 'new_check_out' and (jsonb_typeof(p_input->'new_check_out') is distinct from 'string' or (p_input->>'new_check_out') !~ '^\d{4}-\d{2}-\d{2}$'))
    or (p_input ? 'new_total_minor' and (jsonb_typeof(p_input->'new_total_minor') is distinct from 'number'
      or (p_input->>'new_total_minor') !~ '^(0|[1-9][0-9]*)$' or (p_input->>'new_total_minor')::numeric>9007199254740991))
    or (p_input ? 'free_stay' and jsonb_typeof(p_input->'free_stay') is distinct from 'boolean')
    or p_idempotency_key is null or p_idempotency_key !~ '^[A-Za-z0-9_-]{16,128}$' then
    raise exception using errcode='22023',message='invalid_reservation_transition_input';
  end if;
  v_expected := (p_input->>'expected_version')::integer;
  v_action := p_input->>'action';
  v_decision := p_input->'financial_decision';
  if v_action='release_remaining_days' and (not (p_input ? 'new_check_out') or not (p_input ? 'new_total_minor')) then
    raise exception using errcode='22023',message='release_remaining_days_requires_price_and_date'; end if;
  if p_input ? 'free_stay' and (v_action<>'release_remaining_days'
     or coalesce((p_input->>'free_stay')::boolean,false) is not true
     or coalesce((p_input->>'new_total_minor')::numeric,-1)<>0) then
    raise exception using errcode='22023',message='free_stay_confirmation_not_applicable'; end if;
  if v_action='release_remaining_days' and (p_input->>'new_total_minor')::numeric=0
     and coalesce((p_input->>'free_stay')::boolean,false) is not true then
    raise exception using errcode='22023',message='zero_price_requires_free_stay_confirmation'; end if;
  if v_action in ('confirm','check_in','check_out','release_remaining_days') and p_input ? 'financial_decision' then
    raise exception using errcode='22023',message='financial_decision_not_allowed_for_action'; end if;
  if v_action in ('cancel','no_show') and v_decision is not null and (
      jsonb_typeof(v_decision) is distinct from 'object'
      or v_decision - array['mode','rent_refunds','deposit_returns','commission_keep_minor'] <> '{}'::jsonb
      or v_decision->>'mode' not in ('keep_as_is','adjust')
      or (v_decision->>'mode'='keep_as_is' and (select count(*) from jsonb_object_keys(v_decision))<>1)
      or (v_decision->>'mode'='adjust' and (select count(*) from jsonb_object_keys(v_decision))<2)
      or (v_decision ? 'commission_keep_minor' and (jsonb_typeof(v_decision->'commission_keep_minor') is distinct from 'number'
        or (v_decision->>'commission_keep_minor') !~ '^(0|[1-9][0-9]*)$' or (v_decision->>'commission_keep_minor')::numeric>9007199254740991))
      or (v_decision ? 'rent_refunds' and (jsonb_typeof(v_decision->'rent_refunds') is distinct from 'array'
        or jsonb_array_length(v_decision->'rent_refunds') not between 1 and 100))
      or (v_decision ? 'deposit_returns' and (jsonb_typeof(v_decision->'deposit_returns') is distinct from 'array'
        or jsonb_array_length(v_decision->'deposit_returns') not between 1 and 100))) then
    raise exception using errcode='22023',message='invalid_reservation_financial_decision'; end if;
  if v_action in ('cancel','no_show') and v_decision is not null and v_decision->>'mode'='adjust'
     and not (v_decision ? 'rent_refunds' or v_decision ? 'deposit_returns' or v_decision ? 'commission_keep_minor') then
    raise exception using errcode='22023',message='empty_reservation_financial_adjustment'; end if;
  v_key := v_actor::text||':transitionReservation';
  v_hash := encode(extensions.digest(convert_to(jsonb_build_object('reservation_id',p_reservation_id,'input',p_input)::text,'UTF8'),'sha256'),'hex');
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_key||':'||p_idempotency_key,0));
  select * into v_prior from app_private.idempotency_keys i where i.actor_scope=v_key and i.key=p_idempotency_key for update;
  if found and v_prior.expires_at>v_now then
    if v_prior.operation_id<>'transitionReservation' or v_prior.request_hash<>v_hash then
      raise exception using errcode='23505',message='idempotency_key_payload_conflict'; end if;
    select * into v_r from app_private.reservations r where r.id=p_reservation_id
      and app_private.can_write_reservation(r.property_id,r.owner_account_id);
    if not found then raise exception using errcode='P0002',message='reservation_not_found'; end if;
    if not exists(select 1 from app_private.subscriptions s where s.property_id=v_r.property_id
      and s.owner_account_id=v_r.owner_account_id and s.state in ('trialing','active') and s.current_end>v_now) then
      raise exception using errcode='42501',message='active_entitlement_required'; end if;
    return jsonb_build_object('reservation_id',v_r.id,'version',v_r.version,'replayed',true);
  elsif found then
    update app_private.idempotency_keys set request_hash=v_hash,operation_id='transitionReservation',
      response_status=null,result_id=null,created_at=v_now,expires_at=v_now+interval '24 hours' where id=v_prior.id;
  else
    insert into app_private.idempotency_keys(actor_scope,key,request_hash,operation_id,created_at,expires_at)
      values(v_key,p_idempotency_key,v_hash,'transitionReservation',v_now,v_now+interval '24 hours');
  end if;
  select * into v_r from app_private.reservations r where r.id=p_reservation_id
    and app_private.can_write_reservation(r.property_id,r.owner_account_id);
  if not found then raise exception using errcode='P0002',message='reservation_not_found'; end if;
  if v_action in ('confirm','cancel','no_show','check_out') then
    perform app_private.expire_property_holds(v_r.property_id);
  end if;
  select * into v_r from app_private.reservations r where r.id=p_reservation_id
    and app_private.can_write_reservation(r.property_id,r.owner_account_id) for update;
  if not found then raise exception using errcode='P0002',message='reservation_not_found'; end if;
  if v_r.version<>v_expected then raise exception using errcode='40001',message='reservation_version_conflict'; end if;
  if not exists(select 1 from app_private.subscriptions s where s.property_id=v_r.property_id
    and s.owner_account_id=v_r.owner_account_id and s.state in ('trialing','active') and s.current_end>v_now) then
    raise exception using errcode='42501',message='active_entitlement_required'; end if;
  select exists(select 1 from app_private.rent_entries e where e.reservation_id=v_r.id and e.owner_account_id=v_r.owner_account_id)
      or exists(select 1 from app_private.realtor_accounts a where a.reservation_id=v_r.id and a.owner_account_id=v_r.owner_account_id)
    into v_has_financial;
  if v_action in ('cancel','no_show') and v_has_financial and v_decision is null then
    raise exception using errcode='22023',message='financial_decision_required'; end if;
  if v_action in ('cancel','no_show') and v_decision->>'mode'='adjust' then
    select app_private.is_owner(v_r.owner_account_id) or exists(select 1 from app_private.property_memberships m
      where m.property_id=v_r.property_id and m.owner_account_id=v_r.owner_account_id
        and m.user_id=v_actor and m.permission='full' and m.revoked_at is null)
      into v_has_manager_full;
    if (v_decision ? 'rent_refunds' or v_decision ? 'deposit_returns' or v_decision ? 'commission_keep_minor')
       and not v_has_manager_full then raise exception using errcode='42501',message='finance_manage_required'; end if;
    -- The reservation row is already locked above, serializing all cancellation
    -- decisions for this reservation without granting UPDATE on the append-only ledger.
    for v_item in select value from jsonb_array_elements(coalesce(v_decision->'rent_refunds','[]'::jsonb)) loop
      if jsonb_typeof(v_item) is distinct from 'object' or v_item - array['original_id','amount_minor'] <> '{}'
         or jsonb_typeof(v_item->'original_id') is distinct from 'string'
         or (v_item->>'original_id') !~ '^[0-9a-fA-F-]{36}$'
         or jsonb_typeof(v_item->'amount_minor') is distinct from 'number'
         or (v_item->>'amount_minor') !~ '^[1-9][0-9]*$'
         or (v_item->>'amount_minor')::numeric>9007199254740991 then
        raise exception using errcode='22023',message='invalid_rent_refund_adjustment'; end if;
      select * into v_original from app_private.rent_entries e where e.id=(v_item->>'original_id')::uuid
        and e.reservation_id=v_r.id and e.owner_account_id=v_r.owner_account_id
        and e.kind in ('rent_receipt','deposit_to_rent');
      if not found then raise exception using errcode='22023',message='invalid_rent_refund_receipt'; end if;
      if not app_private.has_property_capability(v_original.property_id,v_original.owner_account_id,'finance.read') then
        raise exception using errcode='42501',message='source_receipt_finance_read_required'; end if;
      select coalesce(sum(case when e.kind='rent_refund' then e.amount_minor when e.kind='reversal' and o.kind='rent_refund' then -e.amount_minor else 0 end),0)
        into v_already from app_private.rent_entries e left join app_private.rent_entries o on o.id=e.original_entry_id
          and o.owner_account_id=e.owner_account_id where e.original_entry_id=v_original.id and e.owner_account_id=v_r.owner_account_id;
      v_amount := (v_item->>'amount_minor')::numeric;
      if v_amount+v_already>v_original.amount_minor then raise exception using errcode='22023',message='rent_refund_exceeds_receipt_balance'; end if;
      v_operation := 'at10-rf-'||md5(v_actor::text||':'||p_idempotency_key||':'||v_original.id::text);
      insert into app_private.rent_entries(owner_account_id,property_id,reservation_id,placement_id,kind,amount_minor,
        custodian,custodian_user_id,realtor_contact_id,original_entry_id,actor_id,occurred_at,note,operation_key)
        values(v_original.owner_account_id,v_original.property_id,v_r.id,v_original.placement_id,'rent_refund',v_amount::bigint,
          v_original.custodian,v_original.custodian_user_id,v_original.realtor_contact_id,v_original.id,v_actor,v_now,
          'reservation_cancel_adjustment',v_operation);
      v_rent_refund_total := v_rent_refund_total+v_amount;
    end loop;
    for v_item in select value from jsonb_array_elements(coalesce(v_decision->'deposit_returns','[]'::jsonb)) loop
      if jsonb_typeof(v_item) is distinct from 'object' or v_item - array['original_id','amount_minor'] <> '{}'
         or jsonb_typeof(v_item->'original_id') is distinct from 'string'
         or (v_item->>'original_id') !~ '^[0-9a-fA-F-]{36}$'
         or jsonb_typeof(v_item->'amount_minor') is distinct from 'number'
         or (v_item->>'amount_minor') !~ '^[1-9][0-9]*$'
         or (v_item->>'amount_minor')::numeric>9007199254740991 then
        raise exception using errcode='22023',message='invalid_deposit_return_adjustment'; end if;
      select * into v_original from app_private.rent_entries e where e.id=(v_item->>'original_id')::uuid
        and e.reservation_id=v_r.id and e.owner_account_id=v_r.owner_account_id
        and e.kind='deposit_receipt';
      if not found then raise exception using errcode='22023',message='invalid_deposit_receipt'; end if;
      if not app_private.has_property_capability(v_original.property_id,v_original.owner_account_id,'finance.read') then
        raise exception using errcode='42501',message='source_receipt_finance_read_required'; end if;
      select coalesce(sum(case when e.kind='deposit_return' then e.amount_minor
        when e.kind in ('deposit_to_rent','deposit_to_damage') then e.amount_minor
        when e.kind='reversal' and o.kind in ('deposit_return','deposit_to_rent','deposit_to_damage') then -e.amount_minor else 0 end),0)
        into v_already from app_private.rent_entries e left join app_private.rent_entries o on o.id=e.original_entry_id
          and o.owner_account_id=e.owner_account_id where e.original_entry_id=v_original.id and e.owner_account_id=v_r.owner_account_id;
      v_amount := (v_item->>'amount_minor')::numeric;
      if v_amount+v_already>v_original.amount_minor then raise exception using errcode='22023',message='deposit_return_exceeds_receipt_balance'; end if;
      v_operation := 'at10-dr-'||md5(v_actor::text||':'||p_idempotency_key||':'||v_original.id::text);
      insert into app_private.rent_entries(owner_account_id,property_id,reservation_id,placement_id,kind,amount_minor,
        custodian,custodian_user_id,realtor_contact_id,original_entry_id,actor_id,occurred_at,note,operation_key)
        values(v_original.owner_account_id,v_original.property_id,v_r.id,v_original.placement_id,'deposit_return',v_amount::bigint,
          v_original.custodian,v_original.custodian_user_id,v_original.realtor_contact_id,v_original.id,v_actor,v_now,
          'reservation_cancel_adjustment',v_operation);
      v_deposit_return_total := v_deposit_return_total+v_amount;
    end loop;
    if v_decision ? 'commission_keep_minor' then
      v_commission_keep_minor := (v_decision->>'commission_keep_minor')::numeric;
      select * into v_commission from app_private.realtor_accounts a where a.reservation_id=v_r.id
        and a.owner_account_id=v_r.owner_account_id for update;
      if found then
        v_amount := v_commission_keep_minor;
        if v_amount>v_commission.earned_minor then raise exception using errcode='22023',message='commission_keep_exceeds_earned'; end if;
        select coalesce(sum(s.amount_minor) filter (where s.kind in ('owner_to_realtor','commission_offset')),0)
          into v_settled_commission from app_private.realtor_settlements s
          where s.realtor_account_id=v_commission.id and s.owner_account_id=v_r.owner_account_id;
        if v_commission_keep_minor<v_settled_commission then
          raise exception using errcode='22023',message='commission_keep_below_settled_amount'; end if;
        update app_private.realtor_accounts set earned_minor=v_amount::bigint,cancel_reviewed_at=v_now,
          updated_at=v_now,version=version+1 where id=v_commission.id;
      elsif v_commission_keep_minor<>0 then raise exception using errcode='22023',message='commission_account_not_found'; end if;
    end if;
  end if;
  if v_action='confirm' then
    if v_r.state<>'hold' then raise exception using errcode='22023',message='invalid_reservation_transition'; end if;
    if v_r.hold_expires_at is null or v_r.hold_expires_at<=v_now then raise exception using errcode='22023',message='reservation_hold_expired'; end if;
    v_new_state := 'confirmed';
  elsif v_action='cancel' then
    if v_r.state not in ('hold','confirmed') then raise exception using errcode='22023',message='invalid_reservation_transition'; end if;
    v_new_state := 'cancelled';
  elsif v_action='no_show' then
    if v_r.state<>'confirmed' or (v_r.check_in+v_r.check_in_time) at time zone 'Asia/Baku'>v_now then
      raise exception using errcode='22023',message='invalid_reservation_transition'; end if;
    v_new_state := 'no_show';
  elsif v_action='check_in' then
    if v_r.state<>'confirmed' then raise exception using errcode='22023',message='invalid_reservation_transition'; end if;
    v_new_state := 'checked_in';
  elsif v_action='check_out' then
    if v_r.state<>'checked_in' then raise exception using errcode='22023',message='invalid_reservation_transition'; end if;
    v_new_state := 'completed';
  else
    if v_r.state<>'completed' or v_r.actual_check_out_at is null then
      raise exception using errcode='22023',message='invalid_reservation_transition'; end if;
    v_check_out := (p_input->>'new_check_out')::date;
    v_total := (p_input->>'new_total_minor')::bigint;
    if v_check_out<=v_r.check_in or v_check_out>=v_r.check_out
       or v_check_out < (v_r.actual_check_out_at at time zone 'Asia/Baku')::date then
      raise exception using errcode='22023',message='invalid_remaining_days_release'; end if;
    v_new_state := 'completed';
  end if;
  if v_action='confirm' then
    update app_private.occupancy set expires_at=null where placement_id=v_r.current_placement_id
      and property_id=v_r.property_id and owner_account_id=v_r.owner_account_id and active;
    get diagnostics v_changed=row_count;
    if v_changed<>1 then raise exception using errcode='23514',message='reservation_active_occupancy_invariant'; end if;
  end if;
  if v_action in ('cancel','no_show') then
    update app_private.occupancy set active=false where placement_id=v_r.current_placement_id
      and property_id=v_r.property_id and owner_account_id=v_r.owner_account_id and active;
    get diagnostics v_changed=row_count;
    if v_changed<>1 then raise exception using errcode='23514',message='reservation_active_occupancy_invariant'; end if;
    for v_task in select * from app_private.tasks t where t.reservation_id=v_r.id
      and t.placement_id=v_r.current_placement_id and t.property_id=v_r.property_id
      and t.owner_account_id=v_r.owner_account_id and t.due_at>v_now
      and t.state in ('open','accepted','reported_done') order by t.id for update
    loop
      insert into app_private.task_transition_events(owner_account_id,property_id,task_id,action,from_state,to_state,
        actor_user_id,note,idempotency_scope,idempotency_key,request_hash,expected_version,resulting_version,created_at)
        values(v_r.owner_account_id,v_r.property_id,v_task.id,'cancel',v_task.state,'cancelled',v_actor,
          case when v_action='cancel' then 'reservation_cancelled' else 'reservation_no_show' end,
          'user:'||v_actor::text||':cancel','at10_'||md5(p_reservation_id::text||':'||p_idempotency_key||':'||v_task.id::text),
          encode(extensions.digest(convert_to(jsonb_build_object('reservation_id',v_r.id,'task_id',v_task.id,
            'action','cancel','expected_version',v_task.version)::text,'UTF8'),'sha256'),'hex'),
          v_task.version,v_task.version+1,v_now);
      update app_private.tasks set state='cancelled',version=version+1,updated_at=v_now
        where id=v_task.id and version=v_task.version;
      if not found then raise exception using errcode='40001',message='reservation_task_version_conflict'; end if;
      update app_private.access_links set revoked_at=v_now,updated_at=v_now,version=version+1
        where kind='task' and task_id=v_task.id and revoked_at is null;
    end loop;
    update app_private.access_links set revoked_at=v_now,updated_at=v_now,version=version+1
      where kind='guest_guide' and reservation_id=v_r.id and placement_id=v_r.current_placement_id and revoked_at is null;
  elsif v_action='check_out' then
    update app_private.occupancy set active=false where placement_id=v_r.current_placement_id
      and property_id=v_r.property_id and owner_account_id=v_r.owner_account_id and active;
    get diagnostics v_changed=row_count;
    if v_changed<>1 then raise exception using errcode='23514',message='reservation_active_occupancy_invariant'; end if;
    insert into app_private.inspection_days(owner_account_id,property_id,local_date)
      values(v_r.owner_account_id,v_r.property_id,(v_now at time zone 'Asia/Baku')::date)
      on conflict(property_id,local_date) do nothing;
    select d.id into v_day from app_private.inspection_days d where d.property_id=v_r.property_id
      and d.owner_account_id=v_r.owner_account_id and d.local_date=(v_now at time zone 'Asia/Baku')::date;
    v_event_key := 'reservation:'||v_r.id::text||':checkout:'||v_r.current_placement_id::text;
    insert into app_private.inspection_events(owner_account_id,property_id,day_id,handover_key,reservation_id,placement_id,event_kind,due_at)
      values(v_r.owner_account_id,v_r.property_id,v_day,v_event_key,v_r.id,v_r.current_placement_id,'check_out',v_now)
      on conflict(property_id,handover_key) do nothing;
    select e.id into v_day from app_private.inspection_events e where e.property_id=v_r.property_id
      and e.handover_key=v_event_key;
    select * into v_task from app_private.tasks t where t.reservation_id=v_r.id and t.placement_id=v_r.current_placement_id
      and t.owner_account_id=v_r.owner_account_id and t.property_id=v_r.property_id and t.kind='cleaning'
      and t.state<>'cancelled' for update;
    if found then
      if v_task.state<>'completed' then update app_private.tasks set due_at=v_now,inspection_event_id=v_day,
        version=version+1,updated_at=v_now
        where id=v_task.id; end if;
    else
      insert into app_private.tasks(owner_account_id,property_id,reservation_id,placement_id,kind,title,due_at,
        required_for_readiness,inspection_event_id)
        values(v_r.owner_account_id,v_r.property_id,v_r.id,v_r.current_placement_id,'cleaning','Təmizlik',v_now,true,v_day);
    end if;
  elsif v_action='release_remaining_days' then
    set constraints all deferred;
    select coalesce(max(p.placement_no),0)+1 into v_next_number from app_private.reservation_placements p where p.reservation_id=v_r.id;
    v_next_placement := gen_random_uuid();
    insert into app_private.reservation_placements(id,owner_account_id,property_id,reservation_id,placement_no,
      check_in_snapshot,check_out_snapshot,effective_from,created_by)
      values(v_next_placement,v_r.owner_account_id,v_r.property_id,v_r.id,v_next_number,
        v_r.check_in,v_check_out,v_now,v_actor);
    update app_private.reservation_placements set effective_to=v_now where id=v_r.current_placement_id and effective_to is null;
    if not found then raise exception using errcode='23514',message='current_placement_not_open'; end if;
    update app_private.access_links set revoked_at=v_now,updated_at=v_now,version=version+1
      where kind='guest_guide' and reservation_id=v_r.id and placement_id=v_r.current_placement_id and revoked_at is null;
  end if;
  update app_private.reservations set state=v_new_state,
    hold_expires_at=case when v_action='confirm' then null else hold_expires_at end,
    actual_check_in_at=case when v_action='check_in' then v_now else actual_check_in_at end,
    actual_check_out_at=case when v_action='check_out' then v_now else actual_check_out_at end,
    check_out=case when v_action='release_remaining_days' then v_check_out else check_out end,
    total_minor=case when v_action='release_remaining_days' then v_total else total_minor end,
    zero_price_confirmed=case when v_action='release_remaining_days' and v_total=0 then true else zero_price_confirmed end,
    current_placement_id=coalesce(v_next_placement,current_placement_id),
    updated_at=v_now,version=version+1 where id=v_r.id and version=v_expected;
  if not found then raise exception using errcode='40001',message='reservation_version_conflict'; end if;
  insert into app_private.audit_events(owner_account_id,property_id,actor_user_id,capability,resource_type,resource_id,
    request_id,redacted_diff,reason,created_at)
    values(v_r.owner_account_id,v_r.property_id,v_actor,'reservation.write','reservation',v_r.id,
      'reservation-transition:'||md5(v_actor::text||':'||p_idempotency_key),
      jsonb_build_object('action',v_action,'state_from',v_r.state,'state_to',v_new_state,
        'version',v_expected+1,'released_placement_id',v_next_placement,
        'check_out_from',case when v_action='release_remaining_days' then v_r.check_out else null end,
        'check_out_to',case when v_action='release_remaining_days' then v_check_out else null end,
        'total_minor_from',case when v_action='release_remaining_days' then v_r.total_minor else null end,
        'total_minor_to',case when v_action='release_remaining_days' then v_total else null end,
        'financial_mode',case when v_action in ('cancel','no_show') then coalesce(v_decision->>'mode','not_required') else null end,
        'rent_refund_count',case when v_action in ('cancel','no_show') then jsonb_array_length(coalesce(v_decision->'rent_refunds','[]'::jsonb)) else 0 end,
        'rent_refund_total_minor',v_rent_refund_total,
        'deposit_return_count',case when v_action in ('cancel','no_show') then jsonb_array_length(coalesce(v_decision->'deposit_returns','[]'::jsonb)) else 0 end,
        'deposit_return_total_minor',v_deposit_return_total,
        'commission_keep_minor',v_commission_keep_minor),
      coalesce(nullif(btrim(p_input->>'reason'),''),'reservation_'||v_action),v_now);
  insert into app_private.outbox(event_kind,dedupe_key,property_id,owner_account_id,payload,state,next_attempt_at)
    values('reservation.'||case when v_action='release_remaining_days' then 'updated' else v_action end,
      'reservation.transition:'||v_r.id::text||':'||(v_expected+1)::text,v_r.property_id,v_r.owner_account_id,
      jsonb_build_object('reservation_id',v_r.id,'action',v_action,'version',v_expected+1,'state',v_new_state),
      'pending',v_now);
  update app_private.idempotency_keys set response_status=200,result_id=v_r.id where actor_scope=v_key and key=p_idempotency_key;
  return jsonb_build_object('reservation_id',v_r.id,'version',v_expected+1,'replayed',false);
end; $$;

revoke all on function api.patch_reservation(uuid,jsonb,text),api.transition_reservation(uuid,jsonb,text)
  from public,anon,authenticated;
grant execute on function api.patch_reservation(uuid,jsonb,text),api.transition_reservation(uuid,jsonb,text)
  to authenticated;
grant create on schema api to app_executor;
grant app_executor to current_user with set true, inherit false;
alter function api.patch_reservation(uuid,jsonb,text) owner to app_executor;
alter function api.transition_reservation(uuid,jsonb,text) owner to app_executor;
revoke app_executor from current_user;
revoke create on schema api from app_executor;
