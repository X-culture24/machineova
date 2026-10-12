import { useState } from "react";
import { useParams } from "react-router-dom";
import { api, type Pace } from "../api";
import { isManager, useAuth } from "../auth";
import { AssignModal } from "../components/AssignModal";
import { Badge, BarChart, Card, Empty, ErrorNote, Field, Kpi, Loading, PageHeader, RankList } from "../components/ui";
import { area, dateTime, num, pct } from "../format";
import { useAsync } from "../useAsync";

const paceLabel: Record<Pace["status"], [string, "green" | "teal" | "red" | "blue"]> = {
  ahead: ["Ahead of target", "green"],
  on_track: ["On track", "teal"],
  behind: ["Behind pace", "red"],
  reached: ["Target reached", "blue"],
};

export default function DriveDetail() {
  const { id = "" } = useParams();
  const { me } = useAuth();
  const manager = isManager(me);
  const detail = useAsync(() => api.drive(id), [id]);
  const ins = useAsync(() => api.mobilizationInsights(id), [id]);
  const list = useAsync(() => api.mobilizations({ drive_id: id }), [id]);
  const [assigning, setAssigning] = useState(false);
  const [target, setTarget] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);

  if (detail.error) return <ErrorNote error={detail.error} />;
  if (!detail.data) return <Loading />;
  const { drive: d, assigned_users } = detail.data;
  const m = ins.data;
  const update = async (body: Parameters<typeof api.updateDrive>[1]) => {
    try {
      setErr(null);
      await api.updateDrive(d.id, body);
      detail.reload();
      ins.reload();
    } catch (e) {
      setErr((e as Error).message);
    }
  };

  return (
    <>
      <PageHeader
        title={d.name}
        subtitle={area(d.county, d.constituency, d.ward)}
        actions={
          <>
            {m?.pace && <Badge tone={paceLabel[m.pace.status][1]}>{paceLabel[m.pace.status][0]}</Badge>}
            {d.active ? <Badge tone="green">Active</Badge> : <Badge>Closed</Badge>}
            {manager && <button className="btn secondary" onClick={() => update({ active: !d.active })}>{d.active ? "Close drive" : "Reopen"}</button>}
          </>
        }
      />
      <ErrorNote error={err} />
      <div className="grid kpis">
        <Kpi label="Voters mobilized" value={num(d.mobilized)} tone="amber" />
        <Kpi label="Of target" value={d.target ? pct(d.progress) : "—"} caption={`target ${num(d.target)}`} progress={d.progress} tone="amber" />
        <Kpi label="Remaining" value={num(d.remaining)} />
        <Kpi label="Mobilized today" value={m ? num(m.today) : "—"} tone="amber" />
      </div>
      <div className="grid cols-2" style={{ marginBottom: 16 }}>
        <Card title="Momentum · last 14 days" extra={m?.pace && <small className="muted">{m.pace.momentum}</small>}>
          {m ? <BarChart tone="amber" data={m.daily.map((x) => ({ label: x.day.slice(5), value: x.count }))} /> : <Loading />}
        </Card>
        <Card title="Pace">
          {!m ? <Loading /> : !m.pace ? <Empty>Set a target to track pace.</Empty> : (
            <div className="stack">
              <div className="row spread"><span>Days left</span><strong>{d.target_date ? num(m.pace.days_left) : "No target date"}</strong></div>
              <div className="row spread"><span>To hit target</span><strong>{num(m.pace.to_hit_target)}</strong></div>
              <div className="row spread"><span>Pace needed</span><strong>{num(m.pace.pace_needed)} / day</strong></div>
              <div className="row spread"><span>Current pace (7-day)</span><strong>{num(m.pace.current_pace)} / day</strong></div>
            </div>
          )}
          {manager && (
            <form className="row gap" style={{ marginTop: 16, alignItems: "flex-end" }}
              onSubmit={(e) => { e.preventDefault(); if (target !== null) update({ target: Number(target) }).then(() => setTarget(null)); }}>
              <Field label="Target voters"><input type="number" min={0} value={target ?? d.target} onChange={(e) => setTarget(e.target.value)} /></Field>
              <button className="btn amber small" disabled={target === null}>Save</button>
            </form>
          )}
        </Card>
      </div>
      <div className="grid cols-2" style={{ marginBottom: 16 }}>
        <Card title="Top mobilizers">{m ? <RankList tone="amber" items={m.top_mobilizers} /> : <Loading />}</Card>
        <Card title={`Assigned mobilizers · ${assigned_users.length}`} extra={manager && <button className="btn small secondary" onClick={() => setAssigning(true)}>Assign</button>}>
          {assigned_users.length === 0 ? <Empty>Nobody assigned yet.</Empty> : (
            <div className="stack">{assigned_users.map((u) => <div key={u.id} className="row spread"><span>{u.name}</span><small className="muted">{u.phone ?? u.email}</small></div>)}</div>
          )}
        </Card>
      </div>
      <Card title="Registered voters">
        {!list.data ? <Loading /> : list.data.length === 0 ? <Empty>No voters registered yet.</Empty> : (
          <div className="table-wrap">
            <table>
              <thead><tr><th>Name</th><th>ID number</th><th>Phone</th><th>Location</th><th>Mobilized by</th><th>When</th></tr></thead>
              <tbody>
                {list.data.map((p) => (
                  <tr key={p.id}><td>{p.name}</td><td>{p.national_id}</td><td>{p.phone ?? "—"}</td><td>{area(p.constituency, p.ward)}</td><td>{p.by}</td><td>{dateTime(p.at)}</td></tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
      {assigning && (
        <AssignModal title="Assign mobilizers" current={assigned_users} save={(ids) => api.setDriveAssignments(d.id, ids)}
          onClose={() => setAssigning(false)} onSaved={() => { setAssigning(false); detail.reload(); }} />
      )}
    </>
  );
}
