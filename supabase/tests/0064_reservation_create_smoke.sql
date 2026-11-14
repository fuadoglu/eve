-- EVE-011.1 local PostgreSQL/JWT-role DB proof; synthetic, not HTTP or production.
do $$
begin
  if (select p.proowner<>'app_executor'::regrole or not p.prosecdef
      or not (coalesce(p.proconfig,array[]::text[]) @> array['search_path=""']::text[])
      from pg_proc p where p.oid='api.create_reservation(jsonb,text)'::regprocedure)
     or has_function_privilege('anon','api.create_reservation(jsonb,text)','EXECUTE')
     or not has_function_privilege('authenticated','api.create_reservation(jsonb,text)','EXECUTE')
     or has_table_privilege('authenticated','app_private.reservations','INSERT') then
    raise exception 'reservation RPC owner/grant boundary is unsafe';
  end if;
end $$;
begin;
insert into auth.users(id) values
 ('f0000000-0000-0000-0000-000000000011'),('f0000000-0000-0000-0000-000000000012'),
 ('f0000000-0000-0000-0000-000000000013'),('f0000000-0000-0000-0000-000000000014')
on conflict (id) do nothing;
insert into app_private.owner_accounts(id,owner_user_id) values
 ('f1000000-0000-0000-0000-000000000011','f0000000-0000-0000-0000-000000000011'),
 ('f1000000-0000-0000-0000-000000000012','f0000000-0000-0000-0000-000000000012');
insert into app_private.properties(id,owner_account_id,name,area,max_guests,default_check_in,default_check_out) values
 ('f2000000-0000-0000-0000-000000000011','f1000000-0000-0000-0000-000000000011','A1','Bakı',1,'15:00','11:00'),
 ('f2000000-0000-0000-0000-000000000012','f1000000-0000-0000-0000-000000000011','A2','Gəncə',4,'14:00','12:00'),
 ('f2000000-0000-0000-0000-000000000013','f1000000-0000-0000-0000-000000000012','B1','Bakı',4,'14:00','12:00');
insert into app_private.subscriptions(owner_account_id,property_id,state,current_end) values
 ('f1000000-0000-0000-0000-000000000011','f2000000-0000-0000-0000-000000000011','trialing',now()+interval '7 days'),
 ('f1000000-0000-0000-0000-000000000011','f2000000-0000-0000-0000-000000000012','draft',null),
 ('f1000000-0000-0000-0000-000000000012','f2000000-0000-0000-0000-000000000013','active',now()+interval '30 days');
insert into app_private.property_memberships(owner_account_id,property_id,user_id,permission,granted_by) values
 ('f1000000-0000-0000-0000-000000000011','f2000000-0000-0000-0000-000000000011','f0000000-0000-0000-0000-000000000013','daily','f0000000-0000-0000-0000-000000000011'),
 ('f1000000-0000-0000-0000-000000000011','f2000000-0000-0000-0000-000000000011','f0000000-0000-0000-0000-000000000014','full','f0000000-0000-0000-0000-000000000011');
update app_private.property_memberships set revoked_at=now() where user_id='f0000000-0000-0000-0000-000000000014';
insert into app_private.contacts(id,owner_account_id,name,phone,service_type) values
 ('f3000000-0000-0000-0000-000000000011','f1000000-0000-0000-0000-000000000011','A realtor','+994501234567','realtor'),
 ('f3000000-0000-0000-0000-000000000012','f1000000-0000-0000-0000-000000000012','B realtor','+994501234568','realtor');
set local role authenticated;
set local request.jwt.claim.sub='f0000000-0000-0000-0000-000000000011';
do $$
declare v_input jsonb; v_first jsonb; v_retry jsonb;
begin
  v_input := '{"property_id":"f2000000-0000-0000-0000-000000000011","guest_name":"A Guest","guest_count":2,"check_in":"2027-05-01","check_out":"2027-05-04","total_minor":30000,"capacity_override_confirmed":true,"initial_receipt":{"amount_minor":10000,"kind":"rent_receipt","custodian":"owner"},"commission":{"contact_id":"f3000000-0000-0000-0000-000000000011","kind":"percentage","percentage_basis_points":1000}}'::jsonb;
  v_first := api.create_reservation(v_input,'reservation-create-owner-key-01');
  v_retry := api.create_reservation(v_input,'reservation-create-owner-key-01');
  if v_first->>'reservation_id' is null or v_first->>'initial_receipt_id' is null
     or v_retry->>'reservation_id'<>v_first->>'reservation_id'
     or v_retry->>'placement_id'<>v_first->>'placement_id'
     or v_first::text like '%A Guest%' then
    raise exception 'create acknowledgement or idempotent retry mismatch: % / %',v_first,v_retry;
  end if;
  begin
    perform api.create_reservation(v_input||'{"total_minor":30001}'::jsonb,'reservation-create-owner-key-01');
    raise exception 'same idempotency key accepted a different payload';
  exception when unique_violation then null;
  end;
  begin
    perform api.create_reservation('{"property_id":"f2000000-0000-0000-0000-000000000011","guest_name":"Lost contact","check_in":"2027-06-01","check_out":"2027-06-02","total_minor":10000,"initial_receipt":{"amount_minor":100,"kind":"rent_receipt","custodian":"owner","contact_id":"f3000000-0000-0000-0000-000000000011"}}'::jsonb,'reservation-create-discarded-contact-key-01');
    raise exception 'non-realtor contact_id was silently discarded';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform api.create_reservation('{"property_id":"f2000000-0000-0000-0000-000000000011","guest_name":"Overlap","check_in":"2027-05-03","check_out":"2027-05-05","total_minor":10000}'::jsonb,'reservation-create-overlap-key-01');
    raise exception 'overlapping reservation accepted';
  exception when exclusion_violation then null;
  end;
  begin
    perform api.create_reservation('{"property_id":"f2000000-0000-0000-0000-000000000011","guest_name":"Capacity","guest_count":2,"check_in":"2027-06-01","check_out":"2027-06-02","total_minor":10000}'::jsonb,'reservation-create-capacity-key-01');
    raise exception 'capacity override omission accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform api.create_reservation('{"property_id":"f2000000-0000-0000-0000-000000000011","guest_name":"Zero","check_in":"2027-06-01","check_out":"2027-06-02","total_minor":0}'::jsonb,'reservation-create-zero-key-01');
    raise exception 'unconfirmed zero quote accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform api.create_reservation('{"property_id":"f2000000-0000-0000-0000-000000000011","guest_name":"Hold","check_in":"2027-06-01","check_out":"2027-06-02","total_minor":10000,"status":"hold"}'::jsonb,'reservation-create-hold-key-01');
    raise exception 'hold without duration accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform api.create_reservation('{"property_id":"f2000000-0000-0000-0000-000000000011","guest_name":"Wrong contact","check_in":"2027-06-01","check_out":"2027-06-02","total_minor":10000,"initial_receipt":{"amount_minor":100,"kind":"rent_receipt","custodian":"realtor","contact_id":"f3000000-0000-0000-0000-000000000012"}}'::jsonb,'reservation-create-cross-contact-key-01');
    raise exception 'cross-owner receipt contact accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform api.create_reservation('{"property_id":"f2000000-0000-0000-0000-000000000012","guest_name":"Draft","check_in":"2027-06-01","check_out":"2027-06-02","total_minor":10000}'::jsonb,'reservation-create-draft-key-01');
    raise exception 'draft subscription accepted';
  exception when insufficient_privilege then null;
  end;
  begin
    perform api.create_reservation('{"property_id":"f2000000-0000-0000-0000-000000000013","guest_name":"Other owner","check_in":"2027-06-01","check_out":"2027-06-02","total_minor":10000}'::jsonb,'reservation-create-owner-b-key-01');
    raise exception 'cross-owner property accepted';
  exception when no_data_found then null;
  end;
  if api.create_reservation('{"property_id":"f2000000-0000-0000-0000-000000000011","guest_name":"Deposit guest","check_in":"2027-07-01","check_out":"2027-07-02","total_minor":20000,"initial_receipt":{"amount_minor":5000,"kind":"deposit_receipt","custodian":"realtor","contact_id":"f3000000-0000-0000-0000-000000000011"}}'::jsonb,'reservation-create-deposit-key-01')->>'initial_receipt_id' is null then
    raise exception 'deposit receipt was not acknowledged';
  end if;
end $$;
reset role;
set local role authenticated;
set local request.jwt.claim.sub='f0000000-0000-0000-0000-000000000013';
do $$
begin
  if api.create_reservation('{"property_id":"f2000000-0000-0000-0000-000000000011","guest_name":"Manager","check_in":"2027-08-01","check_out":"2027-08-02","total_minor":5000}'::jsonb,'reservation-create-manager-key-01')->>'reservation_id' is null then
    raise exception 'active daily manager denied on assigned property';
  end if;
end $$;
reset role;
do $$
begin
  if (select count(*) from app_private.reservations where owner_account_id='f1000000-0000-0000-0000-000000000011')<>3
     or (select count(*) from app_private.reservation_placements where owner_account_id='f1000000-0000-0000-0000-000000000011')<>3
     or (select count(*) from app_private.occupancy where owner_account_id='f1000000-0000-0000-0000-000000000011' and active)<>3
     or (select count(*) from app_private.rent_entries where owner_account_id='f1000000-0000-0000-0000-000000000011')<>2
     or (select count(*) from app_private.realtor_accounts where owner_account_id='f1000000-0000-0000-0000-000000000011')<>1
     or (select count(*) from app_private.outbox where owner_account_id='f1000000-0000-0000-0000-000000000011' and event_kind='reservation.created')<>3 then
    raise exception 'reservation/placement/occupancy/receipt/commission/outbox atomicity mismatch';
  end if;
  if not exists (select 1 from app_private.reservations where guest_name='A Guest' and check_in_time='15:00' and check_out_time='11:00') then
    raise exception 'property check-in/out defaults mismatch';
  end if;
  if not exists (select 1 from app_private.occupancy o join app_private.reservations r on r.current_placement_id=o.placement_id
       where r.guest_name='A Guest' and o.date_range=daterange('2027-05-01','2027-05-04','[)')) then
    raise exception 'reservation occupancy range is not half-open/current';
  end if;
  if not exists (select 1 from app_private.rent_entries where kind='rent_receipt' and amount_minor=10000 and custodian='owner') then
    raise exception 'initial rent receipt mapping mismatch';
  end if;
  if not exists (select 1 from app_private.rent_entries where kind='deposit_receipt' and amount_minor=5000 and custodian='realtor') then
    raise exception 'initial deposit receipt mapping mismatch';
  end if;
  if not exists (select 1 from app_private.realtor_accounts where basis_minor=30000 and percentage_basis_points=1000 and earned_minor=3000) then
    raise exception 'commission basis or half-up result mismatch';
  end if;
  if not exists (select 1 from app_private.idempotency_keys where key='reservation-create-owner-key-01' and response_status=201 and expires_at-created_at=interval '24 hours') then
    raise exception 'idempotency status or 24 hour expiry mismatch';
  end if;
  if not exists (select 1 from app_private.rent_entries
      where reservation_id=(select result_id from app_private.idempotency_keys where key='reservation-create-owner-key-01')
        and custodian='owner' and custodian_user_id='f0000000-0000-0000-0000-000000000011'
        and realtor_contact_id is null) then
    raise exception 'owner receipt custodian identity was not recorded from the selected custodian';
  end if;
  if exists (select 1 from app_private.idempotency_keys where key in ('reservation-create-overlap-key-01','reservation-create-capacity-key-01','reservation-create-zero-key-01','reservation-create-hold-key-01','reservation-create-cross-contact-key-01','reservation-create-draft-key-01','reservation-create-owner-b-key-01')) then
    raise exception 'rejected request left idempotency residue';
  end if;
end $$;
rollback;
begin;
set local role authenticated;
set local request.jwt.claim.sub='';
do $$
begin
  begin
    perform api.create_reservation('{}'::jsonb,'reservation-create-anonymous-key-01');
    raise exception 'unauthenticated create succeeded';
  exception when sqlstate '28000' then null;
  end;
end $$;
rollback;
