import Link from "next/link";

export default function HomePage() {
  return <main className="landing"><div className="landing-card"><p className="eyebrow">GÜNLÜK KİRAYƏ EVLƏRİ</p><h1>Evlərin bir yerdə.</h1><p>Eve tətbiqinin mobil naviqasiyası hazırlanır. Giriş və məlumat əməliyyatları hələ serverə qoşulmayıb.</p><Link className="primary-link" href="/today">Mobil interfeysə bax</Link></div></main>;
}
