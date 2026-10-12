import { useEffect, useState } from "react";
import { api, type Coverage, type CoverageRow } from "../api";
import { num, pct } from "../format";
import { Badge, Card, ErrorNote, Kpi, Loading } from "./ui";

const statusLabel: Record<CoverageRow["status"], string> = {
  strong: "Strong", moderate: "Moderate", low: "Low", critical: "Critical", not_started: "Not started",
};
const statusTone = { strong: "green", moderate: "teal", low: "amber", critical: "red", not_started: "grey" } as const;
const levelLabel = { county: "County", constituency: "Constituency", ward: "Ward", polling_center: "Polling centre" };

/**
 * Coverage analytics: registered voters reached vs registered voters in the area,
 * drilling down constituency → ward → polling centre, with "push here next".
 */
export default function CoveragePanel({ group }: { group: { event_id?: string; drive_id?: string } }) {
  const [drill, setDrill] = useState<{ constituency?: string; ward?: string }>({});
  const [data, setData] = useState<Coverage | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setData(null);
    api.coverage(group, drill).then(setData, (e: Error) => setError(e.message));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [group.event_id, group.drive_id, drill.constituency, drill.ward]);

  const open = (r: CoverageRow) => {
    if (!data) return;
    if (data.level === "constituency") setDrill({ constituency: r.area });
    else if (data.level === "ward") setDrill({ ...drill, ward: r.area });
  };
  const canDrill = data && (data.level === "constituency" || data.level === "ward");

  return (
    <Card
      title={`Coverage${data ? ` · ${data.label}` : ""}`}
      extra={(drill.constituency || drill.ward) && <button className="btn small secondary" onClick={() => setDrill(drill.ward ? { constituency: drill.constituency } : {})}>← Up a level</button>}
    >
      <ErrorNote error={error} />
      {!data ? <Loading /> : (
        <div className="stack">
          <div className="grid kpis">
            <Kpi label="Registered voters reached" value={num(data.reached)} caption={`of ${num(data.registered)} registered`} tone="teal" />
            <Kpi label="Coverage" value={pct(data.coverage)} progress={data.coverage} />
            <Kpi label="Remaining" value={num(data.remaining)} caption="still to reach" />
            <Kpi label="Not registered" value={num(data.not_registered)} caption="reached, not on the register" tone="amber" />
            <Kpi label="Gender mix" value={`${num(data.female)} · ${num(data.male)}`} caption="female · male" />
            <Kpi label="Top age group" value={data.top_age_group ?? "—"} />
          </div>
          {data.push_here_next && data.push_here_next.length > 0 && (
            <div className="alert amber">
              <strong>Push here next:</strong>{" "}
              {data.push_here_next.map((r) => `${r.area} (${num(r.remaining)} to reach)`).join(" · ")}
            </div>
          )}
          <div className="table-wrap">
            <table>
              <thead><tr><th>{levelLabel[data.level]}</th><th>Reached</th><th>Registered</th><th>Coverage</th><th>Status</th></tr></thead>
              <tbody>
                {(data.rows ?? []).map((r) => (
                  <tr key={r.area} className={canDrill ? "clickable" : ""} onClick={() => canDrill && open(r)}>
                    <td>{r.area}{canDrill && <small className="muted"> ›</small>}</td>
                    <td>{num(r.reached)}</td>
                    <td>{num(r.registered)}</td>
                    <td>{pct(r.coverage)}</td>
                    <td><Badge tone={statusTone[r.status]}>{statusLabel[r.status]}</Badge></td>
                  </tr>
                ))}
                {(!data.rows || data.rows.length === 0) && <tr><td colSpan={5} className="muted">No registered voters found for this area.</td></tr>}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </Card>
  );
}
