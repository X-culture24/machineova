import SearchInput, { matchesSearch } from "../components/SearchInput";
import { useState, type FormEvent } from "react";
import { useNavigate } from "react-router-dom";
import { api, type CoverageLevel } from "../api";
import { isManager, useAuth } from "../auth";
import { Badge, Card, Empty, ErrorNote, Field, Kpi, Loading, Modal, PageHeader, Toggle } from "../components/ui";
import { area, dateTime, num } from "../format";
import { useTerms } from "../terms";
import { useAsync } from "../useAsync";

export default function EventsPage() {
  const { me } = useAuth();
  const t = useTerms();
  const nav = useNavigate();
  const { data, error, loading, reload } = useAsync(() => api.events(), []);
  const [query, setQuery] = useState("");
  const [admission, setAdmission] = useState("");
  const items = (data?.items ?? []).filter((e) =>
    (!admission || e.list_only === (admission === "selected")) && matchesSearch(query, e.name, e.venue, e.county, e.constituency, e.ward),
  );
  const [creating, setCreating] = useState(false);

  return (
    <>
      <PageHeader
        title={t.events}
        subtitle="Every event your organization runs check-in for."
        actions={isManager(me) && <button className="btn" onClick={() => setCreating(true)}>+ New event</button>}
      />
      <ErrorNote error={error} />
      {loading && !data && <Loading />}
      {data && (
        <>
          <div className="grid kpis">
            <Kpi label="Total events" value={num(data.summary.total)} />
            <Kpi label="Active now" value={num(data.summary.active)} tone="teal" />
            <Kpi label="Closed" value={num(data.summary.closed)} />
            <Kpi label={t.chiefs ? "Chiefs present" : "Total check-ins"} value={num(data.summary.checkins)} tone="teal" />
          </div>
          <Card>
            <div className="toolbar">
              <SearchInput label="Search events or areas" value={query} onChange={setQuery} />
              <select className="input" aria-label="Event admission" value={admission} onChange={(e) => setAdmission(e.target.value)}>
                <option value="">All events</option>
                <option value="selected">Selected participants only</option>
                <option value="general">General participants</option>
              </select>
            </div>
            {data.items.length > 0 && items.length === 0 ? <Empty>No events match.</Empty> : items.length === 0 ? (
              <Empty>No events yet{isManager(me) ? " — create the first one." : ". Ask an admin to assign you."}</Empty>
            ) : (
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th>{t.event}</th>
                      <th>Area</th>
                      <th>Starts</th>
                      <th>Admission</th>
                      <th className="num">{t.chiefs ? "Marked present" : "Check-ins"}</th>
                      <th className="num">{t.chiefs ? "Chiefs" : "Unique"}</th>
                      <th>Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    {items.map((e) => (
                      <tr key={e.id} className="clickable" onClick={() => nav(`/events/${e.id}`)}>
                        <td>
                          <div style={{ fontWeight: 600 }}>{e.name}</div>
                          <small className="muted">{e.venue}</small>
                        </td>
                        <td>{area(e.county, e.constituency, e.ward)}</td>
                        <td>{dateTime(e.starts_at)}</td>
                        <td>
                          {e.list_only ? "Selected participants only" : "General participants"}
                          {e.region_restricted && <Badge tone="amber">Region-restricted</Badge>}
                        </td>
                        <td className="num">{num(e.checkins)}</td>
                        <td className="num">{num(e.unique)}</td>
                        <td>{e.active ? <Badge tone="green">Active</Badge> : <Badge>Closed</Badge>}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </Card>
        </>
      )}
      {creating && (
        <NewEventModal
          onClose={() => setCreating(false)}
          onCreated={(id) => {
            setCreating(false);
            reload();
            nav(`/events/${id}`);
          }}
        />
      )}
    </>
  );
}

function NewEventModal({ onClose, onCreated }: { onClose: () => void; onCreated: (id: string) => void }) {
  const [f, setF] = useState({ name: "", venue: "", county: "", constituency: "", ward: "", polling_station_code: "", coverage_level: "national" as CoverageLevel, starts_at: "", region_restricted: false, list_only: false });
  const geography = useAsync(() => api.eventGeography(), []);
  const counties = geography.data?.counties ?? [];
  const county = counties.find((c) => c.name === f.county);
  const constituency = county?.constituencies.find((c) => c.name === f.constituency);
  const ward = constituency?.wards.find((w) => w.name === f.ward);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value });

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    try {
      const ev = await api.createEvent({ ...f, starts_at: new Date(f.starts_at).toISOString() });
      onCreated(ev.id);
    } catch (err) {
      setError((err as Error).message);
      setBusy(false);
    }
  }

  return (
    <Modal title="New event" onClose={onClose}>
      <form onSubmit={submit}>
        <ErrorNote error={error} />
        <div className="form-grid">
          <div className="full"><Field label="Event name"><input required value={f.name} onChange={set("name")} /></Field></div>
          <div className="full"><Field label="Venue"><input value={f.venue} onChange={set("venue")} /></Field></div>
          <ErrorNote error={geography.error} />
          <Field label="Vying level">
            <select value={f.coverage_level} onChange={(e) => setF({ ...f, coverage_level: e.target.value as CoverageLevel })}>
              <option value="national">National</option>
              <option value="county">County</option>
              <option value="constituency">Constituency</option>
              <option value="ward">Ward</option>
            </select>
          </Field>
          <Field label="County">
            <select disabled={geography.loading} required={f.coverage_level !== "national" || f.region_restricted} value={f.county}
              onChange={(e) => setF({ ...f, county: e.target.value, constituency: "", ward: "", polling_station_code: "" })}>
              <option value="">{geography.loading ? "Loading counties…" : "Select county"}</option>
              {counties.map((c) => <option key={c.name}>{c.name}</option>)}
            </select>
          </Field>
          <Field label="Constituency">
            <select disabled={!county} required={["constituency", "ward"].includes(f.coverage_level)} value={f.constituency}
              onChange={(e) => setF({ ...f, constituency: e.target.value, ward: "", polling_station_code: "" })}>
              <option value="">Select constituency</option>
              {county?.constituencies.map((c) => <option key={c.name}>{c.name}</option>)}
            </select>
          </Field>
          <Field label="Ward">
            <select disabled={!constituency} required={f.coverage_level === "ward"} value={f.ward}
              onChange={(e) => setF({ ...f, ward: e.target.value, polling_station_code: "" })}>
              <option value="">Select ward</option>
              {constituency?.wards.map((w) => <option key={w.name}>{w.name}</option>)}
            </select>
          </Field>
          <Field label="Venue polling station">
            <select disabled={!ward} value={f.polling_station_code} onChange={set("polling_station_code")}>
              <option value="">Select station (optional)</option>
              {ward?.stations?.map((s) => <option key={s.code} value={s.code}>{s.name} ({s.code})</option>)}
            </select>
          </Field>
          <Field label="Starts"><input type="datetime-local" required value={f.starts_at} onChange={set("starts_at")} /></Field>
          <div className="full stack">
            <Toggle label="Region-restricted — warn on out-of-region voters" checked={f.region_restricted} onChange={(v) => setF({ ...f, region_restricted: v })} />
            <Field label="Admission">
              <select value={f.list_only ? "participants" : "general"} onChange={(e) => setF({ ...f, list_only: e.target.value === "participants" })}>
                <option value="general">General participants</option>
                <option value="participants">Selected participants only</option>
              </select>
            </Field>
          </div>
        </div>
        <div className="modal-actions">
          <button type="button" className="btn secondary" onClick={onClose}>Cancel</button>
          <button className="btn" disabled={busy}>{busy ? "Creating…" : "Create event"}</button>
        </div>
      </form>
    </Modal>
  );
}
