import { randomBytes } from "node:crypto";
import { escapeHtmlAttribute } from "../../../modules/identity/auth-contract.ts";

export function renderConfirmationLanding(tokenHash: string | null): Response {
  const nonce = randomBytes(18).toString("base64");
  const escapedToken = escapeHtmlAttribute(tokenHash ?? "");
  const buttonDisabled = tokenHash ? "" : " disabled";
  const initialStatus = tokenHash ? "Daxil olmaq üçün düyməni seçin." : "Bu keçid artıq aktiv deyil.";
  const html = `<!doctype html>
<html lang="az"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Eve — keçidi təsdiqlə</title>
<style nonce="${nonce}">body{margin:0;background:#f8fafc;color:#0f172a;font:16px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Arial,sans-serif}main{max-width:28rem;margin:12vh auto;padding:1.5rem}section{background:white;border:1px solid #cbd5e1;border-radius:12px;padding:2rem}h1{font-size:1.6rem;line-height:1.2}p{color:#475569}button,a{display:inline-flex;align-items:center;justify-content:center;min-height:48px;padding:.75rem 1rem;border:0;border-radius:12px;background:#0f766e;color:white;font:inherit;font-weight:700;text-decoration:none}button:focus-visible,a:focus-visible{outline:3px solid #0f766e;outline-offset:3px}button:disabled{opacity:.6}</style>
</head><body><main><section><p><strong>eve</strong></p><h1>Email keçidini təsdiqlə</h1><p>Keçid təsdiqlənməyib. Davam etmək üçün aşağıdakı düyməni özünüz seçin.</p>
<form id="confirm-form"><input id="token-hash" type="hidden" value="${escapedToken}"><button id="confirm-button" type="submit"${buttonDisabled}>Eve-yə daxil ol</button></form>
<p id="confirm-status" role="status" aria-live="polite">${initialStatus}</p><noscript><p>Keçidi təsdiqləmək üçün JavaScript-i aktiv edin, sonra giriş keçidini yenidən açın.</p></noscript></section></main>
<script nonce="${nonce}">
(() => {
  const form = document.getElementById("confirm-form");
  const tokenField = document.getElementById("token-hash");
  const button = document.getElementById("confirm-button");
  const status = document.getElementById("confirm-status");
  let tokenHash = tokenField.value;
  tokenField.value = "";
  history.replaceState(null, "", "/auth/confirm");
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!tokenHash || button.disabled) return;
    button.disabled = true;
    status.textContent = "Keçid yoxlanır…";
    try {
      const response = await fetch("/api/v1/auth/confirm", {
        method: "POST",
        credentials: "same-origin",
        headers: { "Content-Type": "application/json", "Accept": "application/json" },
        body: JSON.stringify({ token_hash: tokenHash, verification_type: "email", redirect_path: "/today" })
      });
      tokenHash = "";
      const result = await response.json();
      if (!response.ok) {
        status.textContent = response.status === 410 ? "Bu keçid artıq aktiv deyil." : "Keçid təsdiqlənmədi. Yenidən giriş keçidi istəyin.";
        button.disabled = true;
        return;
      }
      window.location.replace(result.data.redirect_path === "/today" ? "/today" : "/today");
    } catch {
      tokenHash = "";
      status.textContent = "Bağlantı alınmadı. Yenidən cəhd edin.";
      button.disabled = false;
    }
  });
})();
</script></body></html>`;
  return new Response(html, {
    status: 200,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "private, no-store",
      "Referrer-Policy": "no-referrer",
      "X-Robots-Tag": "noindex, nofollow",
      "Content-Security-Policy": `default-src 'none'; script-src 'nonce-${nonce}'; style-src 'nonce-${nonce}'; connect-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'`,
      "X-Content-Type-Options": "nosniff",
    },
  });
}
