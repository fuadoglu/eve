-- EVE-014.1: append-only reservation rent/deposit ledger commands and DTO read.
-- All writes lock the reservation; source limits are read under that reservation lock.
grant select on app_private.contacts, app_private.contact_properties to app_executor;
grant insert on app_private.rent_entries to app_executor;

create or replace function api.create_rent_entry(
  p_reservation_id uuid, p_input jsonb, p_idempotency_key text
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_actor uuid := app_private.current_actor_id();
  v_reservation app_private.reservations%rowtype;
  v_placement app_private.reservation_placements%rowtype;
  v_source app_private.rent_entries%rowtype;
  v_existing app_private.rent_entries%rowtype;
  v_kind app_private.rent_kind;
  v_custodian app_private.custodian;
  v_amount bigint;
  v_contact_id uuid;
  v_original_id uuid;
  v_occurred_at timestamptz;
  v_note varchar(1000);
  v_operation_key text;
  v_used numeric;
  v_is_full boolean;
  v_now timestamptz := statement_timestamp();
  v_entry app_private.rent_entries%rowtype;
begin
  if not api.is_my_session_active() then raise exception using errcode='28000',message='active_session_required'; end if;
  if v_actor is null then raise exception using errcode='28000',message='authentication_required'; end if;
  if p_reservation_id is null or p_input is null or jsonb_typeof(p_input) is distinct from 'object'
    or p_input - array['kind','amount_minor','custodian','contact_id','original_id','occurred_at','note'] <> '{}'::jsonb
    or jsonb_typeof(p_input->'kind') is distinct from 'string'
    or p_input->>'kind' not in ('rent_receipt','rent_refund','deposit_receipt','deposit_return','deposit_to_rent','deposit_to_damage','reversal')
    or jsonb_typeof(p_input->'amount_minor') is distinct from 'number'
    or (p_input->>'amount_minor') !~ '^[1-9][0-9]*$' or (p_input->>'amount_minor')::numeric>9007199254740991
    or jsonb_typeof(p_input->'custodian') is distinct from 'string'
    or p_input->>'custodian' not in ('owner','manager','realtor')
    or (p_input ? 'contact_id' and (jsonb_typeof(p_input->'contact_id') is distinct from 'string' or (p_input->>'contact_id') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'))
    or (p_input ? 'original_id' and (jsonb_typeof(p_input->'original_id') is distinct from 'string' or (p_input->>'original_id') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'))
    or (p_input ? 'occurred_at' and (jsonb_typeof(p_input->'occurred_at') is distinct from 'string'
      or length(p_input->>'occurred_at')>40 or (p_input->>'occurred_at') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$'))
    or (p_input ? 'note' and (jsonb_typeof(p_input->'note') is distinct from 'string' or length(p_input->>'note')>1000))
    or p_idempotency_key is null or p_idempotency_key !~ '^[A-Za-z0-9_-]{16,128}$' then
    raise exception using errcode='22023',message='invalid_rent_entry_input';
  end if;
  v_kind := (p_input->>'kind')::app_private.rent_kind;
  v_custodian := (p_input->>'custodian')::app_private.custodian;
  v_amount := (p_input->>'amount_minor')::bigint;
  v_contact_id := case when p_input ? 'contact_id' then (p_input->>'contact_id')::uuid else null end;
  v_original_id := case when p_input ? 'original_id' then (p_input->>'original_id')::uuid else null end;
  begin
    v_occurred_at := case when p_input ? 'occurred_at' then (p_input->>'occurred_at')::timestamptz else v_now end;
  exception when others then raise exception using errcode='22023',message='invalid_rent_entry_occurred_at';
  end;
  v_note := nullif(btrim(p_input->>'note'),'');
  if v_kind in ('rent_refund','deposit_return','deposit_to_rent','deposit_to_damage','reversal') and v_original_id is null then
    raise exception using errcode='22023',message='rent_entry_original_required'; end if;
  if v_custodian='realtor' and v_contact_id is null then raise exception using errcode='22023',message='realtor_contact_required'; end if;
  if v_custodian<>'realtor' and v_contact_id is not null then raise exception using errcode='22023',message='contact_only_for_realtor'; end if;
  if v_kind in ('deposit_to_rent','deposit_to_damage','reversal') and (v_note is null or length(v_note)=0) then
    raise exception using errcode='22023',message='rent_entry_reason_required'; end if;

  select * into v_reservation from app_private.reservations r where r.id=p_reservation_id
    and app_private.can_write_reservation(r.property_id,r.owner_account_id) for update;
  if not found then raise exception using errcode='P0002',message='reservation_not_found'; end if;
  if not exists(select 1 from app_private.subscriptions s where s.property_id=v_reservation.property_id
    and s.owner_account_id=v_reservation.owner_account_id and s.state in ('trialing','active') and s.current_end>v_now) then
    raise exception using errcode='42501',message='active_entitlement_required'; end if;
  select * into v_placement from app_private.reservation_placements p where p.id=v_reservation.current_placement_id
    and p.reservation_id=v_reservation.id and p.owner_account_id=v_reservation.owner_account_id
    and p.property_id=v_reservation.property_id;
  if not found then raise exception using errcode='P0002',message='reservation_placement_not_found'; end if;

  if v_custodian='owner' and not app_private.is_owner(v_reservation.owner_account_id) then
    raise exception using errcode='42501',message='owner_custodian_required'; end if;
  if v_custodian='manager' and not exists(select 1 from app_private.property_memberships m
    where m.property_id=v_reservation.property_id and m.owner_account_id=v_reservation.owner_account_id
      and m.user_id=v_actor and m.revoked_at is null) then
    raise exception using errcode='42501',message='manager_custodian_required'; end if;
  if v_custodian='realtor' and v_original_id is null and not exists(select 1 from app_private.contacts c
    join app_private.contact_properties cp on cp.contact_id=c.id and cp.owner_account_id=c.owner_account_id
    where c.id=v_contact_id and c.owner_account_id=v_reservation.owner_account_id and c.archived_at is null
      and cp.property_id=v_reservation.property_id) then
    raise exception using errcode='22023',message='realtor_contact_not_assigned'; end if;

  v_operation_key := encode(extensions.digest(convert_to(v_actor::text||':'||p_reservation_id::text||':'||p_idempotency_key,'UTF8'),'sha256'),'hex');
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_operation_key,0));
  select * into v_existing from app_private.rent_entries e where e.owner_account_id=v_reservation.owner_account_id
    and e.operation_key=v_operation_key;
  if found then
    if v_existing.reservation_id<>p_reservation_id or v_existing.kind<>v_kind or v_existing.amount_minor<>v_amount
      or v_existing.custodian<>v_custodian or v_existing.realtor_contact_id is distinct from v_contact_id
      or v_existing.original_entry_id is distinct from v_original_id
      or (case when p_input ? 'occurred_at' then v_existing.occurred_at is distinct from v_occurred_at
          else v_existing.occurred_at is distinct from v_existing.created_at end)
      or v_existing.note is distinct from v_note then
      raise exception using errcode='23505',message='idempotency_key_payload_conflict'; end if;
    if not (app_private.has_property_capability(v_existing.property_id,v_existing.owner_account_id,'finance.read')
      or (app_private.has_property_capability(v_existing.property_id,v_existing.owner_account_id,'reservation.read')
        and exists(select 1 from app_private.reservations r where r.id=v_existing.reservation_id
          and r.owner_account_id=v_existing.owner_account_id and r.property_id=v_existing.property_id
          and r.current_placement_id=v_existing.placement_id))) then
      raise exception using errcode='42501',message='rent_entry_read_scope_required';
    end if;
    v_entry := v_existing;
  else
    if v_original_id is not null then
      -- The reservation row lock above serializes all ledger writers, including AT10.
      -- Ledger rows remain append-only, so do not request UPDATE privilege to lock a source row.
      select * into v_source from app_private.rent_entries e where e.id=v_original_id
        and e.reservation_id=v_reservation.id and e.owner_account_id=v_reservation.owner_account_id;
      if not found then raise exception using errcode='22023',message='rent_entry_source_not_found'; end if;
      if v_kind='rent_refund' and v_source.kind not in ('rent_receipt','deposit_to_rent') then
        raise exception using errcode='22023',message='rent_refund_source_invalid'; end if;
      if v_kind='deposit_return' and v_source.kind<>'deposit_receipt' then
        raise exception using errcode='22023',message='deposit_return_source_invalid'; end if;
      if v_kind in ('deposit_to_rent','deposit_to_damage') and v_source.kind<>'deposit_receipt' then
        raise exception using errcode='22023',message='deposit_allocation_source_invalid'; end if;
      if v_kind='reversal' and v_source.kind='reversal' then raise exception using errcode='22023',message='reversal_source_invalid'; end if;
      if v_kind in ('rent_refund','deposit_return','deposit_to_rent','deposit_to_damage') and v_custodian<>v_source.custodian then
        raise exception using errcode='22023',message='source_custodian_mismatch'; end if;
      if v_kind='reversal' and v_custodian<>v_source.custodian then raise exception using errcode='22023',message='source_custodian_mismatch'; end if;
      if v_kind in ('deposit_to_rent','deposit_to_damage','reversal') then
        select app_private.is_owner(v_source.owner_account_id) or exists(select 1 from app_private.property_memberships m
          where m.property_id=v_source.property_id and m.owner_account_id=v_source.owner_account_id
            and m.user_id=v_actor and m.permission='full' and m.revoked_at is null) into v_is_full;
        if not v_is_full then raise exception using errcode='42501',message='finance_manage_required'; end if;
      end if;
      if v_kind='reversal' then
        if v_source.kind in ('rent_receipt','deposit_to_rent') then
          select coalesce(sum(e.amount_minor) filter (where e.kind='rent_refund'),0)
            + coalesce(sum(e.amount_minor) filter (where e.kind='reversal'),0)
            - coalesce((select sum(rv.amount_minor) from app_private.rent_entries rf
              join app_private.rent_entries rv on rv.original_entry_id=rf.id and rv.kind='reversal'
              where rf.original_entry_id=v_source.id and rf.kind='rent_refund'),0)
            into v_used from app_private.rent_entries e where e.original_entry_id=v_source.id;
        elsif v_source.kind='deposit_receipt' then
          select coalesce(sum(e.amount_minor) filter (where e.kind in ('deposit_return','deposit_to_rent','deposit_to_damage')),0)
            + coalesce(sum(e.amount_minor) filter (where e.kind='reversal'),0)
            - coalesce((select sum(rv.amount_minor) from app_private.rent_entries adj
              join app_private.rent_entries rv on rv.original_entry_id=adj.id and rv.kind='reversal'
              where adj.original_entry_id=v_source.id and adj.kind in ('deposit_return','deposit_to_rent','deposit_to_damage')),0)
            into v_used from app_private.rent_entries e where e.original_entry_id=v_source.id;
        else
          select coalesce(sum(e.amount_minor),0) into v_used from app_private.rent_entries e
            where e.original_entry_id=v_source.id and e.kind='reversal' and e.owner_account_id=v_source.owner_account_id;
        end if;
      elsif v_kind='rent_refund' then
        select coalesce(sum(e.amount_minor),0)
          - coalesce((select sum(rv.amount_minor) from app_private.rent_entries rf
            join app_private.rent_entries rv on rv.original_entry_id=rf.id and rv.kind='reversal'
            where rf.original_entry_id=v_source.id and rf.kind='rent_refund'),0)
          + coalesce((select sum(rv.amount_minor) from app_private.rent_entries rv
            where rv.original_entry_id=v_source.id and rv.kind='reversal'),0)
          into v_used from app_private.rent_entries e
          where e.original_entry_id=v_source.id and e.kind='rent_refund';
      else
        select coalesce(sum(e.amount_minor),0)
          - coalesce((select sum(rv.amount_minor) from app_private.rent_entries adj
            join app_private.rent_entries rv on rv.original_entry_id=adj.id and rv.kind='reversal'
            where adj.original_entry_id=v_source.id and adj.kind in ('deposit_return','deposit_to_rent','deposit_to_damage')),0)
          + coalesce((select sum(rv.amount_minor) from app_private.rent_entries rv
            where rv.original_entry_id=v_source.id and rv.kind='reversal'),0)
          into v_used from app_private.rent_entries e
          where e.original_entry_id=v_source.id and e.kind in ('deposit_return','deposit_to_rent','deposit_to_damage');
      end if;
      if v_used+v_amount>v_source.amount_minor then
        raise exception using errcode='22023',message='rent_entry_source_balance_exceeded';
      end if;
      if v_source.custodian='realtor' and v_contact_id is distinct from v_source.realtor_contact_id then
        raise exception using errcode='22023',message='source_realtor_mismatch'; end if;
      if v_source.custodian<>'realtor' and v_contact_id is not null then
        raise exception using errcode='22023',message='source_realtor_mismatch'; end if;
    end if;
    insert into app_private.rent_entries(owner_account_id,property_id,reservation_id,placement_id,kind,amount_minor,
      custodian,custodian_user_id,realtor_contact_id,original_entry_id,actor_id,occurred_at,note,created_at,operation_key)
    values(v_reservation.owner_account_id,
      case when v_source.id is not null then v_source.property_id else v_placement.property_id end,
      v_reservation.id,
      case when v_source.id is not null then v_source.placement_id else v_placement.id end,
      v_kind,v_amount,v_custodian,
      case when v_custodian='realtor' then null when v_custodian='owner'
        then (select a.owner_user_id from app_private.owner_accounts a where a.id=v_reservation.owner_account_id)
        else v_actor end,
      v_contact_id,v_original_id,v_actor,v_occurred_at,v_note,v_now,v_operation_key)
    returning * into v_entry;
  end if;
  return jsonb_build_object('id',v_entry.id,'reservation_id',v_entry.reservation_id,
    'placement_id',v_entry.placement_id,'property_id',v_entry.property_id,'kind',v_entry.kind::text,
    'amount_minor',v_entry.amount_minor,'currency','AZN','custodian',v_entry.custodian::text,
    'contact_id',v_entry.realtor_contact_id,'original_id',v_entry.original_entry_id,
    'occurred_at',v_entry.occurred_at,'note',v_entry.note,'version',1,
    'created_at',v_entry.created_at,'updated_at',v_entry.created_at);
end;
$$;
revoke all on function api.create_rent_entry(uuid,jsonb,text) from public,anon,authenticated;
grant execute on function api.create_rent_entry(uuid,jsonb,text) to authenticated;
grant create on schema api to app_executor;
grant app_executor to current_user with set true, inherit false;
alter function api.create_rent_entry(uuid,jsonb,text) owner to app_executor;
revoke app_executor from current_user;
revoke create on schema api from app_executor;

create function api.list_reservation_rent_entries(
  p_reservation_id uuid, p_after_at timestamptz default null, p_after_id uuid default null, p_page_size integer default 30
)
returns table (
  id uuid,reservation_id uuid,placement_id uuid,property_id uuid,kind text,amount_minor bigint,currency text,
  custodian text,contact_id uuid,original_id uuid,occurred_at timestamptz,note text,version integer,created_at timestamptz,updated_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select e.id,e.reservation_id,e.placement_id,e.property_id,e.kind::text,e.amount_minor,'AZN',e.custodian::text,
    e.realtor_contact_id,e.original_entry_id,e.occurred_at,e.note,1,e.created_at,e.created_at
  from app_private.rent_entries e
  where p_reservation_id is not null and (p_after_at is null)=(p_after_id is null)
    and p_page_size between 1 and 101 and api.is_my_session_active() and e.reservation_id=p_reservation_id
    and (p_after_at is null or (e.occurred_at,e.id)>(p_after_at,p_after_id))
    and (app_private.has_property_capability(e.property_id,e.owner_account_id,'finance.read') or
      (app_private.has_property_capability(e.property_id,e.owner_account_id,'reservation.read') and exists(
        select 1 from app_private.reservations r where r.id=e.reservation_id and r.owner_account_id=e.owner_account_id
          and r.property_id=e.property_id and r.current_placement_id=e.placement_id)))
  order by e.occurred_at,e.id limit case when p_page_size between 1 and 101 then p_page_size else 0 end;
$$;
revoke all on function api.list_reservation_rent_entries(uuid,timestamptz,uuid,integer) from public,anon,authenticated;
grant execute on function api.list_reservation_rent_entries(uuid,timestamptz,uuid,integer) to authenticated;
grant create on schema api to app_executor;
grant app_executor to current_user with set true, inherit false;
alter function api.list_reservation_rent_entries(uuid,timestamptz,uuid,integer) owner to app_executor;
revoke app_executor from current_user;
revoke create on schema api from app_executor;
