import { useEffect, useState } from "react";
import { api, type RegistrationStats } from "../api";
import { num, pct } from "../format";
import { Card, ErrorNote, Kpi, Loading, PageHeader } from "../components/ui";

/** Registration analysis: adults in the national ID records vs those on the voter register. */
export default function RegistrationPage() {
  const [data, setData] = useState<RegistrationStats | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { api.registration().then(setData, (e: Error) => setError(e.message)); }, []);
  const rows = data ? [...data.rows].sort((a, b) => b.unregistered - a.unregistered) : [];

  return (
    <>
      <PageHeader title="Registration analysis" subtitle="Adults in the national ID records compared with the voter register, by home area — where the unregistered are." />
      <ErrorNote error={error} />
      {!data ? <Loading /> : (
        <>
          <div className="grid kpis">
            <Kpi label="Adults (national ID)" value={num(data.adults)} caption={data.label} />
            <Kpi label="Registered to vote" value={num(data.registered)} tone="teal" progress={data.adults ? data.registered / data.adults : 0} />
            <Kpi label="Not registered" value={num(data.adults - data.registered)} tone="amber" caption="the mobilization opportunity" />
            <Kpi label="Registration rate" value={pct(data.adults ? data.registered / data.adults : 0)} />
          </div>
          <Card title={data.level === "sub_county" ? `By sub-county · ${data.label}` : "By county"} extra={data.built_at && <small className="muted">updated {data.built_at}</small>}>
            <div className="table-wrap">
              <table>
                <thead><tr><th>{data.level === "sub_county" ? "Sub-county" : "County"}</th><th>Adults</th><th>Registered</th><th>Not registered</th><th>Rate</th></tr></thead>
                <tbody>
                  {rows.map((r) => (
                    <tr key={r.area}><td>{r.area}</td><td>{num(r.adults)}</td><td>{num(r.registered)}</td><td><strong>{num(r.unregistered)}</strong></td><td>{pct(r.rate)}</td></tr>
                  ))}
                  {rows.length === 0 && <tr><td colSpan={5} className="muted">Not built yet — run the analytics job after loading the registers.</td></tr>}
                </tbody>
              </table>
            </div>
            <p className="muted" style={{ marginTop: 10 }}>Home area is from the national ID records. Records include anyone ever issued an ID, so “adults” can include people who have since died or moved.</p>
          </Card>
        </>
      )}
    </>
  );
}
