"use client";

import { useState } from "react";

type ScopedTask = { task_id: string; property_label: string; title: string; due_at: string;
  state: "open" | "accepted" | "reported_done" | "completed" | "cancelled"; version: number; address?: string | null };

export function ScopedTaskLanding({ token }: { token: string }) {
  const [task, setTask] = useState<ScopedTask | null>(null);
  const [claimedName, setClaimedName] = useState("");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("Keçidi açmaq üçün düyməni seçin.");
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
  async function act(action: "accept" | "report-done") {
    if (!task || !claimedName.trim() || busy) return;
    setBusy(true);
    try {
      const response = await fetch(`/api/v1/s/${encodeURIComponent(token)}/${action}`, {
        method: "POST", headers: { "Content-Type": "application/json", "Idempotency-Key": crypto.randomUUID() },
        body: JSON.stringify({ expected_version: task.version, claimed_name: claimedName.trim(),
          ...(action === "report-done" && note.trim() ? { note: note.trim() } : {}) }), cache: "no-store",
      });
      const payload = await response.json();
      if (!response.ok || !payload?.data) { setMessage(response.status === 409 ? "Tapşırıq dəyişib. Keçidi yenidən açın."
        : "Əməliyyat təsdiqlənmədi. Yenidən cəhd edin."); return; }
      setTask(payload.data as ScopedTask);
      setMessage(action === "accept" ? "Tapşırıq qəbul edildi." : "Tamamlanma bildirildi. Sahib təsdiqi gözlənilir.");
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
      {(task.state === "open" || task.state === "accepted") && <>
        <label>Adınız<input value={claimedName} onChange={(event) => setClaimedName(event.target.value)} maxLength={100} /></label>
        {task.state === "accepted" && <label>Qeyd<input value={note} onChange={(event) => setNote(event.target.value)} maxLength={2000} /></label>}
        {task.state === "open" && <button type="button" onClick={() => act("accept")} disabled={busy || !claimedName.trim()}>Qəbul et</button>}
        <button type="button" onClick={() => act("report-done")} disabled={busy || !claimedName.trim()}>Tamamladım</button>
      </>}
    </>}
  </main>;
}
