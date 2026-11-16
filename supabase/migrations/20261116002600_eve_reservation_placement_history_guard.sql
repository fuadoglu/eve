-- Reservation placement history is append-only except for its one-way close.
create function app_private.guard_reservation_placement_history()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '23000', message = 'reservation_placement_history_is_immutable';
  end if;

  if row(
       new.id, new.owner_account_id, new.property_id, new.reservation_id,
       new.placement_no, new.check_in_snapshot, new.check_out_snapshot,
       new.effective_from, new.created_by, new.created_at
     ) is distinct from row(
       old.id, old.owner_account_id, old.property_id, old.reservation_id,
       old.placement_no, old.check_in_snapshot, old.check_out_snapshot,
       old.effective_from, old.created_by, old.created_at
     ) then
    raise exception using errcode = '23000', message = 'reservation_placement_history_is_immutable';
  end if;

  if old.effective_to is not null
     or new.effective_to is null
     or new.effective_to <= old.effective_from then
    raise exception using errcode = '23000', message = 'reservation_placement_close_once_violation';
  end if;

  return new;
end;
$$;

revoke all on function app_private.guard_reservation_placement_history() from public, anon, authenticated;

create trigger reservation_placements_history_guard
before update or delete on app_private.reservation_placements
for each row execute function app_private.guard_reservation_placement_history();
