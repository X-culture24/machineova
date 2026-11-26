import { useEffect, useState } from "react";
import { api, type RegistrationStats } from "../api";
import { num, pct } from "../format";
import { Card, ErrorNote, focusSection, Kpi, Loading, PageHeader } from "../components/ui";
import { useTable } from "../components/TableTools";

/** Registration analysis: adults in the national ID records vs those on the voter register. */
export default function RegistrationPage() {
  const [data, setData] = useState<RegistrationStats | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { api.registration().then(setData, (e: Error) => setError(e.message)); }, []);
  const table = useTable(data?.rows, [
    { key: "area", label: data?.level === "sub_county" ? "Sub-county" : "County", sort: (r) => r.area },
    { key: "adults", label: "Adults", num: true, sort: (r) => r.adults },
    { key: "registered", label: "Registered", num: true, sort: (r) => r.registered },
    { key: "unregistered", label: "Not registered", num: true, sort: (r) => r.unregistered },
    { key: "rate", label: "Rate", num: true, sort: (r) => r.rate },
  ], { key: "unregistered", dir: "desc" });
  const rows = table.rows;
  const metric = table.sort?.key;
  const showMetric = (next: "adults" | "registered" | "unregistered" | "rate") => { table.setSort({ key: next, dir: "desc" }); focusSection("registration-areas"); };

  return (
    <>
      <PageHeader title="Registration analysis" subtitle="Adults in the national ID records compared with the voter register, by home area — where the unregistered are." />
      <ErrorNote error={error} />
      {!data ? <Loading /> : (
        <>
          <div className="grid kpis">
            <Kpi label="Adults (national ID)" value={num(data.adults)} caption={data.label} onClick={() => showMetric("adults")} pressed={metric === "adults"} />
            <Kpi label="Registered to vote" value={num(data.registered)} tone="teal" progress={data.adults ? data.registered / data.adults : 0} onClick={() => showMetric("registered")} pressed={metric === "registered"} />
            <Kpi label="Not registered" value={num(data.adults - data.registered)} tone="amber" onClick={() => showMetric("unregistered")} pressed={metric === "unregistered"} />
            <Kpi label="Registration rate" value={pct(data.adults ? data.registered / data.adults : 0)} onClick={() => showMetric("rate")} pressed={metric === "rate"} />
          </div>
          <Card id="registration-areas" title={data.level === "sub_county" ? `By sub-county · ${data.label}` : "By county"} extra={data.built_at && <small className="muted">updated {data.built_at}</small>}>
            <div className="table-wrap">
              <table>
                <thead>{table.head}</thead>
                <tbody>
                  {rows.map((r) => (
                    <tr key={r.area}><td>{r.area}</td><td className="num">{num(r.adults)}</td><td className="num">{num(r.registered)}</td><td className="num"><strong>{num(r.unregistered)}</strong></td><td className="num">{pct(r.rate)}</td></tr>
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
