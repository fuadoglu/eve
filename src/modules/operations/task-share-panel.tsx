"use client";

import { useState } from "react";
import {
  copyTaskShareMessage,
  createWhatsAppShareUrl,
  formatTaskShareExpiry,
  type TaskShareResult,
} from "./task-share.ts";

export function TaskSharePanel({ result }: { result: TaskShareResult }) {
  const [copyState, setCopyState] = useState<"idle" | "copied" | "unavailable">("idle");
  const whatsappUrl = createWhatsAppShareUrl(result.message);
  const expiresAt = formatTaskShareExpiry(result.expires_at);

  async function copyLink() {
    const outcome = await copyTaskShareMessage(
      typeof navigator === "undefined" ? undefined : navigator.clipboard,
      result.message,
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
      <div className="task-share-actions">
        <a className="task-share-whatsapp" href={whatsappUrl} target="_blank" rel="noopener noreferrer">
          WhatsApp-da aç
        </a>
        <button className="task-share-copy" type="button" onClick={copyLink}>
          Keçidi kopyala
        </button>
      </div>
      <p id="task-share-status" className="task-share-status" role="status" aria-live="polite">
        {copyState === "copied" && "Keçid kopyalandı. Göndərilmə statusu izlənmir."}
        {copyState === "unavailable" && "Avtomatik kopyalama alınmadı. Keçidi seçib əl ilə kopyalayın."}
        {copyState === "idle" && "WhatsApp quraşdırılmayıbsa, keçidi seçib əl ilə kopyalaya bilərsiniz."}
      </p>
    </section>
  );
}
