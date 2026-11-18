import assert from "node:assert/strict";
import test from "node:test";
import { InventoryImportParseError, parseInventoryCsv } from "../../../src/modules/inventory/import-parser-csv.ts";

const encoder = new TextEncoder();
const header = "source_row_key,room_name,name,quantity,unit,condition";
const parse = (csv: string) => parseInventoryCsv(encoder.encode(csv));

test("CSV template parses quoted commas, newlines, escaped quotes and optional defaults", () => {
  assert.deepEqual(parse(`\ufeff${header}\r\nA-1,"Yataq, 1","Stol ""yeni""",2.5,piece,ok\r\nA-2,"Qonaq\n otağı",Lampa,1,,\r\n`), [
    { source_row_number: 2, source_row_key: "A-1", room_name: "Yataq, 1", name: 'Stol "yeni"', quantity: "2.5", unit: "piece", condition: "ok" },
    { source_row_number: 3, source_row_key: "A-2", room_name: "Qonaq\n otağı", name: "Lampa", quantity: "1" },
  ]);
});

test("CSV rejects malformed structural input and wrong template", () => {
  for (const [csv, code] of [
    ["", "empty_file"], [header, "empty_file"],
    [`${header}\nA,R,N,1,piece`, "invalid_csv"],
    [`${header}\nA,R,N,1,piece,ok,extra`, "too_many_columns"],
    [`${header}\nA,R,\"broken,1,piece,ok`, "invalid_csv"],
    [`${header}\nA,R,\"ok\"tail,1,piece,ok`, "invalid_csv"],
    [`source_row_key,name,room_name,quantity,unit,condition\nA,R,N,1,piece,ok`, "invalid_header"],
  ] as const) {
    assert.throws(() => parse(csv), (error) => error instanceof InventoryImportParseError && error.code === code, csv);
  }
});

test("CSV rejects invalid UTF-8, NUL and row/file bounds", () => {
  assert.throws(() => parseInventoryCsv(new Uint8Array([0xff])), /invalid_utf8/);
  assert.throws(() => parse(`${header}\nA,R,N,1,piece,o\0k`), /invalid_csv/);
  assert.throws(() => parseInventoryCsv(new Uint8Array(10 * 1024 * 1024 + 1)), /file_too_large/);
  const rows = Array.from({ length: 5_001 }, (_, i) => `${i},R,N,1,piece,ok`);
  assert.throws(() => parse(`${header}\n${rows.join("\n")}`), /too_many_rows/);
});

test("semantic errors stay in rows for DB preview instead of partial import", () => {
  assert.deepEqual(parse(`${header}\ndup,R,N,0,bad,missing\ndup,R,N,1,piece,ok`), [
    { source_row_number: 2, source_row_key: "dup", room_name: "R", name: "N", quantity: "0", unit: "bad", condition: "missing" },
    { source_row_number: 3, source_row_key: "dup", room_name: "R", name: "N", quantity: "1", unit: "piece", condition: "ok" },
  ]);
});
