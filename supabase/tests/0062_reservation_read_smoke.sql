-- Local role-switched read fixture. Synthetic current-placement pointer change only;
-- this does not validate the full move transaction or Supabase JWT/Data API.
do $$
begin
  if has_table_privilege('authenticated','app_private.reservations','SELECT')
     or has_table_privilege('authenticated','app_private.reservation_placements','SELECT')
     or has_function_privilege('anon','api.read_current_reservation(uuid)','EXECUTE') then
    raise exception 'reservation base or anon RPC access leaked';
  end if;
  if not exists (
    select 1 from pg_proc p
    where p.oid='api.read_current_reservation(uuid)'::regprocedure
      and p.proowner='app_executor'::regrole and p.prosecdef
      and p.proconfig @> array['search_path=""']::text[]
  ) then raise exception 'reservation RPC owner/definer/search_path mismatch'; end if;
end $$;

insert into auth.users(id) values
 ('a0000000-0000-0000-0000-000000000001'),
 ('b0000000-0000-0000-0000-000000000001'),
 ('c0000000-0000-0000-0000-000000000001'),
 ('d0000000-0000-0000-0000-000000000001');
insert into app_private.owner_accounts(id,owner_user_id)
 values ('10000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001');
insert into app_private.properties(id,owner_account_id,name,area) values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Source','Bakı'),
 ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Target','Bakı');
insert into app_private.property_memberships(owner_account_id,property_id,user_id,permission,granted_by) values
 ('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000001','daily','a0000000-0000-0000-0000-000000000001'),
 ('10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000001','daily','a0000000-0000-0000-0000-000000000001');

begin;
set constraints all deferred;
insert into app_private.reservations(
 id,owner_account_id,property_id,current_placement_id,guest_name,guest_phone,
 check_in,check_out,check_in_time,check_out_time,total_minor
) values (
 '40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
 '20000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001',
 'Guest A','+994501234567','2027-05-01','2027-05-05','14:00','12:00',10000
);
insert into app_private.reservation_placements(
 id,owner_account_id,property_id,reservation_id,placement_no,
 check_in_snapshot,check_out_snapshot,effective_from,created_by
) values (
 '50000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
 '20000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',
 1,'2027-05-01','2027-05-05',now(),'a0000000-0000-0000-0000-000000000001'
);
commit;

begin;
set local role authenticated;
set local request.jwt.claim.sub='b0000000-0000-0000-0000-000000000001';
do $$ begin
  if (select count(*) from api.read_current_reservation('40000000-0000-0000-0000-000000000001')) <> 1
     or (select guest_name from api.read_current_reservation('40000000-0000-0000-0000-000000000001')) <> 'Guest A' then
    raise exception 'source manager cannot read current reservation';
  end if;
  begin
    execute 'select guest_name from app_private.reservations limit 1';
    raise exception 'authenticated raw reservation read unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub='c0000000-0000-0000-0000-000000000001';
do $$ begin
  if (select count(*) from api.read_current_reservation('40000000-0000-0000-0000-000000000001')) <> 0 then
    raise exception 'target manager saw source reservation early';
  end if;
end $$;
rollback;

-- Simulates only the read-relevant pointer update. The production move RPC
-- must additionally enforce locks, occupancy, task, transfer and link revocation.
begin;
set constraints all deferred;
insert into app_private.reservation_placements(
 id,owner_account_id,property_id,reservation_id,placement_no,
 check_in_snapshot,check_out_snapshot,effective_from,created_by
) values (
 '60000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
 '30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',
 2,'2027-05-01','2027-05-05',now(),'a0000000-0000-0000-0000-000000000001'
);
update app_private.reservation_placements set effective_to=now()
 where id='50000000-0000-0000-0000-000000000001';
update app_private.reservations
 set property_id='30000000-0000-0000-0000-000000000001',
     current_placement_id='60000000-0000-0000-0000-000000000001',
     version=version+1
 where id='40000000-0000-0000-0000-000000000001';
commit;

begin;
set local role authenticated;
set local request.jwt.claim.sub='b0000000-0000-0000-0000-000000000001';
do $$ begin
  if (select count(*) from api.read_current_reservation('40000000-0000-0000-0000-000000000001')) <> 0 then
    raise exception 'source-only manager saw moved current guest';
  end if;
end $$;
rollback;

begin;
set local role app_executor;
set local request.jwt.claim.sub='b0000000-0000-0000-0000-000000000001';
do $$ begin
  if (select count(*) from app_private.reservation_placements
      where id='50000000-0000-0000-0000-000000000001') <> 0 then
    raise exception 'source-only executor saw historical placement';
  end if;
end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub='c0000000-0000-0000-0000-000000000001';
do $$ begin
  if (select count(*) from api.read_current_reservation('40000000-0000-0000-0000-000000000001')) <> 1
     or (select placement_id from api.read_current_reservation('40000000-0000-0000-0000-000000000001'))
        <> '60000000-0000-0000-0000-000000000001'::uuid then
    raise exception 'target manager cannot read moved current reservation';
  end if;
end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub='d0000000-0000-0000-0000-000000000001';
do $$ begin
  if (select count(*) from api.read_current_reservation('40000000-0000-0000-0000-000000000001')) <> 0
     or (select count(*) from api.read_current_reservation('90000000-0000-0000-0000-000000000001')) <> 0
     or (select count(*) from api.read_current_reservation(null)) <> 0 then
    raise exception 'unauthorized/unknown reservation response not neutral';
  end if;
end $$;
rollback;
