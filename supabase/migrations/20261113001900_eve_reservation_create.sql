-- EVE-011.1: property-scoped reservation creation and its optional first receipt.
-- Every write, including occupancy, audit and outbox, commits or rolls back together.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
grant usage on schema extensions to app_executor;

create or replace function app_private.can_write_reservation(
  p_property_id uuid, p_owner_account_id uuid
)
returns boolean
language sql stable security invoker set search_path = ''
as $$
  select (select app_private.current_actor_id()) is not null
    and p_property_id is not null and p_owner_account_id is not null
    and (
      app_private.is_owner(p_owner_account_id)
      or exists (
        select 1 from app_private.property_memberships m
        where m.property_id=p_property_id and m.owner_account_id=p_owner_account_id
          and m.user_id=(select app_private.current_actor_id()) and m.revoked_at is null
      )
    );
$$;
revoke all on function app_private.can_write_reservation(uuid,uuid) from public,anon,authenticated;
grant execute on function app_private.can_write_reservation(uuid,uuid) to app_executor;

grant select on app_private.property_memberships, app_private.subscriptions,
  app_private.contacts, app_private.reservations, app_private.rent_entries,
  app_private.idempotency_keys to app_executor;
grant insert on app_private.reservations, app_private.reservation_placements,
  app_private.occupancy, app_private.rent_entries, app_private.realtor_accounts,
  app_private.outbox, app_private.audit_events, app_private.idempotency_keys to app_executor;
grant update on app_private.idempotency_keys to app_executor;

create policy subscriptions_reservation_write_read on app_private.subscriptions
  for select to app_executor using (
    app_private.can_write_reservation(property_id,owner_account_id)
  );
create policy contacts_reservation_write_read on app_private.contacts
  for select to app_executor using (
    app_private.is_owner(owner_account_id)
    or exists (select 1 from app_private.property_memberships m
      where m.owner_account_id=contacts.owner_account_id
        and m.user_id=(select app_private.current_actor_id()) and m.revoked_at is null)
  );
create policy reservations_create on app_private.reservations
  for insert to app_executor with check (
    app_private.can_write_reservation(property_id,owner_account_id)
  );
create policy reservation_placements_create on app_private.reservation_placements
  for insert to app_executor with check (
    app_private.can_write_reservation(property_id,owner_account_id)
    and created_by=(select app_private.current_actor_id())
  );
create policy occupancy_reservation_create on app_private.occupancy
  for insert to app_executor with check (
    placement_id is not null and manual_block_id is null
    and app_private.can_write_reservation(property_id,owner_account_id)
  );
create policy rent_entries_reservation_create on app_private.rent_entries
  for insert to app_executor with check (
    app_private.can_write_reservation(property_id,owner_account_id)
    and actor_id=(select app_private.current_actor_id())
  );
create policy realtor_accounts_reservation_create on app_private.realtor_accounts
  for insert to app_executor with check (
    app_private.is_owner(owner_account_id)
    or exists (select 1 from app_private.reservations r
      where r.id=realtor_accounts.reservation_id
        and r.property_id is not null and r.owner_account_id=realtor_accounts.owner_account_id
        and app_private.can_write_reservation(r.property_id,r.owner_account_id))
  );
create policy idempotency_keys_reservation_read on app_private.idempotency_keys
  for select to app_executor using (
    actor_scope=(select app_private.current_actor_id())::text||':createReservation'
  );
create policy idempotency_keys_reservation_create on app_private.idempotency_keys
  for insert to app_executor with check (
    actor_scope=(select app_private.current_actor_id())::text||':createReservation'
  );
create policy idempotency_keys_reservation_update on app_private.idempotency_keys
  for update to app_executor using (
    actor_scope=(select app_private.current_actor_id())::text||':createReservation'
  ) with check (
    actor_scope=(select app_private.current_actor_id())::text||':createReservation'
  );
create policy outbox_reservation_create on app_private.outbox
  for insert to app_executor with check (
    property_id is not null and owner_account_id is not null
    and app_private.can_write_reservation(property_id,owner_account_id)
  );
create policy audit_events_reservation_create on app_private.audit_events
  for insert to app_executor with check (
    property_id is not null and owner_account_id is not null
    and actor_user_id=(select app_private.current_actor_id())
    and capability='reservation.write'
    and app_private.can_write_reservation(property_id,owner_account_id)
  );

grant create on schema api to app_executor;
create function api.create_reservation(p_input jsonb, p_idempotency_key text)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_actor uuid := app_private.current_actor_id();
  v_property_id uuid;
  v_owner_id uuid;
  v_default_check_in time;
  v_default_check_out time;
  v_max_guests integer;
  v_archived_at timestamptz;
  v_subscription_state app_private.subscription_state;
  v_subscription_end timestamptz;
  v_guest_name text;
  v_guest_phone text;
  v_guest_count integer;
  v_check_in date;
  v_check_out date;
  v_check_in_time time;
  v_check_out_time time;
  v_state app_private.reservation_state;
  v_hold_duration text;
  v_hold_expires_at timestamptz;
  v_total_minor bigint;
  v_capacity_override boolean;
  v_zero_price boolean;
  v_free_stay boolean;
  v_note text;
  v_initial jsonb;
  v_initial_amount bigint;
  v_initial_kind app_private.rent_kind;
  v_custodian app_private.custodian;
  v_contact_id uuid;
  v_commission jsonb;
  v_commission_contact_id uuid;
  v_commission_kind app_private.commission_kind;
  v_fixed_minor bigint;
  v_percentage_basis_points integer;
  v_earned_minor bigint;
  v_canonical jsonb;
  v_request_hash text;
  v_actor_scope text;
  v_prior app_private.idempotency_keys%rowtype;
  v_reservation_id uuid := gen_random_uuid();
  v_placement_id uuid := gen_random_uuid();
  v_receipt_id uuid;
  v_replay boolean := false;
  v_now timestamptz := statement_timestamp();
begin
  if v_actor is null then
    raise exception using errcode='28000',message='authentication_required';
  end if;
  if p_idempotency_key is null or length(p_idempotency_key)<16 or length(p_idempotency_key)>128
     or p_idempotency_key !~ '^[A-Za-z0-9_-]+$' then
    raise exception using errcode='22023',message='invalid_idempotency_key';
  end if;
  if p_input is null or jsonb_typeof(p_input)<>'object'
     or exists (select 1 from jsonb_object_keys(p_input) k where k not in (
       'property_id','guest_name','guest_phone','guest_count','check_in','check_out',
       'check_in_time','check_out_time','status','hold_duration','total_minor',
       'capacity_override_confirmed','initial_receipt','commission','note','free_stay')) then
    raise exception using errcode='22023',message='invalid_reservation_input';
  end if;

  if jsonb_typeof(p_input->'property_id') is distinct from 'string'
     or (p_input->>'property_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     or jsonb_typeof(p_input->'guest_name') is distinct from 'string'
     or length(p_input->>'guest_name')<1 or length(p_input->>'guest_name')>150
     or length(btrim(p_input->>'guest_name'))=0
     or jsonb_typeof(p_input->'check_in') is distinct from 'string'
     or (p_input->>'check_in') !~ '^\d{4}-\d{2}-\d{2}$'
     or jsonb_typeof(p_input->'check_out') is distinct from 'string'
     or (p_input->>'check_out') !~ '^\d{4}-\d{2}-\d{2}$'
     or jsonb_typeof(p_input->'total_minor') is distinct from 'number'
     or (p_input->>'total_minor') !~ '^(0|[1-9][0-9]*)$' then
    raise exception using errcode='22023',message='invalid_reservation_input';
  end if;
  begin
    v_property_id := (p_input->>'property_id')::uuid;
    v_check_in := (p_input->>'check_in')::date;
    v_check_out := (p_input->>'check_out')::date;
    v_total_minor := (p_input->>'total_minor')::bigint;
  exception when others then
    raise exception using errcode='22023',message='invalid_reservation_input';
  end;
  if v_check_out<=v_check_in or v_total_minor<0 or v_total_minor>9007199254740991 then
    raise exception using errcode='22023',message='invalid_reservation_input';
  end if;

  v_guest_name := p_input->>'guest_name';
  if p_input ? 'guest_phone' then
    if jsonb_typeof(p_input->'guest_phone') is distinct from 'string'
       or (p_input->>'guest_phone') !~ '^\+[1-9][0-9]{7,14}$' then
      raise exception using errcode='22023',message='invalid_reservation_phone';
    end if;
    v_guest_phone := p_input->>'guest_phone';
  end if;
  if p_input ? 'guest_count' then
    if jsonb_typeof(p_input->'guest_count') is distinct from 'number'
       or (p_input->>'guest_count') !~ '^[1-9][0-9]*$'
       or (p_input->>'guest_count')::numeric>1000 then
      raise exception using errcode='22023',message='invalid_guest_count';
    end if;
    v_guest_count := (p_input->>'guest_count')::integer;
  else
    v_guest_count := 1;
  end if;
  if v_guest_count<1 or v_guest_count>1000 then
    raise exception using errcode='22023',message='invalid_guest_count';
  end if;
  if p_input ? 'check_in_time' then
    if jsonb_typeof(p_input->'check_in_time') is distinct from 'string'
       or (p_input->>'check_in_time') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
      raise exception using errcode='22023',message='invalid_check_in_time';
    end if;
    v_check_in_time := (p_input->>'check_in_time')::time;
  end if;
  if p_input ? 'check_out_time' then
    if jsonb_typeof(p_input->'check_out_time') is distinct from 'string'
       or (p_input->>'check_out_time') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
      raise exception using errcode='22023',message='invalid_check_out_time';
    end if;
    v_check_out_time := (p_input->>'check_out_time')::time;
  end if;
  if p_input ? 'status' and (jsonb_typeof(p_input->'status') is distinct from 'string'
       or p_input->>'status' not in ('hold','confirmed')) then
    raise exception using errcode='22023',message='invalid_reservation_status';
  end if;
  v_state := coalesce(p_input->>'status','confirmed')::app_private.reservation_state;
  v_hold_duration := p_input->>'hold_duration';
  if v_state='hold' and (v_hold_duration is null
       or v_hold_duration not in ('one_hour','three_hours','tomorrow_noon')) then
    raise exception using errcode='22023',message='hold_duration_required';
  elsif v_state<>'hold' and v_hold_duration is not null then
    raise exception using errcode='22023',message='hold_duration_only_for_hold';
  end if;
  if p_input ? 'capacity_override_confirmed' and jsonb_typeof(p_input->'capacity_override_confirmed')<>'boolean' then
    raise exception using errcode='22023',message='invalid_capacity_override';
  end if;
  v_capacity_override := coalesce((p_input->>'capacity_override_confirmed')::boolean,false);
  if p_input ? 'free_stay' and jsonb_typeof(p_input->'free_stay')<>'boolean' then
    raise exception using errcode='22023',message='invalid_free_stay';
  end if;
  v_free_stay := coalesce((p_input->>'free_stay')::boolean,false);
  v_zero_price := v_total_minor=0 and v_free_stay;
  if v_total_minor=0 and not v_free_stay then
    raise exception using errcode='22023',message='free_stay_confirmation_required';
  end if;
  if p_input ? 'note' and (jsonb_typeof(p_input->'note') is distinct from 'string'
     or length(p_input->>'note')>2000) then
    raise exception using errcode='22023',message='invalid_reservation_note';
  end if;
  v_note := p_input->>'note';
  v_initial := p_input->'initial_receipt';
  if v_initial is not null and jsonb_typeof(v_initial)<>'null' then
    if jsonb_typeof(v_initial)<>'object'
       or exists (select 1 from jsonb_object_keys(v_initial) k where k not in ('amount_minor','kind','custodian','contact_id'))
       or jsonb_typeof(v_initial->'amount_minor') is distinct from 'number'
       or (v_initial->>'amount_minor') !~ '^[1-9][0-9]*$'
       or (v_initial->>'amount_minor')::numeric>9007199254740991
       or v_initial->>'kind' is distinct from 'rent_receipt' and v_initial->>'kind' is distinct from 'deposit_receipt'
       or v_initial->>'custodian' is distinct from 'owner'
          and v_initial->>'custodian' is distinct from 'manager'
          and v_initial->>'custodian' is distinct from 'realtor' then
      raise exception using errcode='22023',message='invalid_initial_receipt';
    end if;
    v_initial_amount := (v_initial->>'amount_minor')::bigint;
    v_initial_kind := (v_initial->>'kind')::app_private.rent_kind;
    v_custodian := (v_initial->>'custodian')::app_private.custodian;
    if v_custodian='realtor' then
      if jsonb_typeof(v_initial->'contact_id') is distinct from 'string'
         or (v_initial->>'contact_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        raise exception using errcode='22023',message='receipt_realtor_contact_required';
      end if;
      v_contact_id := (v_initial->>'contact_id')::uuid;
    elsif v_initial ? 'contact_id' then
      raise exception using errcode='22023',message='receipt_contact_only_for_realtor';
    end if;
  end if;

  v_commission := p_input->'commission';
  if v_commission is not null and jsonb_typeof(v_commission)<>'null' then
    if jsonb_typeof(v_commission)<>'object'
       or exists (select 1 from jsonb_object_keys(v_commission) k where k not in (
         'contact_id','kind','fixed_minor','basis_minor','percentage_basis_points'))
       or jsonb_typeof(v_commission->'contact_id') is distinct from 'string'
       or (v_commission->>'contact_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or (v_commission->>'kind' is distinct from 'fixed'
           and v_commission->>'kind' is distinct from 'percentage') then
      raise exception using errcode='22023',message='invalid_commission';
    end if;
    v_commission_contact_id := (v_commission->>'contact_id')::uuid;
    v_commission_kind := (v_commission->>'kind')::app_private.commission_kind;
    if v_commission_kind='fixed' then
      if jsonb_typeof(v_commission->'fixed_minor') is distinct from 'number'
         or (v_commission->>'fixed_minor') !~ '^[1-9][0-9]*$'
         or (v_commission->>'fixed_minor')::numeric>9007199254740991
         or v_commission ? 'percentage_basis_points' then
        raise exception using errcode='22023',message='invalid_fixed_commission';
      end if;
      v_fixed_minor := (v_commission->>'fixed_minor')::bigint;
      v_percentage_basis_points := null;
      v_earned_minor := v_fixed_minor;
    else
      if jsonb_typeof(v_commission->'percentage_basis_points') is distinct from 'number'
         or (v_commission->>'percentage_basis_points') !~ '^[1-9][0-9]*$'
         or (v_commission->>'percentage_basis_points')::numeric>10000
         or v_commission ? 'fixed_minor' then
        raise exception using errcode='22023',message='invalid_percentage_commission';
      end if;
      v_fixed_minor := null;
    v_percentage_basis_points := (v_commission->>'percentage_basis_points')::integer;
      v_earned_minor := floor((v_total_minor::numeric*v_percentage_basis_points::numeric/10000)+0.5)::bigint;
    end if;
    if v_commission ? 'basis_minor' and (jsonb_typeof(v_commission->'basis_minor') is distinct from 'number'
       or (v_commission->>'basis_minor') !~ '^(0|[1-9][0-9]*)$'
       or (v_commission->>'basis_minor')::numeric<>v_total_minor) then
      raise exception using errcode='22023',message='commission_basis_must_equal_rent_total';
    end if;
  end if;

  select p.owner_account_id,p.default_check_in,p.default_check_out,p.max_guests,p.archived_at
    into v_owner_id,v_default_check_in,v_default_check_out,v_max_guests,v_archived_at
  from app_private.properties p
  where p.id=v_property_id and app_private.can_write_reservation(p.id,p.owner_account_id);
  if v_owner_id is null or v_archived_at is not null then
    raise exception using errcode='P0002',message='property_not_found';
  end if;
  -- Serialize this create with all writes for the property before taking
  -- authoritative settings, entitlement and timestamps.
  perform app_private.expire_property_holds(v_property_id);
  v_now := clock_timestamp();
  select p.owner_account_id,p.default_check_in,p.default_check_out,p.max_guests,p.archived_at
    into v_owner_id,v_default_check_in,v_default_check_out,v_max_guests,v_archived_at
  from app_private.properties p
  where p.id=v_property_id and app_private.can_write_reservation(p.id,p.owner_account_id);
  if v_owner_id is null or v_archived_at is not null then
    raise exception using errcode='P0002',message='property_not_found';
  end if;
  if not exists (select 1 from app_private.subscriptions s
      where s.property_id=v_property_id and s.owner_account_id=v_owner_id
        and s.state in ('trialing','active') and s.current_end>v_now) then
    raise exception using errcode='42501',message='active_entitlement_required';
  end if;
  if v_check_in_time is null then v_check_in_time := v_default_check_in; end if;
  if v_check_out_time is null then v_check_out_time := v_default_check_out; end if;
  if v_guest_count>v_max_guests and not v_capacity_override then
    raise exception using errcode='22023',message='capacity_confirmation_required';
  end if;
  if v_initial is not null and jsonb_typeof(v_initial)<>'null' and v_custodian='realtor'
     and not exists (select 1 from app_private.contacts c
       where c.id=v_contact_id and c.owner_account_id=v_owner_id and c.archived_at is null) then
    raise exception using errcode='22023',message='receipt_contact_not_found';
  end if;
  if v_initial is not null and jsonb_typeof(v_initial)<>'null' and v_custodian='owner'
     and not exists (select 1 from app_private.owner_accounts a
       where a.id=v_owner_id and a.owner_user_id=v_actor) then
    raise exception using errcode='42501',message='receipt_owner_must_be_actor';
  end if;
  if v_initial is not null and jsonb_typeof(v_initial)<>'null' and v_custodian='manager'
     and not exists (select 1 from app_private.property_memberships m
       where m.owner_account_id=v_owner_id and m.property_id=v_property_id
         and m.user_id=v_actor and m.revoked_at is null) then
    raise exception using errcode='42501',message='receipt_manager_must_be_actor';
  end if;
  if v_commission is not null and jsonb_typeof(v_commission)<>'null'
     and not exists (select 1 from app_private.contacts c
       where c.id=v_commission_contact_id and c.owner_account_id=v_owner_id and c.archived_at is null) then
    raise exception using errcode='22023',message='commission_contact_not_found';
  end if;

  if v_state='hold' then
    v_hold_expires_at := case v_hold_duration
      when 'one_hour' then v_now+interval '1 hour'
      when 'three_hours' then v_now+interval '3 hours'
      when 'tomorrow_noon' then
        (((v_now at time zone 'Asia/Baku')::date+1)+time '12:00') at time zone 'Asia/Baku'
    end;
  end if;
  v_canonical := jsonb_build_object(
    'property_id',v_property_id,'guest_name',v_guest_name,'guest_phone',v_guest_phone,
    'guest_count',v_guest_count,'check_in',v_check_in,'check_out',v_check_out,
    'check_in_time',v_check_in_time,'check_out_time',v_check_out_time,
    'status',v_state,'hold_duration',v_hold_duration,'total_minor',v_total_minor,
    'capacity_override_confirmed',v_capacity_override,'initial_receipt',v_initial,
    'commission',v_commission,'note',v_note,'free_stay',v_free_stay);
  v_request_hash := encode(extensions.digest(convert_to(v_canonical::text,'UTF8'),'sha256'),'hex');
  v_actor_scope := v_actor::text||':createReservation';
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_actor_scope||':'||p_idempotency_key,0));
  select * into v_prior from app_private.idempotency_keys i
  where i.actor_scope=v_actor_scope and i.key=p_idempotency_key for update;
  if found and v_prior.expires_at>v_now then
    if v_prior.operation_id<>'createReservation' or v_prior.request_hash<>v_request_hash then
      raise exception using errcode='23505',message='idempotency_key_payload_conflict';
    end if;
    v_reservation_id := v_prior.result_id;
    v_replay := true;
  elsif found then
    update app_private.idempotency_keys set request_hash=v_request_hash,
      operation_id='createReservation',response_status=null,result_id=null,
      created_at=v_now,expires_at=v_now+interval '24 hours'
    where id=v_prior.id;
  else
    insert into app_private.idempotency_keys(actor_scope,key,request_hash,operation_id,created_at,expires_at)
    values (v_actor_scope,p_idempotency_key,v_request_hash,'createReservation',v_now,v_now+interval '24 hours');
  end if;
  if v_replay then
    select p.id into v_placement_id from app_private.reservation_placements p
    where p.reservation_id=v_reservation_id and p.placement_no=1
      and p.property_id=v_property_id and p.owner_account_id=v_owner_id;
    if v_placement_id is null then
      raise exception using errcode='P0002',message='reservation_not_found';
    end if;
    select e.id into v_receipt_id from app_private.rent_entries e
    where e.reservation_id=v_reservation_id and e.operation_key='reservation_create:'||v_reservation_id::text;
    return jsonb_build_object('reservation_id',v_reservation_id,'placement_id',v_placement_id,
      'initial_receipt_id',v_receipt_id);
  end if;

  -- The exclusion constraint remains the final race-safe occupancy guard.
  set constraints all deferred;
  insert into app_private.reservations(
    id,owner_account_id,property_id,current_placement_id,guest_name,guest_phone,
    check_in,check_out,check_in_time,check_out_time,guest_count,state,total_minor,
    zero_price_confirmed,hold_expires_at,private_note
  ) values (
    v_reservation_id,v_owner_id,v_property_id,v_placement_id,v_guest_name,v_guest_phone,
    v_check_in,v_check_out,v_check_in_time,v_check_out_time,v_guest_count,v_state,v_total_minor,
    v_zero_price,v_hold_expires_at,v_note
  );
  insert into app_private.reservation_placements(
    id,owner_account_id,property_id,reservation_id,placement_no,check_in_snapshot,
    check_out_snapshot,effective_from,created_by
  ) values (
    v_placement_id,v_owner_id,v_property_id,v_reservation_id,1,v_check_in,v_check_out,v_now,v_actor
  );
  insert into app_private.occupancy(owner_account_id,property_id,placement_id,date_range,expires_at)
  values (v_owner_id,v_property_id,v_placement_id,daterange(v_check_in,v_check_out,'[)'),v_hold_expires_at);

  if v_initial is not null and jsonb_typeof(v_initial)<>'null' then
    insert into app_private.rent_entries(
      owner_account_id,property_id,reservation_id,placement_id,kind,amount_minor,
      custodian,custodian_user_id,realtor_contact_id,actor_id,occurred_at,operation_key
    ) values (
      v_owner_id,v_property_id,v_reservation_id,v_placement_id,v_initial_kind,v_initial_amount,
      v_custodian,case when v_custodian='realtor' then null
        when v_custodian='owner' then (select a.owner_user_id from app_private.owner_accounts a where a.id=v_owner_id)
        else v_actor end,
      case when v_custodian='realtor' then v_contact_id else null end,
      v_actor,v_now,'reservation_create:'||v_reservation_id::text
    ) returning id into v_receipt_id;
  end if;
  if v_commission is not null and jsonb_typeof(v_commission)<>'null' then
    insert into app_private.realtor_accounts(
      owner_account_id,reservation_id,contact_id,commission_kind,fixed_minor,
      percentage_basis_points,basis_minor,earned_minor
    ) values (
      v_owner_id,v_reservation_id,v_commission_contact_id,v_commission_kind,
      v_fixed_minor,v_percentage_basis_points,v_total_minor,v_earned_minor
    );
  end if;
  insert into app_private.audit_events(
    owner_account_id,property_id,actor_user_id,capability,resource_type,resource_id,
    request_id,redacted_diff,reason
  ) values (
    v_owner_id,v_property_id,v_actor,'reservation.write','reservation',v_reservation_id,
    v_reservation_id::text,jsonb_build_object('state',v_state,'capacity_override_confirmed',v_capacity_override),
    'reservation_create'
  );
  insert into app_private.outbox(
    event_kind,dedupe_key,property_id,owner_account_id,payload,state,next_attempt_at
  ) values (
    'reservation.created','reservation.created:'||v_reservation_id::text,
    v_property_id,v_owner_id,jsonb_build_object('reservation_id',v_reservation_id),
    'pending',v_now
  );
  update app_private.idempotency_keys set response_status=201,result_id=v_reservation_id
  where actor_scope=v_actor_scope and key=p_idempotency_key;
  return jsonb_build_object('reservation_id',v_reservation_id,'placement_id',v_placement_id,
    'initial_receipt_id',v_receipt_id);
end;
$$;
revoke all on function api.create_reservation(jsonb,text) from public,anon,authenticated;
grant execute on function api.create_reservation(jsonb,text) to authenticated;
grant app_executor to current_user with set true, inherit false;
alter function api.create_reservation(jsonb,text) owner to app_executor;
revoke app_executor from current_user;
revoke create on schema api from app_executor;
grant usage on schema api to authenticated;
