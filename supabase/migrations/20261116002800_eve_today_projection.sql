-- EVE-013.1: authenticated, property-scoped read model for the Today screen.
-- The projection is read-only and returns only the public TodayCard fields.

grant select on app_private.tasks, app_private.subscriptions to app_executor;

create policy tasks_today_projection_read on app_private.tasks
  for select to app_executor using (
    app_private.has_property_capability(property_id,owner_account_id,'property.read')
  );

create policy subscriptions_today_projection_read on app_private.subscriptions
  for select to app_executor using (
    app_private.has_property_capability(property_id,owner_account_id,'property.read')
  );

grant create on schema api to app_executor;

create function api.get_today(p_local_date date default null, p_owner_account_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := app_private.current_actor_id();
  v_date date := coalesce(p_local_date, (statement_timestamp() at time zone 'Asia/Baku')::date);
  v_cards jsonb;
begin
  if v_actor is null or not api.is_my_session_active() then
    raise exception using errcode='28000',message='active_session_required';
  end if;
  if p_owner_account_id is not null and not exists (
    select 1 from app_private.properties p
    where p.owner_account_id=p_owner_account_id and p.archived_at is null
      and app_private.has_property_capability(p.id,p.owner_account_id,'property.read')
  ) then
    raise exception using errcode='P0002',message='today_scope_not_found';
  end if;

  with accessible_properties as (
    select p.id,p.owner_account_id,p.name
    from app_private.properties p
    where p.archived_at is null
      and (p_owner_account_id is null or p.owner_account_id=p_owner_account_id)
      and app_private.has_property_capability(p.id,p.owner_account_id,'property.read')
  ), reservation_cards as (
    select
      gen_random_uuid() as id,
      'arrival'::text as kind,p.id as property_id,p.name::text as property_label,
      left('Giriş · '||r.guest_name,160)::text as title,
      ((r.check_in + r.check_in_time) at time zone 'Asia/Baku') as due_at,
      null::bigint as amount_minor,'check_in'::text as action,r.id as target_id,
      20 as priority
    from accessible_properties p
    join app_private.reservations r on r.property_id=p.id and r.owner_account_id=p.owner_account_id
    join app_private.reservation_placements rp on rp.id=r.current_placement_id
      and rp.reservation_id=r.id and rp.property_id=r.property_id and rp.owner_account_id=r.owner_account_id
      and rp.effective_to is null
    where r.state='confirmed' and r.check_in=v_date
    union all
    select
      gen_random_uuid(),
      'departure',p.id,p.name::text,left('Çıxış · '||r.guest_name,160)::text,
      ((r.check_out + r.check_out_time) at time zone 'Asia/Baku'),
      null::bigint,'check_out',r.id,20
    from accessible_properties p
    join app_private.reservations r on r.property_id=p.id and r.owner_account_id=p.owner_account_id
    join app_private.reservation_placements rp on rp.id=r.current_placement_id
      and rp.reservation_id=r.id and rp.property_id=r.property_id and rp.owner_account_id=r.owner_account_id
      and rp.effective_to is null
    where r.state in ('confirmed','checked_in') and r.check_out=v_date
  ), task_cards as (
    select gen_random_uuid() as id,
      'task'::text as kind,p.id as property_id,p.name::text as property_label,
      left(t.title,160)::text as title,t.due_at,null::bigint as amount_minor,
      case when t.state='reported_done' then 'confirm_task' else 'open_task' end::text as action,
      t.id as target_id,
      case when (t.due_at at time zone 'Asia/Baku')::date<v_date then 10 else 30 end as priority
    from accessible_properties p
    join app_private.tasks t on t.property_id=p.id and t.owner_account_id=p.owner_account_id
    where t.state in ('open','accepted','reported_done')
      and (t.due_at at time zone 'Asia/Baku')::date<=v_date
      and (t.reservation_id is null or exists (
        select 1 from app_private.reservations r
        where r.id=t.reservation_id and r.owner_account_id=t.owner_account_id
          and r.property_id=t.property_id and r.current_placement_id=t.placement_id
      ))
  ), rent_cards as (
    select gen_random_uuid() as id,
      'rent_due'::text as kind,p.id as property_id,p.name::text as property_label,
      'Kirayə qalığı'::text as title,
      ((r.check_in + r.check_in_time) at time zone 'Asia/Baku') as due_at,
      balance.remaining_minor::bigint as amount_minor,'open_money'::text as action,
      r.id as target_id,40 as priority
    from accessible_properties p
    join app_private.reservations r on r.property_id=p.id and r.owner_account_id=p.owner_account_id
    join app_private.reservation_placements rp on rp.id=r.current_placement_id
      and rp.reservation_id=r.id and rp.property_id=r.property_id and rp.owner_account_id=r.owner_account_id
      and rp.effective_to is null
    cross join lateral (
      select greatest(0::numeric,
        r.total_minor::numeric
        - coalesce(sum(case when e.kind in ('rent_receipt','deposit_to_rent') then e.amount_minor else 0 end),0)
        + coalesce(sum(case when e.kind='rent_refund' then e.amount_minor else 0 end),0)
        - coalesce(sum(case when e.kind='reversal' and original.kind in ('rent_receipt','deposit_to_rent') then e.amount_minor else 0 end),0)
        + coalesce(sum(case when e.kind='reversal' and original.kind='rent_refund' then e.amount_minor else 0 end),0)
      ) as remaining_minor
      from app_private.rent_entries e
      left join app_private.rent_entries original
        on original.id=e.original_entry_id and original.owner_account_id=e.owner_account_id
      where e.reservation_id=r.id and e.owner_account_id=r.owner_account_id
    ) balance
    where r.state='confirmed' and r.check_in=v_date and balance.remaining_minor>0
  ), subscription_cards as (
    select gen_random_uuid() as id,
      'subscription'::text as kind,p.id as property_id,p.name::text as property_label,
      'Abunə bu gün bitir'::text as title,s.current_end as due_at,null::bigint as amount_minor,
      'renew'::text as action,s.id as target_id,50 as priority
    from accessible_properties p
    join app_private.subscriptions s on s.property_id=p.id and s.owner_account_id=p.owner_account_id
    where s.state in ('trialing','active')
      and (s.current_end at time zone 'Asia/Baku')::date=v_date
  ), combined as (
    select * from reservation_cards
    union all select * from task_cards
    union all select * from rent_cards
    union all select * from subscription_cards
  )
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'id',id,'kind',kind,'property_id',property_id,'property_label',property_label,
      'title',title,'due_at',due_at,'amount_minor',amount_minor,'action',action,'target_id',target_id
    )) order by priority, due_at nulls last, target_id), '[]'::jsonb)
  into v_cards
  from (select * from combined order by priority,due_at nulls last,target_id limit 1000) c;

  return jsonb_build_object('local_date',v_date,'timezone','Asia/Baku','cards',v_cards);
end;
$$;

revoke all on function api.get_today(date,uuid) from public,anon,authenticated;
grant execute on function api.get_today(date,uuid) to authenticated;
grant app_executor to current_user with set true, inherit false;
alter function api.get_today(date,uuid) owner to app_executor;
revoke app_executor from current_user;
revoke create on schema api from app_executor;
