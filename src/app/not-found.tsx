import Link from "next/link";

export default function NotFound() {
  return <main className="error-page"><h1>Səhifə tapılmadı</h1><p>Bu ünvan üçün səhifə yoxdur.</p><Link href="/today">Bu günə qayıt</Link></main>;
}
