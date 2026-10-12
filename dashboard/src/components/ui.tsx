import { useEffect, type ReactNode } from "react";

export function PageHeader({ title, subtitle, actions }: { title: string; subtitle?: string; actions?: ReactNode }) {
  return (
    <header className="page-header">
      <div>
        <h1>{title}</h1>
        {subtitle && <p className="muted">{subtitle}</p>}
      </div>
      {actions && <div className="row gap">{actions}</div>}
    </header>
  );
}

export function Card({ title, extra, children, className = "" }: { title?: string; extra?: ReactNode; children: ReactNode; className?: string }) {
  return (
    <section className={`card ${className}`}>
      {(title || extra) && (
        <div className="card-head">
          {title && <h2>{title}</h2>}
          {extra}
        </div>
      )}
      {children}
    </section>
  );
}

export function Kpi({ label, value, caption, tone, progress }: { label: string; value: ReactNode; caption?: ReactNode; tone?: "teal" | "amber"; progress?: number }) {
  return (
    <div className={`kpi ${tone ?? ""}`}>
      <div className="kpi-label">{label}</div>
      <div className="kpi-value">{value}</div>
      {caption && <div className="kpi-caption">{caption}</div>}
      {progress !== undefined && <ProgressBar value={progress} tone={tone} />}
    </div>
  );
}

export function ProgressBar({ value, tone = "teal" }: { value: number; tone?: "teal" | "amber" }) {
  const v = Math.max(0, Math.min(1, value));
  return (
    <div className="progress" role="progressbar" aria-valuenow={Math.round(v * 100)} aria-valuemin={0} aria-valuemax={100}>
      <div className={`progress-fill ${tone}`} style={{ width: `${v * 100}%` }} />
    </div>
  );
}

type BadgeTone = "green" | "amber" | "red" | "grey" | "teal" | "blue";
export function Badge({ tone = "grey", children }: { tone?: BadgeTone; children: ReactNode }) {
  return <span className={`badge ${tone}`}>{children}</span>;
}

export const RegionBadge = ({ inRegion }: { inRegion: boolean }) =>
  inRegion ? <Badge tone="green">IN REGION</Badge> : <Badge tone="amber">OUT REGION</Badge>;

/** Vertical bar chart; `highlight` index is drawn in amber (e.g. peak hour). */
export function BarChart({ data, highlight, tone = "teal", height = 160 }: { data: { label: string; value: number }[]; highlight?: number; tone?: "teal" | "amber"; height?: number }) {
  const max = Math.max(1, ...data.map((d) => d.value));
  if (data.length === 0) return <Empty>No activity yet.</Empty>;
  return (
    <div className="barchart" style={{ height }}>
      {data.map((d, i) => (
        <div className="bar-col" key={d.label} title={`${d.label}: ${d.value}`}>
          <span className="bar-value">{d.value}</span>
          <div className={`bar ${i === highlight ? "amber" : tone}`} style={{ height: `${(d.value / max) * 100}%` }} />
          <span className="bar-label">{d.label}</span>
        </div>
      ))}
    </div>
  );
}

/** Horizontal ranked list with bars (top regions, top mobilizers). */
export function RankList({ items, tone = "teal" }: { items: { name: string; count: number; caption?: string }[]; tone?: "teal" | "amber" }) {
  const max = Math.max(1, ...items.map((i) => i.count));
  if (items.length === 0) return <Empty>Nothing to rank yet.</Empty>;
  return (
    <ol className="ranklist">
      {items.map((it) => (
        <li key={it.name}>
          <div className="rank-name">
            {it.name}
            {it.caption && <small className="muted">{it.caption}</small>}
          </div>
          <div className="rank-bar">
            <ProgressBar value={it.count / max} tone={tone} />
          </div>
          <div className="rank-count">{it.count.toLocaleString("en-KE")}</div>
        </li>
      ))}
    </ol>
  );
}

export function Empty({ children }: { children: ReactNode }) {
  return <div className="empty">{children}</div>;
}

export function Loading() {
  return <div className="empty">Loading…</div>;
}

export function ErrorNote({ error }: { error: string | null }) {
  return error ? <div className="alert red">{error}</div> : null;
}

export function Modal({ title, onClose, children }: { title: string; onClose: () => void; children: ReactNode }) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);
  return (
    <div className="modal-backdrop" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className="modal" role="dialog" aria-modal="true" aria-label={title}>
        <div className="card-head">
          <h2>{title}</h2>
          <button className="btn ghost" onClick={onClose} aria-label="Close">✕</button>
        </div>
        {children}
      </div>
    </div>
  );
}

export function Field({ label, children, hint }: { label: string; children: ReactNode; hint?: string }) {
  return (
    <label className="field">
      <span>{label}</span>
      {children}
      {hint && <small className="muted">{hint}</small>}
    </label>
  );
}

export function Toggle({ checked, onChange, label }: { checked: boolean; onChange: (v: boolean) => void; label: string }) {
  return (
    <label className="toggle">
      <input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} />
      <span className="toggle-track" />
      <span>{label}</span>
    </label>
  );
}
