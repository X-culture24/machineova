import { useState } from "react";
import { Link, useParams } from "react-router-dom";
import { api, type CoverageLevel } from "../api";
import { isManager, useAuth } from "../auth";
import { AssignModal } from "../components/AssignModal";
import { Badge, BarChart, Card, Empty, ErrorNote, Kpi, Loading, Modal, PageHeader, RegionBadge, Toggle } from "../components/ui";
import { area, dateTime, hourLabel, num, pct, time } from "../format";
import { useAsync, useDebounced } from "../useAsync";
import { maskId } from "../mask";
import { useTerms } from "../terms";
import CoveragePanel from "../components/Coverage";
import EventStationCoverage from "../components/EventStationCoverage";
import AttendanceExport from "../components/AttendanceExport";

export default function EventDetail() {
  const { id = "" } = useParams();
  const { me } = useAuth();
  const t = useTerms();
  const manager = isManager(me);
  const detail = useAsync(() => api.event(id), [id]);
  const insights = useAsync(() => api.checkinInsights(id), [id]);
  const [query, setQuery] = useState("");
  const search = useDebounced(query);
  const list = useAsync(() => api.checkins({ event_id: id, q: search }), [id, search]);
  const [coverageVersion, refreshCoverage] = useState(0);
  const [modal, setModal] = useState<"assign" | "participants" | null>(null);
  const [actionErr, setActionErr] = useState<string | null>(null);

  if (detail.error) return <ErrorNote error={detail.error} />;
  if (!detail.data) return <Loading />;
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
            {e.list_only && <Badge tone="blue">Participants only</Badge>}
            {e.active ? <Badge tone="green">Active</Badge> : <Badge>Closed</Badge>}
            {e.active && me?.role !== "viewer" && <Link className="btn" to={`/checkin?event=${e.id}`}>{t.checkInPeople}</Link>}
            <button className="btn secondary" onClick={reloadAll}>Refresh</button>
          </>
        }
      />
      <ErrorNote error={actionErr} />
      <div className="grid kpis">
        <Kpi label={t.checkins} value={num(e.checkins)} caption="all visits, every day" tone="teal" />
        <Kpi label="Unique" value={num(e.unique)} caption="different people" tone="teal" />
        <Kpi
          label="Out of region"
          value={num(e.out_of_region)}
          caption={e.checkins ? `${pct(e.out_of_region / e.checkins)} of check-ins` : "—"}
          tone="amber"
        />
        <Kpi label="Peak hour" value={ins?.peak_hour != null ? hourLabel(ins.peak_hour) : "—"} caption={ins ? `on ${ins.day}` : undefined} />
      </div>

      <div className="grid cols-2" style={{ marginBottom: 16 }}>
        <Card title="Check-ins by hour" extra={ins && <small className="muted">{ins.day}</small>}>
          {ins ? (
            <BarChart
              data={ins.by_hour.map((h) => ({ label: hourLabel(h.hour), value: h.count }))}
              highlight={ins.by_hour.findIndex((h) => h.hour === ins.peak_hour)}
            />
          ) : (
            <Loading />
          )}
        </Card>
        <Card title="Check-in mix">
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
            <Toggle label="Region-restricted" checked={e.region_restricted} onChange={(v) => manager && update({ region_restricted: v })} />
            <label className="field">
              <span>Admission</span>
              <select disabled={!manager} value={e.list_only ? "participants" : "general"}
                onChange={(v) => void update({ list_only: v.target.value === "participants" })}>
                <option value="general">General meeting</option>
                <option value="participants">Participants only</option>
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
            {e.list_only && (
              <div className="row spread">
                <span>{num(e.participants)} approved participants</span>
                {manager && <button className="btn small secondary" onClick={() => setModal("participants")}>Upload list</button>}
              </div>
            )}
            {manager && (
              <button className={`btn ${e.active ? "danger" : ""}`} onClick={() => update({ active: !e.active })}>
                {e.active ? "Close event" : "Reopen event"}
              </button>
            )}
          </div>
        </Card>
      </div>

      <CoveragePanel key={`coverage-${id}-${coverageVersion}`} group={{ event_id: e.id }} />
      <EventStationCoverage key={`stations-${id}-${coverageVersion}`} eventId={e.id} />
      <Card title="Who checked in" extra={manager && <AttendanceExport key={id} eventId={id} query={query} />}>
        <div className="toolbar">
          <input className="input" aria-label="Search check-ins" placeholder="Search name, ID or phone…" value={query}
            onChange={(e) => setQuery(e.target.value)} />
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
                <tr><th>Name</th><th>ID number</th><th>Phone</th><th>Location</th><th>By</th><th>Time</th><th>Region</th></tr>
              </thead>
              <tbody>
                {list.data.map((c) => (
                  <tr key={c.id}>
                    <td>{c.name}</td>
                    <td className="id-masked">{maskId(c.national_id)}</td>
                    <td>{c.phone ?? "—"}</td>
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
          }}
        />
      )}
    </>
  );
}

function ParticipantsModal({ eventId, onClose, onSaved }: { eventId: string; onClose: () => void; onSaved: () => void }) {
  const [text, setText] = useState("");
  const [error, setError] = useState<string | null>(null);
  const ids = text.split(/[\n,;\t]+/).map((s) => s.replace(/\s+/g, "")).filter(Boolean);

  async function readFile(file: File) {
    setText(await file.text());
  }

  return (
    <Modal title="Participant list" onClose={onClose}>
      <ErrorNote error={error} />
      <p className="muted" style={{ marginTop: 0 }}>
        Paste ID numbers (one per line or comma-separated) or choose a CSV. This replaces the current list.
      </p>
      <input type="file" accept=".csv,.txt" onChange={(e) => e.target.files?.[0] && readFile(e.target.files[0])} />
      <textarea className="input" rows={8} style={{ marginTop: 10 }} value={text} onChange={(e) => setText(e.target.value)} />
      <div className="modal-actions">
        <span className="muted" style={{ marginRight: "auto" }}>{ids.length} IDs</span>
        <button className="btn secondary" onClick={onClose}>Cancel</button>
        <button
          className="btn"
          onClick={() => api.setEventParticipants(eventId, ids).then(onSaved, (e: Error) => setError(e.message))}
        >
          Save list
        </button>
      </div>
    </Modal>
  );
}
