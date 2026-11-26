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

function parseCsv(csv: string) {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let quoted = false;
  for (let i = csv.charCodeAt(0) === 0xfeff ? 1 : 0; i < csv.length; i++) {
    const char = csv[i];
    if (char === '"') {
      if (quoted && csv[i + 1] === '"') {
        field += '"';
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (!quoted && (char === "," || char === "\r" || char === "\n")) {
      row.push(field);
      field = "";
      if (char === ",") continue;
      if (char === "\r" && csv[i + 1] === "\n") i++;
      rows.push(row);
      row = [];
    } else {
      field += char;
    }
  }
  if (row.length || field) rows.push([...row, field]);
  return rows;
}

async function exportReportPdf(title: string, csv: string, filename: string) {
  const [headers, ...rows] = parseCsv(csv);
  if (!headers?.some(Boolean)) throw new Error("The report returned no columns.");
  const [{ jsPDF }, { autoTable }] = await Promise.all([import("jspdf"), import("jspdf-autotable")]);
  const doc = new jsPDF({ orientation: "landscape" });
  doc.setProperties({ title });
  autoTable(doc, {
    startY: 24,
    head: [headers],
    body: rows,
    styles: { fontSize: 8 },
    didDrawPage: ({ pageNumber }) => {
      doc.setFontSize(12);
      doc.text(doc.splitTextToSize(title, 260).slice(0, 2), 14, 13);
      doc.setFontSize(8);
      doc.text(`Page ${pageNumber}`, 283, 202, { align: "right" });
    },
  });
  doc.save(filename);
}

export function ReportsPage() {
  const { me } = useAuth();
  const ov = useAsync(ops.overview, []);
  const [err, setErr] = useState<string | null>(null);
  const e = ov.data?.election;
  const [busy, setBusy] = useState("");
  async function downloadReport(report: (typeof reports)[number], format: "csv" | "pdf") {
    if (!e || busy) return;
    const filename = `${e.code.toLowerCase()}-${report.kind}.${format}`;
    setErr(null);
    setBusy(`${report.kind}-${format}`);
    try {
      if (format === "csv") await ops.downloadReport(report.kind, filename);
      else await exportReportPdf(`${report.title} — ${e.name}`, await ops.reportText(report.kind), filename);
    } catch (error) {
      setErr((error as Error).message);
    } finally {
      setBusy("");
    }
  }
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
              <button type="button" className="btn small" disabled={!e || !!busy} onClick={() => downloadReport(r, "csv")}>
                {busy === `${r.kind}-csv` ? "Preparing…" : "Export CSV"}
              </button>
              <button type="button" className="btn small secondary" disabled={!e || !!busy} onClick={() => downloadReport(r, "pdf")}>
                {busy === `${r.kind}-pdf` ? "Preparing…" : "Export PDF"}
              </button>
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
