import { createHash } from "node:crypto";

export type MediaKind = "image" | "video" | "audio" | "document";
export type MediaMime =
  | "image/jpeg"
  | "image/png"
  | "image/webp"
  | "video/mp4"
  | "audio/webm"
  | "audio/mp4"
  | "application/pdf";

export type ValidatedMedia = {
  mime: MediaMime;
  sizeBytes: number;
  durationSeconds: number | null;
  sha256: string;
};

export class MediaValidationError extends Error {
  readonly code: "size_mismatch" | "size_limit" | "mime_mismatch" | "duration_limit" | "invalid_container";

  constructor(code: MediaValidationError["code"]) {
    super(code);
    this.code = code;
  }
}

const MAX_PHOTO_BYTES = 15 * 1024 * 1024;
const MAX_FILE_BYTES = 100 * 1024 * 1024;
const MAX_VIDEO_SECONDS = 300;
const MAX_AUDIO_SECONDS = 60;

/** Validate bytes downloaded from private Storage; client headers are never authoritative. */
export function validateMediaBytes(input: {
  kind: MediaKind;
  declaredMime: string;
  maxSizeBytes: number;
  declaredDurationSeconds: number | null;
  bytes: Uint8Array;
}): ValidatedMedia {
  const { kind, declaredMime, maxSizeBytes, declaredDurationSeconds, bytes } = input;
  if (!Number.isSafeInteger(maxSizeBytes) || maxSizeBytes < 1 || bytes.byteLength < 1) {
    throw new MediaValidationError("size_mismatch");
  }
  if (bytes.byteLength > maxSizeBytes) throw new MediaValidationError("size_limit");
  const maxBytes = kind === "image" ? MAX_PHOTO_BYTES : MAX_FILE_BYTES;
  if (bytes.byteLength > maxBytes) throw new MediaValidationError("size_limit");

  const actual = identifyContainer(bytes);
  if (!actual || actual.mime !== declaredMime || !mimeMatchesKind(kind, actual.mime)) {
    throw new MediaValidationError("mime_mismatch");
  }

  if (kind === "image" || kind === "document") {
    if (declaredDurationSeconds !== null) throw new MediaValidationError("duration_limit");
  } else {
    const maxDuration = kind === "video" ? MAX_VIDEO_SECONDS : MAX_AUDIO_SECONDS;
    if (actual.durationSeconds === null || actual.durationSeconds <= 0 || actual.durationSeconds > maxDuration
      || declaredDurationSeconds === null || !Number.isSafeInteger(declaredDurationSeconds)
      || Math.abs(actual.durationSeconds - declaredDurationSeconds) > 2) {
      throw new MediaValidationError("duration_limit");
    }
  }

  return {
    mime: actual.mime,
    sizeBytes: bytes.byteLength,
    durationSeconds: actual.durationSeconds,
    sha256: createHash("sha256").update(bytes).digest("hex"),
  };
}

function mimeMatchesKind(kind: MediaKind, mime: MediaMime): boolean {
  if (kind === "image") return mime.startsWith("image/");
  if (kind === "video") return mime === "video/mp4";
  if (kind === "audio") return mime === "audio/webm" || mime === "audio/mp4";
  return mime === "application/pdf";
}

function identifyContainer(bytes: Uint8Array): { mime: MediaMime; durationSeconds: number | null } | null {
  if (startsWith(bytes, [0xff, 0xd8, 0xff])) return { mime: "image/jpeg", durationSeconds: null };
  if (startsWith(bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return { mime: "image/png", durationSeconds: null };
  if (bytes.length >= 12 && ascii(bytes, 0, 4) === "RIFF" && ascii(bytes, 8, 12) === "WEBP"
    && readU32LE(bytes, 4) === bytes.length - 8) return { mime: "image/webp", durationSeconds: null };
  if (startsWith(bytes, [0x25, 0x50, 0x44, 0x46, 0x2d])) return { mime: "application/pdf", durationSeconds: null };
  if (startsWith(bytes, [0x1a, 0x45, 0xdf, 0xa3])) {
    const metadata = readWebmMetadata(bytes);
    return metadata?.durationSeconds === null || metadata === null || !metadata.hasAudio || metadata.hasVideo
      ? null : { mime: "audio/webm", durationSeconds: metadata.durationSeconds };
  }
  if (bytes.length >= 16 && ascii(bytes, 4, 8) === "ftyp") {
    const metadata = readMp4Metadata(bytes);
    if (!metadata || metadata.durationSeconds === null || (!metadata.hasAudio && !metadata.hasVideo)) return null;
    return { mime: metadata.hasAudio && !metadata.hasVideo ? "audio/mp4" : "video/mp4", durationSeconds: metadata.durationSeconds };
  }
  return null;
}

function readMp4Metadata(bytes: Uint8Array): { durationSeconds: number | null; hasVideo: boolean; hasAudio: boolean } | null {
  let offset = 0;
  while (offset + 8 <= bytes.length) {
    const size32 = readU32BE(bytes, offset);
    const type = ascii(bytes, offset + 4, offset + 8);
    let header = 8;
    let size = size32;
    if (size32 === 1) {
      if (offset + 16 > bytes.length) return null;
      const size64 = readU64BE(bytes, offset + 8);
      if (size64 > BigInt(Number.MAX_SAFE_INTEGER)) return null;
      size = Number(size64);
      header = 16;
    } else if (size32 === 0) {
      size = bytes.length - offset;
    }
    if (size < header || offset + size > bytes.length) return null;
    if (type === "moov") {
      const children = bytes.subarray(offset + header, offset + size);
      const durationSeconds = findMvhdDuration(children);
      const { hasVideo, hasAudio } = findMp4TrackKinds(children);
      return { durationSeconds, hasVideo, hasAudio };
    }
    offset += size;
  }
  return null;
}

function findMp4TrackKinds(bytes: Uint8Array): { hasVideo: boolean; hasAudio: boolean } {
  let offset = 0;
  let hasVideo = false;
  let hasAudio = false;
  while (offset + 8 <= bytes.length) {
    const size = readU32BE(bytes, offset);
    const type = ascii(bytes, offset + 4, offset + 8);
    if (size < 8 || offset + size > bytes.length) break;
    if (type === "trak") {
      const handler = findMp4Handler(bytes.subarray(offset + 8, offset + size));
      hasVideo ||= handler === "vide";
      hasAudio ||= handler === "soun";
    }
    offset += size;
  }
  return { hasVideo, hasAudio };
}

function findMp4Handler(bytes: Uint8Array): string | null {
  let offset = 0;
  while (offset + 8 <= bytes.length) {
    const size = readU32BE(bytes, offset);
    const type = ascii(bytes, offset + 4, offset + 8);
    if (size < 8 || offset + size > bytes.length) return null;
    if (type === "mdia") {
      let child = offset + 8;
      while (child + 8 <= offset + size) {
        const childSize = readU32BE(bytes, child);
        const childType = ascii(bytes, child + 4, child + 8);
        if (childSize < 8 || child + childSize > offset + size) return null;
        if (childType === "hdlr" && childSize >= 20) return ascii(bytes, child + 16, child + 20);
        child += childSize;
      }
    }
    offset += size;
  }
  return null;
}

function findMvhdDuration(bytes: Uint8Array): number | null {
  let offset = 0;
  while (offset + 8 <= bytes.length) {
    const size = readU32BE(bytes, offset);
    const type = ascii(bytes, offset + 4, offset + 8);
    if (size < 8 || offset + size > bytes.length) return null;
    if (type === "mvhd") {
      const payload = offset + 8;
      if (payload + 20 > offset + size) return null;
      const version = bytes[payload];
      if (version === 0) {
        const scale = readU32BE(bytes, payload + 12);
        const duration = readU32BE(bytes, payload + 16);
        return scale === 0 || duration === 0xffffffff ? null : duration / scale;
      }
      if (version === 1) {
        if (payload + 32 > offset + size) return null;
        const scale = readU32BE(bytes, payload + 20);
        const duration = readU64BE(bytes, payload + 24);
        return scale === 0 || duration === BigInt("18446744073709551615") ? null : Number(duration) / scale;
      }
      return null;
    }
    offset += size;
  }
  return null;
}

function readWebmMetadata(bytes: Uint8Array): { durationSeconds: number | null; hasVideo: boolean; hasAudio: boolean } | null {
  let offset = 0;
  const end = bytes.length;
  while (offset < end) {
    const id = readEbmlVint(bytes, offset, true);
    if (!id) return null;
    offset += id.length;
    const size = readEbmlVint(bytes, offset, false);
    if (!size) return null;
    offset += size.length;
    const elementEnd = size.value === -1 ? end : offset + size.value;
    if (elementEnd > end || elementEnd < offset) return null;
    if (id.value === 0x18538067) {
      const info = readWebmInfo(bytes, offset, elementEnd);
      const tracks = readWebmTrackKinds(bytes, offset, elementEnd);
      return info === null || tracks === null ? null : { durationSeconds: info, ...tracks };
    }
    offset = elementEnd;
  }
  return null;
}

function readWebmInfo(bytes: Uint8Array, start: number, end: number): number | null {
  let offset = start;
  let scale = 1_000_000;
  let duration: number | null = null;
  while (offset < end) {
    const id = readEbmlVint(bytes, offset, true);
    if (!id) return null;
    offset += id.length;
    const size = readEbmlVint(bytes, offset, false);
    if (!size || size.value < 0) return null;
    offset += size.length;
    const elementEnd = offset + size.value;
    if (elementEnd > end) return null;
    if (id.value === 0x2ad7b1 && size.value > 0 && size.value <= 4) {
      scale = 0;
      for (let i = offset; i < elementEnd; i++) scale = scale * 256 + bytes[i];
    } else if (id.value === 0x4489 && size.value > 0 && size.value <= 8) {
      duration = readEbmlFloat(bytes, offset, size.value);
    }
    offset = elementEnd;
  }
  return duration === null || scale <= 0 ? null : duration * scale / 1_000_000_000;
}

function readWebmTrackKinds(bytes: Uint8Array, start: number, end: number): { hasVideo: boolean; hasAudio: boolean } | null {
  let offset = start;
  let hasVideo = false;
  let hasAudio = false;
  while (offset < end) {
    const id = readEbmlVint(bytes, offset, true);
    if (!id) return null;
    offset += id.length;
    const size = readEbmlVint(bytes, offset, false);
    if (!size || size.value < 0) return null;
    offset += size.length;
    const elementEnd = offset + size.value;
    if (elementEnd > end) return null;
    if (id.value === 0x1654ae6b) {
      let track = offset;
      while (track < elementEnd) {
        const entryId = readEbmlVint(bytes, track, true);
        if (!entryId) return null;
        track += entryId.length;
        const entrySize = readEbmlVint(bytes, track, false);
        if (!entrySize || entrySize.value < 0) return null;
        track += entrySize.length;
        const entryEnd = track + entrySize.value;
        if (entryEnd > elementEnd) return null;
        if (entryId.value === 0xae) {
          let field = track;
          while (field < entryEnd) {
            const fieldId = readEbmlVint(bytes, field, true);
            if (!fieldId) return null;
            field += fieldId.length;
            const fieldSize = readEbmlVint(bytes, field, false);
            if (!fieldSize || fieldSize.value < 0) return null;
            field += fieldSize.length;
            const fieldEnd = field + fieldSize.value;
            if (fieldEnd > entryEnd) return null;
            if (fieldId.value === 0x83 && fieldSize.value >= 1 && fieldSize.value <= 4) {
              let type = 0;
              for (let i = field; i < fieldEnd; i++) type = type * 256 + bytes[i];
              hasVideo ||= type === 1;
              hasAudio ||= type === 2;
            }
            field = fieldEnd;
          }
        }
        track = entryEnd;
      }
    }
    offset = elementEnd;
  }
  return hasAudio || hasVideo ? { hasAudio, hasVideo } : null;
}

function readEbmlFloat(bytes: Uint8Array, offset: number, size: number): number | null {
  const view = new DataView(bytes.buffer, bytes.byteOffset + offset, size);
  if (size === 4) return view.getFloat32(0, false);
  if (size === 8) return view.getFloat64(0, false);
  return null;
}

function readEbmlVint(bytes: Uint8Array, offset: number, keepMarker: boolean): { value: number; length: number } | null {
  if (offset >= bytes.length) return null;
  const first = bytes[offset];
  let mask = 0x80;
  let length = 1;
  while (length <= 8 && (first & mask) === 0) { mask >>= 1; length++; }
  if (length > 8 || offset + length > bytes.length) return null;
  let value = keepMarker ? first : first & (mask - 1);
  for (let i = 1; i < length; i++) value = value * 256 + bytes[offset + i];
  if (!keepMarker && value === 2 ** (7 * length) - 1) return { value: -1, length };
  return { value, length };
}

function startsWith(bytes: Uint8Array, prefix: number[]): boolean {
  return bytes.length >= prefix.length && prefix.every((value, index) => bytes[index] === value);
}

function ascii(bytes: Uint8Array, start: number, end: number): string {
  return String.fromCharCode(...bytes.subarray(start, end));
}

function readU32BE(bytes: Uint8Array, offset: number): number {
  return ((bytes[offset] * 0x1000000) + (bytes[offset + 1] << 16) + (bytes[offset + 2] << 8) + bytes[offset + 3]) >>> 0;
}

function readU32LE(bytes: Uint8Array, offset: number): number {
  return (bytes[offset] | bytes[offset + 1] << 8 | bytes[offset + 2] << 16 | bytes[offset + 3] << 24) >>> 0;
}

function readU64BE(bytes: Uint8Array, offset: number): bigint {
  return BigInt(readU32BE(bytes, offset)) * BigInt(0x100000000) + BigInt(readU32BE(bytes, offset + 4));
}
