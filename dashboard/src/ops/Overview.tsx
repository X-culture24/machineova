import { useState } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "../auth";
import { Card, Empty, ErrorNote, Kpi, Loading } from "../components/ui";
import { num, pct, time } from "../format";
import { useAsync } from "../useAsync";
import { ops, type AttentionItem } from "./api";
import { NoElection, OpsHeader, TrendChart } from "./components";
import { StationDrawer, type DrawerAction } from "./StationDrawer";

const actionFor: Record<AttentionItem["kind"], DrawerAction | null> = { issue: null, uncovered: "assign", verify: "results" };
const dotFor: Record<AttentionItem["kind"], string> = { issue: "red", uncovered: "amber", verify: "blue" };

export default function OpsOverview() {
  const { me } = useAuth();
  const { data, error, reload } = useAsync(ops.overview, []);
  const [open, setOpen] = useState<{ code: string; action: DrawerAction | null } | null>(null);

  if (error && (error.includes("No active election"))) {
    return (
      <>
        <OpsHeader title="Overview" />
        <NoElection canSetup={me?.role === "owner" || me?.role === "admin"} />
      </>
    );
  }
  const ward = data?.scope.ward;
  return (
    <>
      <OpsHeader
        title="Overview"
        subtitle={data ? `What needs you now in ${data.scope_label}` : undefined}
        election={data?.election}
        scopeLabel={data?.scope_label}
        actions={<button className="btn secondary small" onClick={reload}>Refresh</button>}
      />
      <ErrorNote error={error} />
      {!data ? (
        <Loading />
      ) : (
        <>
          {ward && (
            <div className="grid quick-links">
              <Link className="quick-link" to="/ops/stations"><strong>My stations</strong><small className="muted">{data.stations} stations in {data.scope_label}</small></Link>
              <Link className="quick-link" to="/ops/stations?status=issue"><strong>Needs attention</strong><small className="muted">{data.attention.length} to clear</small></Link>
              <Link className="quick-link" to="/ops/people?role=agent"><strong>My agents</strong><small className="muted">{data.agents} agents · tap to call</small></Link>
            </div>
          )}
          <div className="grid kpis">
            <Kpi label="Reporting progress" value={pct(data.stations ? data.reported / data.stations : 0)}
              caption={`${data.reported} of ${data.stations} stations reported`} progress={data.stations ? data.reported / data.stations : 0} tone="teal" />
            <Kpi label="Stations open" value={num(data.open)} caption={`${data.stations} total · ${data.closed} closed`} />
            <Kpi label="Turnout so far" value={pct(data.turnout)} caption={`${num(data.cast)} of ${num(data.registered)} registered`}
              progress={data.turnout} tone="teal" />
            <Kpi label="Needs attention" value={num(data.attention.length)}
              caption={`${data.issues} issues · ${data.uncovered} uncovered · ${data.to_verify} to verify`} tone="amber" />
          </div>
          <div className="grid cols-2">
            <Card title={`Turnout trend — ${data.scope_label}`} extra={data.last_update && <small className="muted">Last updated {time(data.last_update)}</small>}>
              {data.trend.every((p) => p.cast === 0) ? <Empty>No turnout recorded yet.</Empty> : <TrendChart points={data.trend} slots={[6, 9, 11, 13, 15, 17]} />}
            </Card>
            <Card title="Needs attention now" extra={<span className="badge red">{data.attention.length}</span>}>
              {data.attention.length === 0 ? (
                <Empty>All clear — every station is covered and nothing is flagged.</Empty>
              ) : (
                <div className="attention-list">
                  {data.attention.slice(0, 8).map((a) => (
                    <div key={a.kind + a.code} className="attention-row">
                      <span className={`dot ${dotFor[a.kind]}`} />
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div style={{ fontWeight: 600 }}>{a.name}</div>
                        <small className="muted">{a.area}</small>
                      </div>
                      <span className={`reason ${dotFor[a.kind]}`}>{a.reason}</span>
                      <button className="btn small secondary" onClick={() => setOpen({ code: a.code, action: actionFor[a.kind] })}>{a.action}</button>
                    </div>
                  ))}
                  {data.attention.length > 8 && (
                    <Link className="attention-more" to="/ops/stations">View all {data.attention.length} in Polling stations ›</Link>
                  )}
                </div>
              )}
            </Card>
          </div>
        </>
      )}
      {open && (
        <StationDrawer code={open.code} initialAction={open.action} onClose={() => setOpen(null)} onChanged={reload} />
      )}
    </>
  );
}

