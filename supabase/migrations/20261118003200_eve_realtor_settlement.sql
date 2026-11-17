-- EVE-015.2: versioned, append-only realtor settlement commands (D44).
grant select on app_private.reservations, app_private.reservation_placements,
  app_private.subscriptions, app_private.realtor_accounts, app_private.rent_entries,
  app_private.realtor_settlements to app_executor;
grant insert on app_private.realtor_settlements to app_executor;
grant update (version, updated_at) on app_private.realtor_accounts to app_executor;
alter table app_private.realtor_settlements add column request_hash varchar(64) not null default repeat('0',64);
alter table app_private.realtor_settlements add column balance_version integer not null default 1;
alter table app_private.realtor_settlements add constraint realtor_settlements_balance_version_positive check (balance_version>=1);
alter table app_private.realtor_settlements add constraint realtor_settlements_request_hash_sha256 check (request_hash ~ '^[0-9a-f]{64}$');

create policy realtor_settlement_command_insert on app_private.realtor_settlements
  for insert to app_executor with check (
    actor_id=(select app_private.current_actor_id())
    and app_private.can_write_reservation(property_id,owner_account_id)
  );
create function app_private.bump_realtor_balance_version()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.custodian='realtor' and new.realtor_contact_id is not null and (
    new.kind='rent_receipt'
    or (new.kind='rent_refund' and exists(select 1 from app_private.rent_entries src
      where src.id=new.original_entry_id and src.kind='rent_receipt'))
    or (new.kind='reversal' and exists(select 1 from app_private.rent_entries src
      left join app_private.rent_entries root on root.id=src.original_entry_id
      where src.id=new.original_entry_id and (src.kind='rent_receipt'
        or (src.kind='rent_refund' and root.kind='rent_receipt'))))
  ) then
    update app_private.realtor_accounts a set version=a.version+1,updated_at=statement_timestamp()
    where a.reservation_id=new.reservation_id and a.owner_account_id=new.owner_account_id
      and a.contact_id=new.realtor_contact_id;
  end if;
  return new;
end;
$$;
revoke all on function app_private.bump_realtor_balance_version() from public,anon,authenticated;
grant execute on function app_private.bump_realtor_balance_version() to app_executor;
grant usage,create on schema app_private to app_executor;
grant app_executor to current_user with set true, inherit false;
alter function app_private.bump_realtor_balance_version() owner to app_executor;
revoke app_executor from current_user;
revoke create on schema app_private from app_executor;
grant execute on function app_private.bump_realtor_balance_version() to current_user;
create trigger rent_entries_bump_realtor_balance_version
  after insert on app_private.rent_entries
  for each row execute function app_private.bump_realtor_balance_version();
revoke execute on function app_private.bump_realtor_balance_version() from current_user;

grant usage,create on schema api to app_executor;
create function api.get_realtor_balance(p_reservation_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_out jsonb;
begin
  if not api.is_my_session_active() then raise exception using errcode='28000',message='active_session_required'; end if;
  select jsonb_build_object(
    'version',a.version,'contact_id',a.contact_id,
    'collected_minor',b.collected,'transferred_minor',b.transferred,
    'commission_minor',a.earned_minor,'commission_paid_minor',b.paid,
    'owner_due_minor',greatest(0,(b.collected-b.outflow)-(a.earned_minor-b.paid)),
    'realtor_due_minor',greatest(0,(a.earned_minor-b.paid)-(b.collected-b.outflow))
  ) into v_out
  from app_private.reservations r
  join app_private.realtor_accounts a on a.reservation_id=r.id and a.owner_account_id=r.owner_account_id
  cross join lateral (
    select
      coalesce((select sum(case
        when e.kind='rent_receipt' then e.amount_minor
        when e.kind='rent_refund' and src.kind='rent_receipt' then -e.amount_minor
        when e.kind='reversal' and src.kind='rent_receipt' then -e.amount_minor
        when e.kind='reversal' and src.kind='rent_refund' and root.kind='rent_receipt' then e.amount_minor
        else 0 end)
        from app_private.rent_entries e left join app_private.rent_entries src on src.id=e.original_entry_id
        left join app_private.rent_entries root on root.id=src.original_entry_id
        where e.reservation_id=r.id and e.owner_account_id=r.owner_account_id
          and e.realtor_contact_id=a.contact_id and e.custodian='realtor'),0)::bigint collected,
      coalesce((select sum(s.amount_minor) from app_private.realtor_settlements s
        where s.realtor_account_id=a.id and s.reservation_id=r.id and s.owner_account_id=r.owner_account_id
          and s.kind='realtor_to_owner'),0)::bigint transferred,
      coalesce((select sum(s.amount_minor) from app_private.realtor_settlements s
        where s.realtor_account_id=a.id and s.reservation_id=r.id and s.owner_account_id=r.owner_account_id
          and s.kind in ('owner_to_realtor','commission_offset')),0)::bigint paid,
      coalesce((select sum(s.amount_minor) from app_private.realtor_settlements s
        where s.realtor_account_id=a.id and s.reservation_id=r.id and s.owner_account_id=r.owner_account_id
          and s.kind in ('realtor_to_owner','commission_offset')),0)::bigint outflow
  ) b
  where r.id=p_reservation_id and app_private.has_property_capability(r.property_id,r.owner_account_id,'finance.read');
  if v_out is null then raise exception using errcode='P0002',message='realtor_balance_not_found'; end if;
  -- Held rent is C-T-O. Expose no extra field beyond the OpenAPI contract.
  return v_out;
end;
$$;

create function api.record_realtor_settlement(p_reservation_id uuid,p_input jsonb,p_idempotency_key text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_actor uuid:=app_private.current_actor_id(); v_res app_private.reservations%rowtype;
  v_place app_private.reservation_placements%rowtype; v_account app_private.realtor_accounts%rowtype;
  v_kind app_private.settlement_kind; v_amount bigint; v_expected integer; v_contact uuid;
  v_occurred timestamptz; v_key text; v_hash text; v_old app_private.realtor_settlements%rowtype;
  v_event app_private.realtor_settlements%rowtype; v_collected bigint; v_transferred bigint;
  v_paid bigint; v_held bigint; v_unpaid bigint; v_now timestamptz:=statement_timestamp();
begin
  if not api.is_my_session_active() or v_actor is null then raise exception using errcode='28000',message='active_session_required'; end if;
  if p_reservation_id is null or p_input is null or jsonb_typeof(p_input) is distinct from 'object'
    or p_input-array['expected_version','contact_id','kind','amount_minor','occurred_at']<>'{}'::jsonb
    or jsonb_typeof(p_input->'expected_version') is distinct from 'number'
    or p_input->>'expected_version' !~ '^[1-9][0-9]*$'
    or jsonb_typeof(p_input->'contact_id') is distinct from 'string'
    or jsonb_typeof(p_input->'kind') is distinct from 'string'
    or p_input->>'kind' not in ('realtor_to_owner','owner_to_realtor','commission_offset')
    or jsonb_typeof(p_input->'amount_minor') is distinct from 'number'
    or p_input->>'amount_minor' !~ '^[1-9][0-9]*$'
    or (p_input ? 'occurred_at' and jsonb_typeof(p_input->'occurred_at') is distinct from 'string')
    or p_idempotency_key is null or length(p_idempotency_key) not between 8 and 128 then
    raise exception using errcode='22023',message='invalid_settlement_input'; end if;
  begin
    v_expected:=(p_input->>'expected_version')::integer; v_contact:=(p_input->>'contact_id')::uuid;
    v_amount:=(p_input->>'amount_minor')::bigint; v_kind:=(p_input->>'kind')::app_private.settlement_kind;
    v_occurred:=case when p_input ? 'occurred_at' then (p_input->>'occurred_at')::timestamptz else v_now end;
  exception when others then raise exception using errcode='22023',message='invalid_settlement_input'; end;
  if v_expected<1 or v_amount<1 or v_amount>9007199254740991 then
    raise exception using errcode='22023',message='invalid_settlement_amount_or_version'; end if;
  select * into v_res from app_private.reservations r where r.id=p_reservation_id
    and app_private.can_write_reservation(r.property_id,r.owner_account_id) for update;
  if not found then raise exception using errcode='P0002',message='reservation_not_found'; end if;
  if not app_private.is_owner(v_res.owner_account_id) and not exists(select 1 from app_private.property_memberships m
    where m.property_id=v_res.property_id and m.owner_account_id=v_res.owner_account_id and m.user_id=v_actor
      and m.permission='full' and m.revoked_at is null) then
    raise exception using errcode='42501',message='finance_manage_required'; end if;
  if not exists(select 1 from app_private.subscriptions s where s.property_id=v_res.property_id
    and s.owner_account_id=v_res.owner_account_id and s.state in ('trialing','active') and s.current_end>v_now) then
    raise exception using errcode='42501',message='active_entitlement_required'; end if;
  select * into v_place from app_private.reservation_placements p where p.id=v_res.current_placement_id
    and p.reservation_id=v_res.id and p.property_id=v_res.property_id and p.owner_account_id=v_res.owner_account_id;
  if not found then raise exception using errcode='P0002',message='current_placement_not_found'; end if;
  select * into v_account from app_private.realtor_accounts a where a.reservation_id=v_res.id
    and a.owner_account_id=v_res.owner_account_id and a.contact_id=v_contact for update;
  if not found then raise exception using errcode='P0002',message='realtor_account_not_found'; end if;

  v_key:=encode(extensions.digest(convert_to(v_actor::text||':'||p_reservation_id::text||':'||p_idempotency_key,'UTF8'),'sha256'),'hex');
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('expected_version',v_expected,'contact_id',v_contact,
    'kind',v_kind::text,'amount_minor',v_amount,'occurred_at',case when p_input ? 'occurred_at' then v_occurred else null end)::text,'UTF8'),'sha256'),'hex');
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_key,0));
  select * into v_old from app_private.realtor_settlements s where s.owner_account_id=v_res.owner_account_id and s.operation_key=v_key;
  if found then
    if v_old.request_hash<>v_hash then raise exception using errcode='23505',message='idempotency_key_payload_conflict'; end if;
    if not app_private.has_property_capability(v_old.property_id,v_old.owner_account_id,'finance.read') then
      raise exception using errcode='42501',message='settlement_read_scope_required'; end if;
    return jsonb_build_object('id',v_old.id,'reservation_id',v_old.reservation_id,'contact_id',v_contact,
      'kind',v_old.kind::text,'amount_minor',v_old.amount_minor,'occurred_at',v_old.occurred_at,
      'balance_version',v_old.balance_version,'created_at',v_old.created_at);
  end if;
  if v_account.version<>v_expected then raise exception using errcode='40001',message='stale_realtor_balance'; end if;
  select coalesce(sum(case
    when e.kind='rent_receipt' then e.amount_minor
    when e.kind='rent_refund' and src.kind='rent_receipt' then -e.amount_minor
    when e.kind='reversal' and src.kind='rent_receipt' then -e.amount_minor
    when e.kind='reversal' and src.kind='rent_refund' and root.kind='rent_receipt' then e.amount_minor else 0 end),0)::bigint into v_collected
  from app_private.rent_entries e left join app_private.rent_entries src on src.id=e.original_entry_id
    left join app_private.rent_entries root on root.id=src.original_entry_id
  where e.reservation_id=v_res.id and e.owner_account_id=v_res.owner_account_id
    and e.custodian='realtor' and e.realtor_contact_id=v_contact;
  select coalesce(sum(s.amount_minor) filter(where s.kind='realtor_to_owner'),0),
    coalesce(sum(s.amount_minor) filter(where s.kind in ('owner_to_realtor','commission_offset')),0),
    coalesce(sum(s.amount_minor) filter(where s.kind in ('realtor_to_owner','commission_offset')),0)
    into v_transferred,v_paid,v_held from app_private.realtor_settlements s
    where s.realtor_account_id=v_account.id and s.reservation_id=v_res.id and s.owner_account_id=v_res.owner_account_id;
  v_held:=v_collected-v_held; v_unpaid:=v_account.earned_minor-v_paid;
  if v_held<0 or v_unpaid<0 then raise exception using errcode='22023',message='settlement_balance_invariant'; end if;
  if (v_kind='realtor_to_owner' and v_amount>v_held)
    or (v_kind='owner_to_realtor' and v_amount>v_unpaid)
    or (v_kind='commission_offset' and v_amount>least(v_held,v_unpaid)) then
    raise exception using errcode='22023',message='settlement_amount_exceeds_due'; end if;
  insert into app_private.realtor_settlements(owner_account_id,property_id,realtor_account_id,kind,amount_minor,
    occurred_at,actor_id,reservation_id,placement_id,operation_key,request_hash,balance_version)
  values(v_res.owner_account_id,v_res.property_id,v_account.id,v_kind,v_amount,v_occurred,v_actor,
    v_res.id,v_place.id,v_key,v_hash,v_account.version+1) returning * into v_event;
  update app_private.realtor_accounts set version=version+1,updated_at=v_now
    where id=v_account.id returning * into v_account;
  return jsonb_build_object('id',v_event.id,'reservation_id',v_res.id,'contact_id',v_account.contact_id,
    'kind',v_kind::text,'amount_minor',v_amount,'occurred_at',v_event.occurred_at,
    'balance_version',v_account.version,'created_at',v_event.created_at);
end;
$$;
revoke all on function api.get_realtor_balance(uuid),api.record_realtor_settlement(uuid,jsonb,text) from public,anon,authenticated;
grant execute on function api.get_realtor_balance(uuid),api.record_realtor_settlement(uuid,jsonb,text) to authenticated;
grant app_executor to current_user with set true, inherit false;
alter function api.get_realtor_balance(uuid) owner to app_executor;
alter function api.record_realtor_settlement(uuid,jsonb,text) owner to app_executor;
revoke app_executor from current_user;
revoke create on schema api from app_executor;
