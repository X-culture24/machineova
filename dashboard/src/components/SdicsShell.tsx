import { useEffect, useRef, useState, type ReactNode } from "react";
import { NavLink, useLocation } from "react-router-dom";
import type { Me } from "../api";
import { initials } from "../format";
import { Icon, type IconName } from "./icons";
import ThemeToggle from "./ThemeToggle";

export interface SdTab { to: string; label: string; icon: IconName; end?: boolean }

const when = (d: Date) =>
  d.toLocaleString("en-GB", { weekday: "short", day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }).replace(",", "");

/** The SDICS dashboards' frame (as analytics.sdics.tech and rri.sdics.tech): a header with the coat of
 *  arms, the product name and a live line, the sections as tabs underneath, and the account on the right. */
export default function SdicsShell({ me, tabs, roleText, onSignOut, children }: {
  me: Me; tabs: SdTab[]; roleText: string; onSignOut: () => void; children: ReactNode;
}) {
  const [now, setNow] = useState(new Date());
  const [menu, setMenu] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const account = useRef<HTMLButtonElement>(null);
  const loc = useLocation();
  useEffect(() => {
    const t = setInterval(() => setNow(new Date()), 30_000);
    return () => clearInterval(t);
  }, []);
  useEffect(() => setMenu(false), [loc.pathname]);
  useEffect(() => {
    if (!menu) return;
    const close = (e: MouseEvent) => { if (!ref.current?.contains(e.target as Node)) setMenu(false); };
    const escape = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      setMenu(false);
      account.current?.focus();
    };
    document.addEventListener("mousedown", close);
    document.addEventListener("keydown", escape);
    return () => {
      document.removeEventListener("mousedown", close);
      document.removeEventListener("keydown", escape);
    };
  }, [menu]);

  return (
    <div className="sd-shell">
      <header className="sd-top">
        <div className="sd-top-row">
          <img className="sd-top-logo" src="/sdics-logo.jpeg" alt="Kenya coat of arms" />
          <div className="sd-top-text">
            <div className="sd-top-title">SDICS Checkin</div>
            <div className="sd-top-sub">{me.organization ? `${me.organization.name} · ${me.scope_label}` : "Check-ins"}</div>
            <div className="sd-top-status">Live check-ins · {when(now)}</div>
          </div>
          <div className="sd-top-right" ref={ref}>
            <ThemeToggle />
            <button ref={account} type="button" className="sd-avatar" aria-label="Account menu" onClick={() => setMenu((m) => !m)} aria-expanded={menu} aria-controls={menu ? "sd-account-menu" : undefined}
              title={me.name}>{initials(me.name)}</button>
            {menu && (
              <div id="sd-account-menu" className="sd-menu">
                <div className="who">{me.name}</div>
                <small>{roleText}</small>
                <NavLink to="/account">Account</NavLink>
                <button type="button" onClick={onSignOut}>Sign out</button>
              </div>
            )}
          </div>
        </div>
        <nav className="sd-tabs" aria-label="Sections">
          {tabs.map((t) => (
            <NavLink key={t.to} to={t.to} end={t.end} className={({ isActive }) => `sd-tab${isActive ? " active" : ""}`}>
              <Icon name={t.icon} size={18} />
              {t.label}
            </NavLink>
          ))}
        </nav>
      </header>
      <main className="sd-main">{children}</main>
    </div>
  );
}
