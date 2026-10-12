import { useEffect, useRef, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { useAuth } from "../auth";
import { Badge, Card, Empty, ErrorNote, Kpi, Loading, ProgressBar } from "../components/ui";
import { date, num, pct, time } from "../format";
import { useAsync } from "../useAsync";
import { ops, pp, slotLabel, type Drill, type Leader } from "./api";
import { DrillCrumbs, drillInto, NoElection, OpsHeader, PartyDot, TrendChart } from "./components";

const signalTone: Record<string, "amber" | "red" | "green" | "grey"> = {
  "Push GOTV": "amber", "Behind + low turnout": "red", "Opponent ahead": "red", Strong: "green", "Below average": "amber", "On pace": "grey",
};

function LeaderCell({ l, weLead }: { l: Leader | null; weLead?: boolean | null }) {
  if (!l) return <span className="muted">No results yet</span>;
  return (
    <span className="row gap wrap">
      <PartyDot colour={l.candidate.is_ours ? "var(--teal)" : "var(--amber)"} />
      <strong>{l.candidate.name}</strong>
      <small className="muted">{l.candidate.party_code ?? "IND"} · {pct(l.share)}</small>
      {weLead != null && (weLead ? <Badge tone="green">We lead</Badge> : <Badge tone="red">Trailing</Badge>)}
    </span>
  );
}

export function TurnoutPage() {
  const { me } = useAuth();
  const [drill, setDrill] = useState<Drill>({});
  const t = useAsync(() => ops.turnout(drill), [drill.constituency, drill.ward]);
  if (t.error?.includes("No active election")) return (<><OpsHeader title="Voter turnout" /><NoElection canSetup={me?.role === "owner" || me?.role === "admin"} /></>);
  const d = t.data;
  const root = me?.scope_label ?? d?.election.scope_label ?? "Scope";
  return (
    <>
      <OpsHeader title="Voter turnout" subtitle="Monitor — drill down to where you need attention" election={d?.election} scopeLabel={d?.scope_label}
        actions={<button className="btn small secondary" onClick={t.reload}>Refresh</button>} />
      <ErrorNote error={t.error} />
      {!d ? <Loading /> : (
        <>
          <div className="grid cols-turnout">
            <Card>
              <div className="center">
                <small className="muted">Cumulative turnout — {d.scope_label}</small>
                <div className="big-number accent-text">{pct(d.turnout)}</div>
                <small className="muted">{num(d.cast)} of {num(d.registered)} registered</small>
                <div style={{ marginTop: 12 }}><ProgressBar value={d.turnout} /></div>
              </div>
            </Card>
            <Card title="Turnout trend">
              {d.trend.every((p) => p.cast === 0) ? <Empty>No turnout recorded yet.</Empty> : <TrendChart points={d.trend} slots={[6, ...d.slots]} />}
            </Card>
          </div>
          <Card className="mt" title="Where attention is needed"
            extra={<div className="row gap"><Badge tone="red">{d.attention_count} areas</Badge><small className="muted">Scope average <strong>{pct(d.turnout)}</strong></small><Link className="btn small secondary" to="/ops/results">Open in Results ›</Link></div>}>
            {d.focus_position && (
              <p className="muted" style={{ marginTop: -6 }}>
                {d.focus_position.name} race{d.our_candidate && ` · ${d.our_candidate.name} (${d.our_candidate.party_name ?? d.our_candidate.party_code ?? "Independent"})`}
              </p>
            )}
            <DrillCrumbs root={root} drill={drill} onChange={setDrill} />
            <div className="table-wrap">
              <table className="cards">
                <thead><tr><th>{d.child_level}</th><th className="num">Turnout</th><th className="num">vs avg</th><th>Leading — {d.focus_position?.name ?? "race"}</th><th>Signal</th><th /></tr></thead>
                <tbody>
                  {d.areas.map((a) => {
                    const next = drillInto(drill, d.child_level, a.name);
                    return (
                      <tr key={a.name}>
                        <td data-label={d.child_level} style={{ fontWeight: 600 }}>{a.name}</td>
                        <td data-label="Turnout" className="num accent-text">{pct(a.turnout)}</td>
                        <td data-label="vs avg" className={`num ${a.vs_avg < 0 ? "neg" : "pos"}`}>{pp(a.vs_avg)}</td>
                        <td data-label="Leading"><LeaderCell l={a.leading} weLead={a.we_lead} /></td>
                        <td data-label="Signal"><Badge tone={signalTone[a.signal] ?? "grey"}>{a.signal}</Badge></td>
                        <td>{next && <button className="btn small secondary" onClick={() => setDrill(next)}>Drill ›</button>}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </Card>
          <Card className="mt" title={`Hourly rollup — by ${d.child_level}`}>
            <div className="table-wrap">
              <table className="cards">
                <thead>
                  <tr><th>{d.child_level}</th>{d.slots.map((h) => <th key={h} className="num">{slotLabel(h)}</th>)}<th>Turnout</th></tr>
                </thead>
                <tbody>
                  {d.areas.map((a) => (
                    <tr key={a.name}>
                      <td data-label={d.child_level} style={{ fontWeight: 600 }}>{a.name}</td>
                      {a.hourly.map((v, i) => <td key={i} data-label={slotLabel(d.slots[i]!)} className="num muted">{pct(v)}</td>)}
                      <td data-label="Turnout"><div className="row gap"><div style={{ width: 90 }}><ProgressBar value={a.turnout} /></div><strong>{pct(a.turnout)}</strong></div></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </Card>
        </>
      )}
    </>
  );
}

export function ResultsPage() {
  const { me } = useAuth();
  const [positionId, setPositionId] = useState<string | undefined>();
  const [drill, setDrill] = useState<Drill>({});
  const r = useAsync(() => ops.results(positionId, drill), [positionId, drill.constituency, drill.ward]);
  if (r.error?.includes("No active election")) return (<><OpsHeader title="Results" /><NoElection canSetup={me?.role === "owner" || me?.role === "admin"} /></>);
  const d = r.data;
  const lead = d?.totals?.[0];
  return (
    <>
      <OpsHeader title="Results" subtitle={d ? `Provisional tallies · ${d.scope_label}` : undefined} election={d?.election} scopeLabel={d?.scope_label}
        actions={<button className="btn small secondary" onClick={r.reload}>Refresh</button>} />
      <ErrorNote error={r.error} />
      {!d ? <Loading /> : (
        <>
          <div className="toolbar">
            <div className="tabs">
              {d.positions.map((p) => (
                <button key={p.id} className={d.position.id === p.id ? "on" : ""} onClick={() => setPositionId(p.id)}>{p.name}</button>
              ))}
            </div>
          </div>
          <DrillCrumbs root={me?.scope_label ?? d.election.scope_label} drill={drill} onChange={setDrill} />
          <p className="muted">Provisional · {d.stations_reporting} of {d.stations} stations reporting{d.last_update && ` · last updated ${time(d.last_update)}`}</p>
          {d.single_race && lead ? (
            <div className="grid cols-even">
              <Card>
                <small className="muted">LEADING — {d.position.name.toUpperCase()}{d.race && d.race !== "national" ? `, ${d.race.toUpperCase()}` : ""}</small>
                <div className="row gap" style={{ marginTop: 10 }}>
                  <span className="avatar big">{lead.candidate.name.split(" ").filter(Boolean).slice(-2).map((p) => p[0]).join("")}</span>
                  <div style={{ flex: 1 }}>
                    <div style={{ fontWeight: 700, fontSize: 18 }}>{lead.candidate.name} {lead.candidate.is_ours && "★"}</div>
                    <small className="muted">{lead.candidate.party_name ?? "Independent"}</small>
                  </div>
                  <div style={{ textAlign: "right" }}>
                    <div className="big-number accent-text" style={{ fontSize: 28 }}>{pct(lead.share)}</div>
                    <small className="muted">{num(lead.votes)} votes</small>
                  </div>
                </div>
                <p className="muted" style={{ fontSize: 13, marginTop: 14 }}>
                  What this means: provisional agent-reported tallies for the stations that have reported so far — not an official declaration. Figures change as more stations report.
                </p>
              </Card>
              <Card title="Candidate totals">
                <div className="stack">
                  {d.totals!.map((t) => (
                    <div key={t.candidate.id}>
                      <div className="row spread"><span>{t.candidate.name} · {t.candidate.party_code ?? "IND"} {t.candidate.is_ours && "★"}</span><strong>{num(t.votes)} · {pct(t.share)}</strong></div>
                      <ProgressBar value={t.share} tone={t.candidate.is_ours ? "teal" : "amber"} />
                    </div>
                  ))}
                </div>
              </Card>
            </div>
          ) : !d.single_race ? (
            <div className="alert teal">{d.position.name} has a separate race in each {d.position.level}. Drill into a {d.position.level} to see its candidate totals.</div>
          ) : (
            <Card><Empty>No results submitted for this race yet.</Empty></Card>
          )}
          <Card className="mt">
            <div className="table-wrap">
              <table className="cards">
                <thead><tr><th>{d.child_level}</th><th>Leading</th><th className="num">Share</th><th className="num">Margin</th><th className="num">Reporting</th><th /></tr></thead>
                <tbody>
                  {d.areas.map((a) => {
                    const next = drillInto(drill, d.child_level, a.name);
                    return (
                      <tr key={a.name}>
                        <td data-label={d.child_level} style={{ fontWeight: 600 }}>{a.name}</td>
                        <td data-label="Leading">{a.leading ? <span><strong>{a.leading.candidate.name}</strong> <small className="muted">{a.leading.candidate.party_code ?? "IND"}</small> {a.leading.candidate.is_ours && "★"}</span> : <span className="muted">—</span>}</td>
                        <td data-label="Share" className="num">{a.leading ? pct(a.leading.share) : "—"}</td>
                        <td data-label="Margin" className="num">{a.margin == null ? "—" : pp(a.margin)}</td>
                        <td data-label="Reporting" className="num">{pct(a.reporting)}</td>
                        <td>{next && <button className="btn small secondary" onClick={() => setDrill(next)}>Drill ›</button>}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </Card>
        </>
      )}
    </>
  );
}


export function ReplayPage() {
  const { id = "" } = useParams();
  const nav = useNavigate();
  const [hour, setHour] = useState(15);
  const [playing, setPlaying] = useState(false);
  const r = useAsync(() => ops.replay(id, hour), [id, hour]);
  const timer = useRef<number>();

  useEffect(() => {
    if (!playing) return;
    timer.current = window.setInterval(() => {
      setHour((h) => {
        if (h >= 21) {
          setPlaying(false);
          return h;
        }
        return h + 1;
      });
    }, 1200);
    return () => window.clearInterval(timer.current);
  }, [playing]);

  const d = r.data;
  return (
    <>
      <OpsHeader title={d ? `Election replay — ${d.election.election_date.slice(0, 4)}` : "Election replay"} subtitle="Archived hourly snapshots — scrub or play back election day"
        actions={<button className="btn small secondary" onClick={() => nav("/ops/election")}>‹ Elections</button>} />
      <ErrorNote error={r.error} />
      <Card>
        <div className="row spread wrap">
          <small className="muted">{d ? `${d.election.status === "completed" ? "Completed" : d.election.status === "active" ? "Active" : "Draft"} · ${date(d.election.election_date)} · ${d.election.scope_label}` : ""}</small>
          <div className="row gap">
            <button className="btn small" onClick={() => { if (hour >= 21) setHour(6); setPlaying(!playing); }}>{playing ? "❚❚ Pause" : "▶ Play"}</button>
            <strong>{slotLabel(hour)}</strong>
          </div>
        </div>
        <input type="range" className="scrubber" min={6} max={21} step={1} value={hour} onChange={(e) => { setPlaying(false); setHour(Number(e.target.value)); }} aria-label="Replay time" />
        <div className="row spread scrub-labels">{[6, 9, 12, 15, 18, 21].map((h) => <small key={h} className="muted">{slotLabel(h)}</small>)}</div>
      </Card>
      {!d ? <Loading /> : (
        <>
          <div className="grid kpis mt">
            <Kpi label={`Turnout at ${slotLabel(hour)}`} value={pct(d.turnout)} caption={`${num(d.cast)} of ${num(d.registered)}`} tone="teal" />
            <Kpi label="Stations" value={`${d.stations_reporting} of ${d.stations}`} caption="reporting" />
            <Kpi label={`Leading — ${d.focus_position?.name ?? "race"}`} value={d.leading ? <span style={{ fontSize: 18 }}>{d.leading.candidate.name}</span> : "—"}
              caption={d.leading ? pct(d.leading.share) : "no results yet"} />
            <Kpi label="Our margin" value={d.margin == null || d.we_lead == null ? "—" : `${Math.abs(d.margin)}pp`}
              caption={d.we_lead == null ? undefined : d.we_lead ? "ahead" : "behind"} tone={d.we_lead ? "teal" : "amber"} />
          </div>
          <div className="grid cols-2">
            <Card title={`By ${d.child_level} — at ${slotLabel(hour)}`}>
              <div className="table-wrap">
                <table className="cards">
                  <thead><tr><th>{d.child_level}</th><th className="num">Turnout</th><th>Leading</th><th className="num">Margin</th></tr></thead>
                  <tbody>
                    {d.areas.map((a) => (
                      <tr key={a.name}>
                        <td data-label={d.child_level} style={{ fontWeight: 600 }}>{a.name}</td>
                        <td data-label="Turnout" className="num">{pct(a.turnout)}</td>
                        <td data-label="Leading">{a.leading ? <span>{a.leading.candidate.name} {a.ours != null && <Badge tone={a.ours ? "green" : "red"}>{a.ours ? "Us" : "Opp"}</Badge>}</span> : <span className="muted">—</span>}</td>
                        <td data-label="Margin" className="num">{a.margin == null ? "—" : pp(a.margin)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </Card>
            <Card title={`What happened — up to ${slotLabel(hour)}`}>
              {d.events.length === 0 ? <Empty>Nothing recorded yet at this time.</Empty> : (
                <ol className="timeline">
                  {d.events.map((ev, i) => (
                    <li key={i} className={`tl-${ev.kind}`}><div>{ev.message}</div><small className="muted">{time(ev.at)}</small></li>
                  ))}
                </ol>
              )}
            </Card>
          </div>
        </>
      )}
    </>
  );
}
