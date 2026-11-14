export type BillingPeriodPlan = "monthly" | "yearly";

export type BillingPeriodAnchor = {
  day: number;
  month: number;
  time: string;
  timezone: "Asia/Baku";
};

export type AppliedBillingPeriod = {
  plan: BillingPeriodPlan;
  starts_at: string;
  ends_at: string;
  anchor_day: number;
  anchor_month: number;
  anchor_time: string;
  anchor_timezone: "Asia/Baku";
};

export type ExistingBillingPeriod = AppliedBillingPeriod;

export class BillingPeriodError extends Error {
  readonly code: "invalid_plan" | "invalid_timestamp" | "invalid_anchor";

  constructor(code: BillingPeriodError["code"]) {
    super(code);
    this.name = "BillingPeriodError";
    this.code = code;
  }
}

const BAKU_TIMEZONE = "Asia/Baku" as const;
const RFC3339_INSTANT = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?(Z|[+-](\d{2}):(\d{2}))$/;
const SQL_TIME = /^(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,6})?$/;
const bakuFormatter = new Intl.DateTimeFormat("en-CA", {
  timeZone: BAKU_TIMEZONE,
  calendar: "gregory",
  numberingSystem: "latn",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
  fractionalSecondDigits: 3,
  hourCycle: "h23",
});

/**
 * Apply one server-verified billing period without provider or database side effects.
 * The caller persists the result atomically with its payment/entitlement transaction.
 */
export function applyBillingPeriod(input: {
  plan: BillingPeriodPlan;
  verified_at: string;
  previous_period?: ExistingBillingPeriod | null;
  trial_ends_at?: string | null;
}): AppliedBillingPeriod {
  if (input.plan !== "monthly" && input.plan !== "yearly") {
    throw new BillingPeriodError("invalid_plan");
  }
  const verifiedAt = parseInstant(input.verified_at);
  const previous = input.previous_period ?? null;
  const previousEnd = previous ? parseInstant(previous.ends_at) : null;
  if (previous) {
    const previousStart = parseInstant(previous.starts_at);
    if (previousEnd! <= previousStart) throw new BillingPeriodError("invalid_timestamp");
  }
  const trialEnd = input.trial_ends_at ? parseInstant(input.trial_ends_at) : null;
  const startMicros = [verifiedAt, previousEnd, trialEnd].reduce<bigint>((latest, value) =>
    value !== null && value > latest ? value : latest, verifiedAt);
  const startLocal = partsAtBaku(startMicros);

  let anchor: BillingPeriodAnchor;
  if (previous) {
    anchor = readAnchor(previous);
    // A plan switch is queued at the existing boundary. Keep the day/time rule,
    // while the new calendar period takes the boundary's local month as its anchor.
    if (previous.plan !== input.plan) anchor.month = startLocal.month;
  } else {
    anchor = {
      day: startLocal.day,
      month: startLocal.month,
      time: formatSqlTime(startLocal),
      timezone: BAKU_TIMEZONE,
    };
  }

  const endLocalMonthIndex = startLocal.year * 12 + startLocal.month - 1 + 1;
  const endYear = input.plan === "yearly" ? startLocal.year + 1 : Math.floor(endLocalMonthIndex / 12);
  const endMonth = input.plan === "yearly" ? anchor.month : endLocalMonthIndex % 12 + 1;
  const endDay = Math.min(anchor.day, daysInMonth(endYear, endMonth));
  const endMicros = instantAtBaku({
    year: endYear,
    month: endMonth,
    day: endDay,
    ...parseSqlTime(anchor.time),
  });

  if (endMicros <= startMicros) throw new BillingPeriodError("invalid_timestamp");
  return {
    plan: input.plan,
    starts_at: formatInstant(startMicros),
    ends_at: formatInstant(endMicros),
    anchor_day: anchor.day,
    anchor_month: anchor.month,
    anchor_time: anchor.time,
    anchor_timezone: BAKU_TIMEZONE,
  };
}

function parseInstant(value: string): bigint {
  if (typeof value !== "string") {
    throw new BillingPeriodError("invalid_timestamp");
  }
  const match = RFC3339_INSTANT.exec(value);
  if (!match) throw new BillingPeriodError("invalid_timestamp");
  const [, yearText, monthText, dayText, hourText, minuteText, secondText, fraction = "", , offsetHourText, offsetMinuteText] = match;
  const year = Number(yearText);
  const month = Number(monthText);
  const day = Number(dayText);
  const hour = Number(hourText);
  const minute = Number(minuteText);
  const second = Number(secondText);
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month)
      || hour > 23 || minute > 59 || second > 59
      || (offsetHourText !== undefined && (Number(offsetHourText) > 23 || Number(offsetMinuteText) > 59))) {
    throw new BillingPeriodError("invalid_timestamp");
  }
  const wholeSecond = value.replace(/\.\d+(?=Z|[+-]\d{2}:\d{2}$)/, "");
  const parsed = Date.parse(wholeSecond);
  if (!Number.isFinite(parsed)) throw new BillingPeriodError("invalid_timestamp");
  return BigInt(parsed) * BigInt(1000) + BigInt(fraction.padEnd(6, "0") || "0");
}

function formatInstant(microseconds: bigint): string {
  const wholeMilliseconds = microseconds / BigInt(1000);
  const subMillisecondMicroseconds = microseconds % BigInt(1000);
  const date = new Date(Number(wholeMilliseconds));
  if (!Number.isFinite(date.getTime())) throw new BillingPeriodError("invalid_timestamp");
  const base = date.toISOString().replace(/\.\d{3}Z$/, "");
  const fraction = String((wholeMilliseconds % BigInt(1000)) * BigInt(1000) + subMillisecondMicroseconds).padStart(6, "0");
  return `${base}.${fraction}Z`;
}

function readAnchor(period: ExistingBillingPeriod): BillingPeriodAnchor {
  if (!Number.isInteger(period.anchor_day) || period.anchor_day < 1 || period.anchor_day > 31
      || !Number.isInteger(period.anchor_month) || period.anchor_month < 1 || period.anchor_month > 12
      || !SQL_TIME.test(period.anchor_time) || period.anchor_timezone !== BAKU_TIMEZONE
      || (period.plan !== "monthly" && period.plan !== "yearly")) {
    throw new BillingPeriodError("invalid_anchor");
  }
  return {
    day: period.anchor_day,
    month: period.anchor_month,
    time: period.anchor_time,
    timezone: BAKU_TIMEZONE,
  };
}

type LocalParts = { year: number; month: number; day: number; hour: number; minute: number; second: number; microsecond: number };

function partsAtBaku(instantMicros: bigint): LocalParts {
  const milliseconds = instantMicros / BigInt(1000);
  const date = new Date(Number(milliseconds));
  const parts = Object.fromEntries(bakuFormatter.formatToParts(date).map(({ type, value }) => [type, value]));
  return {
    year: Number(parts.year),
    month: Number(parts.month),
    day: Number(parts.day),
    hour: Number(parts.hour),
    minute: Number(parts.minute),
    second: Number(parts.second),
    microsecond: Number(parts.fractionalSecond) * 1_000 + Number(instantMicros % BigInt(1000)),
  };
}

function parseSqlTime(value: string): Pick<LocalParts, "hour" | "minute" | "second" | "microsecond"> {
  if (!SQL_TIME.test(value)) throw new BillingPeriodError("invalid_anchor");
  const [whole, fraction = "0"] = value.split(".");
  const [hour, minute, second] = whole.split(":").map(Number);
  return { hour, minute, second, microsecond: Number(fraction.padEnd(6, "0")) };
}

function formatSqlTime(parts: Pick<LocalParts, "hour" | "minute" | "second" | "microsecond">): string {
  const base = [parts.hour, parts.minute, parts.second].map((part) => String(part).padStart(2, "0")).join(":");
  return parts.microsecond === 0 ? base : `${base}.${String(parts.microsecond).padStart(6, "0").replace(/0+$/, "")}`;
}

function instantAtBaku(parts: LocalParts): bigint {
  const wallClockAsUtc = BigInt(utcMillis(parts.year, parts.month, parts.day,
    parts.hour, parts.minute, parts.second, Math.floor(parts.microsecond / 1_000))) * BigInt(1000) + BigInt(parts.microsecond % 1_000);
  let candidate = wallClockAsUtc;
  // Resolve the local wall time through Intl instead of hard-coding UTC+4.
  for (let i = 0; i < 4; i += 1) {
    const observed = partsAtBaku(candidate);
    const observedAsUtc = BigInt(utcMillis(observed.year, observed.month, observed.day,
      observed.hour, observed.minute, observed.second, Math.floor(observed.microsecond / 1_000))) * BigInt(1000) + BigInt(observed.microsecond % 1_000);
    const correction = wallClockAsUtc - observedAsUtc;
    candidate += correction;
    if (correction === BigInt(0)) return candidate;
  }
  const resolved = partsAtBaku(candidate);
  if (resolved.year !== parts.year || resolved.month !== parts.month || resolved.day !== parts.day
      || resolved.hour !== parts.hour || resolved.minute !== parts.minute || resolved.second !== parts.second
      || resolved.microsecond !== parts.microsecond) {
    throw new BillingPeriodError("invalid_anchor");
  }
  return candidate;
}

function daysInMonth(year: number, month: number): number {
  const end = new Date(0);
  end.setUTCHours(0, 0, 0, 0);
  end.setUTCFullYear(year, month, 0);
  return end.getUTCDate();
}

function utcMillis(year: number, month: number, day: number, hour: number, minute: number,
  second: number, millisecond: number): number {
  const value = new Date(0);
  value.setUTCHours(hour, minute, second, millisecond);
  value.setUTCFullYear(year, month - 1, day);
  return value.getTime();
}
