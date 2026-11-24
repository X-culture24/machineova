import SearchInput from "../components/SearchInput";
import ParticipantTypeFilter from "../components/ParticipantFilter";
import { useState } from "react";
import { isManager, useAuth } from "../auth";
import AttendanceExport from "../components/AttendanceExport";
import { api, type ParticipantFilter, type PersonRecord } from "../api";
import { Card, Empty, ErrorNote, Loading, PageHeader, RegionBadge } from "../components/ui";
import { area, dateTime, initials } from "../format";
import { useAsync, useDebounced } from "../useAsync";
import { useTerms } from "../terms";
import { maskId } from "../mask";

type Tab = "checkins" | "mobilized";

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
  const t = useTerms();
  const { me } = useAuth();
  const [tab, setTab] = useState<Tab>("checkins");
  const [group, setGroup] = useState("");
  const [participants, setParticipants] = useState<ParticipantFilter>("");
  const [q, setQ] = useState("");
  const dq = useDebounced(q);
  const events = useAsync(() => api.events(), []);
  const drives = useAsync(() => api.drives(), []);
  const list = useAsync(
    () => (tab === "checkins" ? api.checkins({ event_id: group || undefined, q: dq, participants }) : api.mobilizations({ drive_id: group || undefined, q: dq })),
    [tab, group, dq, participants],
  );
  const groups = tab === "checkins" ? events.data?.items ?? [] : drives.data?.items ?? [];

  return (
    <>
      <PageHeader
        title="People reached"
        subtitle={t.peopleSubtitle}
        actions={tab === "checkins" && isManager(me)
          ? <AttendanceExport key={group} eventId={group || undefined} query={q} participants={participants} />
          : list.data && list.data.length > 0 && <button className="btn secondary" onClick={() => downloadCsv(list.data!, tab)}>Export CSV</button>}
      />
      <div className="toolbar">
        <div className="tabs" role="tablist">
          <button className={tab === "checkins" ? "on" : ""} onClick={() => { setTab("checkins"); setGroup(""); }}>{t.checkins}</button>
          {!t.chiefs && <button className={tab === "mobilized" ? "on" : ""} onClick={() => { setTab("mobilized"); setGroup(""); }}>{t.mobilized}</button>}
        </div>
        <select className="input" value={group} onChange={(e) => setGroup(e.target.value)}>
          <option value="">{tab === "checkins" ? `All ${t.events.toLowerCase()}` : t.chiefs ? "All counties" : "All drives"}</option>
          {groups.map((g) => <option key={g.id} value={g.id}>{g.name}</option>)}
        </select>
        <SearchInput label={tab === "checkins" ? "Search name, ID or phone" : "Search name or ID number"} value={q} onChange={setQ} />
        {tab === "checkins" && <ParticipantTypeFilter value={participants} onChange={setParticipants} />}
      </div>
      <ErrorNote error={list.error} />
      <Card>
        {!list.data ? <Loading /> : list.data.length === 0 ? <Empty>No one matches.</Empty> : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr><th>Name</th>{t.chiefs && <th>Phone</th>}{tab === "checkins" && <th>Participant type</th>}<th>Location</th><th>{tab === "checkins" ? t.event : t.drive}</th><th>By</th><th>Time</th>{tab === "checkins" && <th>Region</th>}</tr>
              </thead>
              <tbody>
                {list.data.map((p) => (
                  <tr key={p.id}>
                    <td>
                      <div className="person">
                        <span className={`avatar ${tab === "mobilized" ? "amber" : ""}`}>{initials(p.name)}</span>
                        <div><div style={{ fontWeight: 600 }}>{p.name || "Name not on record"}</div><small className="muted">ID {maskId(p.national_id)}</small></div>
                      </div>
                    </td>
                    {t.chiefs && <td>{p.phone ?? "—"}</td>}
                    {tab === "checkins" && <td>{p.selected_participant ? "Selected" : "General"}</td>}
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
