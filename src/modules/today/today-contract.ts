export const TODAY_KINDS = [
  "arrival",
  "departure",
  "task",
  "rent_due",
  "expense_due",
  "subscription",
  "inspection_problem",
] as const;

export const TODAY_ACTIONS = [
  "open_reservation",
  "check_in",
  "check_out",
  "open_task",
  "confirm_task",
  "open_money",
  "renew",
  "open_inspection",
] as const;

export type TodayCard = {
  id: string;
  kind: (typeof TODAY_KINDS)[number];
  property_id: string;
  property_label: string;
  owner_display_name?: string;
  title: string;
  due_at?: string | null;
  amount_minor?: number | null;
  action: (typeof TODAY_ACTIONS)[number];
  target_id: string;
};

export type TodayProjection = {
  local_date: string;
  timezone: "Asia/Baku";
  cards: TodayCard[];
};

export type TodayEnvelope = {
  data: TodayProjection;
  meta: { request_id: string };
};

export function parseTodayProjection(value: unknown): TodayProjection {
  if (!isRecord(value) || !hasOnlyKeys(value, ["local_date", "timezone", "cards"])
    || !isCalendarDate(value.local_date) || value.timezone !== "Asia/Baku"
    || !Array.isArray(value.cards) || value.cards.length > 1000) {
    throw new TypeError("invalid_today_projection");
  }

  const cards = value.cards.map(parseTodayCard);
  if (new Set(cards.map((card) => card.id)).size !== cards.length) {
    throw new TypeError("duplicate_today_card_id");
  }
  return { local_date: value.local_date, timezone: "Asia/Baku", cards };
}

export function parseTodayEnvelope(value: unknown): TodayEnvelope {
  if (!isRecord(value) || !hasOnlyKeys(value, ["data", "meta"]) || !isRecord(value.meta)
    || !hasOnlyKeys(value.meta, ["request_id"]) || !isUuid(value.meta.request_id)) {
    throw new TypeError("invalid_today_envelope");
  }
  return { data: parseTodayProjection(value.data), meta: { request_id: value.meta.request_id } };
}

function parseTodayCard(value: unknown): TodayCard {
  if (!isRecord(value) || !isUuid(value.id) || !isOneOf(value.kind, TODAY_KINDS)
    || !hasOnlyKeys(value, ["id", "kind", "property_id", "property_label", "owner_display_name", "title", "due_at", "amount_minor", "action", "target_id"])
    || !isUuid(value.property_id) || !isBoundedText(value.property_label, 1, 160)
    || !isBoundedText(value.title, 1, 160) || !isOneOf(value.action, TODAY_ACTIONS)
    || !isUuid(value.target_id)
    || (value.owner_display_name !== undefined && !isBoundedText(value.owner_display_name, 1, 100))
    || (value.due_at !== undefined && value.due_at !== null && !isDateTime(value.due_at))
    || (value.amount_minor !== undefined && value.amount_minor !== null
      && (!Number.isSafeInteger(value.amount_minor) || Number(value.amount_minor) < 0))) {
    throw new TypeError("invalid_today_card");
  }
  return {
    id: value.id,
    kind: value.kind,
    property_id: value.property_id,
    property_label: value.property_label,
    ...(value.owner_display_name === undefined ? {} : { owner_display_name: value.owner_display_name as string }),
    title: value.title,
    ...(value.due_at === undefined ? {} : { due_at: value.due_at as string | null }),
    ...(value.amount_minor === undefined ? {} : { amount_minor: value.amount_minor as number | null }),
    action: value.action,
    target_id: value.target_id,
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasOnlyKeys(value: Record<string, unknown>, allowed: readonly string[]): boolean {
  return Object.keys(value).every((key) => allowed.includes(key));
}

function isOneOf<T extends readonly string[]>(value: unknown, options: T): value is T[number] {
  return typeof value === "string" && (options as readonly string[]).includes(value);
}

function isBoundedText(value: unknown, minimum: number, maximum: number): value is string {
  return typeof value === "string" && [...value].length >= minimum && [...value].length <= maximum;
}

function isUuid(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function isCalendarDate(value: unknown): value is string {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
}

function isDateTime(value: unknown): value is string {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}T/.test(value) && !Number.isNaN(Date.parse(value));
}
