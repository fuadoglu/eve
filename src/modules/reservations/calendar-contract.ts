export type CalendarPropertyOption = {
  id: string;
  owner_account_id: string;
  owner_display_name: string;
  name: string;
  area: string;
};

export type CalendarReservation = {
  id: string;
  property_id: string;
  guest_name: string;
  check_in: string;
  check_out: string;
  status: "hold" | "confirmed" | "checked_in" | "completed" | "cancelled" | "no_show";
  hold_expires_at?: string | null;
};

export type CalendarBlock = {
  id: string;
  property_id: string;
  check_in: string;
  check_out: string;
};

export type CalendarData = {
  reservations: CalendarReservation[];
  blocks: CalendarBlock[];
  from: string;
  to: string;
};

export type CalendarEnvelope = { data: CalendarData; meta: { request_id: string } };

export type CalendarAgendaEventInput = {
  id: string;
  kind: "reservation" | "block";
  checkIn: string;
  checkOut: string;
};

export type CalendarAgendaOccurrence = {
  id: string;
  date: string;
  label: "Giriş" | "Çıxış" | "Blok" | "Davam edir";
};

export type CalendarOwnerOption = { id: string; label: string };

export function parseCalendarQuery(params: URLSearchParams): { from: string; to: string; propertyIds: string[] } | null {
  const allowed = new Set(["from", "to", "property_ids"]);
  if ([...params.keys()].some((key) => !allowed.has(key))) return null;
  const from = params.get("from");
  const to = params.get("to");
  const propertyIds = params.getAll("property_ids");
  if (!isCalendarDate(from) || !isCalendarDate(to) || to <= from || daysBetween(from, to) > 93
      || propertyIds.length < 1 || propertyIds.length > 100 || propertyIds.some((id) => !isUuid(id))) return null;
  return { from, to, propertyIds };
}

export function parseCalendarEnvelope(value: unknown): CalendarEnvelope {
  if (!isRecord(value) || !isRecord(value.data) || !isRecord(value.meta)
      || !isUuid(value.meta.request_id) || !isCalendarDate(value.data.from)
      || !isCalendarDate(value.data.to) || value.data.to <= value.data.from
      || daysBetween(value.data.from, value.data.to) > 93
      || !Array.isArray(value.data.reservations) || value.data.reservations.length > 1000
      || !Array.isArray(value.data.blocks) || value.data.blocks.length > 1000) {
    throw new Error("invalid_calendar_envelope");
  }

  const reservations = value.data.reservations.map((item): CalendarReservation => {
    if (!isRecord(item) || !isUuid(item.id) || !isUuid(item.property_id)
        || typeof item.guest_name !== "string" || item.guest_name.length < 1 || item.guest_name.length > 150
        || !isCalendarDate(item.check_in) || !isCalendarDate(item.check_out) || item.check_out <= item.check_in
        || !isReservationStatus(item.status)
        || (item.hold_expires_at !== undefined && item.hold_expires_at !== null
          && !isDateTime(item.hold_expires_at))) throw new Error("invalid_calendar_reservation");
    return {
      id: item.id,
      property_id: item.property_id,
      guest_name: item.guest_name,
      check_in: item.check_in,
      check_out: item.check_out,
      status: item.status,
      ...(item.hold_expires_at === undefined ? {} : { hold_expires_at: item.hold_expires_at }),
    };
  });

  const blocks = value.data.blocks.map((item): CalendarBlock => {
    if (!isRecord(item) || !isUuid(item.id) || !isUuid(item.property_id)
        || !isCalendarDate(item.check_in) || !isCalendarDate(item.check_out) || item.check_out <= item.check_in) {
      throw new Error("invalid_calendar_block");
    }
    return { id: item.id, property_id: item.property_id, check_in: item.check_in, check_out: item.check_out };
  });

  return { data: { reservations, blocks, from: value.data.from, to: value.data.to }, meta: { request_id: value.meta.request_id } };
}

export function getCalendarRange(anchorDate: string): { from: string; to: string } {
  if (!isCalendarDate(anchorDate)) throw new Error("invalid_calendar_anchor");
  const anchor = parseDate(anchorDate);
  const first = new Date(Date.UTC(anchor.getUTCFullYear(), anchor.getUTCMonth(), 1));
  const mondayOffset = (first.getUTCDay() + 6) % 7;
  const from = new Date(first);
  from.setUTCDate(from.getUTCDate() - mondayOffset);
  const nextMonth = new Date(Date.UTC(anchor.getUTCFullYear(), anchor.getUTCMonth() + 1, 1));
  const nextMondayOffset = (8 - nextMonth.getUTCDay()) % 7;
  const to = new Date(nextMonth);
  to.setUTCDate(to.getUTCDate() + nextMondayOffset);
  return { from: formatDate(from), to: formatDate(to) };
}

export function filterCalendarData(
  data: CalendarData,
  propertyIds: ReadonlySet<string>,
  from: string,
  to: string,
): CalendarData {
  return {
    from,
    to,
    reservations: data.reservations.filter((item) => propertyIds.has(item.property_id)
      && item.check_in < to && item.check_out > from),
    blocks: data.blocks.filter((item) => propertyIds.has(item.property_id)
      && item.check_in < to && item.check_out > from),
  };
}

export function getAgendaOccurrences(
  events: CalendarAgendaEventInput[],
  from: string,
  to: string,
): CalendarAgendaOccurrence[] {
  const occurrences: CalendarAgendaOccurrence[] = [];
  for (const event of events) {
    if (event.checkIn >= to || event.checkOut <= from) continue;
    if (event.kind === "reservation") {
      if (event.checkIn < from) occurrences.push({ id: event.id, date: from, label: "Davam edir" });
      else occurrences.push({ id: event.id, date: event.checkIn, label: "Giriş" });
      if (event.checkOut >= from && event.checkOut < to) {
        occurrences.push({ id: event.id, date: event.checkOut, label: "Çıxış" });
      }
    } else if (event.checkIn < from) {
      occurrences.push({ id: event.id, date: from, label: "Davam edir" });
    } else {
      occurrences.push({ id: event.id, date: event.checkIn, label: "Blok" });
    }
  }
  return occurrences;
}

export function getCalendarOwnerOptions(properties: CalendarPropertyOption[]): CalendarOwnerOption[] {
  const namesById = new Map<string, string>();
  for (const property of properties) {
    if (!namesById.has(property.owner_account_id)) namesById.set(property.owner_account_id, property.owner_display_name);
  }
  const duplicateNames = new Set([...namesById.values()].filter((name, index, names) => names.indexOf(name) !== index));
  const ids = [...namesById.keys()].sort();
  const firstLabels = ids.map((id) => ({ id, name: namesById.get(id) ?? "Sahib" }));
  const candidateLabels = firstLabels.map(({ id, name }) => duplicateNames.has(name)
    ? `${name} · ${id.slice(0, 8).toUpperCase()}` : name);
  const duplicateCandidates = new Set(candidateLabels.filter((label, index, labels) => labels.indexOf(label) !== index));
  return firstLabels.map(({ id, name }, index) => ({
    id,
    label: duplicateCandidates.has(candidateLabels[index]) ? `${name} · ${id}` : candidateLabels[index],
  }));
}

export function isCalendarHoldExpired(
  status: CalendarReservation["status"],
  holdExpiresAt: string | null | undefined,
  nowMs: number,
): boolean {
  return status === "hold" && typeof holdExpiresAt === "string"
    && Number.isFinite(Date.parse(holdExpiresAt)) && Date.parse(holdExpiresAt) <= nowMs;
}

export function isCalendarDate(value: unknown): value is string {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = parseDate(value);
  return Number.isFinite(date.getTime()) && formatDate(date) === value;
}

function isReservationStatus(value: unknown): value is CalendarReservation["status"] {
  return value === "hold" || value === "confirmed" || value === "checked_in"
    || value === "completed" || value === "cancelled" || value === "no_show";
}

function isDateTime(value: unknown): value is string {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/u.test(value)
    && Number.isFinite(Date.parse(value));
}

function isUuid(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function daysBetween(from: string, to: string): number {
  return (parseDate(to).getTime() - parseDate(from).getTime()) / 86_400_000;
}

function parseDate(value: string): Date {
  const [year, month, day] = value.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day));
}

function formatDate(value: Date): string {
  return `${value.getUTCFullYear().toString().padStart(4, "0")}-${(value.getUTCMonth() + 1).toString().padStart(2, "0")}-${value.getUTCDate().toString().padStart(2, "0")}`;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
