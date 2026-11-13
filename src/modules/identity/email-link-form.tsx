"use client";

import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";

type EmailLinkResponse = {
  data: {
    accepted: true;
    resend_after_seconds: number;
    link_ttl_seconds: number;
  };
};

export function EmailLinkForm() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    setMessage("");
    const trimmedEmail = email.trim();
    try {
      const response = await fetch("/api/v1/auth/email-link", {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        credentials: "same-origin",
        body: JSON.stringify({ email: trimmedEmail, redirect_path: "/today" }),
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
          // The HTTP acknowledgement is authoritative; retain the contract cooldown.
        }
        try {
          sessionStorage.setItem("eve.auth.email_hint", trimmedEmail);
          sessionStorage.setItem("eve.auth.resend_after", String(Date.now() + resendAfterSeconds * 1000));
        } catch {
          // Storage can be disabled; the neutral check-email page still works.
        }
        router.push("/login/check-email");
        return;
      }
      if (response.status === 422) {
        setMessage("Email ünvanını yoxlayın.");
      } else if (response.status === 429) {
        setMessage("Bir az gözləyib yenidən cəhd edin.");
      } else {
        setMessage("Sorğunu qəbul etmək mümkün olmadı. Bağlantını yoxlayıb yenidən cəhd edin.");
      }
    } catch {
      setMessage("Bağlantı alınmadı. Məlumat göndərilməyib; yenidən cəhd edin.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className="auth-form" onSubmit={submit}>
      <label htmlFor="login-email">Email ünvanı</label>
      <input
        id="login-email"
        name="email"
        type="email"
        autoComplete="email"
        inputMode="email"
        maxLength={254}
        required
        value={email}
        onChange={(event) => setEmail(event.target.value)}
        aria-describedby="login-help login-status"
      />
      <p id="login-help" className="auth-help">Şifrə tələb olunmur. Email keçidi ilə daxil olun.</p>
      <button className="primary-link auth-submit" type="submit" disabled={busy}>
        {busy ? "Sorğu göndərilir…" : "Email ilə davam et"}
      </button>
      <p id="login-status" className="auth-status" role="status" aria-live="polite">{message}</p>
    </form>
  );
}
