import assert from "node:assert/strict";
import test from "node:test";
import { MediaValidationError, validateMediaBytes } from "../../../src/modules/media/media-validation.ts";

test("accepts the supported passive image/PDF signatures and hashes the exact object bytes", () => {
  const fixtures = [
    { kind: "image" as const, mime: "image/jpeg", bytes: Buffer.from([0xff, 0xd8, 0xff, 0xd9]) },
    { kind: "image" as const, mime: "image/png", bytes: Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) },
    { kind: "image" as const, mime: "image/webp", bytes: Buffer.from([0x52, 0x49, 0x46, 0x46, 4, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]) },
    { kind: "document" as const, mime: "application/pdf", bytes: Buffer.from("%PDF-1.7") },
  ];
  for (const fixture of fixtures) {
    const result = validateMediaBytes({
      kind: fixture.kind,
      declaredMime: fixture.mime,
      declaredSizeBytes: fixture.bytes.byteLength,
      declaredDurationSeconds: null,
      bytes: fixture.bytes,
    });
    assert.equal(result.mime, fixture.mime);
    assert.equal(result.sizeBytes, fixture.bytes.byteLength);
    assert.match(result.sha256, /^[a-f0-9]{64}$/);
  }
});

test("rejects declared size mismatch, unsupported/active MIME and signature spoofing", () => {
  const bytes = Buffer.from("<svg onload=alert(1)>");
  assert.throws(() => validateMediaBytes({
    kind: "image", declaredMime: "image/jpeg", declaredSizeBytes: bytes.byteLength + 1,
    declaredDurationSeconds: null, bytes,
  }), (error: unknown) => error instanceof MediaValidationError && error.code === "size_mismatch");
  assert.throws(() => validateMediaBytes({
    kind: "image", declaredMime: "image/svg+xml", declaredSizeBytes: bytes.byteLength,
    declaredDurationSeconds: null, bytes,
  }), (error: unknown) => error instanceof MediaValidationError && error.code === "mime_mismatch");
  const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  assert.throws(() => validateMediaBytes({
    kind: "image", declaredMime: "image/jpeg", declaredSizeBytes: png.byteLength,
    declaredDurationSeconds: null, bytes: png,
  }), (error: unknown) => error instanceof MediaValidationError && error.code === "mime_mismatch");
});

test("rejects photo above 15 MiB and MIME-kind mismatches", () => {
  const large = new Uint8Array(15 * 1024 * 1024 + 1);
  large.set([0xff, 0xd8, 0xff]);
  assert.throws(() => validateMediaBytes({
    kind: "image", declaredMime: "image/jpeg", declaredSizeBytes: large.byteLength,
    declaredDurationSeconds: null, bytes: large,
  }), (error: unknown) => error instanceof MediaValidationError && error.code === "size_limit");
  const pdf = Buffer.from("%PDF-1.7");
  assert.throws(() => validateMediaBytes({
    kind: "video", declaredMime: "application/pdf", declaredSizeBytes: pdf.byteLength,
    declaredDurationSeconds: 1, bytes: pdf,
  }), (error: unknown) => error instanceof MediaValidationError && error.code === "mime_mismatch");
});

function box(type: string, payload: Buffer): Buffer {
  const head = Buffer.alloc(8);
  head.writeUInt32BE(head.length + payload.length, 0);
  head.write(type, 4, 4, "ascii");
  return Buffer.concat([head, payload]);
}

function mp4(seconds: number, handler: "vide" | "soun"): Buffer {
  const ftyp = box("ftyp", Buffer.from("isom\0\0\0\0isom", "binary"));
  const mvhd = Buffer.alloc(20);
  mvhd.writeUInt32BE(1000, 12);
  mvhd.writeUInt32BE(seconds * 1000, 16);
  const hdlr = Buffer.alloc(12);
  hdlr.write(handler, 8, 4, "ascii");
  return Buffer.concat([ftyp, box("moov", Buffer.concat([box("mvhd", mvhd), box("trak", box("mdia", box("hdlr", hdlr)))]))]);
}

test("parses MP4 duration and distinguishes video from audio MP4", () => {
  for (const [kind, mime, handler] of [
    ["video", "video/mp4", "vide"],
    ["audio", "audio/mp4", "soun"],
  ] as const) {
    const bytes = mp4(12, handler);
    const result = validateMediaBytes({
      kind, declaredMime: mime, declaredSizeBytes: bytes.byteLength,
      declaredDurationSeconds: 12, bytes,
    });
    assert.equal(result.durationSeconds, 12);
  }
  const tooLong = mp4(301, "vide");
  assert.throws(() => validateMediaBytes({
    kind: "video", declaredMime: "video/mp4", declaredSizeBytes: tooLong.byteLength,
    declaredDurationSeconds: 301, bytes: tooLong,
  }), (error: unknown) => error instanceof MediaValidationError && error.code === "duration_limit");
});
