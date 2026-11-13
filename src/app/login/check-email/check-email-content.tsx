"use client";

import Link from "next/link";
import { useEffect, useState } from "react";

type EmailLinkResponse = {
  data: { accepted: true; resend_after_seconds: number; link_ttl_seconds: number };
};

export default function CheckEmailPage() {
  const [email, setEmail] = useState("");
  const [seconds, setSeconds] = useState(0);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");

  useEffect(() => {
    let savedEmail = "";
    let savedDeadline = 0;
    try {
      savedEmail = sessionStorage.getItem("eve.auth.email_hint") ?? "";
      savedDeadline = Number(sessionStorage.getItem("eve.auth.resend_after") ?? "0");
    } catch {
      // The page remains useful with generic copy when browser storage is disabled.
    }
    setEmail(savedEmail);
    setSeconds(Math.max(0, Math.ceil((savedDeadline - Date.now()) / 1000)));
    const timer = window.setInterval(() => {
      let deadline = 0;
      try {
        deadline = Number(sessionStorage.getItem("eve.auth.resend_after") ?? "0");
      } catch {
        // Storage may be disabled or revoked after the page loads.
      }
      setSeconds(Math.max(0, Math.ceil((deadline - Date.now()) / 1000)));
    }, 1000);
    return () => window.clearInterval(timer);
  }, []);

  async function resend() {
    if (!email || busy || seconds > 0) return;
    setBusy(true);
    setMessage("");
    try {
      const response = await fetch("/api/v1/auth/email-link", {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        credentials: "same-origin",
        body: JSON.stringify({ email, redirect_path: "/today" }),
      });
      if (response.status === 202) {
        let resendAfterSeconds = 60;
        try {
          const result = await response.json() as EmailLinkResponse;
          const candidate = result.data?.resend_after_seconds;
          if (Number.isInteger(candidate) && candidate >= 1 && candidate <= 3600) {
            resendAfterSeconds = candidate;
          }
        } catch {
          // Keep the documented cooldown if the acknowledgement body is unavailable.
        }
        try {
          sessionStorage.setItem("eve.auth.resend_after", String(Date.now() + resendAfterSeconds * 1000));
        } catch {
          // Acknowledged resend must not be reported as failed because storage is disabled.
        }
        setSeconds(resendAfterSeconds);
        setMessage("Yeni sorğu qəbul edildi.");
      } else if (response.status === 429) {
        setMessage("Bir az gözləyib yenidən cəhd edin.");
      } else {
        setMessage("Sorğu qəbul edilmədi. Yenidən cəhd edin.");
      }
    } catch {
      setMessage("Bağlantı alınmadı. Sorğu göndərilmədi.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="landing">
      <section className="landing-card auth-card" aria-labelledby="check-title">
        <p className="eyebrow">EMAILİ YOXLAYIN</p>
        <h1 id="check-title">Giriş keçidi istəyi qəbul edildi</h1>
        <p>
          {email ? <>Əgər <strong>{email}</strong> ünvanı ilə giriş mümkündürsə, keçid üçün sorğu qəbul edilib.</> :
            "Əgər email ünvanı ilə giriş mümkündürsə, keçid üçün sorğu qəbul edilib."}
        </p>
        <p className="auth-help">Email-in çatdırılması provayderdən asılıdır. Gəlmədikdə bir az sonra yenidən cəhd edə bilərsiniz.</p>
        {email ? (
          <button className="primary-link auth-submit" type="button" onClick={resend} disabled={busy || seconds > 0}>
            {busy ? "Sorğu göndərilir…" : seconds > 0 ? `Yenidən göndər (${seconds} s)` : "Yenidən göndər"}
          </button>
        ) : <Link className="primary-link auth-submit" href="/login">Email ünvanını daxil et</Link>}
        <p className="auth-status" role="status" aria-live="polite">{message}</p>
      </section>
    </main>
  );
}
