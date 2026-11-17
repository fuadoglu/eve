"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { CalendarDays, CalendarRange, ChevronLeft, ChevronRight, CircleAlert, List, RefreshCw } from "lucide-react";
import {
  filterCalendarData,
  getAgendaOccurrences,
  getCalendarOwnerOptions,
  getCalendarRange,
  isCalendarHoldExpired,
  parseCalendarEnvelope,
  type CalendarData,
  type CalendarPropertyOption,
} from "./calendar-contract.ts";
import styles from "./calendar-agenda.module.css";

type LoadState = { status: "loading" } | { status: "error"; code: string; message: string }
  | { status: "ready"; data: CalendarData };
type ViewMode = "month" | "agenda";

const MAX_SELECTED_PROPERTIES = 100;

export function CalendarAgenda({
  properties,
  loadError = false,
}: {
  properties: CalendarPropertyOption[];
  loadError?: boolean;
}) {
  const initialAnchor = getTodayInBaku();
  const [anchorDate, setAnchorDate] = useState(initialAnchor);
  const [ownerFilter, setOwnerFilter] = useState("all");
  const [selectedPropertyIds, setSelectedPropertyIds] = useState<string[]>(() =>
    properties.length <= MAX_SELECTED_PROPERTIES ? properties.map((property) => property.id) : [],
  );
  const [view, setView] = useState<ViewMode>(properties.length > 1 ? "agenda" : "month");
  const [selectedDate, setSelectedDate] = useState(initialAnchor);
  const [retry, setRetry] = useState(0);
  const [state, setState] = useState<LoadState>(loadError
    ? { status: "error", code: "PROVIDER_UNAVAILABLE", message: "Ev siyahısını yükləmək mümkün olmadı. Bağlantını yoxlayıb səhifəni yeniləyin." }
    : { status: "loading" });

  const owners = useMemo(() => getCalendarOwnerOptions(properties), [properties]);
  const selectedIds = useMemo(() => new Set(selectedPropertyIds), [selectedPropertyIds]);
  const range = useMemo(() => getCalendarRange(anchorDate), [anchorDate]);
  const propertiesById = useMemo(() => new Map(properties.map((property) => [property.id, property])), [properties]);
  const visibleProperties = useMemo(() => properties.filter((property) =>
    ownerFilter === "all" || property.owner_account_id === ownerFilter), [ownerFilter, properties]);
  const canShowMonth = selectedPropertyIds.length === 1;

  const load = useCallback(async (signal: AbortSignal) => {
    if (loadError) return;
    if (properties.length === 0) {
      setState({ status: "error", code: "NO_PROPERTIES", message: "Təqvim üçün icazəli ev tapılmadı." });
      return;
    }
    if (selectedPropertyIds.length === 0) {
      setState({ status: "error", code: "NO_SELECTION", message: "Təqvimə baxmaq üçün ən azı bir ev seçin." });
      return;
    }
    if (selectedPropertyIds.length > MAX_SELECTED_PROPERTIES) {
      setState({ status: "error", code: "TOO_MANY_PROPERTIES", message: "Bir sorğuda ən çox 100 ev seçilə bilər." });
      return;
    }

    setState({ status: "loading" });
    const params = new URLSearchParams({ from: range.from, to: range.to });
    for (const id of selectedPropertyIds) params.append("property_ids", id);
    try {
      const response = await fetch(`/api/v1/calendar?${params.toString()}`, {
        method: "GET",
        credentials: "same-origin",
        cache: "no-store",
        headers: { Accept: "application/json" },
        signal,
      });
      let body: unknown;
      try { body = await response.json(); } catch { throw new CalendarRequestError("PROVIDER_UNAVAILABLE"); }
      if (!response.ok) {
        const code = isRecord(body) && isRecord(body.error) && typeof body.error.code === "string"
          ? body.error.code : "PROVIDER_UNAVAILABLE";
        throw new CalendarRequestError(code);
      }
      const data = parseCalendarEnvelope(body).data;
      setState({ status: "ready", data: filterCalendarData(data, selectedIds, range.from, range.to) });
    } catch (error) {
      if (signal.aborted) return;
      const code = error instanceof CalendarRequestError ? error.code : "PROVIDER_UNAVAILABLE";
      setState({ status: "error", code, message: calendarErrorMessage(code) });
    }
  }, [loadError, properties.length, range.from, range.to, selectedIds, selectedPropertyIds]);

  useEffect(() => {
    const controller = new AbortController();
    void load(controller.signal);
    return () => controller.abort();
  }, [load, retry]);

  const data = state.status === "ready" ? state.data : null;
  const entriesByDate = useMemo(() => data
    ? makeEntriesByDate(data, propertiesById, range.from, range.to)
    : new Map<string, CalendarEntry[]>(), [data, propertiesById, range.from, range.to]);
  const agendaEntriesByDate = useMemo(() => data
    ? makeAgendaEntries(data, propertiesById, range.from, range.to)
    : new Map<string, CalendarEntry[]>(), [data, propertiesById, range.from, range.to]);
  const selectedEntries = entriesByDate.get(selectedDate) ?? [];
  const monthTitle = formatMonth(anchorDate);

  function changeOwner(ownerId: string) {
    setOwnerFilter(ownerId);
    const matches = properties.filter((property) => ownerId === "all" || property.owner_account_id === ownerId);
    setSelectedPropertyIds(matches.slice(0, MAX_SELECTED_PROPERTIES).map((property) => property.id));
    if (matches.length !== 1) setView("agenda");
  }

  function toggleProperty(id: string) {
    setSelectedPropertyIds((current) => current.includes(id)
      ? current.filter((selectedId) => selectedId !== id)
      : current.length < MAX_SELECTED_PROPERTIES ? [...current, id].sort() : current);
  }

  function moveMonth(delta: number) {
    const current = new Date(`${anchorDate}T12:00:00Z`);
    current.setUTCDate(1);
    current.setUTCMonth(current.getUTCMonth() + delta);
    const next = formatDate(current);
    setAnchorDate(next);
    setSelectedDate(next);
  }

  return <section className={styles.calendar} aria-label="Ev təqvimi">
    <div className={styles.toolbar}>
      <div className={styles.monthHeading}>
        <h2>{capitalize(monthTitle)}</h2>
        <p>Bakı tarixi · çıxış günü gecələmə sayılmır</p>
      </div>
      <div className={styles.monthControls} aria-label="Ayı dəyiş">
        <button type="button" aria-label="Əvvəlki ay" onClick={() => moveMonth(-1)}><ChevronLeft size={20} /></button>
        <button type="button" aria-label="Növbəti ay" onClick={() => moveMonth(1)}><ChevronRight size={20} /></button>
      </div>
    </div>

    <div className={styles.filters}>
      {owners.length > 1 && <label className={styles.ownerFilter}>Sahib
        <select value={ownerFilter} onChange={(event) => changeOwner(event.target.value)}>
          <option value="all">Bütün sahiblər</option>
          {owners.map((owner) => <option key={owner.id} value={owner.id}>{owner.label}</option>)}
        </select>
      </label>}
      <fieldset className={styles.propertyFilter}>
        <legend>Ev filtri <span>{selectedPropertyIds.length}/{properties.length}</span></legend>
        <div className={styles.propertyList}>
          {visibleProperties.map((property) => <label key={property.id} className={styles.propertyOption}>
            <input type="checkbox" checked={selectedIds.has(property.id)} onChange={() => toggleProperty(property.id)} />
            <span><strong>{property.name}</strong><small>{property.owner_display_name} · {property.area}</small></span>
          </label>)}
        </div>
        {visibleProperties.length === 0 && <p className={styles.filterHint}>Bu sahib üçün ev yoxdur.</p>}
        {properties.length > MAX_SELECTED_PROPERTIES && <p className={styles.filterHint}>Bir sorğuda ən çox 100 ev seçilə bilər.</p>}
      </fieldset>
    </div>

    <div className={styles.viewSwitch} role="group" aria-label="Təqvim görünüşü">
      <button type="button" aria-pressed={view === "agenda"} onClick={() => setView("agenda")}>
        <List size={17} /> Agenda
      </button>
      <button type="button" aria-pressed={view === "month"} disabled={!canShowMonth}
        title={canShowMonth ? "Bir ev üçün aylıq təqvim" : "Ay görünüşü üçün bir ev seçin"}
        onClick={() => canShowMonth && setView("month")}>
        <CalendarDays size={17} /> Ay
      </button>
    </div>

    {state.status === "loading" ? <div className={styles.loading} role="status" aria-busy="true">Təqvim yüklənir…</div>
      : state.status === "error" ? <CalendarError code={state.code} message={state.message} onRetry={() => setRetry((value) => value + 1)} />
        : data && data.reservations.length === 0 && data.blocks.length === 0
          ? <div className={styles.empty}>
            <CalendarRange size={22} aria-hidden="true" />
            <h3>Bu aralıqda qeyd yoxdur</h3>
            <p>Göstərilən rezervasiya və blok tapılmadı. Boş görünən tarix avtomatik rezervasiya təsdiqi deyil.</p>
          </div>
          : data && view === "month"
            ? <MonthGrid anchorDate={anchorDate} selectedDate={selectedDate} entriesByDate={entriesByDate} onSelectDate={setSelectedDate} />
            : data && <AgendaList data={data} entriesByDate={agendaEntriesByDate} />}

    {data && view === "month" && <SelectedDate entries={selectedEntries} date={selectedDate} />}
    {data && <p className={styles.contractNote}>Tarix seçimi rezervasiya yaratmır.</p>}
  </section>;
}

type CalendarEntry = {
  id: string;
  kind: "reservation" | "block";
  title: string;
  propertyName: string;
  propertyId: string;
  checkIn: string;
  checkOut: string;
  status?: string;
  holdExpiresAt?: string | null;
  eventLabel?: string;
};

function makeEntriesByDate(
  data: CalendarData,
  propertiesById: ReadonlyMap<string, CalendarPropertyOption>,
  from: string,
  to: string,
): Map<string, CalendarEntry[]> {
  const events: CalendarEntry[] = [
    ...data.reservations.map((reservation) => ({
      id: reservation.id,
      kind: "reservation" as const,
      title: reservation.guest_name,
      propertyName: propertiesById.get(reservation.property_id)?.name ?? "Ev",
      propertyId: reservation.property_id,
      checkIn: reservation.check_in,
      checkOut: reservation.check_out,
      status: reservation.status,
      holdExpiresAt: reservation.hold_expires_at,
    })),
    ...data.blocks.map((block) => ({
      id: block.id,
      kind: "block" as const,
      title: "Ev bloklanıb",
      propertyName: propertiesById.get(block.property_id)?.name ?? "Ev",
      propertyId: block.property_id,
      checkIn: block.check_in,
      checkOut: block.check_out,
    })),
  ];
  const map = new Map<string, CalendarEntry[]>();
  for (const event of events) {
    const visibleFrom = event.checkIn < from ? from : event.checkIn;
    const visibleTo = event.checkOut > to ? to : event.checkOut;
    for (const date of eachDate(visibleFrom, visibleTo)) {
      const values = map.get(date) ?? [];
      values.push(event);
      map.set(date, values);
    }
  }
  for (const values of map.values()) values.sort((a, b) => a.propertyName.localeCompare(b.propertyName, "az") || a.title.localeCompare(b.title, "az"));
  return map;
}

function makeAgendaEntries(
  data: CalendarData,
  propertiesById: ReadonlyMap<string, CalendarPropertyOption>,
  from: string,
  to: string,
): Map<string, CalendarEntry[]> {
  const entriesById = new Map<string, CalendarEntry>();
  for (const reservation of data.reservations) {
    const propertyName = propertiesById.get(reservation.property_id)?.name ?? "Ev";
    entriesById.set(reservation.id, {
      id: reservation.id,
      kind: "reservation",
      title: reservation.guest_name,
      propertyName,
      propertyId: reservation.property_id,
      checkIn: reservation.check_in,
      checkOut: reservation.check_out,
      status: reservation.status,
      holdExpiresAt: reservation.hold_expires_at,
    });
  }
  for (const block of data.blocks) {
    entriesById.set(block.id, {
      id: block.id,
      kind: "block",
      title: "Ev bloklanıb",
      propertyName: propertiesById.get(block.property_id)?.name ?? "Ev",
      propertyId: block.property_id,
      checkIn: block.check_in,
      checkOut: block.check_out,
    });
  }

  const map = new Map<string, CalendarEntry[]>();
  const allEvents = [
    ...data.reservations.map((reservation) => ({ id: reservation.id, kind: "reservation" as const,
      checkIn: reservation.check_in, checkOut: reservation.check_out })),
    ...data.blocks.map((block) => ({ id: block.id, kind: "block" as const,
      checkIn: block.check_in, checkOut: block.check_out })),
  ];
  for (const occurrence of getAgendaOccurrences(allEvents, from, to)) {
    const base = entriesById.get(occurrence.id);
    if (!base) continue;
    const entry = { ...base, eventLabel: occurrence.label };
    const date = occurrence.date;
    const values = map.get(date) ?? [];
    values.push(entry);
    map.set(date, values);
  }
  for (const values of map.values()) values.sort((a, b) => a.propertyName.localeCompare(b.propertyName, "az") || a.title.localeCompare(b.title, "az"));
  return map;
}

function MonthGrid({
  anchorDate,
  selectedDate,
  entriesByDate,
  onSelectDate,
}: {
  anchorDate: string;
  selectedDate: string;
  entriesByDate: ReadonlyMap<string, CalendarEntry[]>;
  onSelectDate: (date: string) => void;
}) {
  const { from, to } = getCalendarRange(anchorDate);
  const dates = eachDate(from, to);
  const currentMonth = anchorDate.slice(0, 7);
  const weekDays = ["B.e", "Ç.a", "Çər", "C.a", "Cüm", "Şən", "Baz"];
  return <div className={styles.monthGridWrap}>
    <div className={styles.weekHeader} aria-hidden="true">{weekDays.map((label) => <span key={label}>{label}</span>)}</div>
    <div className={styles.monthGrid} role="group" aria-label={`${formatMonth(anchorDate)} təqvimi`}>
      {dates.map((date) => {
        const entries = entriesByDate.get(date) ?? [];
        const isCurrentMonth = date.slice(0, 7) === currentMonth;
        const dayNumber = Number(date.slice(8, 10));
        const accessibleLabel = entries.length
          ? `${dayNumber} ${entries.length} qeyd, ${formatDateLong(date)}`
          : `${dayNumber}, qeyd yoxdur, ${formatDateLong(date)}`;
        return <button key={date} type="button" aria-label={accessibleLabel}
          aria-pressed={selectedDate === date} className={`${styles.dayCell} ${!isCurrentMonth ? styles.outsideMonth : ""}`}
          onClick={() => onSelectDate(date)}>
          <span className={styles.dayNumber}>{dayNumber}</span>
          {entries.length > 0 && <><span aria-hidden="true"> </span><span aria-hidden="true" className={styles.dayCount}>{entries.length}</span></>}
          <span className={styles.dayMarkers} aria-hidden="true">
            {entries.slice(0, 2).map((entry) => <span key={`${entry.kind}-${entry.id}`} className={entry.kind === "block" ? styles.blockMarker : styles.reservationMarker} />)}
          </span>
        </button>;
      })}
    </div>
  </div>;
}

function AgendaList({ data, entriesByDate }: { data: CalendarData; entriesByDate: ReadonlyMap<string, CalendarEntry[]> }) {
  const dates = [...entriesByDate.keys()].sort();
  if (!dates.length) return <div className={styles.empty}>
    <CalendarRange size={22} aria-hidden="true" />
    <h3>Bu aralıqda qeyd yoxdur</h3>
    <p>Göstərilən rezervasiya və blok tapılmadı. Boş görünən tarix avtomatik rezervasiya təsdiqi deyil.</p>
  </div>;
  return <div className={styles.agenda} aria-label="Agenda">
    <p className={styles.agendaRange}>{formatDateLong(data.from)} – {formatDateLong(addDays(data.to, -1))}</p>
    {dates.map((date) => <section key={date} className={styles.agendaDay}>
      <h3>{capitalize(formatDateLong(date))}</h3>
      <div>{(entriesByDate.get(date) ?? []).map((entry) => <CalendarEntryCard key={`${entry.kind}-${date}-${entry.id}`} entry={entry} />)}</div>
    </section>)}
  </div>;
}

function SelectedDate({ entries, date }: { entries: CalendarEntry[]; date: string }) {
  return <section className={styles.selectedDate} aria-live="polite">
    <h3>{capitalize(formatDateLong(date))}</h3>
    {entries.length === 0 ? <p>Bu tarix üçün görünən qeyd yoxdur.</p>
      : <div>{entries.map((entry) => <CalendarEntryCard key={`${entry.kind}-${entry.id}`} entry={entry} />)}</div>}
  </section>;
}

function CalendarEntryCard({ entry }: { entry: CalendarEntry }) {
  const [now, setNow] = useState<number | null>(null);
  useEffect(() => {
    const refreshNow = () => setNow(Date.now());
    let timeout: number | undefined;
    refreshNow();
    if (entry.status !== "hold" || !entry.holdExpiresAt) return;
    const expiresAt = Date.parse(entry.holdExpiresAt);
    if (!Number.isFinite(expiresAt) || expiresAt <= Date.now()) return;
    const scheduleExpiryRefresh = () => {
      const remaining = expiresAt - Date.now();
      if (remaining <= 0) {
        refreshNow();
        return;
      }
      timeout = window.setTimeout(scheduleExpiryRefresh, Math.min(remaining + 50, 2_147_000_000));
    };
    scheduleExpiryRefresh();
    return () => { if (timeout !== undefined) window.clearTimeout(timeout); };
  }, [entry.status, entry.holdExpiresAt]);
  const kind = entry.eventLabel ?? (entry.kind === "reservation" ? "Rezervasiya" : "Blok");
  const holdExpired = now !== null && entry.status === "hold"
    && isCalendarHoldExpired("hold", entry.holdExpiresAt, now);
  return <article className={`${styles.entryCard} ${entry.kind === "block" ? styles.blockCard : ""}`}>
    <span className={styles.entryKind}>{kind}</span>
    <strong>{entry.title}</strong>
    <span>{entry.propertyName}</span>
    <small>{formatDateShort(entry.checkIn)} – {formatDateShort(entry.checkOut)} · çıxış günü daxil deyil</small>
    {entry.status === "hold" && entry.holdExpiresAt && <small>
      {holdExpired ? "Müddəti bitib · sistemin yeniləməsi gözlənilir" : `Müvəqqəti saxlanma · bitmə vaxtı ${formatDateTimeBaku(entry.holdExpiresAt)}`}
    </small>}
  </article>;
}

function CalendarError({ code, message, onRetry }: { code: string; message: string; onRetry: () => void }) {
  const signInRequired = code === "UNAUTHENTICATED";
  return <div className={styles.error} role="alert">
    <CircleAlert size={22} aria-hidden="true" />
    <h3>{signInRequired ? "Sessiya tələb olunur" : "Təqvimi aça bilmədik"}</h3>
    <p>{message}</p>
    <div className={styles.errorActions}>
      {signInRequired && <Link href="/login">Daxil ol</Link>}
      <button type="button" onClick={onRetry}><RefreshCw size={16} /> Yenidən yoxla</button>
    </div>
  </div>;
}

class CalendarRequestError extends Error {
  constructor(readonly code: string) { super(code); }
}

function calendarErrorMessage(code: string): string {
  if (code === "FORBIDDEN") return "Bu evin təqviminə baxmaq icazəniz yoxdur.";
  if (code === "NOT_FOUND") return "Seçilmiş evlərdən birinin təqvimi tapılmadı. Ev filtrini yeniləyin.";
  if (code === "VALIDATION_ERROR") return "Bu aralıqda həddən artıq qeyd var və ya tarix aralığı uyğun deyil. Daha qısa aralıq seçin.";
  if (code === "UNAUTHENTICATED") return "Davam etmək üçün Eve hesabınıza daxil olun.";
  return "Təqvim məlumatını yükləmək mümkün olmadı. Bağlantını yoxlayıb yenidən cəhd edin.";
}

function getTodayInBaku(): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    year: "numeric", month: "2-digit", day: "2-digit", timeZone: "Asia/Baku",
  }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

function formatMonth(date: string): string {
  return new Intl.DateTimeFormat("az-AZ", { month: "long", year: "numeric", timeZone: "Asia/Baku" })
    .format(new Date(`${date.slice(0, 7)}-01T12:00:00Z`));
}

function formatDateLong(date: string): string {
  return new Intl.DateTimeFormat("az-AZ", { weekday: "long", day: "numeric", month: "long", timeZone: "Asia/Baku" })
    .format(new Date(`${date}T12:00:00Z`));
}

function formatDateShort(date: string): string {
  return new Intl.DateTimeFormat("az-AZ", { day: "numeric", month: "short", timeZone: "Asia/Baku" })
    .format(new Date(`${date}T12:00:00Z`));
}

function formatDateTimeBaku(value: string): string {
  return new Intl.DateTimeFormat("az-AZ", {
    day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", timeZone: "Asia/Baku",
  }).format(new Date(value));
}

function eachDate(from: string, to: string): string[] {
  const result: string[] = [];
  const current = new Date(`${from}T12:00:00Z`);
  const end = new Date(`${to}T12:00:00Z`);
  while (current < end) {
    result.push(formatDate(current));
    current.setUTCDate(current.getUTCDate() + 1);
  }
  return result;
}

function addDays(date: string, amount: number): string {
  const value = new Date(`${date}T12:00:00Z`);
  value.setUTCDate(value.getUTCDate() + amount);
  return formatDate(value);
}

function formatDate(date: Date): string {
  return `${date.getUTCFullYear().toString().padStart(4, "0")}-${(date.getUTCMonth() + 1).toString().padStart(2, "0")}-${date.getUTCDate().toString().padStart(2, "0")}`;
}

function capitalize(value: string): string { return value.charAt(0).toLocaleUpperCase("az-AZ") + value.slice(1); }

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
