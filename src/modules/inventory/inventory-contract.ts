/** API DTOs and RPC contract for EVE-019 inventory operations. */
export type InventoryUnit = "piece" | "set" | "liter" | "kg" | "pack";
export type InventoryCondition = "ok" | "needs_repair" | "damaged" | "missing";
export type InventoryTemplateKey = "standard_apartment";
export type InventoryTemplateStrategy = "append_non_duplicate";

export type RoomDto = {
  id: string;
  property_id: string;
  name: string;
  position: number;
  version: number;
  created_at: string;
  updated_at: string;
};

export type InventoryItemDto = {
  id: string;
  property_id: string;
  room_id: string;
  name: string;
  quantity: number;
  unit: InventoryUnit;
  condition: InventoryCondition;
  minimum_stock?: number | null;
  purchase_minor?: number | null;
  purchased_on?: string | null;
  warranty_until?: string | null;
  model?: string | null;
  serial_number?: string | null;
  note?: string;
  media_ids: string[];
  version: number;
  created_at: string;
  updated_at: string;
};

export type InventoryDto = {
  property_id: string;
  rooms: RoomDto[];
  items: InventoryItemDto[];
};

export type InventoryCopyInput = {
  source_property_id: string;
  /** OpenAPI default is false; media bytes must be copied by a server workflow. */
  include_media?: boolean;
};

export type ImportPreviewKind = "reservations" | "inventory";
export type ImportPreviewState = "preview_ready" | "invalid" | "committing" | "completed" | "failed";

export type ImportPreviewInput = {
  property_id: string;
  kind: ImportPreviewKind;
  media_id: string;
};

export type InventoryImportPreviewInput = Omit<ImportPreviewInput, "kind"> & { kind: "inventory" };

export type ImportPreviewError = {
  row: number;
  field: string;
  message: string;
};

export type ImportPreviewDto = {
  id: string;
  property_id: string;
  kind: ImportPreviewKind;
  state: ImportPreviewState;
  preview_hash: string;
  row_count: number;
  errors: ImportPreviewError[];
  version: number;
  created_at: string;
  updated_at: string;
};

export type CreateRoomInput = { name: string; position?: number };
export type CreateInventoryItemInput = {
  room_id: string;
  name: string;
  quantity: number;
  unit?: InventoryUnit;
  condition?: InventoryCondition;
  minimum_stock?: number | null;
  purchase_minor?: number | null;
  purchased_on?: string | null;
  warranty_until?: string | null;
  model?: string | null;
  serial_number?: string | null;
  note?: string;
  media_ids?: string[];
};

/**
 * Validate the acknowledgements used by copy and import-preview callers.
 * Authorization, source/destination ownership, file parsing, and writes remain
 * server responsibilities; a locally valid request is never a saved result.
 */
export function validateInventoryCopyInput(value: unknown): InventoryCopyInput {
  if (!isRecord(value) || !hasOnlyKeys(value, ["source_property_id", "include_media"]) || !isUuid(value.source_property_id)) {
    throw new TypeError("source_property_id must be a UUID");
  }
  if (value.include_media !== undefined && typeof value.include_media !== "boolean") {
    throw new TypeError("include_media must be boolean");
  }
  return {
    source_property_id: value.source_property_id,
    ...(value.include_media === undefined ? {} : { include_media: value.include_media }),
  };
}

export function validateImportPreviewInput(value: unknown): ImportPreviewInput {
  if (!isRecord(value)
      || !hasOnlyKeys(value, ["property_id", "kind", "media_id"])
      || !isUuid(value.property_id)
      || !isUuid(value.media_id)
      || (value.kind !== "inventory" && value.kind !== "reservations")) {
    throw new TypeError("invalid ImportPreviewInput");
  }
  return { property_id: value.property_id, media_id: value.media_id, kind: value.kind };
}

export function validateInventoryImportPreviewInput(value: unknown): InventoryImportPreviewInput {
  const input = validateImportPreviewInput(value);
  if (input.kind !== "inventory") {
    throw new TypeError("inventory import preview requires kind=inventory");
  }
  return { property_id: input.property_id, media_id: input.media_id, kind: "inventory" };
}

export function validateImportPreview(value: unknown): ImportPreviewDto {
  if (!isRecord(value)
      || !hasOnlyKeys(value, ["id", "property_id", "kind", "state", "preview_hash", "row_count", "errors", "version", "created_at", "updated_at"])
      || !isUuid(value.id)
      || !isUuid(value.property_id)
      || (value.kind !== "inventory" && value.kind !== "reservations")
      || !isImportPreviewState(value.state)
      || typeof value.preview_hash !== "string"
      || !/^[a-f0-9]{64}$/.test(value.preview_hash)
      || !isIntegerInRange(value.row_count, 0, 1_000_000)
      || !Array.isArray(value.errors)
      || value.errors.length > 1_000
      || !isIntegerInRange(value.version, 1, Number.MAX_SAFE_INTEGER)
      || !isDateTime(value.created_at)
      || !isDateTime(value.updated_at)) {
    throw new TypeError("invalid ImportPreview acknowledgement");
  }

  const errors = value.errors.map((error): ImportPreviewError => {
    if (!isRecord(error)
        || !hasOnlyKeys(error, ["row", "field", "message"])
        || !isIntegerInRange(error.row, 1, Number.MAX_SAFE_INTEGER)
        || typeof error.field !== "string"
        || error.field.length > 120
        || typeof error.message !== "string"
        || error.message.length > 300) {
      throw new TypeError("invalid ImportPreview row error");
    }
    return { row: error.row, field: error.field, message: error.message };
  });

  return {
    id: value.id,
    property_id: value.property_id,
    kind: value.kind,
    state: value.state,
    preview_hash: value.preview_hash,
    row_count: value.row_count,
    errors,
    version: value.version,
    created_at: value.created_at,
    updated_at: value.updated_at,
  };
}

/** Methods resolve only after the server RPC returns an acknowledged DTO. */
export interface InventoryProvider {
  getInventory(propertyId: string): Promise<InventoryDto>;
  createRoom(propertyId: string, input: CreateRoomInput): Promise<RoomDto>;
  createInventoryItem(propertyId: string, input: CreateInventoryItemInput): Promise<InventoryItemDto>;
  applyTemplate(
    propertyId: string,
    templateKey: InventoryTemplateKey,
    strategy: InventoryTemplateStrategy,
  ): Promise<InventoryDto>;
  copyInventory(propertyId: string, input: InventoryCopyInput): Promise<InventoryDto>;
  previewImport(input: InventoryImportPreviewInput): Promise<ImportPreviewDto>;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasOnlyKeys(value: Record<string, unknown>, allowed: readonly string[]): boolean {
  return Object.keys(value).every((key) => allowed.includes(key));
}

function isUuid(value: unknown): value is string {
  return typeof value === "string"
    && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function isImportPreviewState(value: unknown): value is ImportPreviewState {
  return value === "preview_ready"
    || value === "invalid"
    || value === "committing"
    || value === "completed"
    || value === "failed";
}

function isIntegerInRange(value: unknown, minimum: number, maximum: number): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= minimum && value <= maximum;
}

function isDateTime(value: unknown): value is string {
  if (typeof value !== "string") return false;
  const match = /^(\d{4})-(\d{2})-(\d{2})[Tt](\d{2}):(\d{2}):(\d{2})(?:\.\d+)?([Zz]|([+-])(\d{2}):(\d{2}))$/.exec(value);
  if (!match) return false;

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6]);
  const offsetHour = Number(match[9] ?? 0);
  const offsetMinute = Number(match[10] ?? 0);
  const leapYear = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const monthDays = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

  const validCalendarTime = month >= 1
    && month <= 12
    && day >= 1
    && day <= (monthDays[month - 1] ?? 0)
    && hour <= 23
    && minute <= 59
    && second <= 60
    && offsetHour <= 23
    && offsetMinute <= 59;
  if (!validCalendarTime) return false;
  if (second < 60) return Number.isFinite(Date.parse(value));

  // RFC 3339's second 60 is valid only at an announced UTC leap second.
  // Convert the local minute using its stated numeric offset and compare the
  // resulting UTC day with the leap-second dates currently in the standard.
  const offsetSign = match[8] === "+" ? 1 : match[8] === "-" ? -1 : 0;
  const offsetMinutes = offsetSign * (offsetHour * 60 + offsetMinute);
  const utcMinute = new Date(Date.UTC(year, month - 1, day, hour, minute) - offsetMinutes * 60_000);
  const utcDate = `${utcMinute.getUTCFullYear().toString().padStart(4, "0")}-${(utcMinute.getUTCMonth() + 1).toString().padStart(2, "0")}-${utcMinute.getUTCDate().toString().padStart(2, "0")}`;
  return utcMinute.getUTCHours() === 23
    && utcMinute.getUTCMinutes() === 59
    && LEAP_SECOND_UTC_DATES.has(utcDate);
}

const LEAP_SECOND_UTC_DATES = new Set([
  "1972-06-30", "1972-12-31", "1973-12-31", "1974-12-31", "1975-12-31", "1976-12-31",
  "1977-12-31", "1978-12-31", "1979-12-31", "1981-06-30", "1982-06-30", "1983-06-30",
  "1985-06-30", "1987-12-31", "1989-12-31", "1990-12-31", "1992-06-30", "1993-06-30",
  "1994-06-30", "1995-12-31", "1997-06-30", "1998-12-31", "2005-12-31", "2008-12-31",
  "2012-06-30", "2015-06-30", "2016-12-31",
]);
