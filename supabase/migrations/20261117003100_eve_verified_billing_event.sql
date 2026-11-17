-- EVE-027.2: accept an already-normalized, already-verified Eve-side payment event.
-- This is a server-only transaction boundary, not a provider webhook or wire parser.
grant select,insert,update on app_private.payment_events to billing_executor;

create policy payment_events_billing_read on app_private.payment_events
  for select to billing_executor using (true);
create policy payment_events_billing_insert on app_private.payment_events
  for insert to billing_executor with check (true);
create policy payment_events_billing_update on app_private.payment_events
  for update to billing_executor using (true) with check (true);

create function app_private.reconcile_verified_billing_event(
  p_order_id uuid,
  p_event_key text,
  p_provider_transaction_id text,
  p_amount_minor bigint,
  p_currency text
)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_order app_private.billing_orders%rowtype;
  v_event app_private.payment_events%rowtype;
  v_event_id uuid;
  v_payload jsonb;
  v_inserted boolean := false;
  v_apply jsonb;
  v_replay boolean := false;
begin
  if p_order_id is null
     or p_event_key is null or length(trim(p_event_key))<1 or length(p_event_key)>255
     or p_event_key<>trim(p_event_key) or p_event_key ~ '[[:cntrl:]]'
     or p_provider_transaction_id is null or length(trim(p_provider_transaction_id))<1
     or length(p_provider_transaction_id)>160 or p_provider_transaction_id<>trim(p_provider_transaction_id)
     or p_provider_transaction_id ~ '[[:cntrl:]]'
     or p_amount_minor is null or p_amount_minor<1 or p_amount_minor>9007199254740991
     or p_currency is null or length(p_currency)>3 then
    raise exception using errcode='22023',message='verified_billing_event_invalid';
  end if;

  -- Keep the order lock first, matching the billing order -> property -> subscription sequence.
  select * into v_order from app_private.billing_orders o where o.id=p_order_id for update;
  if not found then raise exception using errcode='P0002',message='billing_order_not_found'; end if;

  -- Store only Eve-normalized fields. No provider payload, token, signature, or credentials are accepted here.
  v_payload := jsonb_build_object('order_id',p_order_id,'provider_transaction_id',p_provider_transaction_id,
    'amount_minor',p_amount_minor,'currency',p_currency);
  insert into app_private.payment_events(provider,event_key,billing_order_id,payload_redacted,
    verification_state,verified_at)
  values('payriff',p_event_key,p_order_id,v_payload,'received',null)
  on conflict(provider,event_key) do nothing returning id into v_event_id;
  v_inserted := found;

  if not v_inserted then
    select * into v_event from app_private.payment_events e
      where e.provider='payriff' and e.event_key=p_event_key for update;
    if not found then raise exception using errcode='40001',message='billing_event_retry_required'; end if;
    if v_event.billing_order_id is distinct from p_order_id or v_event.payload_redacted is distinct from v_payload then
      raise exception using errcode='23505',message='billing_event_key_payload_conflict';
    end if;
    if v_event.verification_state='applied' then
      return jsonb_build_object('event_id',v_event.id,'order_id',p_order_id,
        'verification_state','applied','replay',true,'entitlement_applied',true,
        'manual_review_required',false);
    end if;
    if v_event.verification_state='rejected' then
      return jsonb_build_object('event_id',v_event.id,'order_id',p_order_id,
        'verification_state','rejected','replay',true,'entitlement_applied',false,
        'manual_review_required',false,'rejection_code',v_event.rejection_code);
    end if;
    if v_event.rejection_code='closed_order_manual_reconcile_required' then
      return jsonb_build_object('event_id',v_event.id,'order_id',p_order_id,
        'verification_state','verified','replay',true,'entitlement_applied',false,
        'manual_review_required',true,'rejection_code',v_event.rejection_code);
    end if;
    v_event_id := v_event.id;
    v_replay := true;
  end if;

  if p_currency<>'AZN' or p_amount_minor<>v_order.amount_minor then
    update app_private.payment_events set verification_state='rejected',
      rejection_code='order_amount_currency_mismatch'
      where id=v_event_id;
    return jsonb_build_object('event_id',v_event_id,'order_id',p_order_id,
      'verification_state','rejected','replay',v_replay,'entitlement_applied',false,
      'manual_review_required',false,'rejection_code','order_amount_currency_mismatch');
  end if;

  if v_order.provider_transaction_id is not null and v_order.provider_transaction_id<>p_provider_transaction_id
     or exists(select 1 from app_private.billing_orders other
       where other.provider_transaction_id=p_provider_transaction_id and other.id<>p_order_id) then
    update app_private.payment_events set verification_state='rejected',
      rejection_code='provider_transaction_conflict'
      where id=v_event_id;
    return jsonb_build_object('event_id',v_event_id,'order_id',p_order_id,
      'verification_state','rejected','replay',v_replay,'entitlement_applied',false,
      'manual_review_required',false,'rejection_code','provider_transaction_conflict');
  end if;

  if v_order.state in ('expired','cancelled','failed','refund_review','refunded','chargeback_review')
     or (v_order.expires_at is not null and v_order.expires_at<=statement_timestamp()) then
    update app_private.payment_events set verification_state='verified',verified_at=coalesce(verified_at,statement_timestamp()),
      rejection_code='closed_order_manual_reconcile_required'
      where id=v_event_id;
    return jsonb_build_object('event_id',v_event_id,'order_id',p_order_id,
      'verification_state','verified','replay',v_replay,'entitlement_applied',false,
      'manual_review_required',true,'rejection_code','closed_order_manual_reconcile_required');
  end if;

  if v_order.state not in ('created','pending','verified_paid','entitlement_applied') then
    update app_private.payment_events set verification_state='rejected',rejection_code='billing_order_state_not_applicable'
      where id=v_event_id;
    return jsonb_build_object('event_id',v_event_id,'order_id',p_order_id,
      'verification_state','rejected','replay',v_replay,'entitlement_applied',false,
      'manual_review_required',false,'rejection_code','billing_order_state_not_applicable');
  end if;

  if v_order.provider_transaction_id is null or v_order.state in ('created','pending') then
    update app_private.billing_orders set provider_transaction_id=p_provider_transaction_id,
      state=case when v_order.state in ('created','pending') then 'verified_paid'::app_private.order_state else state end,
      verified_paid_at=case when v_order.verified_paid_at is null then statement_timestamp() else verified_paid_at end,
      updated_at=statement_timestamp(),version=version+1
      where id=p_order_id;
  end if;

  -- Applies entitlement under the existing order/property/subscription locks. Any failure rolls back the inbox row too.
  v_apply := app_private.apply_verified_billing_order(p_order_id);
  update app_private.payment_events set verification_state='applied',
    verified_at=coalesce(verified_at,statement_timestamp()),rejection_code=null
    where id=v_event_id;
  return jsonb_build_object('event_id',v_event_id,'order_id',p_order_id,
    'verification_state','applied','replay',v_replay,
    'entitlement_applied',true,'entitlement_replay',coalesce((v_apply->>'replay')::boolean,false),
    'manual_review_required',false);
end;
$$;
revoke all on function app_private.reconcile_verified_billing_event(uuid,text,text,bigint,text) from public,anon,authenticated,service_role;
grant execute on function app_private.reconcile_verified_billing_event(uuid,text,text,bigint,text) to app_executor;

grant usage,create on schema api to app_executor;
create function api.reconcile_verified_billing_event_for_server(
  p_order_id uuid,
  p_event_key text,
  p_provider_transaction_id text,
  p_amount_minor bigint,
  p_currency text
)
returns jsonb language plpgsql volatile security definer set search_path = ''
as $$
begin
  if current_setting('request.jwt.claim.role',true) is distinct from 'service_role' then
    raise exception using errcode='42501',message='server_adapter_required';
  end if;
  return app_private.reconcile_verified_billing_event(
    p_order_id,p_event_key,p_provider_transaction_id,p_amount_minor,p_currency);
end;
$$;
revoke all on function api.reconcile_verified_billing_event_for_server(uuid,text,text,bigint,text) from public,anon,authenticated,service_role;
grant execute on function api.reconcile_verified_billing_event_for_server(uuid,text,text,bigint,text) to service_role;

grant usage on schema app_private to billing_executor;
grant app_executor to current_user with set true,inherit false;
grant usage,create on schema app_private to billing_executor;
do $$
declare
  temporary_membership boolean;
  changed_membership boolean := false;
  previous_set boolean;
  previous_inherit boolean;
begin
  select set_option,inherit_option into previous_set,previous_inherit
    from pg_auth_members where roleid='billing_executor'::regrole and member=current_user::regrole;
  temporary_membership := not found;
  if temporary_membership then
    execute format('grant billing_executor to %I with set true,inherit false',current_user);
  elsif not previous_set or previous_inherit then
    execute format('grant billing_executor to %I with set true,inherit false',current_user);
    changed_membership := true;
  end if;
  execute 'alter function app_private.reconcile_verified_billing_event(uuid,text,text,bigint,text) owner to billing_executor';
  if temporary_membership then
    execute format('revoke billing_executor from %I',current_user);
  elsif changed_membership then
    execute format('grant billing_executor to %I with set %s,inherit %s',
      current_user,case when previous_set then 'true' else 'false' end,
      case when previous_inherit then 'true' else 'false' end);
  end if;
end $$;
alter function api.reconcile_verified_billing_event_for_server(uuid,text,text,bigint,text) owner to app_executor;
revoke app_executor from current_user;
revoke create on schema app_private from billing_executor;
revoke create on schema api from app_executor;
