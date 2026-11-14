-- EVE-022.1 synthetic PostgreSQL/JWT test; no Storage bytes/provider URL are exercised.
do $$ begin
  if (select p.proowner<>'app_executor'::regrole or not p.prosecdef
      or not (coalesce(p.proconfig,array[]::text[]) @> array['search_path=""']::text[])
      from pg_proc p where p.oid='app_private.reserve_media_upload(uuid,text,text,text,text,bigint,integer,text)'::regprocedure)
     or has_function_privilege('anon','app_private.reserve_media_upload(uuid,text,text,text,text,bigint,integer,text)','EXECUTE')
     or has_function_privilege('authenticated','app_private.reserve_media_upload(uuid,text,text,text,text,bigint,integer,text)','EXECUTE')
     or has_table_privilege('authenticated','app_private.media_assets','INSERT') then
    raise exception 'upload reservation RPC owner/grant boundary is unsafe';
  end if;
end $$;
begin;
insert into auth.users(id) values ('a0220000-0000-4000-8000-000000000001'),('a0220000-0000-4000-8000-000000000002'),('a0220000-0000-4000-8000-000000000003') on conflict (id) do nothing;
insert into app_private.owner_accounts(id,owner_user_id) values
 ('a0221000-0000-4000-8000-000000000001','a0220000-0000-4000-8000-000000000001'),
 ('a0221000-0000-4000-8000-000000000003','a0220000-0000-4000-8000-000000000003');
insert into app_private.properties(id,owner_account_id,name,area) values
 ('a0222000-0000-4000-8000-000000000001','a0221000-0000-4000-8000-000000000001','Upload test','Bakı'),
 ('a0222000-0000-4000-8000-000000000003','a0221000-0000-4000-8000-000000000003','Other owner','Gəncə');
insert into app_private.subscriptions(owner_account_id,property_id,state,current_end) values ('a0221000-0000-4000-8000-000000000001','a0222000-0000-4000-8000-000000000001','trialing',now()+interval '7 days');
insert into app_private.property_memberships(owner_account_id,property_id,user_id,permission,granted_by) values ('a0221000-0000-4000-8000-000000000001','a0222000-0000-4000-8000-000000000001','a0220000-0000-4000-8000-000000000002','daily','a0220000-0000-4000-8000-000000000001');
set local role app_executor;
set local request.jwt.claim.sub='a0220000-0000-4000-8000-000000000001';
do $$
declare v_first jsonb; v_retry jsonb; v_media uuid; i integer;
begin
  v_first := app_private.reserve_media_upload('a0222000-0000-4000-8000-000000000001','image','public_property','house.jpg','image/jpeg',1048576,null,'upload-positive-0001');
  v_retry := app_private.reserve_media_upload('a0222000-0000-4000-8000-000000000001','image','public_property','house.jpg','image/jpeg',1048576,null,'upload-positive-0001');
  v_media := (v_first->>'media_id')::uuid;
  if v_media is null or v_retry->>'media_id'<>v_media::text or (v_first->>'reserved_bytes')::bigint<>1048576
     or (v_first->>'expires_at')::timestamptz<=now() or (v_first->>'expires_at')::timestamptz>now()+interval '16 minutes'
     or (select count(*) from app_private.media_assets where id=v_media)<>1 then raise exception 'positive reservation/replay failed'; end if;
  begin
    perform app_private.reserve_media_upload('a0222000-0000-4000-8000-000000000001','image','public_property','changed.jpg','image/jpeg',1048576,null,'upload-positive-0001');
    raise exception 'idempotency payload mismatch accepted';
  exception when unique_violation then null; end;
  begin
    perform app_private.reserve_media_upload('a0222000-0000-4000-8000-000000000001','image','public_property','large.jpg','image/jpeg',15728641,null,'upload-photo-limit-01');
    raise exception 'photo above 15 MiB accepted';
  exception when invalid_parameter_value then null; end;
  begin
    perform app_private.reserve_media_upload('a0222000-0000-4000-8000-000000000001','document','public_property','active.svg','image/svg+xml',4096,null,'upload-svg-denied-01');
    raise exception 'active SVG MIME accepted';
  exception when invalid_parameter_value then null; end;
  begin
    perform app_private.reserve_media_upload('a0222000-0000-4000-8000-000000000001','audio','private_task','note.webm','audio/webm',4096,61,'upload-audio-limit-01');
    raise exception 'audio above 60 seconds accepted';
  exception when invalid_parameter_value then null; end;
  for i in 1..10 loop
    perform app_private.reserve_media_upload('a0222000-0000-4000-8000-000000000001','video','private_task','clip.mp4','video/mp4',104857600,300,'upload-quota-'||lpad(i::text,3,'0'));
  end loop;
  begin
    perform app_private.reserve_media_upload('a0222000-0000-4000-8000-000000000001','video','public_guide','extra.mp4','video/mp4',25165824,30,'upload-quota-over-01');
    raise exception 'aggregate upload reservation exceeded 1 GiB';
  exception when numeric_value_out_of_range then null; end;
end $$;
reset role;
update app_private.media_assets set upload_expires_at=now()-interval '1 second'
where property_id='a0222000-0000-4000-8000-000000000001' and state='pending'
  and id<>'a0222000-0000-4000-8000-000000000001';
set local role app_executor;
do $$ begin
  if (app_private.reserve_media_upload('a0222000-0000-4000-8000-000000000001','video','private_task','after-expiry.mp4','video/mp4',104857600,300,'upload-after-expiry-01')->>'media_id') is null then
    raise exception 'expired pending reservations did not release quota'; end if;
end $$;
set local request.jwt.claim.sub='a0220000-0000-4000-8000-000000000002';
do $$ begin
  begin
    perform app_private.reserve_media_upload('a0222000-0000-4000-8000-000000000003','image','public_property','cross-owner.jpg','image/jpeg',1024,null,'upload-cross-owner-01');
    raise exception 'cross-owner upload reservation succeeded';
  exception when no_data_found then null; end;
  begin
    perform app_private.reserve_media_upload('a0222000-0000-4000-8000-000000000001','document','private_receipt','receipt.pdf','application/pdf',1024,null,'upload-daily-receipt-01');
    raise exception 'daily manager reserved financial receipt media';
  exception when no_data_found then null; end;
end $$;
reset role;
rollback;
begin;
set local role app_executor;
set local request.jwt.claim.sub='';
do $$ begin
  begin
    perform app_private.reserve_media_upload('00000000-0000-0000-0000-000000000000','image','public_property','anonymous.jpg','image/jpeg',1024,null,'upload-anonymous-01');
    raise exception 'anonymous upload reservation succeeded';
  exception when sqlstate '28000' then null; end;
end $$;
rollback;
