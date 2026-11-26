import { useEffect, useId, useState } from "react";
import { api, type Coverage, type CoverageRow } from "../api";
import { num, turnoutPercent } from "../format";
import { Badge, Card, ErrorNote, focusSection, Kpi, Loading } from "./ui";
import { useTable } from "./TableTools";

const statusLabel: Record<CoverageRow["status"], string> = {
  strong: "Strong", moderate: "Moderate", low: "Low", critical: "Critical", not_started: "Not started",
};
const statusTone = { strong: "green", moderate: "teal", low: "amber", critical: "red", not_started: "grey" } as const;
const levelLabel = { county: "County", constituency: "Constituency", ward: "Ward", polling_center: "Polling centre" };

/**
 * Coverage analytics: registered voters reached vs registered voters in the area,
 * drilling down constituency → ward → polling centre, with "push here next".
 */
export default function CoveragePanel({ group, onShowStations }: {
  group: { event_id?: string; drive_id?: string };
  onShowStations?: () => void;
}) {
  const areaId = useId();
  const [areasOpen, setAreasOpen] = useState(!onShowStations);
  const showAreas = () => { setAreasOpen(true); focusSection(areaId); };
  const [drill, setDrill] = useState<{ constituency?: string; ward?: string }>({});
  const [data, setData] = useState<Coverage | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    setData(null);
    setError(null);
    api.coverage(group, drill).then(
      (result) => { if (active) setData(result); },
      (e: Error) => { if (active) setError(e.message); },
    );
    return () => { active = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [group.event_id, group.drive_id, drill.constituency, drill.ward]);

  const open = (r: CoverageRow) => {
    if (!data) return;
    if (data.level === "constituency") setDrill({ constituency: r.area });
    else if (data.level === "ward") setDrill({ ...drill, ward: r.area });
  };
  const canDrill = data && (data.level === "constituency" || data.level === "ward");
  const table = useTable(data?.rows, [
    { key: "area", label: data ? levelLabel[data.level] : "Area", sort: (r) => r.area },
    { key: "reached", label: "Reached", num: true, sort: (r) => r.reached },
    { key: "registered", label: "Registered", num: true, sort: (r) => r.registered },
    { key: "coverage", label: "Coverage", num: true, sort: (r) => (r.registered > 0 ? r.reached / r.registered : null) },
    { key: "status", label: "Status", sort: (r) => r.status, filter: (r) => r.status, format: (v) => statusLabel[v as CoverageRow["status"]] ?? v },
  ]);

  return (
    <Card
      title={`Coverage${data ? ` · ${data.label}` : ""}`}
      extra={(drill.constituency || drill.ward) && <button className="btn small secondary" onClick={() => setDrill(drill.ward ? { constituency: drill.constituency } : {})}>← Up a level</button>}
    >
      <ErrorNote error={error} />
      {!data ? !error && <Loading /> : (
        <div className="stack">
          <div className="grid kpis">
            <Kpi label="Registered voters reached" value={num(data.reached)} caption={`of ${num(data.registered)} registered`} tone="teal" onClick={onShowStations ?? showAreas} />
            <Kpi label="Turnout" value={turnoutPercent(data.reached, data.registered)} progress={data.registered ? data.reached / data.registered : 0} onClick={onShowStations ?? showAreas} />
            <Kpi label="Remaining" value={num(data.remaining)} caption="still to reach" onClick={onShowStations ?? showAreas} />
            <Kpi label="Not registered" value={num(data.not_registered)} caption="reached, not on the register" tone="amber" details={<p>People reached in {data.label} whose ID does not match the voter register.</p>} />
            <Kpi label="Gender mix" value={`${num(data.female)} · ${num(data.male)}`} caption="female · male" details={<p>Counts use the available demographic records for {data.label}.</p>} />
            <Kpi label="Top age group" value={data.top_age_group ?? "—"} details={<p>Most common recorded age group among people reached in {data.label}.</p>} />
          </div>
          {data.push_here_next && data.push_here_next.length > 0 && (
            <div className="alert amber">
              <strong>Push here next:</strong>{" "}
              {data.push_here_next.map((r) => `${r.area} (${num(r.remaining)} to reach)`).join(" · ")}
            </div>
          )}
          <details id={areaId} className="insight-target" tabIndex={-1} open={areasOpen} onToggle={(e) => setAreasOpen(e.currentTarget.open)}>
            <summary>Coverage by area</summary>
            {table.filterBar}
            <div className="table-wrap">
              <table>
                <thead>{table.head}</thead>
                <tbody>
                  {table.rows.map((r) => (
                    <tr key={r.area}>
                      <td>{canDrill ? <button type="button" className="btn small ghost" onClick={() => open(r)}>{r.area} ›</button> : r.area}</td>
                      <td className="num">{num(r.reached)}</td>
                      <td className="num">{num(r.registered)}</td>
                      <td className="num">{turnoutPercent(r.reached, r.registered)}</td>
                      <td><Badge tone={statusTone[r.status]}>{statusLabel[r.status]}</Badge></td>
                    </tr>
                  ))}
                  {(!data.rows || data.rows.length === 0) && <tr><td colSpan={5} className="muted">No registered voters found for this area.</td></tr>}
                </tbody>
              </table>
            </div>
          </details>
        </div>
      )}
    </Card>
  );
}
