-- EVE-022.2 DB component smoke. Byte validation is tested in TypeScript;
-- this verifies row transition, scope, idempotency and service-only ACL.
do $$ begin
  if has_function_privilege('anon','api.finalize_media_upload_for_server(uuid,uuid,text,bigint,integer,text,text)','EXECUTE')
     or has_function_privilege('authenticated','api.finalize_media_upload_for_server(uuid,uuid,text,bigint,integer,text,text)','EXECUTE')
     or not has_function_privilege('service_role','api.finalize_media_upload_for_server(uuid,uuid,text,bigint,integer,text,text)','EXECUTE')
     or has_function_privilege('service_role','app_private.finalize_media_upload(uuid,text,bigint,integer,text,text)','EXECUTE') then
    raise exception 'finalize server-only function grant boundary changed';
  end if;
end $$;

begin;
insert into auth.users(id) values
 ('a0222000-0000-4000-8000-000000000011'),
 ('a0222000-0000-4000-8000-000000000012') on conflict(id) do nothing;
insert into app_private.owner_accounts(id,owner_user_id) values
 ('a0222100-0000-4000-8000-000000000011','a0222000-0000-4000-8000-000000000011');
insert into app_private.properties(id,owner_account_id,name,area) values
 ('a0222200-0000-4000-8000-000000000011','a0222100-0000-4000-8000-000000000011','Finalize test','Bakı');
insert into app_private.subscriptions(owner_account_id,property_id,state,current_end) values
 ('a0222100-0000-4000-8000-000000000011','a0222200-0000-4000-8000-000000000011','trialing',now()+interval '7 days');
insert into app_private.property_memberships(owner_account_id,property_id,user_id,permission,granted_by)
values ('a0222100-0000-4000-8000-000000000011','a0222200-0000-4000-8000-000000000011',
 'a0222000-0000-4000-8000-000000000012','daily','a0222000-0000-4000-8000-000000000011');
insert into app_private.media_assets(id,owner_account_id,property_id,classification,bucket,object_key,mime,size_bytes,state,upload_expires_at)
values ('a0222300-0000-4000-8000-000000000011','a0222100-0000-4000-8000-000000000011',
 'a0222200-0000-4000-8000-000000000011','public_property','eve-public-property',
 'a0222300-0000-4000-8000-000000000011','image/jpeg',1024,'pending',now()+interval '15 minutes');
insert into app_private.media_assets(id,owner_account_id,property_id,classification,bucket,object_key,mime,size_bytes,state,upload_expires_at)
values ('a0222300-0000-4000-8000-000000000012','a0222100-0000-4000-8000-000000000011',
 'a0222200-0000-4000-8000-000000000011','private_inventory','eve-private-inventory',
 'a0222300-0000-4000-8000-000000000012','image/jpeg',1024,'pending',now()+interval '15 minutes');

-- Even authenticated users cannot call the server bridge directly.
set local role authenticated;
set local request.jwt.claim.role='authenticated';
do $$ begin
  begin
    perform api.finalize_media_upload_for_server('a0222000-0000-4000-8000-000000000011',
      'a0222300-0000-4000-8000-000000000011','image/jpeg',4,null,repeat('a',64),
      'finalize-auth-denied-0001');
    raise exception 'authenticated client invoked server-only finalize';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

set local role service_role;
set local request.jwt.claim.role='service_role';
do $$ declare v_result jsonb; v_replay jsonb; begin
  perform api.finalize_media_upload_for_server('a0222000-0000-4000-8000-000000000012',
    'a0222300-0000-4000-8000-000000000012','image/jpeg',4,null,repeat('d',64),
    'finalize-revoked-inventory-key');
  begin
    perform api.finalize_media_upload_for_server('a0222000-0000-4000-8000-000000000011',
      'a0222300-0000-4000-8000-000000000011','image/jpeg',1025,null,repeat('c',64),
      'finalize-over-reserved-0001');
    raise exception 'finalize accepted bytes above the quota reservation';
  exception when numeric_value_out_of_range then null; end;
  v_result := api.finalize_media_upload_for_server('a0222000-0000-4000-8000-000000000011',
    'a0222300-0000-4000-8000-000000000011','image/jpeg',4,null,repeat('a',64),
    'finalize-media-key-00001');
  v_replay := api.finalize_media_upload_for_server('a0222000-0000-4000-8000-000000000011',
    'a0222300-0000-4000-8000-000000000011','image/jpeg',4,null,repeat('a',64),
    'finalize-media-key-00001');
  if v_result->>'id'<>'a0222300-0000-4000-8000-000000000011'
     or v_result->>'status'<>'validated' or (v_result->>'size_bytes')::bigint<>4
     or (v_result->>'version')::integer<>2 or v_replay<>v_result then
    raise exception 'finalize measured values or idempotent replay failed';
  end if;
  begin
    perform api.finalize_media_upload_for_server('a0222000-0000-4000-8000-000000000011',
      'a0222300-0000-4000-8000-000000000011','image/jpeg',5,null,repeat('a',64),
      'finalize-media-key-00001');
    raise exception 'idempotency payload mismatch was accepted';
  exception when unique_violation then null; end;
  begin
    perform api.finalize_media_upload_for_server('a0222000-0000-4000-8000-000000000012',
      'a0222300-0000-4000-8000-000000000011','image/jpeg',4,null,repeat('b',64),
      'finalize-cross-owner-key-01');
    raise exception 'cross-owner finalize was accepted';
  exception when insufficient_privilege or unique_violation then null; end;
end $$;
reset role;

update app_private.property_memberships set revoked_at=now()
where property_id='a0222200-0000-4000-8000-000000000011' and user_id='a0222000-0000-4000-8000-000000000012';
set local role service_role;
set local request.jwt.claim.role='service_role';
do $$ begin
  begin
    perform api.finalize_media_upload_for_server('a0222000-0000-4000-8000-000000000012',
      'a0222300-0000-4000-8000-000000000012','image/jpeg',4,null,repeat('d',64),
      'finalize-revoked-inventory-key');
    raise exception 'revoked inventory capability idempotency replay was accepted';
  exception when insufficient_privilege or unique_violation then null; end;
end $$;
reset role;

do $$ begin
  if (select count(*) from app_private.media_assets where id='a0222300-0000-4000-8000-000000000011'
      and state='validated' and size_bytes=4 and sha256=repeat('a',64)
      and upload_expires_at is null and version=2)<>1 then
    raise exception 'finalized row does not store server-verified values';
  end if;
end $$;
rollback;
