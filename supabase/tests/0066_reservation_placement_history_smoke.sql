-- PostgreSQL 17 placement-history guard and current-placement permission regression.
-- The pointer change below is a synthetic fixture, not the reservation move RPC.
begin;
set constraints all deferred;

insert into auth.users(id) values
  ('f6000000-0000-0000-0000-000000000001'),
  ('f6000000-0000-0000-0000-000000000002'),
  ('f6000000-0000-0000-0000-000000000003'),
  ('f6000000-0000-0000-0000-000000000004');
insert into app_private.owner_accounts(id,owner_user_id)
values ('f6100000-0000-0000-0000-000000000001','f6000000-0000-0000-0000-000000000001');
insert into app_private.properties(id,owner_account_id,name,area) values
  ('f6200000-0000-0000-0000-000000000001','f6100000-0000-0000-0000-000000000001','Source','Bakı'),
  ('f6200000-0000-0000-0000-000000000002','f6100000-0000-0000-0000-000000000001','Target','Bakı');
insert into app_private.property_memberships(owner_account_id,property_id,user_id,permission,granted_by) values
  ('f6100000-0000-0000-0000-000000000001','f6200000-0000-0000-0000-000000000001','f6000000-0000-0000-0000-000000000002','daily','f6000000-0000-0000-0000-000000000001'),
  ('f6100000-0000-0000-0000-000000000001','f6200000-0000-0000-0000-000000000002','f6000000-0000-0000-0000-000000000003','daily','f6000000-0000-0000-0000-000000000001');
insert into app_private.reservations(
  id,owner_account_id,property_id,current_placement_id,guest_name,
  check_in,check_out,check_in_time,check_out_time,total_minor
) values (
  'f6300000-0000-0000-0000-000000000001','f6100000-0000-0000-0000-000000000001',
  'f6200000-0000-0000-0000-000000000001','f6400000-0000-0000-0000-000000000001',
  'Synthetic guest','2027-06-01','2027-06-04','14:00','12:00',10000
);
insert into app_private.reservation_placements(
  id,owner_account_id,property_id,reservation_id,placement_no,
  check_in_snapshot,check_out_snapshot,effective_from,created_by
) values (
  'f6400000-0000-0000-0000-000000000001','f6100000-0000-0000-0000-000000000001',
  'f6200000-0000-0000-0000-000000000001','f6300000-0000-0000-0000-000000000001',
  1,'2027-06-01','2027-06-04',statement_timestamp() - interval '1 hour','f6000000-0000-0000-0000-000000000001'
);
set constraints all immediate;

savepoint source_before_move;
set local role authenticated;
set local request.jwt.claim.sub='f6000000-0000-0000-0000-000000000002';
do $$ begin
  if (select count(*) from api.read_current_reservation('f6300000-0000-0000-0000-000000000001')) <> 1 then
    raise exception 'source manager cannot read current reservation';
  end if;
end $$;
rollback to savepoint source_before_move;
release savepoint source_before_move;

savepoint target_before_move;
set local role authenticated;
set local request.jwt.claim.sub='f6000000-0000-0000-0000-000000000003';
do $$ begin
  if (select count(*) from api.read_current_reservation('f6300000-0000-0000-0000-000000000001')) <> 0 then
    raise exception 'target manager read reservation before placement change';
  end if;
end $$;
rollback to savepoint target_before_move;
release savepoint target_before_move;

-- Synthetic pointer change exercises read isolation after a move-like state change.
insert into app_private.reservation_placements(
  id,owner_account_id,property_id,reservation_id,placement_no,
  check_in_snapshot,check_out_snapshot,effective_from,created_by
) values (
  'f6400000-0000-0000-0000-000000000002','f6100000-0000-0000-0000-000000000001',
  'f6200000-0000-0000-0000-000000000002','f6300000-0000-0000-0000-000000000001',
  2,'2027-06-01','2027-06-04',statement_timestamp(),'f6000000-0000-0000-0000-000000000001'
);
update app_private.reservation_placements
set effective_to=statement_timestamp()
where id='f6400000-0000-0000-0000-000000000001';
update app_private.reservations
set property_id='f6200000-0000-0000-0000-000000000002',
    current_placement_id='f6400000-0000-0000-0000-000000000002',version=version+1
where id='f6300000-0000-0000-0000-000000000001';

savepoint source_after_move;
set local role authenticated;
set local request.jwt.claim.sub='f6000000-0000-0000-0000-000000000002';
do $$ begin
  if (select count(*) from api.read_current_reservation('f6300000-0000-0000-0000-000000000001')) <> 0 then
    raise exception 'source-only manager saw moved current guest';
  end if;
end $$;
rollback to savepoint source_after_move;
release savepoint source_after_move;

savepoint target_after_move;
set local role authenticated;
set local request.jwt.claim.sub='f6000000-0000-0000-0000-000000000003';
do $$ begin
  if (select count(*) from api.read_current_reservation('f6300000-0000-0000-0000-000000000001')) <> 1
     or (select placement_id from api.read_current_reservation('f6300000-0000-0000-0000-000000000001'))
        is distinct from 'f6400000-0000-0000-0000-000000000002'::uuid then
    raise exception 'target manager cannot read moved current reservation';
  end if;
end $$;
rollback to savepoint target_after_move;
release savepoint target_after_move;

savepoint history_scope;
set local role authenticated;
set local request.jwt.claim.sub='f6000000-0000-0000-0000-000000000002';
do $$ begin
  begin
    perform 1 from app_private.reservation_placements
      where id='f6400000-0000-0000-0000-000000000001';
    raise exception 'authenticated client unexpectedly read private placement table';
  exception when insufficient_privilege then null;
  end;
end $$;
rollback to savepoint history_scope;
release savepoint history_scope;

do $$ begin
  begin
    update app_private.reservation_placements
      set check_out_snapshot=check_out_snapshot + 1
      where id='f6400000-0000-0000-0000-000000000002';
    raise exception 'placement snapshot mutation unexpectedly succeeded';
  exception when integrity_constraint_violation then null;
  end;

  begin
    update app_private.reservation_placements
      set effective_to=effective_from
      where id='f6400000-0000-0000-0000-000000000002';
    raise exception 'placement close at effective_from unexpectedly succeeded';
  exception when integrity_constraint_violation then null;
  end;

  update app_private.reservation_placements
    set effective_to=effective_from + interval '1 minute'
    where id='f6400000-0000-0000-0000-000000000002';

  if not exists (select 1 from app_private.reservation_placements
      where id='f6400000-0000-0000-0000-000000000002'
        and check_out_snapshot='2027-06-04' and effective_to>effective_from) then
    raise exception 'valid one-way placement close did not preserve snapshot';
  end if;

  begin
    update app_private.reservation_placements
      set effective_to=effective_to + interval '1 second'
      where id='f6400000-0000-0000-0000-000000000002';
    raise exception 'placement second close unexpectedly succeeded';
  exception when integrity_constraint_violation then null;
  end;

  begin
    delete from app_private.reservation_placements where id='f6400000-0000-0000-0000-000000000001';
    raise exception 'placement delete unexpectedly succeeded';
  exception when integrity_constraint_violation then null;
  end;
end $$;

rollback;
