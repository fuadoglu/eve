-- EVE-006.1 foundation. This migration is incomplete until all dictionary tables
-- and constraints are added in this same, unapplied PR. RLS policies/RPC: EVE-006.2.
create schema if not exists app_private;
create schema if not exists api;
revoke all on schema app_private from public, anon, authenticated;
revoke all on schema api from public, anon, authenticated;

create type app_private.locale as enum ('az', 'ru', 'en');
create type app_private.property_type as enum ('apartment', 'house', 'villa', 'other');
create type app_private.readiness as enum ('ready', 'cleaning_pending', 'attention_required');
create type app_private.permission as enum ('daily', 'full');

create table app_private.profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete restrict,
  display_name varchar(120),
  phone varchar(20),
  locale app_private.locale not null default 'az',
  session_revoked_before timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1 check (version >= 1)
);

create table app_private.owner_accounts (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null unique references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1 check (version >= 1)
);

create table app_private.properties (
  id uuid primary key default gen_random_uuid(),
  owner_account_id uuid not null references app_private.owner_accounts(id) on delete restrict,
  name varchar(120) not null,
  area varchar(160) not null,
  property_type app_private.property_type not null default 'apartment',
  private_address varchar(500),
  room_count integer not null default 0 check (room_count >= 0),
  bed_count integer not null default 0 check (bed_count >= 0),
  max_guests integer not null default 1 check (max_guests >= 1),
  default_check_in time not null default '14:00',
  default_check_out time not null default '12:00',
  nightly_rate_minor bigint constraint properties_nightly_rate_minor_safe
    check (nightly_rate_minor is null or (nightly_rate_minor >= 0 and nightly_rate_minor <= 9007199254740991)),
  settings jsonb not null default '{}'::jsonb,
  readiness app_private.readiness not null default 'ready',
  inventory_version integer not null default 1 check (inventory_version >= 1),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1 check (version >= 1),
  unique (id, owner_account_id)
);
create index properties_owner_account_id_archived_at_idx
  on app_private.properties (owner_account_id, archived_at);

create table app_private.property_memberships (
  id uuid primary key default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  user_id uuid not null references auth.users(id) on delete restrict,
  permission app_private.permission not null,
  revoked_at timestamptz,
  granted_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1 check (version >= 1),
  unique (property_id, user_id),
  unique (id, property_id, owner_account_id),
  constraint property_memberships_property_owner_fk foreign key (property_id, owner_account_id)
    references app_private.properties(id, owner_account_id) on delete restrict
);

alter table app_private.profiles enable row level security;
alter table app_private.profiles force row level security;
alter table app_private.owner_accounts enable row level security;
alter table app_private.owner_accounts force row level security;
alter table app_private.properties enable row level security;
alter table app_private.properties force row level security;
alter table app_private.property_memberships enable row level security;
alter table app_private.property_memberships force row level security;

revoke all on all tables in schema app_private from public, anon, authenticated;
