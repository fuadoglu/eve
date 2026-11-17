import assert from "node:assert/strict";
import test from "node:test";
import { filterCalendarData, getAgendaOccurrences, getCalendarOwnerOptions, getCalendarRange, isCalendarHoldExpired, parseCalendarEnvelope, parseCalendarQuery } from "../../../src/modules/reservations/calendar-contract.ts";

const propertyA = "f9300000-0000-4000-8000-000000000001";
const propertyB = "f9300000-0000-4000-8000-000000000002";
const idA = "f9400000-0000-4000-8000-000000000001";
const idB = "f9400000-0000-4000-8000-000000000002";
const idC = "f9400000-0000-4000-8000-000000000003";
const requestId = "f9500000-0000-4000-8000-000000000001";

test("calendar parser keeps the fields the view needs and discards private DTO fields", () => {
  const parsed = parseCalendarEnvelope({
    data: {
      from: "2027-02-01",
      to: "2027-03-01",
      reservations: [{
        id: idA,
        property_id: propertyA,
        guest_name: "Qonaq",
        guest_phone: "+994501234567",
        check_in: "2027-02-10",
        check_out: "2027-02-12",
        status: "confirmed",
        hold_expires_at: null,
        total_minor: 50000,
        balance: { remaining_minor: 10000 },
      }, {
        id: idC, property_id: propertyA, guest_name: "Müddəti bitmiş hold",
        check_in: "2027-02-20", check_out: "2027-02-22", status: "hold",
        hold_expires_at: "2027-01-01T10:00:00Z",
      }],
      blocks: [{ id: idB, property_id: propertyB, check_in: "2027-02-15", check_out: "2027-02-16", reason: "private reason" }],
    },
    meta: { request_id: requestId },
  });

  assert.deepEqual(parsed.data.reservations[0], {
    id: idA, property_id: propertyA, guest_name: "Qonaq", check_in: "2027-02-10", check_out: "2027-02-12", status: "confirmed", hold_expires_at: null,
  });
  assert.equal(parsed.data.reservations[1].hold_expires_at, "2027-01-01T10:00:00Z");
  assert.deepEqual(parsed.data.blocks[0], { id: idB, property_id: propertyB, check_in: "2027-02-15", check_out: "2027-02-16" });
  assert.equal(JSON.stringify(parsed).includes("+994501234567"), false);
  assert.equal(JSON.stringify(parsed).includes("private reason"), false);
});

test("calendar parser rejects invalid and overlong ranges", () => {
  const base = { reservations: [], blocks: [], from: "2027-01-01", to: "2027-02-01" };
  assert.throws(() => parseCalendarEnvelope({ data: { ...base, from: "2027-02-30" }, meta: { request_id: requestId } }));
  assert.throws(() => parseCalendarEnvelope({
    data: { ...base, to: "2027-04-05" }, meta: { request_id: requestId },
  }));
});

test("calendar query matches documented required fields, repeated IDs and bounds", () => {
  const valid = new URLSearchParams({ from: "2027-02-01", to: "2027-03-01" });
  valid.append("property_ids", propertyA);
  valid.append("property_ids", propertyB);
  assert.deepEqual(parseCalendarQuery(valid), {
    from: "2027-02-01", to: "2027-03-01", propertyIds: [propertyA, propertyB],
  });

  assert.equal(parseCalendarQuery(new URLSearchParams({ from: "2027-02-01", to: "2027-03-01" })), null);
  const unknown = new URLSearchParams(valid);
  unknown.set("owner_account_id", propertyA);
  assert.equal(parseCalendarQuery(unknown), null);
  const overlong = new URLSearchParams({ from: "2027-01-01", to: "2027-04-05", property_ids: propertyA });
  assert.equal(parseCalendarQuery(overlong), null);
});

test("month view requests a Monday-aligned bounded grid", () => {
  const range = getCalendarRange("2027-02-15");
  assert.deepEqual(range, { from: "2027-02-01", to: "2027-03-01" });
  const gridDays = (Date.parse(`${range.to}T00:00:00Z`) - Date.parse(`${range.from}T00:00:00Z`)) / 86_400_000;
  assert.ok(gridDays >= 28 && gridDays <= 42);
  assert.throws(() => getCalendarRange("2027-02-30"));
});

test("calendar filtering follows property selection and half-open stay overlap", () => {
  const data = parseCalendarEnvelope({
    data: {
      from: "2027-02-01", to: "2027-03-01",
      reservations: [
        { id: idA, property_id: propertyA, guest_name: "A", check_in: "2027-01-31", check_out: "2027-02-02", status: "confirmed" },
        { id: idB, property_id: propertyB, guest_name: "B", check_in: "2027-02-28", check_out: "2027-03-01", status: "hold" },
      ],
      blocks: [],
    },
    meta: { request_id: requestId },
  }).data;

  const filtered = filterCalendarData(data, new Set([propertyA]), "2027-02-01", "2027-03-01");
  assert.deepEqual(filtered.reservations.map((reservation) => reservation.id), [idA]);
  assert.equal(filtered.from, "2027-02-01");
  assert.equal(filtered.to, "2027-03-01");
});

test("agenda keeps occupancy that began before the selected range visible", () => {
  assert.deepEqual(getAgendaOccurrences([
    { id: idA, kind: "reservation", checkIn: "2027-01-31", checkOut: "2027-02-28" },
    { id: idB, kind: "block", checkIn: "2027-01-15", checkOut: "2027-04-01" },
  ], "2027-02-01", "2027-03-01"), [
    { id: idA, date: "2027-02-01", label: "Davam edir" },
    { id: idA, date: "2027-02-28", label: "Çıxış" },
    { id: idB, date: "2027-02-01", label: "Davam edir" },
  ]);
});

test("owner filter uses names and disambiguates duplicate display names", () => {
  const options = getCalendarOwnerOptions([
    { id: propertyA, owner_account_id: "f9600000-0000-4000-8000-000000000001", owner_display_name: "Aysel", name: "Ev A", area: "Bakı" },
    { id: propertyB, owner_account_id: "f9600000-0000-4000-8000-000000000001", owner_display_name: "Aysel", name: "Ev B", area: "Bakı" },
    { id: idA, owner_account_id: "f9600000-0000-4000-8000-000000000002", owner_display_name: "Aysel", name: "Ev C", area: "Bakı" },
  ]);
  assert.equal(options.length, 2);
  assert.ok(options.every((option) => option.label.startsWith("Aysel · ")));
  assert.notEqual(options[0].label, options[1].label);
});

test("calendar identifies expired holds without mutating the reservation", () => {
  const now = Date.parse("2027-02-01T12:00:00Z");
  assert.equal(isCalendarHoldExpired("hold", "2027-02-01T10:00:00Z", now), true);
  assert.equal(isCalendarHoldExpired("hold", "2027-02-01T13:00:00Z", now), false);
  assert.equal(isCalendarHoldExpired("confirmed", "2027-02-01T10:00:00Z", now), false);
});
