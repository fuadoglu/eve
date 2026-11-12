"use client";

import Link from "next/link";
import { CalendarDays, House, ListTodo } from "lucide-react";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState } from "react";

const destinations = [
  { href: "/today", label: "Bu gün", icon: ListTodo },
  { href: "/calendar", label: "Təqvim", icon: CalendarDays },
  { href: "/properties", label: "Mənzillər", icon: House },
] as const;

const actions = ["Rezervasiya", "Pul qeydi", "Xərc", "Tapşırıq"] as const;

export function MobileShell({ children }: { children: React.ReactNode }) {
  const path = usePathname();
  const [menuOpen, setMenuOpen] = useState(false);
  const [online, setOnline] = useState(true);
  const plusRef = useRef<HTMLButtonElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const sync = () => setOnline(navigator.onLine);
    sync();
    window.addEventListener("online", sync);
    window.addEventListener("offline", sync);
    return () => {
      window.removeEventListener("online", sync);
      window.removeEventListener("offline", sync);
    };
  }, []);

  useEffect(() => {
    if (!menuOpen) return;
    menuRef.current?.focus();
    const close = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setMenuOpen(false);
        plusRef.current?.focus();
      }
    };
    window.addEventListener("keydown", close);
    return () => window.removeEventListener("keydown", close);
  }, [menuOpen]);

  return (
    <div className="app-shell">
      <header className="app-header">
        <span className="wordmark" aria-label="Eve">eve</span>
        <span className="header-note">Evlərin bir yerdə</span>
      </header>
      {!online && <p className="offline-banner" role="status">Bağlantı yoxdur. Məlumat yenilənmir.</p>}
      <main id="main-content" className="app-content">{children}</main>
      <div className="action-area">
        {menuOpen && (
          <div className="action-menu" id="action-menu" ref={menuRef} tabIndex={-1} role="dialog" aria-modal="false" aria-label="Yeni əməliyyat">
            <p className="menu-heading">Yeni əməliyyat</p>
            <p className="menu-help">Əvvəl ev seçilməlidir. Ev məlumatları serverə qoşulduqda bu əməliyyatlar açılacaq.</p>
            {actions.map((action) => <button className="menu-action" type="button" disabled key={action}>{action}</button>)}
            <button className="menu-close" type="button" onClick={() => { setMenuOpen(false); plusRef.current?.focus(); }}>Bağla</button>
          </div>
        )}
        <button ref={plusRef} className="plus-button" type="button" aria-label="Əlavə et" aria-expanded={menuOpen} aria-controls={menuOpen ? "action-menu" : undefined} onClick={() => setMenuOpen((value) => !value)}>+</button>
      </div>
      <nav className="bottom-nav" aria-label="Əsas mobil naviqasiya">
        {destinations.map(({ href, label, icon: Icon }) => (
          <Link href={href} key={href} className="nav-link" aria-current={path === href ? "page" : undefined} onClick={() => setMenuOpen(false)}>
            <Icon className="nav-icon" size={20} strokeWidth={2} aria-hidden="true" /><span>{label}</span>
          </Link>
        ))}
      </nav>
    </div>
  );
}

export function EmptyState({ title, detail }: { title: string; detail: string }) {
  return <section className="state-card" aria-labelledby="empty-title"><span className="state-mark"><House size={24} strokeWidth={2} aria-hidden="true" /></span><h2 id="empty-title">{title}</h2><p>{detail}</p></section>;
}
