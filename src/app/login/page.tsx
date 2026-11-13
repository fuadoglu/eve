import { EmailLinkForm } from "../../modules/identity/email-link-form.tsx";

export const metadata = {
  title: "Email ilə daxil ol — Eve",
  robots: { index: false, follow: false },
};

export default function LoginPage() {
  return (
    <main className="landing">
      <section className="landing-card auth-card" aria-labelledby="login-title">
        <p className="eyebrow">EVE-YƏ DAXİL OL</p>
        <h1 id="login-title">Evlərin bir yerdə.</h1>
        <p>Email ünvanınızı yazın. Sizə şifrəsiz giriş keçidi istəyi yaradacağıq.</p>
        <EmailLinkForm />
      </section>
    </main>
  );
}
