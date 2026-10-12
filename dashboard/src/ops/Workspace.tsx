import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "../auth";
import { Card, ErrorNote, Field, Loading, PageHeader } from "../components/ui";
import { useAsync } from "../useAsync";
import { ops } from "./api";
import { OpsHeader } from "./components";

const reports = [
  { kind: "coverage", title: "Station coverage", text: "Agents assigned per station, the uncovered list, and manager contacts." },
  { kind: "turnout", title: "Turnout by region", text: "Hourly cumulative turnout at every level of your area." },
  { kind: "results", title: "Results summary", text: "Provisional tallies per position, with verification status per station." },
  { kind: "incidents", title: "Incident log", text: "Every flag raised — type, note, resolution and timing." },
];

/** Renders a CSV as a printable table in a new window (browser "Save as PDF"). */
function printCsv(title: string, csv: string) {
  const rows = csv.trim().split("\n").map((line) => {
    const out: string[] = [];
    let cur = "", quoted = false;
    for (let i = 0; i < line.length; i++) {
      const ch = line[i]!;
      if (ch === '"' && line[i + 1] === '"' && quoted) { cur += '"'; i++; }
      else if (ch === '"') quoted = !quoted;
      else if (ch === "," && !quoted) { out.push(cur); cur = ""; }
      else cur += ch;
    }
    out.push(cur);
    return out;
  });
  const esc = (s: string) => s.replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[c]!);
  const w = window.open("", "_blank");
  if (!w) return;
  w.document.write(`<!doctype html><meta charset="utf-8"><title>${esc(title)}</title>
    <style>body{font:12px system-ui,sans-serif;margin:24px}h1{font-size:18px}table{border-collapse:collapse;width:100%}
    th,td{border:1px solid #ccc;padding:4px 6px;text-align:left}th{background:#f2f5f4}</style>
    <h1>${esc(title)}</h1><p>Generated ${new Date().toLocaleString()}</p>
    <table><thead><tr>${rows[0]!.map((h) => `<th>${esc(h)}</th>`).join("")}</tr></thead>
    <tbody>${rows.slice(1).map((r) => `<tr>${r.map((c) => `<td>${esc(c)}</td>`).join("")}</tr>`).join("")}</tbody></table>`);
  w.document.close();
  w.focus();
  w.print();
}

export function ReportsPage() {
  const { me } = useAuth();
  const ov = useAsync(ops.overview, []);
  const [err, setErr] = useState<string | null>(null);
  const e = ov.data?.election;
  return (
    <>
      <OpsHeader title="Reports" subtitle={`Exports scoped to ${me?.scope_label ?? "your area"}`} election={e} scopeLabel={me?.scope_label} />
      <ErrorNote error={err ?? (ov.error?.includes("No active election") ? "No active election to report on." : ov.error)} />
      <div className="grid cols-even">
        {reports.map((r) => (
          <Card key={r.kind} title={r.title}>
            <p className="muted" style={{ marginTop: -6 }}>{r.text}</p>
            <small className="muted">Scoped to {me?.scope_label}{e && ` · ${e.name}`}</small>
            <div className="row gap" style={{ marginTop: 12 }}>
              <button className="btn small" disabled={!e} onClick={() => ops.downloadReport(r.kind, `${e!.code.toLowerCase()}-${r.kind}.csv`).catch((x: Error) => setErr(x.message))}>Export CSV</button>
              <button className="btn small secondary" disabled={!e} onClick={() => ops.reportText(r.kind).then((csv) => printCsv(`${r.title} — ${e!.name}`, csv), (x: Error) => setErr(x.message))}>Export PDF</button>
            </div>
          </Card>
        ))}
      </div>
    </>
  );
}

export function SettingsPage() {
  const { me } = useAuth();
  const s = useAsync(ops.settings, []);
  const [name, setName] = useState("");
  const [accent, setAccent] = useState("#0F8A7A");
  const [msg, setMsg] = useState<{ tone: "green" | "red"; text: string } | null>(null);
  useEffect(() => {
    if (s.data) {
      setName(s.data.name);
      setAccent(s.data.accent_color);
    }
  }, [s.data]);
  const owner = me?.role === "owner";
  return (
    <>
      <PageHeader title="Branding & workspace" subtitle={owner ? undefined : "Only the owner can change branding."} />
      <ErrorNote error={s.error} />
      {!s.data ? <Loading /> : (
        <div className="grid cols-even" style={{ alignItems: "start" }}>
          <Card title="Branding">
            <p className="muted" style={{ marginTop: -6 }}>Applied live for every member of the organization — sidebar, buttons, charts.</p>
            {msg && <div className={`alert ${msg.tone}`}>{msg.text}</div>}
            <div className="stack">
              <Field label="Organization name"><input value={name} disabled={!owner} onChange={(e) => setName(e.target.value)} /></Field>
              <Field label="Accent color">
                <div className="row gap">
                  <input type="color" value={accent} disabled={!owner} onChange={(e) => setAccent(e.target.value)} style={{ width: 52, height: 38, padding: 2 }} />
                  <input value={accent} disabled={!owner} onChange={(e) => setAccent(e.target.value)} />
                </div>
              </Field>
              <div className="brand-preview" style={{ ["--preview" as string]: accent }}>
                <span className="brand-mark" style={{ background: accent }}>✓</span>
                <div><strong>{name}</strong><small className="muted"> · sign-in preview</small></div>
                <button className="btn small" style={{ background: accent, marginLeft: "auto" }}>Sign In</button>
              </div>
              {owner && (
                <button className="btn" onClick={() => ops.updateSettings({ name, accent_color: accent.toUpperCase() }).then(() => {
                  setMsg({ tone: "green", text: "Saved. Members see the new branding on their next page load." });
                  document.documentElement.style.setProperty("--teal", accent);
                }, (e: Error) => setMsg({ tone: "red", text: e.message }))}>Save branding</button>
              )}
            </div>
          </Card>
          <Card title="Members & roles">
            <p className="muted" style={{ marginTop: -6 }}>Role and geography decide what each person sees.</p>
            <Link className="btn secondary" to="/ops/people">Open people directory</Link>
          </Card>
        </div>
      )}
    </>
  );
}
