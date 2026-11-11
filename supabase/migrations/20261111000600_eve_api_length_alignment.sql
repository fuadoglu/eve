-- EVE-006.2: align directly/aliased API string limits with the DB contract.
-- Applied migration 001 is immutable. PostgreSQL rejects overlong existing rows;
-- no value is silently truncated during this forward migration. One DO
-- statement makes a late-table failure roll back every earlier ALTER.
do $$
begin
  alter table app_private.profiles
    alter column display_name type varchar(100),
    alter column phone type varchar(16);
  alter table app_private.manager_invites
    alter column normalized_email type varchar(254);
  alter table app_private.contacts
    alter column phone type varchar(16);
  alter table app_private.reservations
    alter column guest_name type varchar(150),
    alter column guest_phone type varchar(16),
    alter column private_note type varchar(2000);
  alter table app_private.recurring_expenses
    alter column note type varchar(160);
  alter table app_private.tasks
    alter column title type varchar(160),
    alter column description type varchar(2000);
  alter table app_private.inventory_items
    alter column model type varchar(150),
    alter column serial_number type varchar(150);
  alter table app_private.inspection_events
    alter column handover_key type varchar(150);
  alter table app_private.inspection_room_answers
    alter column reason type varchar(500);
  alter table app_private.inspection_submissions
    alter column claimed_name type varchar(100);
  alter table app_private.guide_versions
    alter column title type varchar(160);
  alter table app_private.push_subscriptions
    alter column auth_key type varchar(128);
end $$;
