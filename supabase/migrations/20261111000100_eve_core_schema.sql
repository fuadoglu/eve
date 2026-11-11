-- EVE-006.1: data-dictionary.json v2.0.0 structural schema.
-- Domain transitions, cross-row triggers, RLS policies and RPC are EVE-006.2/006.3.
create extension if not exists btree_gist;
create schema if not exists app_private;
create schema if not exists api;
revoke all on schema app_private from public, anon, authenticated;
revoke all on schema api from public, anon, authenticated;

create type app_private.permission as enum ('daily', 'full');
create type app_private.reservation_state as enum ('hold', 'confirmed', 'checked_in', 'completed', 'cancelled', 'no_show');
create type app_private.task_state as enum ('open', 'accepted', 'reported_done', 'completed', 'cancelled');
create type app_private.task_kind as enum ('cleaning', 'repair', 'purchase', 'other');
create type app_private.readiness as enum ('ready', 'cleaning_pending', 'attention_required');
create type app_private.expense_approval as enum ('proposed', 'approved', 'rejected');
create type app_private.expense_payment as enum ('unpaid', 'partial', 'paid');
create type app_private.expense_category as enum ('utilities', 'building_service', 'cleaning', 'repair', 'purchase', 'consumables', 'other');
create type app_private.rent_kind as enum ('rent_receipt', 'rent_refund', 'deposit_receipt', 'deposit_return', 'deposit_to_rent', 'deposit_to_damage', 'reversal');
create type app_private.custodian as enum ('owner', 'manager', 'realtor');
create type app_private.inventory_state as enum ('ok', 'needs_repair', 'damaged', 'missing');
create type app_private.inventory_condition as enum ('ok', 'missing', 'damaged', 'unable');
create type app_private.inspection_side as enum ('giver', 'receiver');
create type app_private.submission_state as enum ('draft', 'completed');
create type app_private.guide_classification as enum ('general_public', 'safety_public', 'guest_private');
create type app_private.locale as enum ('az', 'ru', 'en');
create type app_private.media_classification as enum ('public_property', 'public_guide', 'private_guest', 'private_receipt', 'private_inspection', 'private_task');
create type app_private.media_state as enum ('pending', 'validated', 'rejected', 'deleted');
create type app_private.link_kind as enum ('task', 'inspection', 'guest_guide');
create type app_private.subscription_state as enum ('draft', 'trialing', 'active', 'expired');
create type app_private.billing_plan as enum ('monthly', 'yearly');
create type app_private.order_state as enum ('created', 'pending', 'verified_paid', 'entitlement_applied', 'failed', 'cancelled', 'expired', 'refund_review', 'refunded', 'chargeback_review');
create type app_private.event_verification as enum ('received', 'verified', 'rejected', 'applied');
create type app_private.job_state as enum ('pending', 'processing', 'completed', 'failed');
create type app_private.invite_state as enum ('pending', 'accepted', 'revoked', 'expired');
create type app_private.commission_kind as enum ('fixed', 'percentage');
create type app_private.settlement_kind as enum ('realtor_to_owner', 'owner_to_realtor', 'commission_offset');
create type app_private.import_kind as enum ('reservations', 'inventory');
create type app_private.import_state as enum ('uploaded', 'preview_ready', 'invalid', 'committing', 'completed', 'failed');
create type app_private.support_state as enum ('open', 'in_progress', 'resolved');
create type app_private.notification_channel as enum ('email', 'push', 'in_app');
create type app_private.property_type as enum ('apartment', 'house', 'villa', 'other');

create table app_private.profiles (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null,
  display_name varchar(120),
  phone varchar(20),
  locale app_private.locale not null default 'az',
  session_revoked_before timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (user_id),
  check (version >= 1)
);
alter table app_private.profiles enable row level security;
alter table app_private.profiles force row level security;

create table app_private.owner_accounts (
  id uuid not null default gen_random_uuid(),
  owner_user_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (owner_user_id),
  check (version >= 1)
);
alter table app_private.owner_accounts enable row level security;
alter table app_private.owner_accounts force row level security;

create table app_private.properties (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  name varchar(120) not null,
  area varchar(160) not null,
  property_type app_private.property_type not null default 'apartment',
  private_address varchar(500),
  room_count integer not null default 0,
  bed_count integer not null default 0,
  max_guests integer not null default 1,
  default_check_in time not null default '14:00',
  default_check_out time not null default '12:00',
  nightly_rate_minor bigint,
  settings jsonb not null default '{}'::jsonb,
  readiness app_private.readiness not null default 'ready',
  inventory_version integer not null default 1,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (id, owner_account_id),
  check (room_count >= 0),
  check (bed_count >= 0),
  check (max_guests >= 1),
  check (nightly_rate_minor >= 0),
  check (nightly_rate_minor <= 9007199254740991),
  check (jsonb_typeof(settings) = 'object'),
  check (inventory_version >= 1),
  check (version >= 1),
  constraint properties_nightly_rate_minor_safe check (nightly_rate_minor IS NULL OR (nightly_rate_minor >= 0 AND nightly_rate_minor <= 9007199254740991))
);
alter table app_private.properties enable row level security;
alter table app_private.properties force row level security;

create table app_private.property_memberships (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  user_id uuid not null,
  permission app_private.permission not null,
  revoked_at timestamptz,
  granted_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (property_id, user_id),
  unique (id, property_id, owner_account_id),
  check (version >= 1)
);
alter table app_private.property_memberships enable row level security;
alter table app_private.property_memberships force row level security;

create table app_private.manager_invites (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  normalized_email varchar(320) not null,
  token_hash varchar(64) not null,
  expires_at timestamptz not null,
  state app_private.invite_state not null default 'pending',
  accepted_user_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (token_hash),
  unique (id, owner_account_id),
  check (version >= 1),
  constraint invite_expiry check (expires_at > created_at)
);
alter table app_private.manager_invites enable row level security;
alter table app_private.manager_invites force row level security;

create table app_private.invite_properties (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  invite_id uuid not null,
  permission app_private.permission not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (invite_id, property_id),
  unique (id, property_id, owner_account_id),
  check (version >= 1)
);
alter table app_private.invite_properties enable row level security;
alter table app_private.invite_properties force row level security;

create table app_private.contacts (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  name varchar(120) not null,
  phone varchar(20) not null,
  service_type varchar(80) not null,
  private_note varchar(2000),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (id, owner_account_id),
  check (version >= 1)
);
alter table app_private.contacts enable row level security;
alter table app_private.contacts force row level security;

create table app_private.contact_properties (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  contact_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (contact_id, property_id),
  unique (id, property_id, owner_account_id),
  check (version >= 1)
);
alter table app_private.contact_properties enable row level security;
alter table app_private.contact_properties force row level security;

create table app_private.reservations (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  current_placement_id uuid not null,
  guest_name varchar(160) not null,
  guest_phone varchar(20),
  check_in date not null,
  check_out date not null,
  check_in_time time not null,
  check_out_time time not null,
  guest_count integer not null default 1,
  state app_private.reservation_state not null default 'confirmed',
  total_minor bigint not null,
  zero_price_confirmed boolean not null default false,
  hold_expires_at timestamptz,
  actual_check_in_at timestamptz,
  actual_check_out_at timestamptz,
  private_note varchar(3000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (id, property_id, owner_account_id),
  unique (id, owner_account_id),
  check (guest_count >= 1),
  check (total_minor >= 0),
  check (total_minor <= 9007199254740991),
  check (version >= 1),
  constraint dates check (check_out > check_in),
  constraint zero_price check (total_minor>0 OR zero_price_confirmed),
  constraint hold_expiry check (state <> 'hold' OR hold_expires_at IS NOT NULL),
  constraint reservations_total_minor_safe check (total_minor IS NULL OR (total_minor >= 0 AND total_minor <= 9007199254740991))
);
alter table app_private.reservations enable row level security;
alter table app_private.reservations force row level security;

create table app_private.reservation_placements (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  reservation_id uuid not null,
  placement_no integer not null,
  check_in_snapshot date not null,
  check_out_snapshot date not null,
  effective_from timestamptz not null,
  effective_to timestamptz,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  primary key (id),
  unique (reservation_id, placement_no),
  unique (id, reservation_id, property_id, owner_account_id),
  unique (id, property_id, owner_account_id),
  check (placement_no >= 1),
  constraint placement_dates check (check_out_snapshot > check_in_snapshot)
);
alter table app_private.reservation_placements enable row level security;
alter table app_private.reservation_placements force row level security;

create table app_private.reservation_attribution_transfers (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  reservation_id uuid not null,
  from_placement_id uuid not null,
  to_placement_id uuid not null,
  rent_net_snapshot_minor bigint not null,
  deposit_net_snapshot_minor bigint not null,
  actor_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (id),
  unique (to_placement_id),
  unique (id, owner_account_id),
  check (rent_net_snapshot_minor >= 0),
  check (rent_net_snapshot_minor <= 9007199254740991),
  check (deposit_net_snapshot_minor >= 0),
  check (deposit_net_snapshot_minor <= 9007199254740991),
  constraint reservation_attribution_transfers_rent_net_snapshot_minor_safe check (rent_net_snapshot_minor IS NULL OR (rent_net_snapshot_minor >= 0 AND rent_net_snapshot_minor <= 9007199254740991)),
  constraint reservation_attribution_transfers_deposit_net_minor_safe check (deposit_net_snapshot_minor IS NULL OR (deposit_net_snapshot_minor >= 0 AND deposit_net_snapshot_minor <= 9007199254740991))
);
alter table app_private.reservation_attribution_transfers enable row level security;
alter table app_private.reservation_attribution_transfers force row level security;

create table app_private.manual_blocks (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  check_in date not null,
  check_out date not null,
  reason varchar(1000),
  released_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (id, property_id, owner_account_id),
  check (version >= 1),
  constraint block_dates check (check_out > check_in)
);
alter table app_private.manual_blocks enable row level security;
alter table app_private.manual_blocks force row level security;

create table app_private.occupancy (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  placement_id uuid,
  manual_block_id uuid,
  date_range daterange not null,
  active boolean not null default true,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (id),
  unique (id, property_id, owner_account_id),
  constraint one_source check (num_nonnulls(placement_id,manual_block_id)=1),
  constraint finite_range check (NOT isempty(date_range) AND NOT lower_inf(date_range) AND NOT upper_inf(date_range) AND lower_inc(date_range) AND NOT upper_inc(date_range))
);
alter table app_private.occupancy enable row level security;
alter table app_private.occupancy force row level security;

create table app_private.rent_entries (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  reservation_id uuid not null,
  placement_id uuid not null,
  kind app_private.rent_kind not null,
  amount_minor bigint not null,
  custodian app_private.custodian not null,
  custodian_user_id uuid,
  realtor_contact_id uuid,
  original_entry_id uuid,
  actor_id uuid not null,
  occurred_at timestamptz not null,
  note varchar(1000),
  created_at timestamptz not null default now(),
  operation_key varchar(64) not null,
  primary key (id),
  unique (id, property_id, owner_account_id),
  unique (id, owner_account_id),
  unique (owner_account_id, operation_key),
  check (amount_minor > 0),
  check (amount_minor <= 9007199254740991),
  constraint realtor_required check ((custodian='realtor')=(realtor_contact_id IS NOT NULL)),
  constraint rent_entries_amount_minor_safe check (amount_minor > 0 AND amount_minor <= 9007199254740991),
  constraint custodian_identity check ((custodian='realtor' AND realtor_contact_id IS NOT NULL AND custodian_user_id IS NULL) OR (custodian IN ('owner','manager') AND custodian_user_id IS NOT NULL AND realtor_contact_id IS NULL)),
  constraint original_required check ((kind IN ('rent_refund','deposit_return','deposit_to_rent','deposit_to_damage','reversal'))=(original_entry_id IS NOT NULL))
);
alter table app_private.rent_entries enable row level security;
alter table app_private.rent_entries force row level security;

create table app_private.realtor_accounts (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  reservation_id uuid not null,
  contact_id uuid not null,
  commission_kind app_private.commission_kind not null,
  fixed_minor bigint,
  percentage_basis_points integer,
  basis_minor bigint not null,
  earned_minor bigint not null,
  cancel_reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (reservation_id),
  unique (id, reservation_id, owner_account_id),
  unique (id, owner_account_id),
  check (fixed_minor >= 0),
  check (fixed_minor <= 9007199254740991),
  check (percentage_basis_points >= 0),
  check (basis_minor >= 0),
  check (basis_minor <= 9007199254740991),
  check (earned_minor >= 0),
  check (earned_minor <= 9007199254740991),
  check (version >= 1),
  constraint commission_shape check ((commission_kind='fixed' AND fixed_minor IS NOT NULL AND percentage_basis_points IS NULL) OR (commission_kind='percentage' AND fixed_minor IS NULL AND percentage_basis_points BETWEEN 0 AND 10000)),
  constraint realtor_accounts_fixed_minor_safe check (fixed_minor IS NULL OR (fixed_minor >= 0 AND fixed_minor <= 9007199254740991)),
  constraint realtor_accounts_basis_minor_safe check (basis_minor IS NULL OR (basis_minor >= 0 AND basis_minor <= 9007199254740991)),
  constraint realtor_accounts_earned_minor_safe check (earned_minor IS NULL OR (earned_minor >= 0 AND earned_minor <= 9007199254740991))
);
alter table app_private.realtor_accounts enable row level security;
alter table app_private.realtor_accounts force row level security;

create table app_private.realtor_settlements (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  realtor_account_id uuid not null,
  kind app_private.settlement_kind not null,
  amount_minor bigint not null,
  occurred_at timestamptz not null,
  actor_id uuid not null,
  created_at timestamptz not null default now(),
  reservation_id uuid not null,
  placement_id uuid not null,
  operation_key varchar(64) not null,
  primary key (id),
  unique (id, property_id, owner_account_id),
  unique (owner_account_id, operation_key),
  check (amount_minor > 0),
  check (amount_minor <= 9007199254740991),
  constraint realtor_settlements_amount_minor_safe check (amount_minor > 0 AND amount_minor <= 9007199254740991)
);
alter table app_private.realtor_settlements enable row level security;
alter table app_private.realtor_settlements force row level security;

create table app_private.expenses (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  category app_private.expense_category not null,
  total_minor bigint not null,
  approval app_private.expense_approval not null default 'proposed',
  payment_status app_private.expense_payment not null default 'unpaid',
  expense_date date not null,
  due_date date,
  contact_id uuid,
  source_task_id uuid,
  submitted_by uuid,
  submitted_link_id uuid,
  approved_by uuid,
  note varchar(2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (id, owner_account_id),
  check (total_minor > 0),
  check (total_minor <= 9007199254740991),
  check (version >= 1),
  constraint approved_actor check (approval <> 'approved' OR approved_by IS NOT NULL),
  constraint expenses_total_minor_safe check (total_minor IS NULL OR (total_minor >= 0 AND total_minor <= 9007199254740991))
);
alter table app_private.expenses enable row level security;
alter table app_private.expenses force row level security;

create table app_private.expense_allocations (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  expense_id uuid not null,
  amount_minor bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (expense_id, property_id),
  unique (id, property_id, owner_account_id),
  check (amount_minor > 0),
  check (amount_minor <= 9007199254740991),
  check (version >= 1),
  constraint expense_allocations_amount_minor_safe check (amount_minor IS NULL OR (amount_minor >= 0 AND amount_minor <= 9007199254740991))
);
alter table app_private.expense_allocations enable row level security;
alter table app_private.expense_allocations force row level security;

create table app_private.expense_payments (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  expense_id uuid not null,
  amount_minor bigint not null,
  occurred_at timestamptz not null,
  actor_id uuid not null,
  created_at timestamptz not null default now(),
  operation_key varchar(64) not null,
  primary key (id),
  unique (id, owner_account_id),
  unique (owner_account_id, operation_key),
  check (amount_minor > 0),
  check (amount_minor <= 9007199254740991),
  constraint expense_payments_amount_minor_safe check (amount_minor > 0 AND amount_minor <= 9007199254740991)
);
alter table app_private.expense_payments enable row level security;
alter table app_private.expense_payments force row level security;

create table app_private.recurring_expenses (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  category app_private.expense_category not null,
  suggested_minor bigint,
  day_of_month integer not null default 1,
  next_date date not null,
  enabled boolean not null default true,
  note varchar(1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (id, property_id, owner_account_id),
  check (suggested_minor >= 0),
  check (suggested_minor <= 9007199254740991),
  check (day_of_month >= 1),
  check (version >= 1),
  constraint day_limit check (day_of_month BETWEEN 1 AND 31),
  constraint recurring_expenses_suggested_minor_safe check (suggested_minor IS NULL OR (suggested_minor >= 0 AND suggested_minor <= 9007199254740991))
);
alter table app_private.recurring_expenses enable row level security;
alter table app_private.recurring_expenses force row level security;

create table app_private.tasks (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  reservation_id uuid,
  placement_id uuid,
  kind app_private.task_kind not null default 'other',
  title varchar(180) not null,
  description varchar(4000),
  due_at timestamptz not null,
  assignee_contact_id uuid,
  state app_private.task_state not null default 'open',
  accepted_at timestamptz,
  reported_done_at timestamptz,
  confirmed_at timestamptz,
  confirmed_by uuid,
  required_for_readiness boolean not null default false,
  inspection_event_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (id, property_id, owner_account_id),
  unique (id, owner_account_id),
  check (version >= 1),
  constraint reservation_pair check ((reservation_id IS NULL)=(placement_id IS NULL))
);
alter table app_private.tasks enable row level security;
alter table app_private.tasks force row level security;

create table app_private.rooms (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  name varchar(100) not null,
  position integer not null default 0,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (id, property_id, owner_account_id),
  check (position >= 0),
  check (version >= 1)
);
alter table app_private.rooms enable row level security;
alter table app_private.rooms force row level security;

create table app_private.inventory_items (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  room_id uuid not null,
  name varchar(160) not null,
  quantity numeric(12,3) not null default '1',
  unit varchar(20) not null default 'ədəd',
  state app_private.inventory_state not null default 'ok',
  consumable boolean not null default false,
  min_stock numeric(12,3),
  purchase_minor bigint,
  purchased_on date,
  warranty_until date,
  model varchar(160),
  serial_number varchar(160),
  note varchar(1000),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (id, property_id, owner_account_id),
  check (quantity >= 0),
  check (quantity <= 999999999.999),
  check (min_stock >= 0),
  check (purchase_minor >= 0),
  check (purchase_minor <= 9007199254740991),
  check (version >= 1),
  constraint inventory_items_purchase_minor_safe check (purchase_minor IS NULL OR (purchase_minor >= 0 AND purchase_minor <= 9007199254740991))
);
alter table app_private.inventory_items enable row level security;
alter table app_private.inventory_items force row level security;

create table app_private.inspection_days (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  local_date date not null,
  created_at timestamptz not null default now(),
  primary key (id),
  unique (property_id, local_date),
  unique (id, property_id, owner_account_id)
);
alter table app_private.inspection_days enable row level security;
alter table app_private.inspection_days force row level security;

create table app_private.inspection_events (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  day_id uuid not null,
  handover_key varchar(160) not null,
  reservation_id uuid,
  placement_id uuid,
  event_kind varchar(30) not null,
  due_at timestamptz not null,
  created_at timestamptz not null default now(),
  primary key (id),
  unique (property_id, handover_key),
  unique (id, property_id, owner_account_id),
  constraint event_kind check (event_kind IN ('check_in','check_out','manual')),
  constraint event_reservation_pair check ((reservation_id IS NULL)=(placement_id IS NULL))
);
alter table app_private.inspection_events enable row level security;
alter table app_private.inspection_events force row level security;

create table app_private.inspection_snapshots (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  event_id uuid not null,
  inventory_version integer not null,
  manifest jsonb not null,
  content_hash varchar(64) not null,
  created_at timestamptz not null default now(),
  primary key (id),
  unique (event_id),
  unique (id, property_id, owner_account_id),
  check (inventory_version >= 1),
  check (jsonb_typeof(manifest) = 'object')
);
alter table app_private.inspection_snapshots enable row level security;
alter table app_private.inspection_snapshots force row level security;

create table app_private.inspection_snapshot_rooms (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  snapshot_id uuid not null,
  source_room_id uuid not null,
  name varchar(100) not null,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  primary key (id),
  unique (snapshot_id, source_room_id),
  unique (id, property_id, owner_account_id),
  check (position >= 0)
);
alter table app_private.inspection_snapshot_rooms enable row level security;
alter table app_private.inspection_snapshot_rooms force row level security;

create table app_private.inspection_snapshot_items (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  snapshot_id uuid not null,
  snapshot_room_id uuid not null,
  source_item_id uuid not null,
  name varchar(160) not null,
  quantity numeric(12,3) not null,
  unit varchar(20) not null,
  state app_private.inventory_state not null,
  created_at timestamptz not null default now(),
  primary key (id),
  unique (snapshot_id, source_item_id),
  unique (id, snapshot_id, property_id, owner_account_id),
  unique (id, property_id, owner_account_id),
  check (quantity>=0)
);
alter table app_private.inspection_snapshot_items enable row level security;
alter table app_private.inspection_snapshot_items force row level security;

create table app_private.inspection_submissions (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  event_id uuid not null,
  snapshot_id uuid not null,
  side app_private.inspection_side not null,
  revision integer not null default 1,
  previous_submission_id uuid,
  claimed_name varchar(160),
  actor_user_id uuid,
  access_link_id uuid,
  state app_private.submission_state not null default 'draft',
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (event_id, side, revision),
  unique (id, property_id, owner_account_id),
  check (revision >= 1),
  check (version >= 1),
  constraint completed_identity check (state<>'completed' OR (completed_at IS NOT NULL AND (actor_user_id IS NOT NULL OR length(trim(claimed_name))>0)))
);
alter table app_private.inspection_submissions enable row level security;
alter table app_private.inspection_submissions force row level security;

create table app_private.inspection_room_answers (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  submission_id uuid not null,
  snapshot_room_id uuid not null,
  result varchar(20) not null,
  reason varchar(1000),
  confirmed_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (submission_id, snapshot_room_id),
  unique (id, property_id, owner_account_id),
  check (version >= 1),
  constraint room_result check (result IN ('ok','problems','unable')),
  constraint unable_reason check (result<>'unable' OR length(trim(reason))>0)
);
alter table app_private.inspection_room_answers enable row level security;
alter table app_private.inspection_room_answers force row level security;

create table app_private.inspection_answers (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  submission_id uuid not null,
  snapshot_item_id uuid not null,
  condition app_private.inventory_condition not null,
  actual_quantity numeric(12,3),
  note varchar(1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (submission_id, snapshot_item_id),
  unique (id, property_id, owner_account_id),
  check (actual_quantity>=0),
  check (version >= 1),
  constraint missing_quantity check (condition<>'missing' OR actual_quantity IS NOT NULL)
);
alter table app_private.inspection_answers enable row level security;
alter table app_private.inspection_answers force row level security;

create table app_private.guides (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  stable_slug varchar(80) not null,
  classification app_private.guide_classification not null,
  guidance_kind varchar(80) not null,
  primary_locale app_private.locale not null default 'az',
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (stable_slug),
  unique (id, property_id, owner_account_id),
  check (version >= 1)
);
alter table app_private.guides enable row level security;
alter table app_private.guides force row level security;

create table app_private.guide_versions (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  guide_id uuid not null,
  locale app_private.locale not null,
  content_version integer not null default 1,
  title varchar(180) not null,
  blocks jsonb not null default '[]'::jsonb,
  published_at timestamptz,
  published_by uuid,
  created_at timestamptz not null default now(),
  primary key (id),
  unique (guide_id, locale, content_version),
  unique (id, property_id, owner_account_id),
  check (content_version >= 1),
  check (jsonb_typeof(blocks) = 'array')
);
alter table app_private.guide_versions enable row level security;
alter table app_private.guide_versions force row level security;

create table app_private.public_pages (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  slug varchar(80) not null,
  enabled boolean not null default false,
  show_dates boolean not null default false,
  show_price boolean not null default false,
  show_map boolean not null default false,
  show_exact_address boolean not null default false,
  published_version integer not null default 0,
  published_snapshot jsonb not null,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (property_id),
  unique (slug),
  unique (id, property_id, owner_account_id),
  check (published_version >= 0),
  check (jsonb_typeof(published_snapshot) = 'object'),
  check (version >= 1)
);
alter table app_private.public_pages enable row level security;
alter table app_private.public_pages force row level security;

create table app_private.access_links (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  token_hash varchar(64) not null,
  kind app_private.link_kind not null,
  task_id uuid,
  inspection_event_id uuid,
  reservation_id uuid,
  placement_id uuid,
  side app_private.inspection_side,
  scopes jsonb not null default '[]'::jsonb,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (token_hash),
  unique (id, property_id, owner_account_id),
  check (jsonb_typeof(scopes) = 'array'),
  check (version >= 1),
  constraint link_target check ((kind='task' AND task_id IS NOT NULL AND inspection_event_id IS NULL AND reservation_id IS NULL AND placement_id IS NULL AND side IS NULL) OR (kind='inspection' AND task_id IS NULL AND inspection_event_id IS NOT NULL AND reservation_id IS NULL AND placement_id IS NULL AND side IS NOT NULL) OR (kind='guest_guide' AND task_id IS NULL AND inspection_event_id IS NULL AND reservation_id IS NOT NULL AND placement_id IS NOT NULL AND side IS NULL)),
  constraint link_expiry check (expires_at>created_at)
);
alter table app_private.access_links enable row level security;
alter table app_private.access_links force row level security;

create table app_private.media_assets (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  classification app_private.media_classification not null,
  bucket varchar(80) not null,
  object_key varchar(500) not null,
  mime varchar(100) not null,
  size_bytes bigint not null,
  duration_seconds integer,
  state app_private.media_state not null default 'pending',
  sha256 varchar(64),
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (bucket, object_key),
  unique (id, property_id, owner_account_id),
  check (size_bytes>0),
  check (size_bytes<=104857600),
  check (duration_seconds >= 0),
  check (version >= 1)
);
alter table app_private.media_assets enable row level security;
alter table app_private.media_assets force row level security;

create table app_private.media_bindings (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  media_asset_id uuid not null,
  task_id uuid,
  expense_id uuid,
  inspection_answer_id uuid,
  guide_version_id uuid,
  inventory_item_id uuid,
  public_property_gallery boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (id),
  unique (id, property_id, owner_account_id),
  constraint one_binding_target check (num_nonnulls(task_id,expense_id,inspection_answer_id,guide_version_id,inventory_item_id)+(CASE WHEN public_property_gallery THEN 1 ELSE 0 END)=1)
);
alter table app_private.media_bindings enable row level security;
alter table app_private.media_bindings force row level security;

create table app_private.trial_claims (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  started_at timestamptz not null,
  ends_at timestamptz not null,
  created_at timestamptz not null default now(),
  primary key (id),
  unique (owner_account_id),
  unique (property_id),
  unique (id, owner_account_id),
  constraint trial_duration check (ends_at=started_at+interval '7 days')
);
alter table app_private.trial_claims enable row level security;
alter table app_private.trial_claims force row level security;

create table app_private.subscriptions (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  state app_private.subscription_state not null default 'draft',
  current_end timestamptz,
  anchor_day integer,
  anchor_month integer,
  anchor_time time,
  anchor_timezone varchar(80) not null default 'Asia/Baku',
  auto_renew_opt_in boolean not null default false,
  opted_in_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (property_id),
  unique (id, property_id, owner_account_id),
  check (anchor_day >= 1),
  check (anchor_month >= 1),
  check (version >= 1),
  constraint anchor_bounds check ((anchor_day IS NULL OR anchor_day BETWEEN 1 AND 31) AND (anchor_month IS NULL OR anchor_month BETWEEN 1 AND 12))
);
alter table app_private.subscriptions enable row level security;
alter table app_private.subscriptions force row level security;

create table app_private.billing_orders (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  currency varchar(3) not null default 'AZN',
  amount_minor bigint not null,
  state app_private.order_state not null default 'created',
  provider_order_id varchar(160),
  provider_transaction_id varchar(160),
  verified_paid_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (provider_order_id),
  unique (provider_transaction_id),
  unique (id, owner_account_id),
  check (amount_minor > 0),
  check (amount_minor <= 9007199254740991),
  check (version >= 1),
  constraint azn_only check (currency='AZN'),
  constraint billing_orders_amount_minor_safe check (amount_minor IS NULL OR (amount_minor >= 0 AND amount_minor <= 9007199254740991))
);
alter table app_private.billing_orders enable row level security;
alter table app_private.billing_orders force row level security;

create table app_private.billing_order_lines (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  order_id uuid not null,
  plan app_private.billing_plan not null,
  price_minor bigint not null,
  entitlement_applied_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (id),
  unique (order_id, property_id),
  unique (id, property_id, owner_account_id),
  check (price_minor > 0),
  check (price_minor <= 9007199254740991),
  constraint catalog_price check ((plan='monthly' AND price_minor=999) OR (plan='yearly' AND price_minor=9999)),
  constraint billing_order_lines_price_minor_safe check (price_minor IS NULL OR (price_minor >= 0 AND price_minor <= 9007199254740991))
);
alter table app_private.billing_order_lines enable row level security;
alter table app_private.billing_order_lines force row level security;

create table app_private.subscription_periods (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  order_line_id uuid not null,
  plan app_private.billing_plan not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  anchor_day integer not null,
  anchor_month integer not null,
  created_at timestamptz not null default now(),
  primary key (id),
  unique (order_line_id),
  unique (id, property_id, owner_account_id),
  check (anchor_day >= 1),
  check (anchor_month >= 1),
  constraint period_range check (ends_at>starts_at)
);
alter table app_private.subscription_periods enable row level security;
alter table app_private.subscription_periods force row level security;

create table app_private.payment_events (
  id uuid not null default gen_random_uuid(),
  provider varchar(30) not null default 'payriff',
  event_key varchar(255) not null,
  billing_order_id uuid,
  payload_redacted jsonb not null,
  verification_state app_private.event_verification not null default 'received',
  verified_at timestamptz,
  rejection_code varchar(80),
  created_at timestamptz not null default now(),
  primary key (id),
  unique (provider, event_key),
  check (jsonb_typeof(payload_redacted) = 'object')
);
alter table app_private.payment_events enable row level security;
alter table app_private.payment_events force row level security;

create table app_private.idempotency_keys (
  id uuid not null default gen_random_uuid(),
  actor_scope varchar(160) not null,
  key varchar(128) not null,
  request_hash varchar(64) not null,
  operation_id varchar(100) not null,
  response_status integer,
  result_id uuid,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  primary key (id),
  unique (actor_scope, key),
  check (response_status >= 100)
);
alter table app_private.idempotency_keys enable row level security;
alter table app_private.idempotency_keys force row level security;

create table app_private.outbox (
  id uuid not null default gen_random_uuid(),
  event_kind varchar(100) not null,
  dedupe_key varchar(255) not null,
  recipient_user_id uuid,
  property_id uuid,
  owner_account_id uuid,
  payload jsonb not null,
  state app_private.job_state not null default 'pending',
  attempts integer not null default 0,
  next_attempt_at timestamptz not null,
  locked_until timestamptz,
  last_error_code varchar(100),
  created_at timestamptz not null default now(),
  primary key (id),
  unique (dedupe_key),
  check (jsonb_typeof(payload) = 'object'),
  check (attempts >= 0)
);
alter table app_private.outbox enable row level security;
alter table app_private.outbox force row level security;

create table app_private.audit_events (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid,
  property_id uuid,
  actor_user_id uuid,
  actor_link_id uuid,
  capability varchar(100) not null,
  resource_type varchar(100) not null,
  resource_id uuid not null,
  request_id varchar(100) not null,
  redacted_diff jsonb not null,
  reason varchar(1000),
  created_at timestamptz not null default now(),
  primary key (id),
  check (jsonb_typeof(redacted_diff) = 'object')
);
alter table app_private.audit_events enable row level security;
alter table app_private.audit_events force row level security;

create table app_private.support_requests (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null,
  owner_account_id uuid,
  category varchar(80) not null,
  message varchar(4000) not null,
  state app_private.support_state not null default 'open',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  check (version >= 1)
);
alter table app_private.support_requests enable row level security;
alter table app_private.support_requests force row level security;

create table app_private.notification_preferences (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null,
  preferences jsonb not null,
  quiet_start time not null default '22:00',
  quiet_end time not null default '08:00',
  timezone varchar(80) not null default 'Asia/Baku',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (user_id),
  check (jsonb_typeof(preferences) = 'object'),
  check (version >= 1)
);
alter table app_private.notification_preferences enable row level security;
alter table app_private.notification_preferences force row level security;

create table app_private.push_subscriptions (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null,
  endpoint varchar(2000) not null,
  p256dh varchar(255) not null,
  auth_key varchar(255) not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (endpoint),
  check (version >= 1)
);
alter table app_private.push_subscriptions enable row level security;
alter table app_private.push_subscriptions force row level security;

create table app_private.import_jobs (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  requested_by uuid not null,
  kind app_private.import_kind not null,
  state app_private.import_state not null default 'uploaded',
  file_hash varchar(64) not null,
  preview_hash varchar(64),
  preview jsonb,
  row_count integer not null default 0,
  storage_key varchar(500),
  committed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (id, owner_account_id),
  check (jsonb_typeof(preview) = 'object'),
  check (row_count >= 0),
  check (version >= 1)
);
alter table app_private.import_jobs enable row level security;
alter table app_private.import_jobs force row level security;

create table app_private.import_rows (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  import_job_id uuid not null,
  source_row_key varchar(160) not null,
  row_number integer not null,
  created_reservation_id uuid,
  created_inventory_item_id uuid,
  error_code varchar(100),
  created_at timestamptz not null default now(),
  primary key (id),
  unique (owner_account_id, source_row_key),
  unique (id, property_id, owner_account_id),
  check (row_number >= 1),
  constraint import_result check (num_nonnulls(created_reservation_id,created_inventory_item_id)<=1)
);
alter table app_private.import_rows enable row level security;
alter table app_private.import_rows force row level security;

create table app_private.export_jobs (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  requested_by uuid not null,
  filter jsonb not null,
  state app_private.job_state not null default 'pending',
  storage_key varchar(500),
  expires_at timestamptz not null,
  error_code varchar(100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  primary key (id),
  unique (id, owner_account_id),
  check (jsonb_typeof(filter) = 'object'),
  check (version >= 1)
);
alter table app_private.export_jobs enable row level security;
alter table app_private.export_jobs force row level security;

-- Indexes, including filtered uniqueness.
create index properties_index_1 on app_private.properties using btree (owner_account_id, archived_at);
create index property_memberships_index_1 on app_private.property_memberships using btree (user_id, revoked_at);
create index property_memberships_index_2 on app_private.property_memberships using btree (property_id, revoked_at);
create index contacts_index_1 on app_private.contacts using btree (owner_account_id, phone);
create index reservations_index_1 on app_private.reservations using btree (property_id, check_in, check_out);
create index reservations_index_2 on app_private.reservations using btree (property_id, state);
create unique index occupancy_unique_1 on app_private.occupancy (placement_id) where active;
create unique index occupancy_unique_2 on app_private.occupancy (manual_block_id) where active;
create index occupancy_index_1 on app_private.occupancy using gist (property_id, date_range);
create index occupancy_index_2 on app_private.occupancy using btree (expires_at) where active AND expires_at IS NOT NULL;
create index rent_entries_index_1 on app_private.rent_entries using btree (reservation_id, occurred_at);
create index rent_entries_index_2 on app_private.rent_entries using btree (property_id, occurred_at);
create index expenses_index_1 on app_private.expenses using btree (owner_account_id, expense_date);
create unique index tasks_unique_1 on app_private.tasks (reservation_id, kind) where kind='cleaning' AND state<>'cancelled';
create index tasks_index_1 on app_private.tasks using btree (property_id, due_at);
create index tasks_index_2 on app_private.tasks using btree (assignee_contact_id, state);
create index rooms_index_1 on app_private.rooms using btree (property_id, position);
create index inventory_items_index_1 on app_private.inventory_items using btree (room_id, archived_at);
create unique index inspection_submissions_unique_2 on app_private.inspection_submissions (event_id, side) where state='draft';
create index media_assets_index_1 on app_private.media_assets using btree (property_id, classification, state);
create index payment_events_index_1 on app_private.payment_events using btree (verification_state, created_at);
create index outbox_index_1 on app_private.outbox using btree (state, next_attempt_at);
create index audit_events_index_1 on app_private.audit_events using btree (owner_account_id, created_at);
create index audit_events_index_2 on app_private.audit_events using btree (property_id, created_at);
create index audit_events_index_3 on app_private.audit_events using btree (request_id);
create index import_jobs_index_1 on app_private.import_jobs using btree (owner_account_id, created_at);

-- Foreign keys are added after tables to resolve dictionary cycles.
alter table app_private.profiles add constraint profiles_fk_1 foreign key (user_id) references auth.users (id) on delete RESTRICT on update NO ACTION;
alter table app_private.owner_accounts add constraint owner_accounts_fk_1 foreign key (owner_user_id) references auth.users (id) on delete RESTRICT on update NO ACTION;
alter table app_private.properties add constraint properties_fk_1 foreign key (owner_account_id) references app_private.owner_accounts (id) on delete RESTRICT on update NO ACTION;
alter table app_private.property_memberships add constraint property_memberships_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.property_memberships add constraint property_memberships_fk_2 foreign key (user_id) references auth.users (id) on delete RESTRICT on update NO ACTION;
alter table app_private.property_memberships add constraint property_memberships_fk_3 foreign key (granted_by) references auth.users (id) on delete RESTRICT on update NO ACTION;
alter table app_private.manager_invites add constraint manager_invites_fk_1 foreign key (owner_account_id) references app_private.owner_accounts (id) on delete RESTRICT on update NO ACTION;
alter table app_private.manager_invites add constraint manager_invites_fk_2 foreign key (accepted_user_id) references auth.users (id) on delete RESTRICT on update NO ACTION;
alter table app_private.invite_properties add constraint invite_properties_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.invite_properties add constraint invite_properties_fk_2 foreign key (invite_id, owner_account_id) references app_private.manager_invites (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.contacts add constraint contacts_fk_1 foreign key (owner_account_id) references app_private.owner_accounts (id) on delete RESTRICT on update NO ACTION;
alter table app_private.contact_properties add constraint contact_properties_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.contact_properties add constraint contact_properties_fk_2 foreign key (contact_id, owner_account_id) references app_private.contacts (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.reservations add constraint reservations_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.reservations add constraint reservations_fk_2 foreign key (current_placement_id, id, property_id, owner_account_id) references app_private.reservation_placements (id, reservation_id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION deferrable initially immediate;
alter table app_private.reservation_placements add constraint reservation_placements_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.reservation_placements add constraint reservation_placements_fk_2 foreign key (reservation_id, owner_account_id) references app_private.reservations (id, owner_account_id) on delete RESTRICT on update NO ACTION deferrable initially immediate;
alter table app_private.reservation_placements add constraint reservation_placements_fk_3 foreign key (created_by) references auth.users (id) on delete RESTRICT on update NO ACTION;
alter table app_private.reservation_attribution_transfers add constraint reservation_attribution_transfers_fk_1 foreign key (owner_account_id) references app_private.owner_accounts (id) on delete RESTRICT on update NO ACTION;
alter table app_private.reservation_attribution_transfers add constraint reservation_attribution_transfers_fk_2 foreign key (reservation_id, owner_account_id) references app_private.reservations (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.reservation_attribution_transfers add constraint reservation_attribution_transfers_fk_3 foreign key (from_placement_id) references app_private.reservation_placements (id) on delete RESTRICT on update NO ACTION;
alter table app_private.reservation_attribution_transfers add constraint reservation_attribution_transfers_fk_4 foreign key (to_placement_id) references app_private.reservation_placements (id) on delete RESTRICT on update NO ACTION;
alter table app_private.reservation_attribution_transfers add constraint reservation_attribution_transfers_fk_5 foreign key (actor_id) references auth.users (id) on delete RESTRICT on update NO ACTION;
alter table app_private.manual_blocks add constraint manual_blocks_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.occupancy add constraint occupancy_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.occupancy add constraint occupancy_fk_2 foreign key (placement_id, property_id, owner_account_id) references app_private.reservation_placements (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.occupancy add constraint occupancy_fk_3 foreign key (manual_block_id, property_id, owner_account_id) references app_private.manual_blocks (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.rent_entries add constraint rent_entries_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.rent_entries add constraint rent_entries_fk_2 foreign key (placement_id, reservation_id, property_id, owner_account_id) references app_private.reservation_placements (id, reservation_id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.rent_entries add constraint rent_entries_fk_3 foreign key (original_entry_id, owner_account_id) references app_private.rent_entries (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.rent_entries add constraint rent_entries_fk_4 foreign key (realtor_contact_id, owner_account_id) references app_private.contacts (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.rent_entries add constraint rent_entries_fk_5 foreign key (actor_id) references auth.users (id) on delete RESTRICT on update NO ACTION;
alter table app_private.rent_entries add constraint rent_entries_fk_6 foreign key (custodian_user_id) references auth.users (id) on delete RESTRICT on update NO ACTION;
alter table app_private.realtor_accounts add constraint realtor_accounts_fk_1 foreign key (owner_account_id) references app_private.owner_accounts (id) on delete RESTRICT on update NO ACTION;
alter table app_private.realtor_accounts add constraint realtor_accounts_fk_2 foreign key (reservation_id, owner_account_id) references app_private.reservations (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.realtor_accounts add constraint realtor_accounts_fk_3 foreign key (contact_id, owner_account_id) references app_private.contacts (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.realtor_settlements add constraint realtor_settlements_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.realtor_settlements add constraint realtor_settlements_fk_2 foreign key (actor_id) references auth.users (id) on delete RESTRICT on update NO ACTION;
alter table app_private.realtor_settlements add constraint realtor_settlements_fk_3 foreign key (realtor_account_id, reservation_id, owner_account_id) references app_private.realtor_accounts (id, reservation_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.realtor_settlements add constraint realtor_settlements_fk_4 foreign key (placement_id, reservation_id, property_id, owner_account_id) references app_private.reservation_placements (id, reservation_id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.expenses add constraint expenses_fk_1 foreign key (owner_account_id) references app_private.owner_accounts (id) on delete RESTRICT on update NO ACTION;
alter table app_private.expenses add constraint expenses_fk_2 foreign key (contact_id, owner_account_id) references app_private.contacts (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.expenses add constraint expenses_fk_3 foreign key (source_task_id, owner_account_id) references app_private.tasks (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.expenses add constraint expenses_fk_4 foreign key (submitted_by) references auth.users (id) on delete RESTRICT on update NO ACTION;
alter table app_private.expenses add constraint expenses_fk_5 foreign key (approved_by) references auth.users (id) on delete RESTRICT on update NO ACTION;
alter table app_private.expenses add constraint expenses_fk_6 foreign key (submitted_link_id) references app_private.access_links (id) on delete RESTRICT on update NO ACTION;
alter table app_private.expense_allocations add constraint expense_allocations_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.expense_allocations add constraint expense_allocations_fk_2 foreign key (expense_id, owner_account_id) references app_private.expenses (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.expense_payments add constraint expense_payments_fk_1 foreign key (owner_account_id) references app_private.owner_accounts (id) on delete RESTRICT on update NO ACTION;
alter table app_private.expense_payments add constraint expense_payments_fk_2 foreign key (expense_id, owner_account_id) references app_private.expenses (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.expense_payments add constraint expense_payments_fk_3 foreign key (actor_id) references auth.users (id) on delete RESTRICT on update NO ACTION;
alter table app_private.recurring_expenses add constraint recurring_expenses_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.tasks add constraint tasks_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.tasks add constraint tasks_fk_2 foreign key (placement_id, reservation_id, property_id, owner_account_id) references app_private.reservation_placements (id, reservation_id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.tasks add constraint tasks_fk_3 foreign key (assignee_contact_id, owner_account_id) references app_private.contacts (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.tasks add constraint tasks_fk_4 foreign key (confirmed_by) references auth.users (id) on delete RESTRICT on update NO ACTION;
alter table app_private.tasks add constraint tasks_fk_5 foreign key (inspection_event_id, property_id, owner_account_id) references app_private.inspection_events (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.rooms add constraint rooms_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.inventory_items add constraint inventory_items_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.inventory_items add constraint inventory_items_fk_2 foreign key (room_id, property_id, owner_account_id) references app_private.rooms (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.inspection_days add constraint inspection_days_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.inspection_events add constraint inspection_events_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.inspection_events add constraint inspection_events_fk_2 foreign key (day_id, property_id, owner_account_id) references app_private.inspection_days (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.inspection_events add constraint inspection_events_fk_3 foreign key (placement_id, reservation_id, property_id, owner_account_id) references app_private.reservation_placements (id, reservation_id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.inspection_snapshots add constraint inspection_snapshots_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.inspection_snapshots add constraint inspection_snapshots_fk_2 foreign key (event_id, property_id, owner_account_id) references app_private.inspection_events (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.inspection_snapshot_rooms add constraint inspection_snapshot_rooms_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.inspection_snapshot_rooms add constraint inspection_snapshot_rooms_fk_2 foreign key (snapshot_id, property_id, owner_account_id) references app_private.inspection_snapshots (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.inspection_snapshot_rooms add constraint inspection_snapshot_rooms_fk_3 foreign key (source_room_id, property_id, owner_account_id) references app_private.rooms (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.inspection_snapshot_items add constraint inspection_snapshot_items_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.inspection_snapshot_items add constraint inspection_snapshot_items_fk_2 foreign key (snapshot_id, property_id, owner_account_id) references app_private.inspection_snapshots (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.inspection_snapshot_items add constraint inspection_snapshot_items_fk_3 foreign key (snapshot_room_id, property_id, owner_account_id) references app_private.inspection_snapshot_rooms (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.inspection_snapshot_items add constraint inspection_snapshot_items_fk_4 foreign key (source_item_id, property_id, owner_account_id) references app_private.inventory_items (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.inspection_submissions add constraint inspection_submissions_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.inspection_submissions add constraint inspection_submissions_fk_2 foreign key (event_id, property_id, owner_account_id) references app_private.inspection_events (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.inspection_submissions add constraint inspection_submissions_fk_3 foreign key (snapshot_id, property_id, owner_account_id) references app_private.inspection_snapshots (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.inspection_submissions add constraint inspection_submissions_fk_4 foreign key (previous_submission_id, property_id, owner_account_id) references app_private.inspection_submissions (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.inspection_submissions add constraint inspection_submissions_fk_5 foreign key (actor_user_id) references auth.users (id) on delete RESTRICT on update NO ACTION;
alter table app_private.inspection_submissions add constraint inspection_submissions_fk_6 foreign key (access_link_id) references app_private.access_links (id) on delete RESTRICT on update NO ACTION;
alter table app_private.inspection_room_answers add constraint inspection_room_answers_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.inspection_room_answers add constraint inspection_room_answers_fk_2 foreign key (submission_id, property_id, owner_account_id) references app_private.inspection_submissions (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.inspection_room_answers add constraint inspection_room_answers_fk_3 foreign key (snapshot_room_id, property_id, owner_account_id) references app_private.inspection_snapshot_rooms (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.inspection_answers add constraint inspection_answers_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.inspection_answers add constraint inspection_answers_fk_2 foreign key (submission_id, property_id, owner_account_id) references app_private.inspection_submissions (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.inspection_answers add constraint inspection_answers_fk_3 foreign key (snapshot_item_id, property_id, owner_account_id) references app_private.inspection_snapshot_items (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.guides add constraint guides_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.guide_versions add constraint guide_versions_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.guide_versions add constraint guide_versions_fk_2 foreign key (guide_id, property_id, owner_account_id) references app_private.guides (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.guide_versions add constraint guide_versions_fk_3 foreign key (published_by) references auth.users (id) on delete RESTRICT on update NO ACTION;
alter table app_private.public_pages add constraint public_pages_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.access_links add constraint access_links_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.access_links add constraint access_links_fk_2 foreign key (task_id, property_id, owner_account_id) references app_private.tasks (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.access_links add constraint access_links_fk_3 foreign key (inspection_event_id, property_id, owner_account_id) references app_private.inspection_events (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.access_links add constraint access_links_fk_4 foreign key (placement_id, reservation_id, property_id, owner_account_id) references app_private.reservation_placements (id, reservation_id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.access_links add constraint access_links_fk_5 foreign key (created_by) references auth.users (id) on delete RESTRICT on update NO ACTION;
alter table app_private.media_assets add constraint media_assets_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.media_bindings add constraint media_bindings_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.media_bindings add constraint media_bindings_fk_2 foreign key (media_asset_id, property_id, owner_account_id) references app_private.media_assets (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.media_bindings add constraint media_bindings_fk_3 foreign key (task_id, property_id, owner_account_id) references app_private.tasks (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.media_bindings add constraint media_bindings_fk_4 foreign key (expense_id, owner_account_id) references app_private.expenses (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.media_bindings add constraint media_bindings_fk_5 foreign key (inspection_answer_id, property_id, owner_account_id) references app_private.inspection_answers (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.media_bindings add constraint media_bindings_fk_6 foreign key (guide_version_id, property_id, owner_account_id) references app_private.guide_versions (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.media_bindings add constraint media_bindings_fk_7 foreign key (inventory_item_id, property_id, owner_account_id) references app_private.inventory_items (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.trial_claims add constraint trial_claims_fk_1 foreign key (owner_account_id) references app_private.owner_accounts (id) on delete RESTRICT on update NO ACTION;
alter table app_private.trial_claims add constraint trial_claims_fk_2 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.subscriptions add constraint subscriptions_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.billing_orders add constraint billing_orders_fk_1 foreign key (owner_account_id) references app_private.owner_accounts (id) on delete RESTRICT on update NO ACTION;
alter table app_private.billing_order_lines add constraint billing_order_lines_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.billing_order_lines add constraint billing_order_lines_fk_2 foreign key (order_id, owner_account_id) references app_private.billing_orders (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.subscription_periods add constraint subscription_periods_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.subscription_periods add constraint subscription_periods_fk_2 foreign key (order_line_id, property_id, owner_account_id) references app_private.billing_order_lines (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.payment_events add constraint payment_events_fk_1 foreign key (billing_order_id) references app_private.billing_orders (id) on delete RESTRICT on update NO ACTION;
alter table app_private.outbox add constraint outbox_fk_1 foreign key (recipient_user_id) references auth.users (id) on delete RESTRICT on update NO ACTION;
alter table app_private.outbox add constraint outbox_fk_2 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.audit_events add constraint audit_events_fk_1 foreign key (actor_user_id) references auth.users (id) on delete RESTRICT on update NO ACTION;
alter table app_private.audit_events add constraint audit_events_fk_2 foreign key (actor_link_id) references app_private.access_links (id) on delete RESTRICT on update NO ACTION;
alter table app_private.support_requests add constraint support_requests_fk_1 foreign key (user_id) references auth.users (id) on delete RESTRICT on update NO ACTION;
alter table app_private.support_requests add constraint support_requests_fk_2 foreign key (owner_account_id) references app_private.owner_accounts (id) on delete RESTRICT on update NO ACTION;
alter table app_private.notification_preferences add constraint notification_preferences_fk_1 foreign key (user_id) references auth.users (id) on delete RESTRICT on update NO ACTION;
alter table app_private.push_subscriptions add constraint push_subscriptions_fk_1 foreign key (user_id) references auth.users (id) on delete RESTRICT on update NO ACTION;
alter table app_private.import_jobs add constraint import_jobs_fk_1 foreign key (owner_account_id) references app_private.owner_accounts (id) on delete RESTRICT on update NO ACTION;
alter table app_private.import_jobs add constraint import_jobs_fk_2 foreign key (requested_by) references auth.users (id) on delete RESTRICT on update NO ACTION;
alter table app_private.import_rows add constraint import_rows_fk_1 foreign key (property_id, owner_account_id) references app_private.properties (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.import_rows add constraint import_rows_fk_2 foreign key (import_job_id, owner_account_id) references app_private.import_jobs (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.import_rows add constraint import_rows_fk_3 foreign key (created_reservation_id, owner_account_id) references app_private.reservations (id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.import_rows add constraint import_rows_fk_4 foreign key (created_inventory_item_id, property_id, owner_account_id) references app_private.inventory_items (id, property_id, owner_account_id) on delete RESTRICT on update NO ACTION;
alter table app_private.export_jobs add constraint export_jobs_fk_1 foreign key (owner_account_id) references app_private.owner_accounts (id) on delete RESTRICT on update NO ACTION;
alter table app_private.export_jobs add constraint export_jobs_fk_2 foreign key (requested_by) references auth.users (id) on delete RESTRICT on update NO ACTION;

-- Structural exclusion constraints. Cross-row settlement and transitions follow in EVE-006.2/006.3.
alter table app_private.occupancy add constraint occupancy_no_overlap exclude using gist (property_id with =, date_range with &&) where (active);
alter table app_private.subscription_periods add constraint subscription_periods_no_overlap exclude using gist (property_id with =, tstzrange(starts_at, ends_at, '[)') with &&) deferrable initially immediate;

revoke all on all tables in schema app_private from public, anon, authenticated;
