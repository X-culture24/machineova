import type { ReactNode } from "react";
import { Badge } from "../components/ui";
import { statusLabel, statusTone, slotLabel, type Drill, type Election, type StationStatus, type TrendPoint } from "./api";

/** Page header for the ops workspace: title, subtitle, and the active-election + scope pills. */
export function OpsHeader({ title, subtitle, election, scopeLabel, actions }: {
  title: string;
  subtitle?: string;
  election?: Election | null;
  scopeLabel?: string;
  actions?: ReactNode;
}) {
  return (
    <header className="page-header ops-header">
      <div className="ops-title">
        <h1>{title}</h1>
        {subtitle && <p className="muted">{subtitle}</p>}
      </div>
      <div className="row gap wrap">
        {actions}
        {election && <span className="pill accent">● {election.name}</span>}
        {scopeLabel && (
          <span className="pill">
            <span className="muted">Scope</span> <strong>{scopeLabel}</strong>
          </span>
        )}
      </div>
    </header>
  );
}

export const StatusBadge = ({ status }: { status: StationStatus }) => (
  <Badge tone={statusTone[status]}>
    {status === "issue" ? "● " : ""}
    {statusLabel[status]}
  </Badge>
);

/** Cumulative turnout area chart over the reporting slots. */
export function TrendChart({ points, slots, height = 180 }: { points: TrendPoint[]; slots: number[]; height?: number }) {
  const w = 600;
  const pad = { l: 24, r: 24, t: 12, b: 24 };
  const first = slots[0] ?? 6;
  const last = slots[slots.length - 1] ?? 17;
  const x = (h: number) => pad.l + ((h - first) / Math.max(1, last - first)) * (w - pad.l - pad.r);
  const maxT = Math.max(0.1, ...points.map((p) => p.turnout));
  const y = (t: number) => pad.t + (1 - t / maxT) * (height - pad.t - pad.b);
  const line = points.map((p, i) => `${i ? "L" : "M"}${x(p.hour).toFixed(1)},${y(p.turnout).toFixed(1)}`).join(" ");
  const area = points.length ? `${line} L${x(points[points.length - 1]!.hour)},${height - pad.b} L${x(points[0]!.hour)},${height - pad.b} Z` : "";
  return (
    <svg className="trend" viewBox={`0 0 ${w} ${height}`} preserveAspectRatio="none" role="img" aria-label="Turnout trend">
      <defs>
        <linearGradient id="trendFill" x1="0" x2="0" y1="0" y2="1">
          <stop offset="0" stopColor="var(--teal)" stopOpacity="0.35" />
          <stop offset="1" stopColor="var(--teal)" stopOpacity="0.02" />
        </linearGradient>
      </defs>
      {[0.25, 0.5, 0.75].map((f) => (
        <line key={f} x1={pad.l} x2={w - pad.r} y1={pad.t + f * (height - pad.t - pad.b)} y2={pad.t + f * (height - pad.t - pad.b)} className="grid-line" />
      ))}
      {points.length > 0 && (
        <>
          <path d={area} fill="url(#trendFill)" />
          <path d={line} fill="none" stroke="var(--teal)" strokeWidth="2.5" vectorEffect="non-scaling-stroke" />
          {points.map((p) => (
            <circle key={p.hour} cx={x(p.hour)} cy={y(p.turnout)} r="3.5" fill="var(--teal)">
              <title>{`${slotLabel(p.hour)}: ${Math.round(p.turnout * 100)}%`}</title>
            </circle>
          ))}
        </>
      )}
      {slots.map((h) => (
        <text key={h} x={x(h)} y={height - 6} textAnchor="middle" className="axis-label">
          {slotLabel(h)}
        </text>
      ))}
    </svg>
  );
}

/** Breadcrumb for region drill-down: scope › constituency › ward. */
export function DrillCrumbs({ root, drill, onChange }: { root: string; drill: Drill; onChange: (d: Drill) => void }) {
  return (
    <div className="crumbs">
      <button className="crumb" onClick={() => onChange({})} disabled={!drill.constituency && !drill.ward}>{root}</button>
      {drill.constituency && (
        <>
          <span className="muted">›</span>
          <button className="crumb" onClick={() => onChange({ constituency: drill.constituency })} disabled={!drill.ward}>
            {drill.constituency}
          </button>
        </>
      )}
      {drill.ward && (
        <>
          <span className="muted">›</span>
          <span className="crumb current">{drill.ward}</span>
        </>
      )}
    </div>
  );
}

/** Drill into a child row: constituency first, then ward. */
export function drillInto(drill: Drill, childLevel: string, name: string): Drill | null {
  if (childLevel === "constituency") return { constituency: name };
  if (childLevel === "ward") return { ...drill, ward: name };
  return null;
}

export function Pager({ page, pageSize, total, onPage }: { page: number; pageSize: number; total: number; onPage: (p: number) => void }) {
  const pages = Math.max(1, Math.ceil(total / pageSize));
  const from = total === 0 ? 0 : (page - 1) * pageSize + 1;
  const to = Math.min(total, page * pageSize);
  return (
    <div className="pager">
      <span className="muted">Showing {from}–{to} of {total}</span>
      <div className="row gap">
        <button className="btn small secondary" disabled={page <= 1} onClick={() => onPage(page - 1)}>Prev</button>
        {Array.from({ length: Math.min(pages, 5) }, (_, i) => {
          const n = Math.min(Math.max(1, page - 2), Math.max(1, pages - 4)) + i;
          return (
            <button key={n} className={`btn small ${n === page ? "" : "secondary"}`} onClick={() => onPage(n)}>{n}</button>
          );
        })}
        <button className="btn small secondary" disabled={page >= pages} onClick={() => onPage(page + 1)}>Next</button>
      </div>
    </div>
  );
}

export function PartyDot({ colour }: { colour?: string | null }) {
  return <span className="party-dot" style={{ background: colour ?? "var(--muted)" }} />;
}

/** Tel / WhatsApp quick links for a phone number. */
export function ContactLinks({ phone }: { phone: string | null }) {
  if (!phone) return <span className="muted">—</span>;
  const digits = phone.replace(/[^0-9]/g, "");
  return (
    <span className="row gap">
      <a className="btn small secondary" href={`tel:${phone.replace(/\s/g, "")}`}>Call</a>
      <a className="btn small whatsapp" href={`https://wa.me/${digits}`} target="_blank" rel="noreferrer">WhatsApp</a>
    </span>
  );
}

export function NoElection({ canSetup }: { canSetup: boolean }) {
  return (
    <div className="card">
      <div className="empty">
        <p style={{ fontWeight: 600, color: "var(--text)" }}>No active election</p>
        <p>{canSetup ? "Create or activate one under Set up › Election." : "Ask your admin to activate the election."}</p>
        {canSetup && <a className="btn" href="/ops/election">Go to Election setup</a>}
      </div>
    </div>
  );
}
