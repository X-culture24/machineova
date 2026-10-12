import { useEffect, useState } from "react";
import { api, type AuditEntry } from "../api";
import { Card, ErrorNote, Loading, PageHeader } from "../components/ui";

/** Append-only audit trail: every sign-in and every change in the organization. */
export default function ActivityPage() {
  const [rows, setRows] = useState<AuditEntry[] | null>(null);
  const [q, setQ] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [more, setMore] = useState(true);

  const load = (before?: string) =>
    api.audit({ q: q || undefined, before }).then((r) => {
      setRows((prev) => (before && prev ? [...prev, ...r] : r));
      setMore(r.length === 100);
    }, (e: Error) => setError(e.message));

  useEffect(() => {
    const t = setTimeout(() => { setRows(null); load(); }, 250);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q]);

  return (
    <>
      <PageHeader title="Activity log" subtitle="Every sign-in and every change, with who, when and from where. Entries can't be edited or deleted." />
      <ErrorNote error={error} />
      <Card>
        <input placeholder="Search by person or action…" value={q} onChange={(e) => setQ(e.target.value)} style={{ marginBottom: 12, width: "100%" }} />
        {!rows ? <Loading /> : (
          <div className="table-wrap">
            <table>
              <thead><tr><th>When</th><th>Who</th><th>What</th><th>Result</th><th>From</th></tr></thead>
              <tbody>
                {rows.map((e, i) => (
                  <tr key={i}>
                    <td>{new Date(e.at).toLocaleString()}</td>
                    <td>{e.actor ?? "—"}</td>
                    <td><code>{e.action}</code></td>
                    <td><span className={`badge ${e.status < 300 ? "green" : e.status < 500 ? "amber" : "red"}`}>{e.status}</span></td>
                    <td><small className="muted">{e.ip ?? "—"}</small></td>
                  </tr>
                ))}
                {rows.length === 0 && <tr><td colSpan={5} className="muted">No activity yet.</td></tr>}
              </tbody>
            </table>
          </div>
        )}
        {rows && more && rows.length > 0 && (
          <button className="btn secondary" style={{ marginTop: 12 }} onClick={() => load(rows[rows.length - 1].at)}>Load older</button>
        )}
      </Card>
    </>
  );
}
