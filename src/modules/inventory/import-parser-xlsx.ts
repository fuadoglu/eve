import ExcelJS from "exceljs";
import {
  INVENTORY_IMPORT_MAX_ROWS,
  InventoryImportParseError,
  normalizeInventoryTable,
  type InventoryImportRow,
} from "./import-parser-csv.ts";
import { guardInventoryXlsxZip } from "./import-parser-zip-guard.ts";

const MAX_WORKSHEETS = 1;
const MAX_COLUMNS = 6;
const MAX_CELL_TEXT = 2_000;

/** Parse the documented inventory template; formulas and workbook links are never evaluated. */
export async function parseInventoryXlsx(bytes: Uint8Array): Promise<InventoryImportRow[]> {
  guardInventoryXlsxZip(bytes);
  try {
    const workbook = new ExcelJS.Workbook();
    const input = Buffer.from(bytes) as unknown as Parameters<typeof workbook.xlsx.load>[0];
    await workbook.xlsx.load(input);
    if (workbook.worksheets.length !== MAX_WORKSHEETS) {
      throw new InventoryImportParseError("unsupported_xlsx");
    }
    const sheet = workbook.worksheets[0];
    if (sheet.rowCount > INVENTORY_IMPORT_MAX_ROWS + 1 || sheet.columnCount > MAX_COLUMNS) {
      throw new InventoryImportParseError(sheet.rowCount > INVENTORY_IMPORT_MAX_ROWS + 1 ? "too_many_rows" : "too_many_columns");
    }
    const table: string[][] = [];
    sheet.eachRow({ includeEmpty: true }, (row) => {
      const values: string[] = [];
      for (let index = 1; index <= MAX_COLUMNS; index++) {
        const cell = row.getCell(index);
        if (cell.type === ExcelJS.ValueType.Formula || cell.type === ExcelJS.ValueType.Hyperlink
          || cell.type === ExcelJS.ValueType.RichText || cell.type === ExcelJS.ValueType.Merge) {
          throw new InventoryImportParseError("unsafe_xlsx");
        }
        const value = cell.value;
        if (value === null || value === undefined) values.push("");
        else if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
          const text = String(value);
          if (text.length > MAX_CELL_TEXT) throw new InventoryImportParseError("invalid_xlsx");
          values.push(text);
        } else throw new InventoryImportParseError("unsafe_xlsx");
      }
      if (values.some((value) => value !== "")) table.push(values);
      if (table.length > INVENTORY_IMPORT_MAX_ROWS + 1) throw new InventoryImportParseError("too_many_rows");
    });
    return normalizeInventoryTable(table);
  } catch (error) {
    if (error instanceof InventoryImportParseError) throw error;
    throw new InventoryImportParseError("invalid_xlsx");
  }
}
