/** Compile-time guardrails mirrored by configuration.json and checked by CI. */
export const INVENTORY_IMPORT_LIMITS = {
  maxFileBytes: 10_485_760,
  maxRows: 5_000,
  maxColumns: 6,
  maxCellCharacters: 2_000,
  previewErrorLimit: 1_000,
  xlsx: {
    maxEntries: 128,
    maxEntryUncompressedBytes: 16_777_216,
    maxTotalUncompressedBytes: 33_554_432,
    maxCompressionRatio: 300,
    maxWorksheets: 1,
  },
} as const;
