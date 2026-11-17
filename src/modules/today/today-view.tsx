"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { CalendarCheck2, CalendarClock, CircleAlert, CreditCard, ListChecks, Wallet } from "lucide-react";
import { parseTodayEnvelope, type TodayCard, type TodayProjection } from "./today-contract.ts";

type LoadState = { status: "loading" } | { status: "error"; message: string; signInRequired: boolean }
  | { status: "ready"; data: TodayProjection };

const cardMeta = {
  arrival: { label: "Giriş", icon: CalendarCheck2 },
  departure: { label: "Çıxış", icon: CalendarClock },
  task: { label: "Tapşırıq", icon: ListChecks },
  rent_due: { label: "Kirayə qalığı", icon: Wallet },
  expense_due: { label: "Xərc", icon: CreditCard },
  subscription: { label: "Abunə", icon: CreditCard },
  inspection_problem: { label: "Yoxlama", icon: CircleAlert },
} as const;

const actionLabels = {
  open_reservation: "Rezervasiyaya bax",
  check_in: "Girişi qeyd et",
  check_out: "Çıxışı qeyd et",
  open_task: "Tapşırığa bax",
  confirm_task: "Tapşırığı təsdiqlə",
  open_money: "Pul qeydini aç",
  renew: "Abunəni yenilə",
  open_inspection: "Yoxlamanı aç",
} as const;

export function TodayView() {
  const [retry, setRetry] = useState(0);
  const [state, setState] = useState<LoadState>({ status: "loading" });

  const load = useCallback(async (signal: AbortSignal) => {
    setState({ status: "loading" });
    try {
      const response = await fetch("/api/v1/today", {
        method: "GET",
        credentials: "same-origin",
        cache: "no-store",
        headers: { Accept: "application/json" },
        signal,
      });
      const body: unknown = await response.json();
      if (!response.ok) {
        const code = isRecord(body) && isRecord(body.error) && typeof body.error.code === "string"
          ? body.error.code : "PROVIDER_UNAVAILABLE";
        throw new TodayRequestError(code);
      }
      setState({ status: "ready", data: parseTodayEnvelope(body).data });
    } catch (error) {
      if (signal.aborted) return;
      const signInRequired = error instanceof TodayRequestError && error.code === "UNAUTHENTICATED";
      setState({
        status: "error",
        signInRequired,
        message: signInRequired
          ? "Davam etmək üçün Eve hesabınıza daxil olun."
          : "Bugünkü planı yükləmək mümkün olmadı. Bağlantını yoxlayıb yenidən cəhd edin.",
      });
    }
  }, []);

  useEffect(() => {
    const controller = new AbortController();
    void load(controller.signal);
    return () => controller.abort();
  }, [load, retry]);

  if (state.status === "loading") {
    return <section className="today-loading" aria-label="Bugünkü plan yüklənir" aria-busy="true">
      <p className="today-status" role="status">Bugünkü plan yüklənir…</p>
      <div className="today-skeleton" />
      <div className="today-skeleton" />
      <div className="today-skeleton today-skeleton-short" />
    </section>;
  }

  if (state.status === "error") {
    return <section className="today-error" role="alert">
      <span className="today-error-mark" aria-hidden="true"><CircleAlert size={22} /></span>
      <h2>{state.signInRequired ? "Sessiya tələb olunur" : "Planı aça bilmədik"}</h2>
      <p>{state.message}</p>
      <div className="today-error-actions">
        {state.signInRequired && <Link className="today-primary-action" href="/login">Daxil ol</Link>}
        <button className="today-secondary-action" type="button" onClick={() => setRetry((value) => value + 1)}>Yenidən yoxla</button>
      </div>
    </section>;
  }

  return <TodayContent data={state.data} onRetry={() => setRetry((value) => value + 1)} />;
}

function TodayContent({ data, onRetry }: { data: TodayProjection; onRetry: () => void }) {
  const arrivals = data.cards.filter((card) => card.kind === "arrival" || card.kind === "departure").length;
  const tasks = data.cards.filter((card) => card.kind === "task").length;
  const moneyMinor = data.cards.reduce((total, card) =>
    card.kind === "rent_due" || card.kind === "expense_due" ? total + BigInt(card.amount_minor ?? 0) : total, BigInt(0));
  const money = useMemo(() => formatAznMinor(moneyMinor), [moneyMinor]);
  const date = useMemo(() => new Intl.DateTimeFormat("az-AZ", {
    weekday: "long", day: "numeric", month: "long", timeZone: "Asia/Baku",
  }).format(new Date(`${data.local_date}T12:00:00Z`)), [data.local_date]);

  return <>
    <div className="today-date-row"><span>{capitalize(date)}</span><span className="today-timezone">Bakı vaxtı</span></div>
    <section className="today-metrics" aria-label="Günün xülasəsi">
      <Metric value={String(arrivals)} label="Giriş / çıxış" />
      <Metric value={String(tasks)} label="Tapşırıq" />
      <Metric value={money} label="Pul xatırlatması" />
    </section>
    <div className="today-section-heading"><h2>Günün planı</h2><button type="button" onClick={onRetry} className="today-refresh">Yenilə</button></div>
    {data.cards.length === 0 ? <section className="today-empty" aria-live="polite">
      <span className="today-empty-mark" aria-hidden="true"><CalendarCheck2 size={22} /></span>
      <h2>Bu gün üçün plan yoxdur</h2>
      <p>Bu tarix üçün giriş, çıxış və gecikən tapşırıq qeydi tapılmadı.</p>
      <Link href="/calendar" className="today-secondary-action">Təqvimə bax</Link>
    </section> : <section className="today-card-list" aria-label="Bugünkü işlər">
      {data.cards.map((card) => <TodayCardView key={card.id} card={card} />)}
    </section>}
  </>;
}

function TodayCardView({ card }: { card: TodayCard }) {
  const { label, icon: Icon } = cardMeta[card.kind];
  return <article className={`today-card today-card-${card.kind}`}>
    <div className="today-card-icon" aria-hidden="true"><Icon size={20} strokeWidth={1.8} /></div>
    <div className="today-card-body">
      <div className="today-card-topline"><span className="today-card-kind">{label}</span>{card.due_at && <time dateTime={card.due_at}>{formatTime(card.due_at)}</time>}</div>
      <h3>{card.title}</h3>
      <p>{card.property_label}</p>
      {card.owner_display_name && <p className="today-owner">Sahib: {card.owner_display_name}</p>}
      <p className="today-next-action">Növbəti əməliyyat: {actionLabels[card.action]}</p>
    </div>
    {card.amount_minor != null && <strong className="today-amount">{formatAznMinor(card.amount_minor)}</strong>}
  </article>;
}

function Metric({ value, label }: { value: string; label: string }) {
  return <div className="today-metric"><strong>{value}</strong><span>{label}</span></div>;
}

function formatTime(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return new Intl.DateTimeFormat("az-AZ", { hour: "2-digit", minute: "2-digit", timeZone: "Asia/Baku" }).format(date);
}

function formatAznMinor(value: number | bigint): string {
  const minor = typeof value === "bigint" ? value : BigInt(value);
  const negative = minor < BigInt(0);
  const absolute = negative ? -minor : minor;
  const whole = absolute / BigInt(100);
  const fraction = String(absolute % BigInt(100)).padStart(2, "0");
  const groupedWhole = new Intl.NumberFormat("az-AZ", { maximumFractionDigits: 0 }).format(whole);
  const decimal = new Intl.NumberFormat("az-AZ").formatToParts(1.1).find((part) => part.type === "decimal")?.value ?? ",";
  const currency = new Intl.NumberFormat("az-AZ", { style: "currency", currency: "AZN", minimumFractionDigits: 0, maximumFractionDigits: 0 })
    .formatToParts(0).find((part) => part.type === "currency")?.value ?? "₼";
  return `${negative ? "−" : ""}${groupedWhole}${decimal}${fraction}\u00a0${currency}`;
}

function capitalize(value: string): string { return value.charAt(0).toLocaleUpperCase("az-AZ") + value.slice(1); }
function isRecord(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value); }

class TodayRequestError extends Error {
  constructor(readonly code: string) { super(code); }
}
