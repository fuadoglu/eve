"use client";

import { useRef, useState } from "react";

type ScopedTask = { task_id: string; property_label: string; title: string; due_at: string;
  state: "open" | "accepted" | "reported_done" | "completed" | "cancelled"; version: number; address?: string | null };

export function ScopedTaskLanding({ token }: { token: string }) {
  const [task, setTask] = useState<ScopedTask | null>(null);
  const [claimedName, setClaimedName] = useState("");
  const [note, setNote] = useState("");
  const [includeExpense, setIncludeExpense] = useState(false);
  const [expenseAmount, setExpenseAmount] = useState("");
  const [expenseCategory, setExpenseCategory] = useState<"utilities" | "building_service" | "cleaning" | "repair" | "purchase" | "consumables" | "other">("cleaning");
  const [expenseNote, setExpenseNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("Keçidi açmaq üçün düyməni seçin.");
  const pending = useRef<{ action: string; body: string; key: string } | null>(null);
  async function open() {
    setBusy(true);
    window.history.replaceState(null, "", "/s");
    try {
      const exchange = await fetch("/api/v1/link-session", { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token }), cache: "no-store" });
      if (!exchange.ok) { setMessage("Keçid aktiv deyil və ya açılmır."); return; }
      const read = await fetch(`/api/v1/s/${encodeURIComponent(token)}/task`, { cache: "no-store" });
      const payload = await read.json();
      if (!read.ok || !payload?.data) { setMessage("Tapşırıq artıq əlçatan deyil."); return; }
      setTask(payload.data as ScopedTask);
      setMessage("");
    } catch { setMessage("Bağlantı xətası. Yenidən cəhd edin."); }
    finally { setBusy(false); }
  }
  async function refresh() {
    if (busy) return;
    setBusy(true);
    try {
      const response = await fetch(`/api/v1/s/${encodeURIComponent(token)}/task`, { cache: "no-store" });
      const payload = await response.json();
      if (!response.ok || !payload?.data) { setMessage("Tapşırıq artıq əlçatan deyil."); return; }
      setTask(payload.data as ScopedTask);
      setMessage("Vəziyyət yeniləndi.");
    } catch { setMessage("Bağlantı xətası. Yenidən cəhd edin."); }
    finally { setBusy(false); }
  }
  async function act(action: "accept" | "report-done") {
    if (!task || !claimedName.trim() || busy) return;
    let amountMinor: number | null = null;
    if (action === "report-done" && includeExpense) {
      if (!/^\d+(?:\.\d{1,2})?$/.test(expenseAmount)) { setMessage("Xərc məbləğini AZN ilə düzgün yazın."); return; }
      const [whole, fraction = ""] = expenseAmount.split(".");
      amountMinor = Number(whole) * 100 + Number(fraction.padEnd(2, "0"));
      if (!Number.isSafeInteger(amountMinor) || amountMinor <= 0) {
        setMessage("Xərc məbləği düzgün deyil."); return;
      }
    }
    setBusy(true);
    try {
      const body = JSON.stringify({ expected_version: task.version, claimed_name: claimedName.trim(),
        ...(action === "report-done" && note.trim() ? { note: note.trim() } : {}),
        ...(action === "report-done" && amountMinor !== null ? { expense_proposal: {
          amount_minor: amountMinor, category: expenseCategory,
          ...(expenseNote.trim() ? { note: expenseNote.trim() } : {}),
        } } : {}) });
      if (!pending.current || pending.current.action !== action || pending.current.body !== body)
        pending.current = { action, body, key: crypto.randomUUID() };
      const response = await fetch(`/api/v1/s/${encodeURIComponent(token)}/${action}`, {
        method: "POST", headers: { "Content-Type": "application/json", "Idempotency-Key": pending.current.key },
        body, cache: "no-store",
      });
      const payload = await response.json();
      if (!response.ok || !payload?.data) {
        if (response.status !== 503) pending.current = null;
        setMessage(response.status === 409 ? "Tapşırıq dəyişib. Vəziyyəti yeniləyin."
          : "Əməliyyat təsdiqlənmədi. Yenidən cəhd edin."); return;
      }
      pending.current = null;
      setTask(payload.data as ScopedTask);
      setMessage(action === "accept" ? "Tapşırıq qəbul edildi." : includeExpense
        ? "Tamamlanma və xərc təklifi qəbul edildi. Sahib təsdiqi gözlənilir."
        : "Tamamlanma bildirildi. Sahib təsdiqi gözlənilir.");
    } catch { setMessage("Bağlantı xətası. Əməliyyatın vəziyyətini yenidən yoxlayın."); }
    finally { setBusy(false); }
  }
  return <main style={{ maxWidth: 480, margin: "3rem auto", padding: "1.5rem" }}>
    <h1>Tapşırıq keçidi</h1>
    {message && <p role="status">{message}</p>}
    {!task ? <button type="button" onClick={open} disabled={busy}>Eve-də aç</button> : <>
      <p><strong>{task.property_label}</strong></p><h2>{task.title}</h2>
      {task.address && <p>{task.address}</p>}
      <p>Vaxt: {new Date(task.due_at).toLocaleString("az-AZ")}</p>
      <p>Vəziyyət: {task.state}</p>
      <button type="button" onClick={refresh} disabled={busy}>Vəziyyəti yenilə</button>
      {(task.state === "open" || task.state === "accepted") && <>
        <label>Adınız<input value={claimedName} onChange={(event) => setClaimedName(event.target.value)} maxLength={100} /></label>
        {task.state === "accepted" && <label>Qeyd<input value={note} onChange={(event) => setNote(event.target.value)} maxLength={2000} /></label>}
        <label><input type="checkbox" checked={includeExpense} onChange={(event) => setIncludeExpense(event.target.checked)} /> Xərc təklifi əlavə et</label>
        {includeExpense && <>
          <label>Məbləğ (AZN)<input inputMode="decimal" value={expenseAmount}
            onChange={(event) => setExpenseAmount(event.target.value)} placeholder="0.00" /></label>
          <label>Kateqoriya<select value={expenseCategory} onChange={(event) => setExpenseCategory(event.target.value as typeof expenseCategory)}>
            <option value="utilities">Kommunal</option><option value="building_service">Bina xidməti</option>
            <option value="cleaning">Təmizlik</option><option value="repair">Təmir</option>
            <option value="purchase">Alış</option><option value="consumables">Sərf materialı</option>
            <option value="other">Digər</option>
          </select></label>
          <label>Xərc qeydi<input value={expenseNote} onChange={(event) => setExpenseNote(event.target.value)} maxLength={2000} /></label>
        </>}
        {task.state === "open" && <button type="button" onClick={() => act("accept")} disabled={busy || !claimedName.trim()}>Qəbul et</button>}
        <button type="button" onClick={() => act("report-done")} disabled={busy || !claimedName.trim()}>Tamamladım</button>
      </>}
    </>}
  </main>;
}
