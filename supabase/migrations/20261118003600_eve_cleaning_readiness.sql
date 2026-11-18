-- EVE-018.1: a required task and its linked inspection drive property readiness.
-- This trigger runs in the reservation checkout/move or task transition transaction.
create function app_private.recompute_property_readiness(
  p_property_id uuid, p_owner_account_id uuid
) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_previous app_private.readiness;
  v_pending boolean;
  v_next app_private.readiness;
begin
  -- Reservation move/checkout may hold the property before a task. If this
  -- transaction holds a task first, fail promptly and retry the full command.
  begin
    select p.readiness into v_previous
      from app_private.properties p
      where p.id=p_property_id and p.owner_account_id=p_owner_account_id
      for update nowait;
  exception when lock_not_available then
    raise exception using errcode='40001',message='readiness_retry_required';
  end;
  if not found then
    raise exception using errcode='23503', message='readiness_property_not_found';
  end if;

  select exists (
    select 1 from app_private.tasks t
    where t.property_id=p_property_id and t.owner_account_id=p_owner_account_id
      and t.required_for_readiness and t.state<>'cancelled'
      and (t.state<>'completed' or t.inspection_event_id is null or not exists (
        select 1 from app_private.inspection_submissions s
        where s.event_id=t.inspection_event_id and s.property_id=t.property_id
          and s.owner_account_id=t.owner_account_id and s.state='completed'
          and s.completed_at is not null
          and not exists (
            select 1 from app_private.inspection_snapshot_rooms sr
            where sr.snapshot_id=s.snapshot_id and sr.property_id=s.property_id
              and sr.owner_account_id=s.owner_account_id and not exists (
                select 1 from app_private.inspection_room_answers ra
                where ra.submission_id=s.id and ra.snapshot_room_id=sr.id
                  and ra.property_id=s.property_id and ra.owner_account_id=s.owner_account_id
              )
          )
      ))
  ) into v_pending;

  -- An explicit attention state is never silently cleared by cleaning completion.
  v_next := case
    when v_previous='attention_required' then 'attention_required'::app_private.readiness
    when v_pending then 'cleaning_pending'::app_private.readiness
    else 'ready'::app_private.readiness
  end;
  if v_next is distinct from v_previous then
    update app_private.properties p
      set readiness=v_next, version=p.version+1, updated_at=clock_timestamp()
      where p.id=p_property_id and p.owner_account_id=p_owner_account_id;
  end if;
end;
$$;
revoke all on function app_private.recompute_property_readiness(uuid,uuid)
  from public, anon, authenticated, service_role, app_executor;

create function app_private.task_readiness_changed()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op='DELETE' then
    if old.required_for_readiness then
      perform app_private.recompute_property_readiness(old.property_id,old.owner_account_id);
    end if;
    return old;
  end if;
  if tg_op='UPDATE' and old.required_for_readiness
     and (old.property_id,old.owner_account_id) is distinct from
         (new.property_id,new.owner_account_id) then
    perform app_private.recompute_property_readiness(old.property_id,old.owner_account_id);
  end if;
  if new.required_for_readiness and (tg_op='INSERT' or
      (old.property_id,old.owner_account_id,old.state,old.required_for_readiness,old.inspection_event_id)
      is distinct from
      (new.property_id,new.owner_account_id,new.state,new.required_for_readiness,new.inspection_event_id)) then
    perform app_private.recompute_property_readiness(new.property_id,new.owner_account_id);
  elsif tg_op='UPDATE' and old.required_for_readiness and not new.required_for_readiness then
    perform app_private.recompute_property_readiness(new.property_id,new.owner_account_id);
  end if;
  return new;
end;
$$;
revoke all on function app_private.task_readiness_changed()
  from public, anon, authenticated, service_role, app_executor;

create trigger task_readiness_after_write
after insert or update or delete on app_private.tasks
for each row execute function app_private.task_readiness_changed();

-- A completed task can still wait for its linked inspection submission or a
-- late room answer. These writes must update readiness in the same transaction.
create function app_private.inspection_readiness_changed()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_event_ids uuid[] := array[]::uuid[];
  v_event_id uuid;
  v_property record;
begin
  if tg_table_name='inspection_submissions' then
    if tg_op in ('DELETE','UPDATE') then
      v_event_ids := array_append(v_event_ids,old.event_id);
    end if;
    if tg_op in ('INSERT','UPDATE') then
      v_event_ids := array_append(v_event_ids,new.event_id);
    end if;
  else
    if tg_op in ('DELETE','UPDATE') then
      select s.event_id into v_event_id from app_private.inspection_submissions s
        where s.id=old.submission_id;
      if v_event_id is not null then v_event_ids := array_append(v_event_ids,v_event_id); end if;
    end if;
    if tg_op in ('INSERT','UPDATE') then
      select s.event_id into v_event_id from app_private.inspection_submissions s
        where s.id=new.submission_id;
      if v_event_id is not null then v_event_ids := array_append(v_event_ids,v_event_id); end if;
    end if;
  end if;
  for v_property in
    select distinct t.property_id,t.owner_account_id
    from app_private.tasks t
    where t.required_for_readiness and t.inspection_event_id=any(v_event_ids)
    order by t.property_id,t.owner_account_id
  loop
    perform app_private.recompute_property_readiness(
      v_property.property_id,v_property.owner_account_id);
  end loop;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function app_private.inspection_readiness_changed()
  from public,anon,authenticated,service_role,app_executor;

create trigger inspection_submission_readiness_after_write
after insert or update or delete on app_private.inspection_submissions
for each row execute function app_private.inspection_readiness_changed();
create trigger inspection_room_answer_readiness_after_write
after insert or update or delete on app_private.inspection_room_answers
for each row execute function app_private.inspection_readiness_changed();

-- Checkout may reuse a same-placement cleaning task created before this
-- migration, including one already completed. Attach the checkout inspection
-- and require readiness without changing identity, state, instructions,
-- assignee or immutable transition history.
create function app_private.checkout_cleaning_required()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_event_id uuid;
begin
  if old.state is distinct from new.state and new.state='completed'
     and new.actual_check_out_at is not null then
    select e.id into v_event_id
      from app_private.inspection_events e
      where e.owner_account_id=new.owner_account_id and e.property_id=new.property_id
        and e.reservation_id=new.id and e.placement_id=new.current_placement_id
        and e.event_kind='check_out'
        and e.handover_key='reservation:'||new.id::text||':checkout:'||new.current_placement_id::text;
    if v_event_id is null then
      raise exception using errcode='23514',message='checkout_inspection_event_missing';
    end if;
    update app_private.tasks t
      set required_for_readiness=true,inspection_event_id=v_event_id,
          version=t.version+1,updated_at=clock_timestamp()
      where t.reservation_id=new.id and t.placement_id=new.current_placement_id
        and t.property_id=new.property_id and t.owner_account_id=new.owner_account_id
        and t.kind='cleaning' and t.state<>'cancelled'
        and (not t.required_for_readiness or t.inspection_event_id is distinct from v_event_id);
  end if;
  return new;
end;
$$;
revoke all on function app_private.checkout_cleaning_required()
  from public, anon, authenticated, service_role, app_executor;
create trigger reservation_checkout_cleaning_required
after update of state on app_private.reservations
for each row execute function app_private.checkout_cleaning_required();

-- Existing required tasks need a one-time projection when this forward migration lands.
do $$
declare v_property record;
begin
  for v_property in
    select distinct property_id,owner_account_id from app_private.tasks
      where required_for_readiness
    order by property_id,owner_account_id
  loop
    perform app_private.recompute_property_readiness(
      v_property.property_id,v_property.owner_account_id);
  end loop;
end;
$$;
