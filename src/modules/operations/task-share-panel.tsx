"use client";

import { useState } from "react";
import {
  copyTaskShareMessage,
  buildTaskShareMessage,
  createWhatsAppShareUrl,
  formatTaskShareExpiry,
  type TaskShareResult,
} from "./task-share.ts";

export function TaskSharePanel({ result }: { result: TaskShareResult }) {
  const [copyState, setCopyState] = useState<"idle" | "copied" | "unavailable">("idle");
  const shareMessage = buildTaskShareMessage(result.message, result.url);
  const whatsappUrl = createWhatsAppShareUrl(shareMessage);
  const expiresAt = formatTaskShareExpiry(result.expires_at);

  async function copyLink() {
    const outcome = await copyTaskShareMessage(
      typeof navigator === "undefined" ? undefined : navigator.clipboard,
      shareMessage,
    );
    setCopyState(outcome);
  }

  return (
    <section className="task-share-card" aria-labelledby="task-share-title">
      <h2 id="task-share-title">Tapşırığı paylaş</h2>
      <p className="task-share-note">
        Keçid {expiresAt ? `${expiresAt} tarixinədək` : "məhdud müddətə"} aktivdir. Göndərilmə və oxunma statusu izləmirik.
      </p>
      <label className="task-share-field" htmlFor="task-share-url">Məhdud keçid</label>
      <input
        id="task-share-url"
        className="task-share-input"
        type="url"
        readOnly
        value={result.url}
        onFocus={(event) => event.currentTarget.select()}
        aria-describedby="task-share-status"
      />
      <label className="task-share-field" htmlFor="task-share-message">WhatsApp mətni və keçidi</label>
      <textarea
        id="task-share-message"
        className="task-share-input task-share-message"
        readOnly
        rows={3}
        value={shareMessage}
        onFocus={(event) => event.currentTarget.select()}
        aria-describedby="task-share-status"
      />
      <div className="task-share-actions">
        {whatsappUrl && <a className="task-share-whatsapp" href={whatsappUrl} target="_blank" rel="noopener noreferrer">
          WhatsApp-da aç
        </a>}
        <button className="task-share-copy" type="button" onClick={copyLink}>
          Mətni və keçidi kopyala
        </button>
      </div>
      <p id="task-share-status" className="task-share-status" role="status" aria-live="polite">
        {copyState === "copied" && "Mətn və keçid kopyalandı. Göndərilmə statusu izlənmir."}
        {copyState === "unavailable" && "Avtomatik kopyalama alınmadı. Aşağıdakı mətni və keçidi seçib əl ilə kopyalayın."}
        {copyState === "idle" && (whatsappUrl
          ? "WhatsApp quraşdırılmayıbsa, mətni və keçidi kopyalaya bilərsiniz. Göndərilmə statusu izlənmir."
          : "WhatsApp keçidi bu mesaj üçün çox uzundur. Aşağıdakı mətni və keçidi kopyalayın.")}
      </p>
    </section>
  );
}
