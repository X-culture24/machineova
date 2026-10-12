import { useEffect, useState } from "react";
import { api, type PersonRecord } from "../api";
import { Card, Empty, ErrorNote, Loading, PageHeader, RegionBadge } from "../components/ui";
import { area, dateTime, initials } from "../format";
import { useAsync } from "../useAsync";
import { maskId } from "../mask";

type Tab = "checkins" | "mobilized";

function useDebounced<T>(value: T, ms = 300) {
  const [v, setV] = useState(value);
  useEffect(() => {
    const t = setTimeout(() => setV(value), ms);
    return () => clearTimeout(t);
  }, [value, ms]);
  return v;
}

function downloadCsv(rows: PersonRecord[], tab: Tab) {
  const header = ["name", "national_id", "sex", "phone", "county", "constituency", "ward", tab === "checkins" ? "event" : "drive", "by", "at"];
  const esc = (s: unknown) => `"${String(s ?? "").replace(/"/g, '""')}"`;
  const lines = rows.map((r) => [r.name, maskId(r.national_id), r.sex, r.phone, r.county, r.constituency, r.ward, r.group_name, r.by, r.at].map(esc).join(","));
  const blob = new Blob([[header.join(","), ...lines].join("\n")], { type: "text/csv" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = `${tab}-${new Date().toISOString().slice(0, 10)}.csv`;
  a.click();
  URL.revokeObjectURL(a.href);
}

export default function PeoplePage() {
  const [tab, setTab] = useState<Tab>("checkins");
  const [group, setGroup] = useState("");
  const [q, setQ] = useState("");
  const dq = useDebounced(q);
  const events = useAsync(() => api.events(), []);
  const drives = useAsync(() => api.drives(), []);
  const list = useAsync(
    () => (tab === "checkins" ? api.checkins({ event_id: group || undefined, q: dq }) : api.mobilizations({ drive_id: group || undefined, q: dq })),
    [tab, group, dq],
  );
  const groups = tab === "checkins" ? events.data?.items ?? [] : drives.data?.items ?? [];

  return (
    <>
      <PageHeader
        title="People reached"
        subtitle="Everyone checked in at events and mobilized in the field."
        actions={list.data && list.data.length > 0 && <button className="btn secondary" onClick={() => downloadCsv(list.data!, tab)}>Export CSV</button>}
      />
      <div className="toolbar">
        <div className="tabs" role="tablist">
          <button className={tab === "checkins" ? "on" : ""} onClick={() => { setTab("checkins"); setGroup(""); }}>Check-ins</button>
          <button className={tab === "mobilized" ? "on" : ""} onClick={() => { setTab("mobilized"); setGroup(""); }}>Mobilized</button>
        </div>
        <select className="input" value={group} onChange={(e) => setGroup(e.target.value)}>
          <option value="">{tab === "checkins" ? "All events" : "All drives"}</option>
          {groups.map((g) => <option key={g.id} value={g.id}>{g.name}</option>)}
        </select>
        <input className="input" placeholder="Search name or ID number…" value={q} onChange={(e) => setQ(e.target.value)} />
      </div>
      <ErrorNote error={list.error} />
      <Card>
        {!list.data ? <Loading /> : list.data.length === 0 ? <Empty>No one matches.</Empty> : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr><th>Name</th><th>Location</th><th>{tab === "checkins" ? "Event" : "Drive"}</th><th>By</th><th>Time</th>{tab === "checkins" && <th>Region</th>}</tr>
              </thead>
              <tbody>
                {list.data.map((p) => (
                  <tr key={p.id}>
                    <td>
                      <div className="person">
                        <span className={`avatar ${tab === "mobilized" ? "amber" : ""}`}>{initials(p.name)}</span>
                        <div><div style={{ fontWeight: 600 }}>{p.name}</div><small className="muted">ID {maskId(p.national_id)}</small></div>
                      </div>
                    </td>
                    <td>{area(p.constituency, p.ward)}</td>
                    <td>{p.group_name}</td>
                    <td>{p.by}</td>
                    <td>{dateTime(p.at)}</td>
                    {tab === "checkins" && <td><RegionBadge inRegion={p.in_region ?? true} /></td>}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </>
  );
}
