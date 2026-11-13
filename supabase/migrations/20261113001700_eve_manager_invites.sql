-- EVE-008.2: issue and accept property-scoped manager invitations.
-- This RPC accepts only a pre-hashed bearer token; raw tokens never enter PostgreSQL.

alter table app_private.manager_invites drop constraint invite_expiry;
alter table app_private.manager_invites add constraint invite_expiry
  check (expires_at > created_at and expires_at <= created_at + interval '24 hours');
alter table app_private.manager_invites add constraint manager_invites_token_hash_sha256
  check (token_hash ~ '^[0-9a-f]{64}$');
alter table app_private.manager_invites add constraint manager_invites_normalized_email
  check (normalized_email=lower(btrim(normalized_email))
    and normalized_email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$');
alter table app_private.manager_invites add column invited_by_user_id uuid;
update app_private.manager_invites i set invited_by_user_id=a.owner_user_id
from app_private.owner_accounts a where a.id=i.owner_account_id;
alter table app_private.manager_invites alter column invited_by_user_id set not null;
alter table app_private.manager_invites add constraint manager_invites_invited_by_user_fk
  foreign key (invited_by_user_id) references auth.users(id) on delete restrict;
create index manager_invites_owner_email_pending_idx
  on app_private.manager_invites(owner_account_id,normalized_email)
  where state='pending';

create function app_private.current_actor_email()
returns text
language sql stable security invoker set search_path = ''
as $$
  select lower(btrim(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email'));
$$;
revoke all on function app_private.current_actor_email() from public, anon, authenticated;
grant execute on function app_private.current_actor_email() to app_executor;

grant select, insert, update on app_private.manager_invites to app_executor;
grant select, insert on app_private.invite_properties to app_executor;
grant select, insert, update on app_private.property_memberships to app_executor;
grant select on app_private.subscriptions to app_executor;

create policy subscriptions_owner_invite_read on app_private.subscriptions
  for select to app_executor using (app_private.is_owner(owner_account_id));
create policy manager_invites_owner_read on app_private.manager_invites
  for select to app_executor using (app_private.is_owner(owner_account_id));
create policy manager_invites_owner_create on app_private.manager_invites
  for insert to app_executor with check (app_private.is_owner(owner_account_id));
create policy manager_invites_owner_update on app_private.manager_invites
  for update to app_executor using (app_private.is_owner(owner_account_id))
  with check (app_private.is_owner(owner_account_id));
create policy manager_invites_matching_email_read on app_private.manager_invites
  for select to app_executor using (
    normalized_email=(select app_private.current_actor_email())
    and (select app_private.current_actor_id()) is not null
  );
create policy manager_invites_matching_email_update on app_private.manager_invites
  for update to app_executor
  using (state='pending' and normalized_email=(select app_private.current_actor_email())
    and (select app_private.current_actor_id()) is not null)
  with check (normalized_email=(select app_private.current_actor_email())
    and ((state='accepted' and accepted_user_id=(select app_private.current_actor_id()))
      or (state='expired' and accepted_user_id is null)));

create policy invite_properties_owner_read on app_private.invite_properties
  for select to app_executor using (app_private.is_owner(owner_account_id));
create policy invite_properties_owner_create on app_private.invite_properties
  for insert to app_executor with check (app_private.is_owner(owner_account_id));
create policy invite_properties_matching_email_read on app_private.invite_properties
  for select to app_executor using (exists (
    select 1 from app_private.manager_invites i
    where i.id=invite_properties.invite_id and i.owner_account_id=invite_properties.owner_account_id
      and i.state='pending' and i.normalized_email=(select app_private.current_actor_email())
      and (select app_private.current_actor_id()) is not null
  ));

create policy property_memberships_invite_create on app_private.property_memberships
  for insert to app_executor with check (exists (
    select 1 from app_private.manager_invites i
    join app_private.invite_properties ip on ip.invite_id=i.id and ip.owner_account_id=i.owner_account_id
    where i.owner_account_id=property_memberships.owner_account_id
      and ip.property_id=property_memberships.property_id
      and i.state='pending' and i.normalized_email=(select app_private.current_actor_email())
      and property_memberships.user_id=(select app_private.current_actor_id())
      and property_memberships.permission=ip.permission
  ));
create policy property_memberships_invite_reactivate on app_private.property_memberships
  for update to app_executor
  using (revoked_at is not null and exists (
    select 1 from app_private.manager_invites i
    join app_private.invite_properties ip on ip.invite_id=i.id and ip.owner_account_id=i.owner_account_id
    where i.owner_account_id=property_memberships.owner_account_id
      and ip.property_id=property_memberships.property_id
      and i.state='pending' and i.normalized_email=(select app_private.current_actor_email())
      and property_memberships.user_id=(select app_private.current_actor_id())
  ))
  with check (revoked_at is null and exists (
    select 1 from app_private.manager_invites i
    join app_private.invite_properties ip on ip.invite_id=i.id and ip.owner_account_id=i.owner_account_id
    where i.owner_account_id=property_memberships.owner_account_id
      and ip.property_id=property_memberships.property_id
      and i.state='pending' and i.normalized_email=(select app_private.current_actor_email())
      and property_memberships.user_id=(select app_private.current_actor_id())
      and property_memberships.permission=ip.permission
  ));

grant create on schema api to app_executor;
create function api.create_manager_invite(
  p_path_property_id uuid,
  p_email text,
  p_property_ids uuid[],
  p_permission text,
  p_token_hash text
)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_actor uuid := app_private.current_actor_id();
  v_email text := lower(btrim(p_email));
  v_owner uuid;
  v_invite uuid;
  v_created timestamptz := statement_timestamp();
  v_rows jsonb;
begin
  if v_actor is null then
    raise exception using errcode='28000', message='authentication_required';
  end if;
  if p_path_property_id is null or v_email is null or v_email='' or length(v_email)>254
     or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
     or p_permission is null or p_permission not in ('daily','full')
     or p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$'
     or p_property_ids is null or cardinality(p_property_ids)<1 or cardinality(p_property_ids)>100
     or array_position(p_property_ids,null) is not null
     or cardinality(p_property_ids) <> cardinality(array(select distinct x from unnest(p_property_ids) x))
     or not (p_path_property_id=any(p_property_ids)) then
    raise exception using errcode='22023', message='invalid_manager_invite';
  end if;

  select p.owner_account_id into v_owner
  from app_private.properties p
  where p.id=p_path_property_id and app_private.is_owner(p.owner_account_id)
    and p.archived_at is null;
  if v_owner is null then
    raise exception using errcode='P0002', message='property_not_found';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_owner::text || ':' || v_email, 0));
  if (select count(*) from app_private.properties p
      where p.id=any(p_property_ids) and p.owner_account_id=v_owner and p.archived_at is null) <> cardinality(p_property_ids)
     or exists (
       select 1 from app_private.properties p
       where p.id=any(p_property_ids) and p.owner_account_id=v_owner
         and not exists (select 1 from app_private.subscriptions s
           where s.property_id=p.id and s.owner_account_id=v_owner
             and s.state in ('trialing','active') and s.current_end>v_created)
     ) then
    raise exception using errcode='42501', message='property_scope_or_entitlement_invalid';
  end if;

  update app_private.manager_invites
    set state='revoked', updated_at=v_created, version=version+1
    where owner_account_id=v_owner and normalized_email=v_email and state='pending';

  insert into app_private.manager_invites(
    owner_account_id,invited_by_user_id,normalized_email,token_hash,expires_at,created_at,updated_at)
  values (v_owner,v_actor,v_email,p_token_hash,v_created+interval '24 hours',v_created,v_created)
  returning id into v_invite;

  insert into app_private.invite_properties(owner_account_id,property_id,invite_id,permission)
  select v_owner, p.id, v_invite, p_permission::app_private.permission
  from app_private.properties p where p.id=any(p_property_ids) and p.owner_account_id=v_owner
  order by p.id;

  select jsonb_agg(jsonb_build_object(
    'id',ip.id,'user_id',null,'property_id',ip.property_id,'email',v_email,
    'permission',ip.permission::text,'status','invited','expires_at',v_created+interval '24 hours',
    'version',ip.version,'created_at',ip.created_at,'updated_at',ip.updated_at
  ) order by ip.property_id) into v_rows
  from app_private.invite_properties ip where ip.invite_id=v_invite;

  return jsonb_build_object('items',coalesce(v_rows,'[]'::jsonb),'next_cursor',null);
end;
$$;
revoke all on function api.create_manager_invite(uuid,text,uuid[],text,text) from public, anon, authenticated;
grant execute on function api.create_manager_invite(uuid,text,uuid[],text,text) to authenticated;
grant app_executor to current_user with set true, inherit false;
alter function api.create_manager_invite(uuid,text,uuid[],text,text) owner to app_executor;
revoke app_executor from current_user;
revoke create on schema api from app_executor;

grant create on schema api to app_executor;
create function api.accept_manager_invite(p_token_hash text)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_actor uuid := app_private.current_actor_id();
  v_email text := app_private.current_actor_email();
  v_invite app_private.manager_invites%rowtype;
  v_owner_user uuid;
  v_items jsonb;
  v_now timestamptz := statement_timestamp();
begin
  if v_actor is null or v_email is null or v_email='' then
    raise exception using errcode='28000', message='authenticated_email_required';
  end if;
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode='22023', message='invalid_invite_token';
  end if;

  select i.* into v_invite
  from app_private.manager_invites i
  where i.token_hash=p_token_hash and i.normalized_email=v_email;
  if not found then
    raise exception using errcode='P0002', message='invite_not_found';
  end if;
  if v_invite.state='expired' then
    return jsonb_build_object('status','expired');
  end if;
  if v_invite.state <> 'pending' then
    raise exception using errcode='23505', message='invite_not_active';
  end if;
  select i.* into v_invite
  from app_private.manager_invites i
  where i.id=v_invite.id and i.state='pending'
  for update;
  if not found then
    raise exception using errcode='23505', message='invite_not_active';
  end if;
  if v_invite.expires_at <= v_now then
    update app_private.manager_invites
      set state='expired', updated_at=v_now, version=version+1
      where id=v_invite.id;
    return jsonb_build_object('status','expired');
  end if;

  if (select count(*) from app_private.invite_properties ip
      join app_private.properties p on p.id=ip.property_id and p.owner_account_id=ip.owner_account_id
      join app_private.subscriptions s on s.property_id=p.id and s.owner_account_id=p.owner_account_id
      where ip.invite_id=v_invite.id and p.archived_at is null
        and s.state in ('trialing','active') and s.current_end>v_now)
     <> (select count(*) from app_private.invite_properties ip where ip.invite_id=v_invite.id) then
    raise exception using errcode='42501', message='property_scope_or_entitlement_invalid';
  end if;

  v_owner_user := v_invite.invited_by_user_id;
  if v_owner_user is null then
    raise exception using errcode='P0002', message='invite_not_found';
  end if;

  if v_owner_user=v_actor then
    raise exception using errcode='23505', message='owner_cannot_accept_own_invite';
  end if;

  -- Serialize overlapping property grants for the same recipient across distinct invites.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_actor::text || ':' || ip.property_id::text, 0))
  from app_private.invite_properties ip
  where ip.invite_id=v_invite.id
  order by ip.property_id;

  if exists (
    select 1 from app_private.property_memberships m
    join app_private.invite_properties ip on ip.property_id=m.property_id
      and ip.owner_account_id=m.owner_account_id
    where ip.invite_id=v_invite.id and m.user_id=v_actor and m.revoked_at is null
  ) then
    raise exception using errcode='23505', message='membership_already_active';
  end if;

  insert into app_private.property_memberships(
    owner_account_id,property_id,user_id,permission,granted_by)
  select ip.owner_account_id,ip.property_id,v_actor,ip.permission,v_owner_user
  from app_private.invite_properties ip
  where ip.invite_id=v_invite.id and ip.owner_account_id=v_invite.owner_account_id
  order by ip.property_id
  on conflict (property_id,user_id) do update
    set permission=excluded.permission,granted_by=excluded.granted_by,
        revoked_at=null,updated_at=v_now,version=app_private.property_memberships.version+1
    where app_private.property_memberships.revoked_at is not null;

  if (select count(*) from app_private.property_memberships m
      join app_private.invite_properties ip on ip.property_id=m.property_id
        and ip.owner_account_id=m.owner_account_id
      where ip.invite_id=v_invite.id and m.user_id=v_actor and m.revoked_at is null)
     <> (select count(*) from app_private.invite_properties ip where ip.invite_id=v_invite.id) then
    raise exception using errcode='23505', message='membership_already_active';
  end if;

  select jsonb_agg(jsonb_build_object(
    'id',m.id,'user_id',m.user_id,'property_id',m.property_id,'email',v_email,
    'permission',m.permission::text,'status','active','version',m.version,
    'created_at',m.created_at,'updated_at',m.updated_at
  ) order by m.property_id) into v_items
  from app_private.property_memberships m
  join app_private.invite_properties ip on ip.property_id=m.property_id
    and ip.owner_account_id=m.owner_account_id
  where ip.invite_id=v_invite.id and m.user_id=v_actor and m.revoked_at is null;

  update app_private.manager_invites
    set state='accepted',accepted_user_id=v_actor,updated_at=v_now,version=version+1
    where id=v_invite.id;

  return jsonb_build_object('status','accepted','items',coalesce(v_items,'[]'::jsonb),'next_cursor',null);
end;
$$;
revoke all on function api.accept_manager_invite(text) from public, anon, authenticated;
grant execute on function api.accept_manager_invite(text) to authenticated;
grant app_executor to current_user with set true, inherit false;
alter function api.accept_manager_invite(text) owner to app_executor;
revoke app_executor from current_user;
revoke create on schema api from app_executor;

