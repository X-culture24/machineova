import { useState } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "../auth";
import { Badge, Card, Empty, ErrorNote, Kpi, Loading, ProgressBar } from "../components/ui";
import { num, pct, time } from "../format";
import { useAsync } from "../useAsync";
import { ops, pp, regionLabel, type AttentionItem, type SeatHistory } from "./api";
import { NoElection, OpsHeader, TrendChart } from "./components";
import { StationDrawer, type DrawerAction } from "./StationDrawer";

const actionFor: Record<AttentionItem["kind"], DrawerAction | null> = { issue: null, uncovered: "assign", verify: "results" };
const dotFor: Record<AttentionItem["kind"], string> = { issue: "red", uncovered: "amber", verify: "blue" };

export default function OpsOverview() {
  const { me } = useAuth();
  const { data, error, reload } = useAsync(ops.overview, []);
  const seats = useAsync(ops.seatHistory, []);
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
              <Link className="quick-link" to="/ops/stations"><strong>My stations</strong><small className="muted">{num(data.stations)} stations in {data.scope_label}</small></Link>
              <Link className="quick-link" to="/ops/stations?status=issue"><strong>Open issues</strong><small className="muted">{num(data.issues)} {data.issues === 1 ? "station" : "stations"} flagged</small></Link>
              <Link className="quick-link" to="/ops/people?role=agent"><strong>My agents</strong><small className="muted">{num(data.agents)} agents · tap to call</small></Link>
            </div>
          )}
          {seats.data?.map((h) => <SeatCard key={h.ours.id} h={h} />)}
          <div className="grid kpis">
            <Kpi label="Reporting progress" value={pct(data.stations ? data.reported / data.stations : 0)}
              caption={`${num(data.reported)} of ${num(data.stations)} stations reported`} progress={data.stations ? data.reported / data.stations : 0} tone="teal" />
            <Kpi label="Stations open" value={num(data.open)} caption={`${num(data.stations)} total · ${num(data.closed)} closed`} />
            <Kpi label="Turnout so far" value={pct(data.turnout)} caption={`${num(data.cast)} of ${num(data.registered)} registered`}
              progress={data.turnout} tone="teal" />
            <Kpi label="Needs attention" value={num(data.attention_count)}
              caption={`${num(data.issues)} ${data.issues === 1 ? "issue" : "issues"} · ${num(data.uncovered)} uncovered · ${num(data.to_verify)} to verify`} tone="amber" />
          </div>
          <div className="grid cols-2">
            <Card title={`Turnout trend — ${data.scope_label}`} extra={data.last_update && <small className="muted">Last updated {time(data.last_update)}</small>}>
              {data.trend.every((p) => p.cast === 0) ? <Empty>No turnout recorded yet.</Empty> : <TrendChart points={data.trend} slots={[6, 9, 11, 13, 15, 17]} />}
            </Card>
            <Card title="Needs attention now" extra={<span className="badge red">{num(data.attention_count)}</span>}>
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
                  {data.attention_count > 8 && (
                    <Link className="attention-more" to="/ops/stations">View all {num(data.attention_count)} in Polling stations ›</Link>
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


const ordinal = (n: number) => {
  const suffix = ["th", "st", "nd", "rd"], v = n % 100;
  return n + (suffix[(v - 20) % 10] ?? suffix[v] ?? suffix[0]);
};

/** Our candidate's seat in the last completed election: standing, the gap, and where to work. */
function SeatCard({ h }: { h: SeatHistory }) {
  const seat = `${h.position.name}${h.region ? ` — ${regionLabel(h.region)}` : ""}`;
  const winner = h.totals[0];
  const then = h.ours_then;
  const gap = then && winner && h.rank > 1 ? winner.votes - then.votes : null;
  const lead = then && h.rank === 1 && h.totals[1] ? then.votes - h.totals[1].votes : null;
  const areas = h.areas.filter((a) => a.margin != null);
  const strong = areas.filter((a) => a.margin! > 0).slice(0, 3);
  const work = [...areas].reverse().filter((a) => a.margin! <= 0).slice(0, 3);
  return (
    <Card className="seat-card" title={`Your seat — ${seat}`}
      extra={<Link className="btn small secondary" to={`/ops/results?election=${h.election.id}`}>{h.election.name} results ›</Link>}>
      <p style={{ marginTop: -6 }}>
        {then ? (
          <>
            <strong>{h.ours.name}</strong> came <strong>{ordinal(h.rank)}</strong> in {h.election.name} with {pct(then.share)} ({num(then.votes)} votes)
            {gap != null && winner && <> — <strong>{num(gap)} votes</strong> behind {winner.candidate.name} ({winner.candidate.party_code ?? "IND"}).</>}
            {lead != null && <> — won by <strong>{num(lead)} votes</strong>.</>}
          </>
        ) : (
          <>
            <strong>{h.ours.name}</strong> did not stand in {h.election.name}.
            {winner && <> {winner.candidate.name} ({winner.candidate.party_code ?? "IND"}) won with {pct(winner.share)}.</>}
          </>
        )}
        <span className="muted"> Turnout was {pct(h.turnout)}.</span>
      </p>
      <div className="grid cols-even">
        <div className="stack" style={{ gap: 8 }}>
          {h.totals.slice(0, 4).map((t) => {
            const mine = then?.candidate.id === t.candidate.id;
            return (
              <div key={t.candidate.id}>
                <div className="row spread"><span>{t.candidate.name} · {t.candidate.party_code ?? "IND"} {mine && "★"}</span><strong>{num(t.votes)} · {pct(t.share)}</strong></div>
                <ProgressBar value={t.share} tone={mine ? "teal" : "amber"} />
              </div>
            );
          })}
        </div>
        {then ? (
          <div className="stack" style={{ gap: 10 }}>
            <div>
              <div className="section-label" style={{ margin: "0 0 6px" }}>STRONGHOLDS</div>
              {strong.length === 0 ? <small className="muted">No {h.child_level} won last time.</small> : (
                <div className="row gap wrap">{strong.map((a) => <Badge key={a.name} tone="green">{a.name} {pp(a.margin!)}</Badge>)}</div>
              )}
            </div>
            <div>
              <div className="section-label" style={{ margin: "0 0 6px" }}>WHERE TO WORK</div>
              {work.length === 0 ? <small className="muted">Ahead in every {h.child_level}.</small> : (
                <div className="row gap wrap">{work.map((a) => <Badge key={a.name} tone="red">{a.name} {pp(a.margin!)}{a.leader && ` · ${a.leader.candidate.name.split(" ").slice(-1)[0]} led`}</Badge>)}</div>
              )}
            </div>
          </div>
        ) : (
          <div className="stack" style={{ gap: 6 }}>
            <div className="section-label" style={{ margin: "0 0 6px" }}>WHO LED WHERE</div>
            {h.areas.slice(0, 6).map((a) => (
              <div key={a.name} className="row spread"><span>{a.name}</span><small className="muted">{a.leader ? `${a.leader.candidate.name} · ${pct(a.leader.share)}` : "—"}</small></div>
            ))}
          </div>
        )}
      </div>
    </Card>
  );
}
