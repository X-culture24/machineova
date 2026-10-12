import { useState, type FormEvent } from "react";
import { useNavigate } from "react-router-dom";
import { api } from "../api";
import { isManager, useAuth } from "../auth";
import { Badge, Card, Empty, ErrorNote, Field, Kpi, Loading, Modal, PageHeader, Toggle } from "../components/ui";
import { area, dateTime, num } from "../format";
import { useAsync } from "../useAsync";

export default function EventsPage() {
  const { me } = useAuth();
  const nav = useNavigate();
  const { data, error, loading, reload } = useAsync(() => api.events(), []);
  const [creating, setCreating] = useState(false);

  return (
    <>
      <PageHeader
        title="Events"
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
            <Kpi label="Total check-ins" value={num(data.summary.checkins)} tone="teal" />
          </div>
          <Card>
            {data.items.length === 0 ? (
              <Empty>No events yet{isManager(me) ? " — create the first one." : ". Ask an admin to assign you."}</Empty>
            ) : (
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th>Event</th>
                      <th>Area</th>
                      <th>Starts</th>
                      <th>Rules</th>
                      <th className="num">Check-ins</th>
                      <th className="num">Unique</th>
                      <th>Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.items.map((e) => (
                      <tr key={e.id} className="clickable" onClick={() => nav(`/events/${e.id}`)}>
                        <td>
                          <div style={{ fontWeight: 600 }}>{e.name}</div>
                          <small className="muted">{e.venue}</small>
                        </td>
                        <td>{area(e.county, e.constituency, e.ward)}</td>
                        <td>{dateTime(e.starts_at)}</td>
                        <td className="row gap">
                          {e.region_restricted && <Badge tone="amber">Region-restricted</Badge>}
                          {e.list_only && <Badge tone="blue">List-only</Badge>}
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
  const [f, setF] = useState({ name: "", venue: "", county: "", constituency: "", ward: "", starts_at: "", region_restricted: false, list_only: false });
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
          <Field label="County"><input value={f.county} onChange={set("county")} /></Field>
          <Field label="Constituency"><input value={f.constituency} onChange={set("constituency")} /></Field>
          <Field label="Ward" hint="Leave area fields blank for no restriction."><input value={f.ward} onChange={set("ward")} /></Field>
          <Field label="Starts"><input type="datetime-local" required value={f.starts_at} onChange={set("starts_at")} /></Field>
          <div className="full stack">
            <Toggle label="Region-restricted — warn on out-of-region voters" checked={f.region_restricted} onChange={(v) => setF({ ...f, region_restricted: v })} />
            <Toggle label="List-only — only approved participant IDs can check in" checked={f.list_only} onChange={(v) => setF({ ...f, list_only: v })} />
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
