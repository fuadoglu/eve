import { inflateRawSync } from "node:zlib";
import { INVENTORY_IMPORT_MAX_BYTES, InventoryImportParseError } from "./import-parser-csv.ts";
import { INVENTORY_IMPORT_LIMITS } from "./import-parser-limits.ts";

const { maxEntries, maxEntryUncompressedBytes, maxTotalUncompressedBytes, maxCompressionRatio } = INVENTORY_IMPORT_LIMITS.xlsx;

type Entry = { name: string; crc: number; compressed: number; uncompressed: number;
  offset: number; method: number; flags: number };

/** Bounded ZIP preflight before ExcelJS sees untrusted XLSX bytes. This does not parse OOXML. */
export function guardInventoryXlsxZip(bytes: Uint8Array): void {
  if (bytes.byteLength > INVENTORY_IMPORT_MAX_BYTES) throw new InventoryImportParseError("file_too_large");
  if (bytes.byteLength < 22) throw new InventoryImportParseError("invalid_xlsx");
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const u16 = (at: number) => view.getUint16(at, true);
  const u32 = (at: number) => view.getUint32(at, true);
  let eocd = -1;
  for (let at = bytes.length - 22; at >= Math.max(0, bytes.length - 65_557); at--) {
    if (u32(at) === 0x06054b50 && at + 22 + u16(at + 20) === bytes.length) { eocd = at; break; }
  }
  if (eocd < 0 || u16(eocd + 4) !== 0 || u16(eocd + 6) !== 0
    || u16(eocd + 8) !== u16(eocd + 10) || u16(eocd + 10) > maxEntries
    || u16(eocd + 10) === 0) throw new InventoryImportParseError("invalid_xlsx");
  const directorySize = u32(eocd + 12);
  const directoryOffset = u32(eocd + 16);
  if (directorySize === 0xffffffff || directoryOffset === 0xffffffff
    || directoryOffset + directorySize !== eocd) throw new InventoryImportParseError("unsupported_xlsx");
  let at = directoryOffset;
  const entries: Entry[] = [];
  const names = new Set<string>();
  let total = 0;
  for (let i = 0; i < u16(eocd + 10); i++) {
    if (at + 46 > eocd || u32(at) !== 0x02014b50) throw new InventoryImportParseError("invalid_xlsx");
    const flags = u16(at + 8), method = u16(at + 10);
    const crc = u32(at + 16), compressed = u32(at + 20), uncompressed = u32(at + 24);
    const nameLength = u16(at + 28), extraLength = u16(at + 30), commentLength = u16(at + 32);
    const localOffset = u32(at + 42);
    if (at + 46 + nameLength + extraLength + commentLength > eocd
      || compressed === 0xffffffff || uncompressed === 0xffffffff || localOffset === 0xffffffff
      || (flags & 0x41) !== 0 || ![0, 8].includes(method)) throw new InventoryImportParseError("unsafe_xlsx");
    const nameBytes = bytes.subarray(at + 46, at + 46 + nameLength);
    const name = decodeName(nameBytes, (flags & 0x800) !== 0);
    if (!name || !/^[A-Za-z0-9_./\[\]-]+$/.test(name) || name.startsWith("/")
      || name.split("/").includes("..") || names.has(name.toLowerCase())
      || /(^|\/)(vbaProject\.bin|externalLinks|embeddings)(\/|$)/i.test(name)) {
      throw new InventoryImportParseError("unsafe_xlsx");
    }
    names.add(name.toLowerCase());
    if (name.endsWith("/") && (compressed !== 0 || uncompressed !== 0)) throw new InventoryImportParseError("unsafe_xlsx");
    if (uncompressed > maxEntryUncompressedBytes || (compressed === 0 && uncompressed !== 0)
      || (compressed > 0 && uncompressed / compressed > maxCompressionRatio)) {
      throw new InventoryImportParseError("unsafe_xlsx");
    }
    total += uncompressed;
    if (total > maxTotalUncompressedBytes) throw new InventoryImportParseError("unsafe_xlsx");
    // Unix symlink entries can redirect a consumer that extracts by name.
    const unixMode = u16(at + 40) >>> 12;
    if (u16(at + 4) >>> 8 === 3 && unixMode === 0xa) throw new InventoryImportParseError("unsafe_xlsx");
    entries.push({ name, crc, compressed, uncompressed, offset: localOffset, method, flags });
    at += 46 + nameLength + extraLength + commentLength;
  }
  if (at !== eocd || !names.has("[content_types].xml")
    || !names.has("xl/workbook.xml") || !names.has("xl/_rels/workbook.xml.rels")) {
    throw new InventoryImportParseError("invalid_xlsx");
  }
  const intervals: Array<[number, number]> = [];
  for (const entry of entries) {
    const start = entry.offset;
    if (start + 30 > directoryOffset || u32(start) !== 0x04034b50
      || u16(start + 6) !== entry.flags || u16(start + 8) !== entry.method) {
      throw new InventoryImportParseError("invalid_xlsx");
    }
    const localNameLength = u16(start + 26), localExtraLength = u16(start + 28);
    const dataStart = start + 30 + localNameLength + localExtraLength;
    const dataEnd = dataStart + entry.compressed;
    if (dataEnd > directoryOffset
      || decodeName(bytes.subarray(start + 30, start + 30 + localNameLength), (entry.flags & 0x800) !== 0) !== entry.name) {
      throw new InventoryImportParseError("invalid_xlsx");
    }
    let end = dataEnd;
    if ((entry.flags & 0x8) !== 0) {
      if (dataEnd + 12 > directoryOffset) throw new InventoryImportParseError("invalid_xlsx");
      const hasSignature = u32(dataEnd) === 0x08074b50;
      const data = dataEnd + (hasSignature ? 4 : 0);
      if (data + 12 > directoryOffset || u32(data) !== entry.crc
        || u32(data + 4) !== entry.compressed || u32(data + 8) !== entry.uncompressed) {
        throw new InventoryImportParseError("invalid_xlsx");
      }
      end = data + 12;
    } else if (u32(start + 14) !== entry.crc || u32(start + 18) !== entry.compressed
      || u32(start + 22) !== entry.uncompressed) throw new InventoryImportParseError("invalid_xlsx");
    intervals.push([start, end]);
    const compressedBytes = bytes.subarray(dataStart, dataEnd);
    let contents: Uint8Array;
    try {
      contents = entry.method === 0 ? compressedBytes : inflateRawSync(compressedBytes, { maxOutputLength: entry.uncompressed + 1 });
    } catch { throw new InventoryImportParseError("invalid_xlsx"); }
    if (contents.byteLength !== entry.uncompressed || crc32(contents) !== entry.crc) {
      throw new InventoryImportParseError("invalid_xlsx");
    }
    if (/\.(xml|rels)$/i.test(entry.name)) {
      const xml = new TextDecoder("utf-8", { fatal: true });
      let decoded: string;
      try { decoded = xml.decode(contents); } catch { throw new InventoryImportParseError("invalid_xlsx"); }
      if (/<!\s*(DOCTYPE|ENTITY)/i.test(decoded)) throw new InventoryImportParseError("unsafe_xlsx");
    }
  }
  intervals.sort((a, b) => a[0] - b[0]);
  for (let i = 1; i < intervals.length; i++) {
    if (intervals[i][0] < intervals[i - 1][1]) throw new InventoryImportParseError("unsafe_xlsx");
  }
  if (intervals.some(([, end]) => end > directoryOffset)) throw new InventoryImportParseError("unsafe_xlsx");
}

function decodeName(bytes: Uint8Array, utf8: boolean): string {
  try { return new TextDecoder(utf8 ? "utf-8" : "ascii", { fatal: true }).decode(bytes); }
  catch { throw new InventoryImportParseError("unsafe_xlsx"); }
}

function crc32(bytes: Uint8Array): number {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (-(crc & 1) & 0xedb88320);
  }
  return (crc ^ 0xffffffff) >>> 0;
}
