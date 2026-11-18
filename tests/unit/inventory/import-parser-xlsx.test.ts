import assert from "node:assert/strict";
import test from "node:test";
import { deflateRawSync } from "node:zlib";
import ExcelJS from "exceljs";
import { InventoryImportParseError, INVENTORY_IMPORT_HEADERS } from "../../../src/modules/inventory/import-parser-csv.ts";
import { parseInventoryXlsx } from "../../../src/modules/inventory/import-parser-xlsx.ts";
import { guardInventoryXlsxZip } from "../../../src/modules/inventory/import-parser-zip-guard.ts";

async function workbookBytes(setup: (sheet: ExcelJS.Worksheet) => void): Promise<Uint8Array> {
  const workbook = new ExcelJS.Workbook();
  setup(workbook.addWorksheet("Inventory"));
  const buffer = await workbook.xlsx.writeBuffer();
  return new Uint8Array(buffer);
}

type ZipFixtureEntry = {
  name: string;
  data: Uint8Array;
  method?: 0 | 8;
  declaredUncompressedBytes?: number;
};

function zipFixture(entries: readonly ZipFixtureEntry[]): Uint8Array {
  const local: Buffer[] = [];
  const central: Buffer[] = [];
  let offset = 0;
  for (const entry of entries) {
    const name = Buffer.from(entry.name, "ascii");
    const input = Buffer.from(entry.data);
    const method = entry.method ?? 8;
    const compressed = method === 8 ? deflateRawSync(input) : input;
    const crc = crc32(input);
    const uncompressed = entry.declaredUncompressedBytes ?? input.byteLength;
    const localHeader = Buffer.alloc(30);
    localHeader.writeUInt32LE(0x04034b50, 0);
    localHeader.writeUInt16LE(20, 4);
    localHeader.writeUInt16LE(method, 8);
    localHeader.writeUInt32LE(crc, 14);
    localHeader.writeUInt32LE(compressed.byteLength, 18);
    localHeader.writeUInt32LE(uncompressed, 22);
    localHeader.writeUInt16LE(name.byteLength, 26);
    local.push(localHeader, name, compressed);

    const directoryHeader = Buffer.alloc(46);
    directoryHeader.writeUInt32LE(0x02014b50, 0);
    directoryHeader.writeUInt16LE(20, 4);
    directoryHeader.writeUInt16LE(20, 6);
    directoryHeader.writeUInt16LE(method, 10);
    directoryHeader.writeUInt32LE(crc, 16);
    directoryHeader.writeUInt32LE(compressed.byteLength, 20);
    directoryHeader.writeUInt32LE(uncompressed, 24);
    directoryHeader.writeUInt16LE(name.byteLength, 28);
    directoryHeader.writeUInt32LE(offset, 42);
    central.push(directoryHeader, name);
    offset += localHeader.byteLength + name.byteLength + compressed.byteLength;
  }
  const directory = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(directory.byteLength, 12);
  end.writeUInt32LE(offset, 16);
  return new Uint8Array(Buffer.concat([...local, directory, end]));
}

function crc32(bytes: Uint8Array): number {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (-(crc & 1) & 0xedb88320);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

const requiredZipEntries = () => [
  { name: "[Content_Types].xml", data: Buffer.from("<Types/>") },
  { name: "xl/workbook.xml", data: Buffer.from("<workbook/>") },
  { name: "xl/_rels/workbook.xml.rels", data: Buffer.from("<Relationships/>") },
] as const;

test("XLSX parses the inventory template and normalizes blank optional cells", async () => {
  const bytes = await workbookBytes((sheet) => {
    sheet.addRow([...INVENTORY_IMPORT_HEADERS]);
    sheet.addRow(["A-1", "Yataq", "Lampa", 2, "piece", "ok"]);
    sheet.addRow(["A-2", "Mətbəx", "Stəkan", 6, null, null]);
  });
  assert.deepEqual(await parseInventoryXlsx(bytes), [
    { source_row_number: 2, source_row_key: "A-1", room_name: "Yataq", name: "Lampa", quantity: "2", unit: "piece", condition: "ok" },
    { source_row_number: 3, source_row_key: "A-2", room_name: "Mətbəx", name: "Stəkan", quantity: "6" },
  ]);
});

test("XLSX preserves the source worksheet row after a blank row", async () => {
  const bytes = await workbookBytes((sheet) => {
    sheet.addRow([...INVENTORY_IMPORT_HEADERS]);
    sheet.addRow(["A-1", "Yataq", "Lampa", 2, "piece", "ok"]);
    sheet.getRow(3);
    sheet.getRow(4).values = ["A-2", "Mətbəx", "", "bad", "piece", "ok"];
  });
  assert.deepEqual(await parseInventoryXlsx(bytes), [
    { source_row_number: 2, source_row_key: "A-1", room_name: "Yataq", name: "Lampa", quantity: "2", unit: "piece", condition: "ok" },
    { source_row_number: 4, source_row_key: "A-2", room_name: "Mətbəx", name: "", quantity: "bad", unit: "piece", condition: "ok" },
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

test("XLSX ZIP preflight accepts a bounded archive and rejects compression bombs", () => {
  assert.doesNotThrow(() => guardInventoryXlsxZip(zipFixture(requiredZipEntries())));
  const bomb = zipFixture([
    { name: "[Content_Types].xml", data: Buffer.from("A".repeat(300_000)) },
    ...requiredZipEntries().slice(1),
  ]);
  assert.throws(() => guardInventoryXlsxZip(bomb), (error) =>
    error instanceof InventoryImportParseError && error.code === "unsafe_xlsx");
});

test("XLSX ZIP preflight rejects entry, per-entry and aggregate inflate ceilings", () => {
  const tooManyEntries = Array.from({ length: 129 }, (_, index) => ({
    name: `extra-${index}.bin`, data: new Uint8Array(), method: 0 as const,
  }));
  assert.throws(() => guardInventoryXlsxZip(zipFixture(tooManyEntries)), /invalid_xlsx/);

  const oversizedEntry = zipFixture([{
    name: "[Content_Types].xml", data: new Uint8Array(60_000), method: 0,
    declaredUncompressedBytes: 17_000_000,
  }]);
  assert.throws(() => guardInventoryXlsxZip(oversizedEntry), /unsafe_xlsx/);

  const oversizedAggregate = zipFixture(requiredZipEntries().map((entry) => ({
    ...entry, data: new Uint8Array(50_000), method: 0 as const, declaredUncompressedBytes: 12_000_000,
  })));
  assert.throws(() => guardInventoryXlsxZip(oversizedAggregate), /unsafe_xlsx/);
});

test("XLSX ZIP preflight rejects traversal paths and XML entity declarations", () => {
  const traversal = zipFixture([...requiredZipEntries(), { name: "../escape.xml", data: Buffer.from("<x/>") }]);
  assert.throws(() => guardInventoryXlsxZip(traversal), /unsafe_xlsx/);

  const entity = zipFixture([
    { name: "[Content_Types].xml", data: Buffer.from("<Types/>") },
    { name: "xl/workbook.xml", data: Buffer.from('<!DOCTYPE a [<!ENTITY x "y">]><a>&x;</a>') },
    requiredZipEntries()[2],
  ]);
  assert.throws(() => guardInventoryXlsxZip(entity), /unsafe_xlsx/);
});
