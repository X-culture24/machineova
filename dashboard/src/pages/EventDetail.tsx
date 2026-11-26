import SearchInput, { matchesSearch } from "../components/SearchInput";
import ParticipantTypeFilter from "../components/ParticipantFilter";
import { useEffect, useState } from "react";
import { Link, useParams, useSearchParams } from "react-router-dom";
import { api, type CoverageLevel, type ParticipantFilter } from "../api";
import { isManager, useAuth } from "../auth";
import { AssignModal } from "../components/AssignModal";
import { Badge, BarChart, Card, Empty, ErrorNote, focusSection, Kpi, Loading, Modal, PageHeader, RegionBadge, Toggle } from "../components/ui";
import { area, dateTime, hourLabel, num, pct, time } from "../format";
import { useAsync, useDebounced } from "../useAsync";
import { maskId } from "../mask";
import { useTerms } from "../terms";
import CoveragePanel from "../components/Coverage";
import EventStationCoverage from "../components/EventStationCoverage";
import AttendanceExport from "../components/AttendanceExport";
import { SortTh, useSort } from "../components/TableTools";

export default function EventDetail() {
  const { id = "" } = useParams();
  const [params, setParams] = useSearchParams();
  const section: "attendance" | "stations" =
    params.get("section") === "stations" || params.get("view") === "stations" ? "stations" : "attendance";
  const selectSection = (next: "attendance" | "stations") => {
    setParams((current) => {
      const updated = new URLSearchParams(current);
      updated.delete("view");
      if (next === "stations") updated.set("section", "stations");
      else updated.delete("section");
      return updated;
    });
  };
  const { me } = useAuth();
  const t = useTerms();
  const manager = isManager(me);
  const detail = useAsync(() => api.event(id), [id]);
  const insights = useAsync(() => api.checkinInsights(id), [id]);
  const [query, setQuery] = useState("");
  const search = useDebounced(query);
  const [participants, setParticipants] = useState<ParticipantFilter>("");
  const order = useSort({ key: "at", dir: "desc" });
  const list = useAsync(() => api.checkins({ event_id: id, q: search, participants, ...order.params }),
    [id, search, participants, order.sort?.key, order.sort?.dir]);
  const th = (label: string, key: string) => <SortTh label={label} sortKey={key} sort={order.sort} onSort={order.toggle} />;
  const [coverageVersion, refreshCoverage] = useState(0);
  const [modal, setModal] = useState<"assign" | "participants" | null>(null);
  const [actionErr, setActionErr] = useState<string | null>(null);

  const loadedId = detail.data?.event.id;
  const [attendanceTarget, setAttendanceTarget] = useState("");
  const openAttendance = (target: string) => {
    if (section === "attendance") focusSection(target);
    else {
      setAttendanceTarget(target);
      selectSection("attendance");
    }
  };
  useEffect(() => {
    if (loadedId !== id) return;
    if (section === "stations") focusSection("polling-stations", "instant");
    if (section === "attendance" && attendanceTarget) {
      focusSection(attendanceTarget);
      setAttendanceTarget("");
    }
  }, [id, loadedId, section, attendanceTarget]);

  if (detail.error) return <ErrorNote error={detail.error} />;
  if (!detail.data || loadedId !== id) return <Loading />;
  const { event: e, assigned_users } = detail.data;
  const reloadAll = () => {
    detail.reload();
    insights.reload();
    list.reload();
    refreshCoverage((v) => v + 1);
  };
  const update = async (body: Parameters<typeof api.updateEvent>[1]) => {
    try {
      setActionErr(null);
      await api.updateEvent(e.id, body);
      detail.reload();
      if (body.coverage_level) refreshCoverage((v) => v + 1);
    } catch (err) {
      setActionErr((err as Error).message);
    }
  };
  const ins = insights.data;

  return (
    <>
      <PageHeader
        title={e.name}
        subtitle={`${area(e.venue, e.polling_station_code, e.county, e.constituency, e.ward)} · ${dateTime(e.starts_at)}`}
        actions={
          <>
            {e.region_restricted && <Badge tone="amber">Region-restricted</Badge>}
            <Badge tone={e.list_only ? "blue" : "grey"}>{e.list_only ? "Selected participants only" : "General participants"}</Badge>
            {e.active ? <Badge tone="green">Active</Badge> : <Badge>Closed</Badge>}
            {e.active && me?.role !== "viewer" && <Link className="btn" to={`/checkin?event=${e.id}`}>{t.checkInPeople}</Link>}
            <button className="btn secondary" onClick={() => {
              if (section === "stations") focusSection("polling-stations");
              else selectSection("stations");
            }}>Polling-station turnout</button>
            {me?.role !== "viewer" && <Link className="btn secondary" to={`/issues?event=${e.id}`}>Report a problem</Link>}
            <button className="btn secondary" onClick={reloadAll}>Refresh</button>
          </>
        }
      />
      <ErrorNote error={actionErr} />
      <div className="grid kpis">
        <Kpi label="Check-ins" value={num(e.checkins)} caption="View attendance records" tone="teal"
          onClick={() => openAttendance("event-attendance")} />
        <Kpi label="Unique members" value={num(e.unique)} caption="View attendance breakdown" tone="teal"
          onClick={() => openAttendance("event-insights")} />
        <Kpi
          label="Out of region"
          value={num(e.out_of_region)}
          caption={e.checkins ? `${pct(e.out_of_region / e.checkins)} of check-ins` : "—"}
          tone="amber"
          onClick={() => openAttendance("event-insights")}
        />
        <Kpi label="Peak hour" value={ins?.peak_hour != null ? hourLabel(ins.peak_hour) : "—"} caption="View hourly arrivals"
          onClick={() => openAttendance("hourly-arrivals")} />
      </div>

      <div className="tabs event-detail-tabs" role="tablist" aria-label="Event details">
        <button type="button" role="tab" aria-selected={section === "attendance"} className={section === "attendance" ? "on" : ""}
          onClick={() => selectSection("attendance")}>Attendance &amp; insights</button>
        <button type="button" role="tab" aria-selected={section === "stations"} className={section === "stations" ? "on" : ""}
          onClick={() => selectSection("stations")}>
          Polling stations · {e.coverage_level === "national" ? "National" : area(e.county, e.constituency, e.ward)}
        </button>
      </div>
      {section === "stations" ? (
        <div id="polling-stations" className="insight-target stack" tabIndex={-1}>
          <EventStationCoverage key={`stations-${id}-${coverageVersion}`} eventId={e.id} />
          <CoveragePanel key={`coverage-${id}-${coverageVersion}`} group={{ event_id: e.id }} />
        </div>
      ) : <>
      <CoveragePanel key={`coverage-${id}-${coverageVersion}`} group={{ event_id: e.id }}
        onShowStations={() => selectSection("stations")} />

      <div className="grid cols-2" style={{ marginBottom: 16 }}>
        <div id="hourly-arrivals" className="insight-target" tabIndex={-1}>
          <Card title="Check-ins by hour" extra={ins && <small className="muted">{ins.day}</small>}>
            {ins ? (
              <BarChart
                data={ins.by_hour.map((h) => ({ label: hourLabel(h.hour), value: h.count }))}
                highlight={ins.by_hour.findIndex((h) => h.hour === ins.peak_hour)}
              />
            ) : insights.error ? <ErrorNote error={insights.error} /> : <Loading />}
          </Card>
        </div>
        <div id="event-insights" className="insight-target" tabIndex={-1}>
          <Card title="Attendance breakdown">
            <ErrorNote error={insights.error} />
            <div className="stack">
              <div className="row spread"><span>Unique members</span><strong>{num(e.unique)}</strong></div>
              <div className="row spread"><span>Repeat check-ins</span><strong>{num(Math.max(0, e.checkins - e.unique))}</strong></div>
              <div className="row spread"><span>In-region check-ins</span><strong>{num(e.checkins - e.out_of_region)}</strong></div>
              <div className="row spread"><span>Out-of-region check-ins</span><strong>{num(e.out_of_region)}{e.checkins > 0 ? ` · ${pct(e.out_of_region / e.checkins)}` : ""}</strong></div>
            </div>
            {ins && ins.total > 0 ? (
              <div className="stack">
                <div className="row spread"><span>In-region rate</span><strong>{pct(ins.in_region_rate)}</strong></div>
                <div className="row spread"><span>Female · Male</span><strong>{num(ins.female)} · {num(ins.male)}</strong></div>
                <div className="split" aria-label="Gender mix">
                  <div style={{ width: `${(ins.female / ins.total) * 100}%` }} />
                  <div style={{ flex: 1 }} />
                </div>
                <small className="muted">Teal = female, amber = male</small>
              </div>
            ) : (
              <Empty>No check-ins on this day yet.</Empty>
            )}
          </Card>
        </div>
      </div>

      <div className="grid cols-2" style={{ marginBottom: 16 }}>
        <Card
          title={`Assigned operators · ${assigned_users.length}`}
          extra={manager && <button className="btn small secondary" onClick={() => setModal("assign")}>Assign</button>}
        >
          {assigned_users.length === 0 ? (
            <Empty>Nobody is assigned. Members can only check in to events they're assigned to.</Empty>
          ) : (
            <div className="stack">
              {assigned_users.map((u) => (
                <div key={u.id} className="row spread">
                  <span>{u.name}</span>
                  <small className="muted">{u.phone ?? u.email}</small>
                </div>
              ))}
            </div>
          )}
        </Card>
        <Card title="Event rules">
          <div className="stack">
            <Toggle label="Region-restricted" checked={e.region_restricted} disabled={!manager} onChange={(v) => manager && update({ region_restricted: v })} />
            <label className="field">
              <span>Admission</span>
              <select disabled={!manager} value={e.list_only ? "participants" : "general"}
                onChange={(v) => void update({ list_only: v.target.value === "participants" })}>
                <option value="general">General participants</option>
                <option value="participants">Selected participants only</option>
              </select>
            </label>
            <label className="field">
              <span>Vying level</span>
              <select disabled={!manager} value={e.coverage_level ?? (e.ward ? "ward" : e.constituency ? "constituency" : e.county ? "county" : "national")}
                onChange={(v) => void update({ coverage_level: v.target.value as CoverageLevel })}>
                <option value="national">National</option>
                <option value="county" disabled={!e.county}>County</option>
                <option value="constituency" disabled={!e.county || !e.constituency}>Constituency</option>
                <option value="ward" disabled={!e.county || !e.constituency || !e.ward}>Ward</option>
              </select>
            </label>
            <div className="row spread">
              <span>{num(e.participants)} selected participants on the event list</span>
              {manager && <button className="btn small secondary" onClick={() => setModal("participants")}>Manage list</button>}
            </div>
            {manager && (
              <button className={`btn ${e.active ? "danger" : ""}`} onClick={() => update({ active: !e.active })}>
                {e.active ? "Close event" : "Reopen event"}
              </button>
            )}
          </div>
        </Card>
      </div>

      <div id="event-attendance" className="insight-target" tabIndex={-1}>
        <Card title="Who checked in" extra={manager && <AttendanceExport key={id} eventId={id} eventName={e.name} query={query} participants={participants} />}>
          <div className="toolbar">
            <SearchInput label="Search name, ID or phone" value={query} onChange={setQuery} />
            <ParticipantTypeFilter value={participants} onChange={setParticipants} />
          </div>
          <ErrorNote error={list.error} />
          {list.loading ? (
            <Loading />
          ) : !list.data?.length ? (
            <Empty>No matching check-ins.</Empty>
          ) : (
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>{th("Name", "name")}<th>ID number</th><th>Phone</th><th>Participant type</th>{th("Location", "ward")}{th("By", "by")}{th("Time", "at")}{th("Region", "region")}</tr>
                </thead>
                <tbody>
                  {list.data.map((c) => (
                    <tr key={c.id}>
                      <td>{c.name}</td>
                      <td className="id-masked">{maskId(c.national_id)}</td>
                      <td>{c.phone ?? "—"}</td>
                      <td>{c.selected_participant ? "Selected" : "General"}</td>
                      <td>{area(c.constituency, c.ward)}</td>
                      <td>{c.by}</td>
                      <td>{time(c.at)}</td>
                      <td><RegionBadge inRegion={c.in_region ?? true} /></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      </div>
      </>}

      {modal === "assign" && (
        <AssignModal
          title="Assign operators"
          current={assigned_users}
          save={(ids) => api.setEventAssignments(e.id, ids)}
          onClose={() => setModal(null)}
          onSaved={() => {
            setModal(null);
            detail.reload();
          }}
        />
      )}
      {modal === "participants" && (
        <ParticipantsModal
          eventId={e.id}
          onClose={() => setModal(null)}
          onSaved={() => {
            setModal(null);
            detail.reload();
            list.reload();
          }}
        />
      )}
    </>
  );
}

function ParticipantsModal({ eventId, onClose, onSaved }: { eventId: string; onClose: () => void; onSaved: () => void }) {
  const roster = useAsync(() => api.eventParticipants(eventId), [eventId]);
  const [draft, setText] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [busy, setBusy] = useState(false);
  const text = draft ?? roster.data?.join("\n") ?? "";
  const [error, setError] = useState<string | null>(null);
  const ids = text.split(/[\n,;\t]+/).map((s) => s.replace(/\s+/g, "")).filter(Boolean);

  const matches = ids.filter((id) => matchesSearch(query, id));

  async function save() {
    setBusy(true);
    setError(null);
    try {
      await api.setEventParticipants(eventId, ids);
      onSaved();
    } catch (err) {
      setError((err as Error).message);
      setBusy(false);
    }
  }

  return (
    <Modal title="Selected participant list" onClose={onClose}>
      <ErrorNote error={error ?? roster.error} />
      <p className="muted" style={{ marginTop: 0 }}>
        Paste ID numbers (one per line or comma-separated) or choose a CSV. This replaces the current list.
      </p>
      {roster.loading && <Loading />}
      <input type="file" accept=".csv,.txt" disabled={!roster.data || busy}
        onChange={(e) => { const file = e.target.files?.[0]; if (file) void file.text().then(setText, (err: Error) => setError(err.message)); }} />
      <textarea className="input" rows={8} style={{ marginTop: 10 }} value={text} disabled={!roster.data || busy} onChange={(e) => setText(e.target.value)} />
      <SearchInput label="Search participant IDs" value={query} onChange={setQuery} />
      {query.trim() && <p className="muted">{matches.length ? matches.slice(0, 20).join(", ") + (matches.length > 20 ? ` and ${matches.length - 20} more` : "") : "No IDs match."}</p>}
      <div className="modal-actions">
        <span className="muted" style={{ marginRight: "auto" }}>{ids.length} IDs</span>
        <button className="btn secondary" onClick={onClose}>Cancel</button>
        <button
          className="btn"
          disabled={!roster.data || draft === null || busy}
          onClick={() => void save()}
        >
          Save list
        </button>
      </div>
    </Modal>
  );
}
