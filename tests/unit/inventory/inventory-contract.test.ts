import assert from "node:assert/strict";
import test from "node:test";

import {
  validateImportPreview,
  validateInventoryCopyInput,
  validateInventoryImportPreviewInput,
} from "../../../src/modules/inventory/inventory-contract.ts";

const propertyId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const mediaId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const previewId = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const previewHash = "a".repeat(64);

test("inventory copy follows OpenAPI source field and false media default", () => {
  assert.deepEqual(validateInventoryCopyInput({ source_property_id: propertyId }), {
    source_property_id: propertyId,
  });
  assert.deepEqual(validateInventoryCopyInput({ source_property_id: propertyId, include_media: false }), {
    source_property_id: propertyId,
    include_media: false,
  });
  assert.throws(() => validateInventoryCopyInput({ source_property_id: propertyId, include_media: "yes" }), TypeError);
  assert.throws(() => validateInventoryCopyInput({ source_property_id: propertyId, source_id: propertyId }), TypeError);
});

test("import preview input preserves the documented property, kind, and private media fields", () => {
  assert.deepEqual(validateInventoryImportPreviewInput({
    property_id: propertyId,
    kind: "inventory",
    media_id: mediaId,
  }), {
    property_id: propertyId,
    kind: "inventory",
    media_id: mediaId,
  });
  assert.throws(() => validateInventoryImportPreviewInput({
    property_id: propertyId,
    kind: "inventory",
    media_id: mediaId,
    rows: [],
  }), TypeError);
  assert.throws(() => validateInventoryImportPreviewInput({
    property_id: propertyId,
    kind: "inventory_items",
    media_id: mediaId,
  }), TypeError);
  assert.throws(() => validateInventoryImportPreviewInput({
    property_id: propertyId,
    kind: "reservations",
    media_id: mediaId,
  }), TypeError);
});

test("import preview accepts a bounded server acknowledgement and reports row errors", () => {
  const acknowledgement = {
    id: previewId,
    property_id: propertyId,
    kind: "inventory",
    state: "invalid",
    preview_hash: previewHash,
    row_count: 2,
    errors: [{ row: 2, field: "quantity", message: "Dəyər yanlışdır" }],
    version: 1,
    created_at: "2026-11-13T10:00:00Z",
    updated_at: "2026-11-13T10:00:00+04:00",
  };

  assert.deepEqual(validateImportPreview(acknowledgement), acknowledgement);
  assert.throws(() => validateImportPreview({ ...acknowledgement, preview_hash: "short" }), TypeError);
  assert.throws(() => validateImportPreview({ ...acknowledgement, errors: [{ row: 0, field: "quantity", message: "x" }] }), TypeError);
  assert.throws(() => validateImportPreview({ ...acknowledgement, row_count: 1_000_001 }), TypeError);
  assert.throws(() => validateImportPreview({ ...acknowledgement, invented: true }), TypeError);
  assert.throws(() => validateImportPreview({ ...acknowledgement, created_at: "2026-02-30T10:00:00Z" }), TypeError);
  assert.doesNotThrow(() => validateImportPreview({
    ...acknowledgement,
    created_at: "2024-02-29T10:00:00Z",
  }));
  assert.doesNotThrow(() => validateImportPreview({
    ...acknowledgement,
    created_at: "2016-12-31t23:59:60z",
  }));
  assert.doesNotThrow(() => validateImportPreview({
    ...acknowledgement,
    created_at: "2017-01-01T03:59:60+04:00",
  }));
  assert.throws(() => validateImportPreview({
    ...acknowledgement,
    created_at: "2016-12-30T23:59:60Z",
  }), TypeError);
});
