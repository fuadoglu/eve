-- EVE-006.2: API enum-like varchar values and inventory unit default.
-- One statement fails atomically if existing rows violate the contract.
do $$
begin
  alter table app_private.contacts
    add constraint contacts_service_type_allowed
      check (service_type in ('cleaner','repair','realtor','other'));
  alter table app_private.inventory_items
    alter column unit set default 'piece',
    add constraint inventory_items_unit_allowed
      check (unit in ('piece','set','liter','kg','pack'));
  alter table app_private.media_assets
    add constraint media_assets_mime_allowed
      check (mime in ('image/jpeg','image/png','image/webp','video/mp4',
                     'audio/webm','audio/mp4','application/pdf'));
  alter table app_private.support_requests
    add constraint support_requests_category_allowed
      check (category in ('login','billing','usage','bug','other'));
end $$;
