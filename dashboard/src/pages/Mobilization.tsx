import { useState, type FormEvent } from "react";
import { useNavigate } from "react-router-dom";
import { api } from "../api";
import { isManager, useAuth } from "../auth";
import { Badge, Card, Empty, ErrorNote, Field, Kpi, Loading, Modal, PageHeader, ProgressBar } from "../components/ui";
import { area, num, pct } from "../format";
import { useAsync } from "../useAsync";

export default function MobilizationPage() {
  const { me } = useAuth();
  const nav = useNavigate();
  const { data, error, loading, reload } = useAsync(() => api.drives(), []);
  const [creating, setCreating] = useState(false);
  const s = data?.summary;

  return (
    <>
      <PageHeader
        title="Mobilization"
        subtitle="Voters your field teams register during outreach, by region."
        actions={isManager(me) && <button className="btn amber" onClick={() => setCreating(true)}>+ New drive</button>}
      />
      <ErrorNote error={error} />
      {loading && !data && <Loading />}
      {data && s && (
        <>
          <div className="grid kpis">
            <Kpi label="Active regions" value={num(s.active_regions)} tone="amber" />
            <Kpi label="Voters mobilized" value={num(s.mobilized)} caption={s.target ? `${pct(s.mobilized / s.target)} of ${num(s.target)} target` : undefined}
              progress={s.target ? s.mobilized / s.target : undefined} tone="amber" />
            <Kpi label="Boundary" value={<span style={{ fontSize: 18 }}>{area(s.boundary_county, s.boundary_constituency)}</span>} />
            <Kpi label="Org status" value={s.org_active ? <Badge tone="green">Active</Badge> : <Badge tone="red">Inactive</Badge>} />
          </div>
          <Card>
            {data.items.length === 0 ? (
              <Empty>No mobilization drives yet.</Empty>
            ) : (
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr><th>Region / drive</th><th>Area</th><th className="num">Target</th><th className="num">Mobilized</th><th className="num">Remaining</th><th style={{ width: 200 }}>Progress</th><th>Status</th></tr>
                  </thead>
                  <tbody>
                    {data.items.map((d) => (
                      <tr key={d.id} className="clickable" onClick={() => nav(`/mobilization/${d.id}`)}>
                        <td style={{ fontWeight: 600 }}>{d.name}</td>
                        <td>{area(d.county, d.constituency, d.ward)}</td>
                        <td className="num">{num(d.target)}</td>
                        <td className="num">{num(d.mobilized)}</td>
                        <td className="num">{num(d.remaining)}</td>
                        <td><div className="row gap"><div style={{ flex: 1 }}><ProgressBar value={d.progress} tone="amber" /></div><small>{pct(d.progress)}</small></div></td>
                        <td>{d.active ? <Badge tone="green">Active</Badge> : <Badge>Closed</Badge>}</td>
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
        <NewDriveModal onClose={() => setCreating(false)} onCreated={(id) => { setCreating(false); reload(); nav(`/mobilization/${id}`); }} />
      )}
    </>
  );
}

function NewDriveModal({ onClose, onCreated }: { onClose: () => void; onCreated: (id: string) => void }) {
  const [f, setF] = useState({ name: "", county: "", constituency: "", ward: "", target: "", target_date: "" });
  const [error, setError] = useState<string | null>(null);
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value });

  async function submit(e: FormEvent) {
    e.preventDefault();
    try {
      const d = await api.createDrive({ ...f, target: Number(f.target) || 0, target_date: f.target_date || null });
      onCreated(d.id);
    } catch (err) {
      setError((err as Error).message);
    }
  }

  return (
    <Modal title="New mobilization drive" onClose={onClose}>
      <form onSubmit={submit}>
        <ErrorNote error={error} />
        <div className="form-grid">
          <div className="full"><Field label="Drive / region name"><input required value={f.name} onChange={set("name")} /></Field></div>
          <Field label="County"><input value={f.county} onChange={set("county")} /></Field>
          <Field label="Constituency"><input value={f.constituency} onChange={set("constituency")} /></Field>
          <div className="full"><Field label="Ward"><input value={f.ward} onChange={set("ward")} /></Field></div>
          <Field label="Target voters"><input type="number" min={0} value={f.target} onChange={set("target")} /></Field>
          <Field label="Target date"><input type="date" value={f.target_date} onChange={set("target_date")} /></Field>
        </div>
        <div className="modal-actions">
          <button type="button" className="btn secondary" onClick={onClose}>Cancel</button>
          <button className="btn amber">Create drive</button>
        </div>
      </form>
    </Modal>
  );
}
