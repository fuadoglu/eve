-- EVE-008.2 PostgreSQL role/JWT-fixture smoke; synthetic, not hosted SMTP or production proof.
begin;

insert into auth.users(id) values
  ('f0000000-0000-0000-0000-000000000001'), -- owner A
  ('f0000000-0000-0000-0000-000000000002'), -- owner B
  ('f0000000-0000-0000-0000-000000000003'), -- manager
  ('f0000000-0000-0000-0000-000000000004'), -- mismatched email
  ('f0000000-0000-0000-0000-000000000005'), -- unconfirmed email
  ('f0000000-0000-0000-0000-000000000006')  -- expired invite recipient
on conflict (id) do nothing;
update auth.users set
  email=case id
    when 'f0000000-0000-0000-0000-000000000001' then 'owner-a@example.test'
    when 'f0000000-0000-0000-0000-000000000002' then 'owner-b@example.test'
    when 'f0000000-0000-0000-0000-000000000003' then 'manager@example.test'
    when 'f0000000-0000-0000-0000-000000000004' then 'other@example.test'
    when 'f0000000-0000-0000-0000-000000000005' then 'unconfirmed@example.test'
    when 'f0000000-0000-0000-0000-000000000006' then 'expired@example.test'
  end,
  email_confirmed_at=case when id='f0000000-0000-0000-0000-000000000005' then null else now() end
where id in (
  'f0000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-000000000002',
  'f0000000-0000-0000-0000-000000000003','f0000000-0000-0000-0000-000000000004',
  'f0000000-0000-0000-0000-000000000005','f0000000-0000-0000-0000-000000000006'
);

insert into app_private.owner_accounts(id,owner_user_id) values
  ('f1000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-000000000001'),
  ('f1000000-0000-0000-0000-000000000002','f0000000-0000-0000-0000-000000000002');
insert into app_private.properties(id,owner_account_id,name,area) values
  ('f2000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001','A1','Bakı'),
  ('f2000000-0000-0000-0000-000000000002','f1000000-0000-0000-0000-000000000001','A2','Gəncə'),
  ('f2000000-0000-0000-0000-000000000003','f1000000-0000-0000-0000-000000000002','B1','Bakı'),
  ('f2000000-0000-0000-0000-000000000004','f1000000-0000-0000-0000-000000000001','A3 draft','Şəki');
insert into app_private.subscriptions(owner_account_id,property_id,state,current_end) values
  ('f1000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000001','active',now()+interval '30 days'),
  ('f1000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000002','trialing',now()+interval '30 days'),
  ('f1000000-0000-0000-0000-000000000002','f2000000-0000-0000-0000-000000000003','active',now()+interval '30 days'),
  ('f1000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000004','draft',null);

set local role authenticated;
set local request.jwt.claims = '{"sub":"f0000000-0000-0000-0000-000000000001","email":"owner-a@example.test"}';
do $$
declare v_result jsonb;
begin
  v_result := api.create_manager_invite(
    'f2000000-0000-0000-0000-000000000001',
    '  Manager@Example.Test ',
    array['f2000000-0000-0000-0000-000000000002'::uuid,'f2000000-0000-0000-0000-000000000001'::uuid],
    'daily',repeat('a',64));
  if jsonb_array_length(v_result->'items') <> 2
     or v_result::text like '%'||repeat('a',64)||'%'
     or exists (select 1 from jsonb_array_elements(v_result->'items') as item(value)
       where value->>'status'<>'invited' or value->>'email'<>'manager@example.test'
         or value->>'permission'<>'daily' or value->>'expires_at' is null) then
    raise exception 'invite response is incomplete or exposes token hash: %',v_result;
  end if;
end $$;
reset role;

do $$
declare v_invite app_private.manager_invites%rowtype; v_count integer;
begin
  select * into strict v_invite from app_private.manager_invites where token_hash=repeat('a',64);
  if v_invite.normalized_email <> 'manager@example.test'
     or v_invite.expires_at-v_invite.created_at <> interval '24 hours'
     or v_invite.state <> 'pending'
     or (select count(*) from app_private.invite_properties where invite_id=v_invite.id) <> 2 then
    raise exception 'invite persistence / 24 hour TTL mismatch';
  end if;
  select count(*) into v_count from app_private.invite_properties ip
  where ip.invite_id=v_invite.id and ip.permission='daily';
  if v_count <> 2 then raise exception 'permission not applied to every selected property'; end if;
end $$;

set local role authenticated;
set local request.jwt.claims = '{"sub":"f0000000-0000-0000-0000-000000000004","email":"other@example.test"}';
do $$
begin
  begin
    perform api.accept_manager_invite(repeat('a',64));
    raise exception 'mismatched email accepted invite';
  exception when no_data_found then null;
  end;
end $$;

set local request.jwt.claims = '{"sub":"f0000000-0000-0000-0000-000000000003","email":"manager@example.test"}';
do $$
begin
  if exists (select 1 from api.list_visible_property_summaries(null,100)
      where property_id in ('f2000000-0000-0000-0000-000000000001',
                            'f2000000-0000-0000-0000-000000000002')) then
    raise exception 'pending invite RLS leaked properties through the normal property list';
  end if;
end $$;
reset role;
set local role app_executor;
set local request.jwt.claims = '{"sub":"f0000000-0000-0000-0000-000000000003","email":"manager@example.test"}';
select set_config('app.manager_invite_accept_id',
  (select id::text from app_private.manager_invites where token_hash=repeat('a',64)),true);
do $$
begin
  if exists (select 1 from app_private.properties where id in (
        'f2000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000002'))
     or exists (select 1 from app_private.subscriptions where property_id in (
        'f2000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000002'))
     or exists (select 1 from app_private.invite_properties
        where invite_id=(select id from app_private.manager_invites where token_hash=repeat('a',64))) then
    raise exception 'client-set GUC bypassed pending invite transaction-context RLS';
  end if;
end $$;
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"f0000000-0000-0000-0000-000000000003","email":"manager@example.test"}';
do $$
declare v_result jsonb;
begin
  v_result := api.accept_manager_invite(repeat('a',64));
  if v_result->>'status' is distinct from 'accepted' or jsonb_array_length(v_result->'items')<>2
     or v_result::text like '%'||repeat('a',64)||'%' then
    raise exception 'accept response mismatch or token hash leak: %',v_result;
  end if;
end $$;
reset role;

do $$
begin
  if (select state from app_private.manager_invites where token_hash=repeat('a',64)) <> 'accepted'
     or (select count(*) from app_private.property_memberships
         where user_id='f0000000-0000-0000-0000-000000000003'
           and owner_account_id='f1000000-0000-0000-0000-000000000001'
           and revoked_at is null and permission='daily') <> 2 then
    raise exception 'acceptance did not atomically grant all scoped memberships';
  end if;
end $$;
do $$
begin
  if exists (select 1 from app_private.manager_invite_accept_context
      where actor_id='f0000000-0000-0000-0000-000000000003') then
    raise exception 'successful accept left transaction context behind';
  end if;
end $$;

set local role authenticated;
set local request.jwt.claims = '{"sub":"f0000000-0000-0000-0000-000000000001","email":"owner-a@example.test"}';
do $$
begin
  perform api.create_manager_invite(
    'f2000000-0000-0000-0000-000000000001','unconfirmed@example.test',
    array['f2000000-0000-0000-0000-000000000001'::uuid],
    'daily',repeat('9',64));
end $$;
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"f0000000-0000-0000-0000-000000000005","email":"unconfirmed@example.test"}';
do $$
begin
  begin
    perform api.accept_manager_invite(repeat('9',64));
    raise exception 'unconfirmed auth email accepted manager invite';
  exception when sqlstate '28000' then null;
  end;
end $$;
reset role;
do $$
begin
  if (select state from app_private.manager_invites where token_hash=repeat('9',64)) <> 'pending'
     or exists (select 1 from app_private.property_memberships
       where user_id='f0000000-0000-0000-0000-000000000005' and revoked_at is null) then
    raise exception 'unconfirmed recipient changed invite or gained membership';
  end if;
end $$;

set local role authenticated;
set local request.jwt.claims = '{"sub":"f0000000-0000-0000-0000-000000000003","email":"manager@example.test"}';
do $$
begin
  begin
    perform api.accept_manager_invite(repeat('a',64));
    raise exception 'replayed invite accepted';
  exception when unique_violation then null;
  end;
end $$;
reset role;

update app_private.property_memberships set revoked_at=now(),version=version+1
where user_id='f0000000-0000-0000-0000-000000000003'
  and property_id='f2000000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"f0000000-0000-0000-0000-000000000001","email":"owner-a@example.test"}';
do $$
begin
  perform api.create_manager_invite(
    'f2000000-0000-0000-0000-000000000001','manager@example.test',
    array['f2000000-0000-0000-0000-000000000001'::uuid],
    'full',repeat('e',64));
end $$;
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"f0000000-0000-0000-0000-000000000003","email":"manager@example.test"}';
do $$
declare v_result jsonb;
begin
  v_result := api.accept_manager_invite(repeat('e',64));
  if v_result->>'status' is distinct from 'accepted' or jsonb_array_length(v_result->'items')<>1
     or v_result->'items'->0->>'permission'<>'full' then
    raise exception 'revoked membership was not safely reactivated with the new permission: %',v_result;
  end if;
end $$;
reset role;
do $$
begin
  if (select count(*) from app_private.property_memberships
      where user_id='f0000000-0000-0000-0000-000000000003'
        and property_id='f2000000-0000-0000-0000-000000000001'
        and revoked_at is null and permission='full') <> 1 then
    raise exception 'revoked membership reactivation failed';
  end if;
end $$;

set local role authenticated;
set local request.jwt.claims = '{"sub":"f0000000-0000-0000-0000-000000000001","email":"owner-a@example.test"}';
do $$
begin
  perform api.create_manager_invite(
    'f2000000-0000-0000-0000-000000000001','manager@example.test',
    array['f2000000-0000-0000-0000-000000000001'::uuid],
    'daily',repeat('f',64));
end $$;
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"f0000000-0000-0000-0000-000000000003","email":"manager@example.test"}';
do $$
begin
  begin
    perform api.accept_manager_invite(repeat('f',64));
    raise exception 'invite silently changed an active membership permission';
  exception when unique_violation then null;
  end;
end $$;
reset role;
do $$
begin
  if (select permission from app_private.property_memberships
      where user_id='f0000000-0000-0000-0000-000000000003'
        and property_id='f2000000-0000-0000-0000-000000000001' and revoked_at is null) <> 'full'
     or (select state from app_private.manager_invites where token_hash=repeat('f',64)) <> 'pending' then
    raise exception 'conflicting active membership was altered or invite state was consumed';
  end if;
end $$;

set local role authenticated;
set local request.jwt.claims = '{"sub":"f0000000-0000-0000-0000-000000000001","email":"owner-a@example.test"}';
do $$
begin
  begin
    perform api.create_manager_invite(
      'f2000000-0000-0000-0000-000000000001','other@example.test',
      array['f2000000-0000-0000-0000-000000000001'::uuid,'f2000000-0000-0000-0000-000000000003'::uuid],
      'full',repeat('b',64));
    raise exception 'cross-owner property was accepted';
  exception when insufficient_privilege then null;
  end;
  begin
    perform api.create_manager_invite(
      'f2000000-0000-0000-0000-000000000004','other@example.test',
      array['f2000000-0000-0000-0000-000000000004'::uuid],
      'full',repeat('c',64));
    raise exception 'draft entitlement was accepted';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

insert into app_private.manager_invites(owner_account_id,invited_by_user_id,normalized_email,token_hash,expires_at)
values ('f1000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-000000000001','expired@example.test',repeat('d',64),now()+interval '1 day')
returning id \gset expired_invite_
insert into app_private.invite_properties(owner_account_id,property_id,invite_id,permission)
values ('f1000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000001',:'expired_invite_id','daily');
update app_private.manager_invites set created_at=now()-interval '25 hours',expires_at=now()-interval '1 hour'
where id=:'expired_invite_id';

set local role app_executor;
set local request.jwt.claims = '{"sub":"f0000000-0000-0000-0000-000000000006","email":"expired@example.test"}';
select set_config('app.manager_invite_accept_id',:'expired_invite_id',true);
do $$
begin
  if exists (select 1 from app_private.properties where id='f2000000-0000-0000-0000-000000000001')
     or exists (select 1 from app_private.subscriptions where property_id='f2000000-0000-0000-0000-000000000001')
     or exists (select 1 from app_private.invite_properties
       where invite_id=(select id from app_private.manager_invites where token_hash=repeat('d',64))) then
    raise exception 'expired invite or client-set GUC bypassed accept-context RLS';
  end if;
end $$;
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"f0000000-0000-0000-0000-000000000006","email":"expired@example.test"}';
do $$
declare v_result jsonb;
begin
  v_result := api.accept_manager_invite(repeat('d',64));
  if v_result->>'status' is distinct from 'expired' then raise exception 'expired invite status mismatch: %',v_result; end if;
end $$;
reset role;
do $$
begin
  if (select state from app_private.manager_invites where token_hash=repeat('d',64)) <> 'expired'
     or exists (select 1 from app_private.property_memberships where user_id='f0000000-0000-0000-0000-000000000006'
       and owner_account_id='f1000000-0000-0000-0000-000000000001' and revoked_at is null
       and property_id in (select property_id from app_private.invite_properties
         where invite_id=(select id from app_private.manager_invites where token_hash=repeat('d',64)))) then
    raise exception 'expired invite created memberships or failed to transition';
  end if;
end $$;
set local role authenticated;
set local request.jwt.claims = '{"sub":"f0000000-0000-0000-0000-000000000006","email":"expired@example.test"}';
do $$
begin
  if api.accept_manager_invite(repeat('d',64))->>'status' is distinct from 'expired' then
    raise exception 'expired invite retry was not safely idempotent';
  end if;
end $$;
reset role;

do $$
begin
  begin
    insert into app_private.manager_invites(owner_account_id,invited_by_user_id,normalized_email,token_hash,expires_at)
    values ('f1000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-000000000001','long@example.test',repeat('e',64),now()+interval '25 hours');
    raise exception 'invite over 24h accepted';
  exception when check_violation then null;
  end;
  begin
    insert into app_private.manager_invites(owner_account_id,invited_by_user_id,normalized_email,token_hash,expires_at)
    values ('f1000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-000000000001','hash@example.test','raw-token-not-a-hash',now()+interval '1 hour');
    raise exception 'non-SHA256 token stored';
  exception when check_violation then null;
  end;
  begin
    insert into app_private.manager_invites(owner_account_id,invited_by_user_id,normalized_email,token_hash,expires_at)
    values ('f1000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-000000000001','Upper@example.test',repeat('f',64),now()+interval '1 hour');
    raise exception 'non-normalized email stored';
  exception when check_violation then null;
  end;
end $$;

rollback;
