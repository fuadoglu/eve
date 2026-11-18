import assert from "node:assert/strict";
import test from "node:test";
import ExcelJS from "exceljs";
import { InventoryImportParseError, INVENTORY_IMPORT_HEADERS } from "../../../src/modules/inventory/import-parser-csv.ts";
import { parseInventoryXlsx } from "../../../src/modules/inventory/import-parser-xlsx.ts";

async function workbookBytes(setup: (sheet: ExcelJS.Worksheet) => void): Promise<Uint8Array> {
  const workbook = new ExcelJS.Workbook();
  setup(workbook.addWorksheet("Inventory"));
  const buffer = await workbook.xlsx.writeBuffer();
  return new Uint8Array(buffer);
}

test("XLSX parses the inventory template and normalizes blank optional cells", async () => {
  const bytes = await workbookBytes((sheet) => {
    sheet.addRow([...INVENTORY_IMPORT_HEADERS]);
    sheet.addRow(["A-1", "Yataq", "Lampa", 2, "piece", "ok"]);
    sheet.addRow(["A-2", "Mətbəx", "Stəkan", 6, null, null]);
  });
  assert.deepEqual(await parseInventoryXlsx(bytes), [
    { source_row_key: "A-1", room_name: "Yataq", name: "Lampa", quantity: "2", unit: "piece", condition: "ok" },
    { source_row_key: "A-2", room_name: "Mətbəx", name: "Stəkan", quantity: "6" },
  ]);
});

test("XLSX rejects wrong headers, formulas, and workbook extras", async () => {
  const wrong = await workbookBytes((sheet) => { sheet.addRow(["name", "quantity"]); sheet.addRow(["Lamp", 1]); });
  await assert.rejects(parseInventoryXlsx(wrong), (e) => e instanceof InventoryImportParseError && e.code === "invalid_header");
  const formula = await workbookBytes((sheet) => {
    sheet.addRow([...INVENTORY_IMPORT_HEADERS]); sheet.addRow(["A", "R", "N", { formula: "1+1" }, "piece", "ok"]);
  });
  await assert.rejects(parseInventoryXlsx(formula), (e) => e instanceof InventoryImportParseError && e.code === "unsafe_xlsx");
  const multiple = await workbookBytes((sheet) => {
    sheet.addRow([...INVENTORY_IMPORT_HEADERS]); sheet.addRow(["A", "R", "N", 1, "piece", "ok"]);
    sheet.workbook.addWorksheet("Extra");
  });
  await assert.rejects(parseInventoryXlsx(multiple), (e) => e instanceof InventoryImportParseError && e.code === "unsupported_xlsx");
});

test("XLSX rejects invalid ZIP and file byte limit", async () => {
  await assert.rejects(parseInventoryXlsx(new Uint8Array([1, 2, 3])), /invalid_xlsx/);
  await assert.rejects(parseInventoryXlsx(new Uint8Array(10 * 1024 * 1024 + 1)), /file_too_large/);
});
