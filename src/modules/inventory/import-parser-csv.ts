import { INVENTORY_IMPORT_LIMITS } from "./import-parser-limits.ts";
export { INVENTORY_IMPORT_LIMITS } from "./import-parser-limits.ts";

export const INVENTORY_IMPORT_MAX_BYTES = INVENTORY_IMPORT_LIMITS.maxFileBytes;
export const INVENTORY_IMPORT_MAX_ROWS = INVENTORY_IMPORT_LIMITS.maxRows;
export const INVENTORY_IMPORT_HEADERS = [
  "source_row_key", "room_name", "name", "quantity", "unit", "condition",
] as const;

export type InventoryImportRow = {
  /** CSV record's starting physical line or XLSX worksheet row; header is included. */
  source_row_number: number;
  source_row_key: string;
  room_name: string;
  name: string;
  quantity: string;
  unit?: string;
  condition?: string;
};

export class InventoryImportParseError extends Error {
  readonly code:
    | "file_too_large" | "empty_file" | "invalid_utf8" | "invalid_csv"
    | "invalid_header" | "too_many_rows" | "too_many_columns"
    | "invalid_xlsx" | "unsafe_xlsx" | "unsupported_xlsx";

  constructor(code: InventoryImportParseError["code"]) {
    super(code);
    this.name = "InventoryImportParseError";
    this.code = code;
  }
}

/** RFC 4180 quoting, strict UTF-8, bounded cells and exact versioned template. */
export function parseInventoryCsv(bytes: Uint8Array): InventoryImportRow[] {
  if (bytes.byteLength > INVENTORY_IMPORT_MAX_BYTES) throw new InventoryImportParseError("file_too_large");
  if (bytes.byteLength === 0) throw new InventoryImportParseError("empty_file");
  let content: string;
  try { content = new TextDecoder("utf-8", { fatal: true }).decode(bytes); }
  catch { throw new InventoryImportParseError("invalid_utf8"); }
  if (content.charCodeAt(0) === 0xfeff) content = content.slice(1);
  if (content.includes("\0")) throw new InventoryImportParseError("invalid_csv");

  const table: string[][] = [];
  const sourceRowNumbers: number[] = [];
  let row: string[] = [];
  let cell = "";
  let quoted = false;
  let closedQuote = false;
  let atStart = true;
  let physicalLine = 1;
  let rowStartLine = 1;
  for (let i = 0; i < content.length; i++) {
    const c = content[i];
    if (quoted) {
      if (c === '"' && content[i + 1] === '"') { cell += '"'; i++; }
      else if (c === '"') { quoted = false; closedQuote = true; }
      else if (c === "\r" || c === "\n") {
        if (c === "\r" && content[i + 1] === "\n") { cell += "\r\n"; i++; }
        else cell += c;
        physicalLine++;
      } else cell += c;
    } else if (c === '"') {
      if (!atStart || closedQuote) throw new InventoryImportParseError("invalid_csv");
      quoted = true;
    } else if (c === "," || c === "\n" || c === "\r") {
      if (row.length >= INVENTORY_IMPORT_HEADERS.length) throw new InventoryImportParseError("too_many_columns");
      row.push(cell); cell = ""; closedQuote = false; atStart = true;
      if (c !== ",") {
        table.push(row); sourceRowNumbers.push(rowStartLine); row = [];
        if (table.length > INVENTORY_IMPORT_MAX_ROWS + 1) throw new InventoryImportParseError("too_many_rows");
        if (c === "\r" && content[i + 1] === "\n") i++;
        physicalLine++;
        rowStartLine = physicalLine;
      }
    } else {
      if (closedQuote) throw new InventoryImportParseError("invalid_csv");
      cell += c;
    }
    if (cell.length > INVENTORY_IMPORT_LIMITS.maxCellCharacters) throw new InventoryImportParseError("invalid_csv");
    if (c !== '"' && c !== "\r" && c !== "\n" && c !== ",") atStart = false;
  }
  if (quoted) throw new InventoryImportParseError("invalid_csv");
  if (row.length || cell.length || closedQuote) {
    if (row.length >= INVENTORY_IMPORT_HEADERS.length) throw new InventoryImportParseError("too_many_columns");
    row.push(cell); table.push(row); sourceRowNumbers.push(rowStartLine);
  }
  if (table.length < 2) throw new InventoryImportParseError("empty_file");
  return normalizeInventoryTable(table, sourceRowNumbers);
}

export function normalizeInventoryTable(
  table: readonly (readonly string[])[],
  sourceRowNumbers: readonly number[] = table.map((_, index) => index + 1),
): InventoryImportRow[] {
  if (table.length < 2) throw new InventoryImportParseError("empty_file");
  if (table.length > INVENTORY_IMPORT_MAX_ROWS + 1) throw new InventoryImportParseError("too_many_rows");
  const header = table[0];
  if (header.length !== INVENTORY_IMPORT_HEADERS.length
    || header.some((value, index) => value !== INVENTORY_IMPORT_HEADERS[index])) {
    throw new InventoryImportParseError("invalid_header");
  }
  const result: InventoryImportRow[] = [];
  for (const [index, row] of table.slice(1).entries()) {
    if (row.length !== INVENTORY_IMPORT_HEADERS.length) throw new InventoryImportParseError("invalid_csv");
    // Preserve semantic errors for the database preview, which reports row and field.
    result.push({
      source_row_number: sourceRowNumbers[index + 1] ?? index + 2,
      source_row_key: row[0], room_name: row[1], name: row[2], quantity: row[3],
      ...(row[4] === "" ? {} : { unit: row[4] }),
      ...(row[5] === "" ? {} : { condition: row[5] }),
    });
  }
  return result;
}
