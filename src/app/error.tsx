"use client";

export default function ErrorPage({ reset }: { error: Error; reset: () => void }) {
  return <main className="error-page" role="alert"><h1>Məlumat açıla bilmədi</h1><p>Bir az sonra yenidən sınayın. Heç bir dəyişiklik saxlanılmayıb.</p><button type="button" onClick={reset}>Yenidən yoxla</button></main>;
}
