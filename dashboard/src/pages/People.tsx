import SearchInput from "../components/SearchInput";
import ParticipantTypeFilter from "../components/ParticipantFilter";
import { useSearchParams } from "react-router-dom";
import { useState } from "react";
import { isManager, useAuth } from "../auth";
import AttendanceExport from "../components/AttendanceExport";
import { api, type CheckinQuery, type FacetValue, type ParticipantFilter, type PersonRecord } from "../api";
import { Card, Empty, ErrorNote, Loading, PageHeader, RegionBadge } from "../components/ui";
import { area, dateTime, initials } from "../format";
import { useAsync, useDebounced } from "../useAsync";
import { useTerms } from "../terms";
import { maskId } from "../mask";
import { compareCells } from "../components/TableTools";

type Tab = "checkins" | "mobilized";
type Filters = Pick<CheckinQuery, "sex" | "age_group" | "county" | "constituency" | "ward" | "region" | "home_county" | "by" | "station">;
type Sort = { sort: string; dir: "asc" | "desc" };
const noFilters: Filters = {};
const newest: Sort = { sort: "at", dir: "desc" };
const sexLabel = (v: string) => (v === "F" ? "Female" : v === "M" ? "Male" : v);
const regionLabel = (v: string) => (v === "in" ? "In region" : v === "out" ? "Out of region" : v);

/** One demographic filter: the values present in the list, with counts. */
function FacetSelect({ label, value, values, format, onChange }: {
  label: string; value?: string; values?: FacetValue[]; format?: (v: string) => string; onChange: (v: string) => void;
}) {
  if (!values?.length && !value) return null;
  return (
    <select className="input" aria-label={label} value={value ?? ""} onChange={(e) => onChange(e.target.value)}>
      <option value="">{`All · ${label.toLowerCase()}`}</option>
      {(values ?? []).map((f) => <option key={f.value} value={f.value}>{`${f.label || (format ? format(f.value) : f.value)} (${f.count.toLocaleString()})`}</option>)}
    </select>
  );
}

function downloadCsv(rows: PersonRecord[], tab: Tab) {
  const header = ["name", "national_id", "sex", "phone", "county", "constituency", "ward", tab === "checkins" ? "event" : "drive", "by", "at"];
  const esc = (value: unknown) => {
    const text = String(value ?? "");
    const safe = /^[\s]*[=+@-]|^[\t\r\n]/.test(text) ? "'" + text : text;
    return '"' + safe.replaceAll('"', '""') + '"';
  };
  const lines = rows.map((r) => [r.name, maskId(r.national_id), r.sex, r.phone, r.county, r.constituency, r.ward, r.group_name, r.by, r.at].map(esc).join(","));
  const blob = new Blob([[header.join(","), ...lines].join("\n")], { type: "text/csv" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = `${tab}-${new Date().toISOString().slice(0, 10)}.csv`;
  a.click();
  window.setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

export default function PeoplePage() {
  const t = useTerms();
  const { me } = useAuth();
  const [params, setParams] = useSearchParams();
  const tab: Tab = !t.chiefs && params.get("tab") === "mobilized" ? "mobilized" : "checkins";
  const setTab = (selected: Tab) => setParams(selected === "mobilized" ? { tab: selected } : {});
  const [group, setGroup] = useState("");
  const [participants, setParticipants] = useState<ParticipantFilter>("");
  const [q, setQ] = useState("");
  const [filters, setFilters] = useState<Filters>(noFilters);
  const [sort, setSort] = useState<Sort>(newest);
  const dq = useDebounced(q);
  const events = useAsync(() => api.events(), []);
  const drives = useAsync(() => api.drives(), []);
  const facets = useAsync(
    () => (tab === "checkins" ? api.checkinFacets({ event_id: group || undefined, participants }) : Promise.resolve(null)),
    [tab, group, participants],
  );
  const list = useAsync(
    () => (tab === "checkins"
      ? api.checkins({ event_id: group || undefined, q: dq, participants, ...filters, ...sort })
      : api.mobilizations({ drive_id: group || undefined, q: dq })),
    [tab, group, dq, participants, JSON.stringify(filters), sort.sort, sort.dir],
  );
  // Mobilized lists arrive whole and sort here; check-ins sort in the API.
  const rows = tab === "checkins" || !list.data ? list.data : [...list.data].sort((a, b) => {
    const pick = (p: PersonRecord) => (sort.sort === "name" ? p.name : sort.sort === "ward" ? area(p.constituency, p.ward)
      : sort.sort === "event" ? p.group_name : sort.sort === "by" ? p.by : p.at);
    const c = compareCells(pick(a), pick(b));
    return sort.dir === "asc" ? c : -c;
  });
  const filter = (key: keyof Filters, value: string) => setFilters((f) => ({ ...f, [key]: value || undefined }));
  const filtered = Object.values(filters).some(Boolean) || sort.sort !== newest.sort || sort.dir !== newest.dir;
  // Click a heading to sort by it; click again to reverse.
  const sortBy = (key: string) => setSort((s) => (s.sort === key ? { sort: key, dir: s.dir === "asc" ? "desc" : "asc" } : { sort: key, dir: key === "at" ? "desc" : "asc" }));
  const th = (label: string, key: string) => (
    <th aria-sort={sort.sort === key ? (sort.dir === "asc" ? "ascending" : "descending") : "none"}>
      <button type="button" className="th-sort" onClick={() => sortBy(key)}>
        {label}{sort.sort === key ? (sort.dir === "asc" ? " ▲" : " ▼") : ""}
      </button>
    </th>
  );
  const f = facets.data;
  const groups = tab === "checkins" ? events.data?.items ?? [] : drives.data?.items ?? [];

  return (
    <>
      <PageHeader
        title="People reached"
        subtitle={t.peopleSubtitle}
        actions={tab === "checkins" && isManager(me)
          ? <AttendanceExport key={group} eventId={group || undefined} eventName={groups.find((g) => g.id === group)?.name} query={q} participants={participants} filters={{ ...filters, ...sort }} />
          : !list.loading && q === dq && list.data && list.data.length > 0 && <button type="button" className="btn secondary" onClick={() => downloadCsv(list.data!, tab)}>Export CSV</button>}
      />
      <div className="toolbar">
        <div className="tabs" role="tablist">
          <button className={tab === "checkins" ? "on" : ""} onClick={() => { setTab("checkins"); setGroup(""); setFilters(noFilters); setSort(newest); }}>{t.checkins}</button>
          {!t.chiefs && <button className={tab === "mobilized" ? "on" : ""} onClick={() => { setTab("mobilized"); setGroup(""); setFilters(noFilters); setSort(newest); }}>{t.mobilized}</button>}
        </div>
        <select className="input" value={group} onChange={(e) => setGroup(e.target.value)}>
          <option value="">{tab === "checkins" ? `All ${t.events.toLowerCase()}` : t.chiefs ? "All counties" : "All drives"}</option>
          {groups.map((g) => <option key={g.id} value={g.id}>{g.name}</option>)}
        </select>
        <SearchInput label={tab === "checkins" ? "Search name, ID or phone" : "Search name or ID number"} value={q} onChange={setQ} />
        {tab === "checkins" && <ParticipantTypeFilter value={participants} onChange={setParticipants} />}
      </div>
      {tab === "checkins" && (
        <div className="toolbar" aria-label="Filter check-ins">
          <FacetSelect label="Sex" value={filters.sex} values={f?.sex} format={sexLabel} onChange={(v) => filter("sex", v)} />
          <FacetSelect label="Age group" value={filters.age_group} values={f?.age_group} onChange={(v) => filter("age_group", v)} />
          <FacetSelect label="County" value={filters.county} values={f?.county} onChange={(v) => filter("county", v)} />
          <FacetSelect label="Constituency" value={filters.constituency} values={f?.constituency} onChange={(v) => filter("constituency", v)} />
          <FacetSelect label="Ward" value={filters.ward} values={f?.ward} onChange={(v) => filter("ward", v)} />
          <FacetSelect label="Region" value={filters.region} values={f?.region} format={regionLabel} onChange={(v) => filter("region", v)} />
          <FacetSelect label="Home county" value={filters.home_county} values={f?.home_county} onChange={(v) => filter("home_county", v)} />
          <FacetSelect label="Polling station" value={filters.station} values={f?.station} onChange={(v) => filter("station", v)} />
          <FacetSelect label="Checked in by" value={filters.by} values={f?.by} onChange={(v) => filter("by", v)} />
          {filtered && <button type="button" className="btn ghost" onClick={() => { setFilters(noFilters); setSort(newest); }}>Clear filters</button>}
          {list.data && <small className="muted" style={{ alignSelf: "center" }}>{list.data.length.toLocaleString()} shown{list.data.length >= 200 ? " (first 200; narrow the filters or export)" : ""}</small>}
        </div>
      )}
      <ErrorNote error={list.error} />
      <Card>
        {!rows ? <Loading /> : rows.length === 0 ? <Empty>No one matches.</Empty> : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>{th("Name", "name")}{t.chiefs && <th>Phone</th>}{tab === "checkins" && <>{th("Sex", "sex")}{th("Age", "age")}</>}{tab === "checkins" && <th>Participant type</th>}{tab === "checkins" && th("County", "county")}{th("Location", "ward")}{tab === "checkins" && th("Polling station", "station")}{th(tab === "checkins" ? t.event : t.drive, "event")}{th("By", "by")}{th("Time", "at")}{tab === "checkins" && th("Region", "region")}</tr>
              </thead>
              <tbody>
                {rows.map((p) => (
                  <tr key={p.id}>
                    <td>
                      <div className="person">
                        <span className={`avatar ${tab === "mobilized" ? "amber" : ""}`}>{initials(p.name)}</span>
                        <div><div style={{ fontWeight: 600 }}>{p.name || "Name not on record"}</div><small className="muted">ID {maskId(p.national_id)}</small></div>
                      </div>
                    </td>
                    {t.chiefs && <td>{p.phone ?? "—"}</td>}
                    {tab === "checkins" && <><td>{p.sex ? sexLabel(p.sex) : "—"}</td><td>{p.age ?? "—"}{p.age_group && p.age_group !== "Unknown" ? <small className="muted"> · {p.age_group}</small> : null}</td></>}
                    {tab === "checkins" && <td>{p.selected_participant ? "Selected" : "General"}</td>}
                    {tab === "checkins" && <td>{p.county || "—"}</td>}
                    <td>{area(p.constituency, p.ward)}</td>
                    {tab === "checkins" && <td>{p.station || "—"}</td>}
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
