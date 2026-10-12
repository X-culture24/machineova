import { useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useAuth } from "../auth";
import { Badge, Card, Empty, ErrorNote, Field, Loading } from "../components/ui";
import { date, num, pct } from "../format";
import { useAsync } from "../useAsync";
import { ops, type Drill, type ElectionSummary, type Level } from "./api";
import { DrillCrumbs, drillInto, OpsHeader } from "./components";

export default function ElectionPage() {
  const { me } = useAuth();
  const canSetup = me?.role === "owner" || me?.role === "admin";
  const nav = useNavigate();
  const list = useAsync(ops.elections, []);
  const [err, setErr] = useState<string | null>(null);
  const active = list.data?.find((e) => e.status === "active");
  const others = list.data?.filter((e) => e.status !== "active") ?? [];

  const setStatus = async (e: ElectionSummary, status: ElectionSummary["status"]) => {
    if (status === "active" && active && !confirm(`Activate ${e.name}? ${active.name} goes back to draft.`)) return;
    if (status === "completed" && !confirm(`Mark ${e.name} as completed? It moves to past elections and becomes replayable.`)) return;
    try {
      setErr(null);
      await ops.setElectionStatus(e.id, status);
      list.reload();
    } catch (x) {
      setErr((x as Error).message);
    }
  };

  return (
    <>
      <OpsHeader title="Election" subtitle="One active election scopes the whole workspace" election={active} scopeLabel={active?.scope_label}
        actions={canSetup && <Link className="btn" to="/ops/election/new">+ New election</Link>} />
      <ErrorNote error={list.error ?? err} />
      {!list.data ? (
        <Loading />
      ) : (
        <>
          {active ? <ActiveElection e={active} canSetup={canSetup} onComplete={() => setStatus(active, "completed")} /> : (
            <Card><Empty>No active election. {canSetup ? "Create one, or activate a draft below." : "Ask your admin to activate one."}</Empty></Card>
          )}
          <Card title="Other elections — drafts & past" className="mt">
            {others.length === 0 ? <Empty>Nothing else yet.</Empty> : (
              <div className="stack">
                {others.map((e) => (
                  <div key={e.id} className="row spread wrap election-row">
                    <div>
                      <div style={{ fontWeight: 600 }}>{e.name}</div>
                      <small className="muted">{date(e.election_date)} · {e.scope_label} · {e.positions} positions · {e.stations} stations</small>
                    </div>
                    <div className="row gap">
                      <Badge tone={e.status === "draft" ? "amber" : "grey"}>{e.status === "draft" ? "Draft" : "Completed"}</Badge>
                      {e.status === "completed" && <button className="btn small secondary" onClick={() => nav(`/ops/replay/${e.id}`)}>▶ Replay</button>}
                      {canSetup && e.status === "draft" && <button className="btn small" onClick={() => setStatus(e, "active")}>Activate</button>}
                      {canSetup && e.status === "draft" && (
                        <button className="btn small ghost" onClick={async () => {
                          if (!confirm(`Delete draft ${e.name}?`)) return;
                          try { await ops.deleteElection(e.id); list.reload(); } catch (x) { setErr((x as Error).message); }
                        }}>Delete</button>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </Card>
        </>
      )}
    </>
  );
}

function ActiveElection({ e, canSetup, onComplete }: { e: ElectionSummary; canSetup: boolean; onComplete: () => void }) {
  const [drill, setDrill] = useState<Drill>({});
  const detail = useAsync(() => ops.election(e.id, drill), [e.id, drill.constituency, drill.ward]);
  const d = detail.data;
  return (
    <>
      <Card>
        <div className="row spread wrap" style={{ marginBottom: 14 }}>
          <div>
            <small className="muted">ACTIVE ELECTION</small>
            <h2 style={{ fontSize: 18 }}>{e.name}</h2>
            <small className="muted">{date(e.election_date)} · {e.code} · Scope: {e.scope_label}</small>
          </div>
          {canSetup && <button className="btn secondary small" onClick={onComplete}>Mark completed</button>}
        </div>
        <div className="grid kpis" style={{ marginBottom: 0 }}>
          <div className="stat"><small>POSITIONS</small><strong>{e.positions}</strong></div>
          <div className="stat"><small>ELECTION REGIONS</small><strong>{e.counties} · {e.constituencies} · {e.wards}</strong><small className="muted">counties · constituencies · wards</small></div>
          <div className="stat"><small>REGISTERED VOTERS</small><strong>{num(e.registered)}</strong></div>
          <div className="stat"><small>STATIONS REPORTED</small><strong>{pct(e.reported_share)}</strong></div>
        </div>
      </Card>
      <ErrorNote error={detail.error} />
      {d && (
        <div className="grid cols-even mt">
          <Card title="Election regions — derived from positions">
            <div className="stack">
              {d.levels.map((l) => (
                <div key={l.level} className="region-derive">
                  <div style={{ fontWeight: 600 }}>{l.positions.join(" · ")}</div>
                  <div className="muted">→ {describeLevel(l.level, e.scope_label)}</div>
                  <Badge tone="teal">{l.regions.length} {plural(l.level, l.regions.length)}</Badge>
                </div>
              ))}
            </div>
          </Card>
          <Card title="Region drill-down" extra={<small className="muted">{e.name}</small>}>
            <DrillCrumbs root={e.scope_label} drill={drill} onChange={setDrill} />
            <div className="table-wrap">
              <table className="cards">
                <thead><tr><th>{d.drill.child_level}</th><th>Races held here</th><th className="num">Stations</th><th className="num">Reg. voters</th><th /></tr></thead>
                <tbody>
                  {d.drill.rows.map((r) => {
                    const next = drillInto(drill, d.drill.child_level, r.name);
                    return (
                      <tr key={r.name}>
                        <td data-label={d.drill.child_level} style={{ fontWeight: 600 }}>{r.name}</td>
                        <td data-label="Races">{r.races || "—"}</td>
                        <td data-label="Stations" className="num">{r.stations}</td>
                        <td data-label="Reg. voters" className="num">{num(r.registered)}</td>
                        <td>{next && <button className="btn small secondary" onClick={() => setDrill(next)}>Drill ›</button>}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </Card>
        </div>
      )}
    </>
  );
}

const plural = (level: string, n: number) =>
  ({ national: "nation", county: n === 1 ? "county" : "counties", constituency: n === 1 ? "constituency" : "constituencies", ward: n === 1 ? "ward" : "wards" })[level] ?? level;

function describeLevel(level: string, scope: string) {
  switch (level) {
    case "national": return "one national race";
    case "county": return `${scope} — one county-wide race each`;
    case "constituency": return "Every constituency in scope holds its own race";
    default: return "Every ward in scope holds its own race";
  }
}

// ---------------- New election wizard ----------------

const standardPositions: { name: string; level: Level }[] = [
  { name: "President", level: "national" },
  { name: "Governor", level: "county" },
  { name: "Senator", level: "county" },
  { name: "Woman Representative", level: "county" },
  { name: "Member of Parliament", level: "constituency" },
  { name: "MCA", level: "ward" },
];
const levelRank: Record<Level, number> = { national: 0, county: 1, constituency: 2, ward: 3 };
const steps = ["Details", "Scope", "Positions", "Candidates", "Review"];

export function NewElectionWizard() {
  const { me } = useAuth();
  const nav = useNavigate();
  const regions = useAsync(ops.regions, []);
  const [step, setStep] = useState(0);
  const [f, setF] = useState({ name: "", code: "", election_date: "", county: me?.organization?.boundary.county ?? "", constituency: me?.organization?.boundary.constituency ?? "" });
  const [picked, setPicked] = useState<Set<string>>(new Set(["Governor", "Senator", "Woman Representative", "Member of Parliament", "MCA"]));
  const [custom, setCustom] = useState<{ name: string; level: Level }[]>([]);
  const [customName, setCustomName] = useState("");
  const [customLevel, setCustomLevel] = useState<Level>("ward");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const scopeRank = f.constituency ? 2 : f.county ? 1 : 0;
  const inPlay = (l: Level) => levelRank[l] >= scopeRank;
  const positions = useMemo(
    () => [...standardPositions.filter((p) => picked.has(p.name) && inPlay(p.level)), ...custom.filter((p) => inPlay(p.level))],
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [picked, custom, scopeRank],
  );
  const counties = regions.data?.counties ?? [];
  const constituencies = counties.find((c) => c.name === f.county)?.constituencies ?? [];
  const boundary = me?.organization?.boundary;
  const valid = [
    f.name.trim() !== "" && f.code.trim() !== "" && f.election_date !== "",
    f.county !== "" || !boundary?.county,
    positions.length > 0,
    true,
    true,
  ];

  async function create() {
    setBusy(true);
    setError(null);
    try {
      await ops.createElection({ name: f.name, code: f.code, election_date: f.election_date, scope_county: f.county || undefined, scope_constituency: f.constituency || undefined, positions });
      nav("/ops/election");
    } catch (e) {
      setError((e as Error).message);
      setBusy(false);
    }
  }

  return (
    <>
      <OpsHeader title="New election" subtitle="Boundary from the register — regions follow the positions" />
      <Card>
        <ol className="stepper">
          {steps.map((s, i) => (
            <li key={s} className={i < step ? "done" : i === step ? "on" : ""}><span>{i < step ? "✓" : i + 1}</span>{s}</li>
          ))}
        </ol>
        <ErrorNote error={error} />
        {step === 0 && (
          <div className="form-grid">
            <div className="full"><Field label="Election name"><input value={f.name} placeholder="e.g. Migori County General Election 2027" onChange={(e) => setF({ ...f, name: e.target.value })} /></Field></div>
            <Field label="Code"><input value={f.code} placeholder="e.g. MGR-GE27" onChange={(e) => setF({ ...f, code: e.target.value })} /></Field>
            <Field label="Election day"><input type="date" value={f.election_date} onChange={(e) => setF({ ...f, election_date: e.target.value })} /></Field>
          </div>
        )}
        {step === 1 && (
          <div className="form-grid">
            <Field label="County" hint={boundary?.county ? `Your organization is bounded to ${boundary.county}.` : undefined}>
              <select value={f.county} disabled={!!boundary?.county} onChange={(e) => setF({ ...f, county: e.target.value, constituency: "" })}>
                <option value="">All counties</option>
                {counties.map((c) => <option key={c.name}>{c.name}</option>)}
              </select>
            </Field>
            <Field label="Constituency (optional — for a by-election)">
              <select value={f.constituency} disabled={!!boundary?.constituency || !f.county} onChange={(e) => setF({ ...f, constituency: e.target.value })}>
                <option value="">Whole {f.county || "scope"}</option>
                {constituencies.map((c) => <option key={c.name}>{c.name}</option>)}
              </select>
            </Field>
            {regions.data && counties.length === 0 && <div className="full alert amber">The polling-station register is empty. Import it first (see README: import-registry).</div>}
          </div>
        )}
        {step === 2 && (
          <>
            <h3>Positions on the ballot</h3>
            <p className="muted">Positions define the election's regions: pick MP and every constituency in scope holds a race; pick MCA and every ward does. Anything above the scope is out of play. Custom positions are welcome too.</p>
            <div className="choice-list">
              {standardPositions.map((p) => {
                const ok = inPlay(p.level);
                return (
                  <label key={p.name} className={`choice ${picked.has(p.name) && ok ? "on" : ""} ${ok ? "" : "disabled"}`}>
                    <input type="checkbox" disabled={!ok} checked={picked.has(p.name) && ok}
                      onChange={(e) => { const n = new Set(picked); if (e.target.checked) n.add(p.name); else n.delete(p.name); setPicked(n); }} />
                    <div><strong>{p.name}</strong><small className="muted">{ok ? `${cap(p.level)} level` : `${cap(p.level)} level — outside this election's scope`}</small></div>
                  </label>
                );
              })}
              {custom.map((p) => (
                <label key={p.name} className="choice on">
                  <input type="checkbox" checked onChange={() => setCustom(custom.filter((c) => c !== p))} />
                  <div><strong>{p.name}</strong><small className="muted">Custom · {p.level} level</small></div>
                </label>
              ))}
            </div>
            <div className="row gap wrap" style={{ marginTop: 12 }}>
              <input className="input" style={{ flex: 1, minWidth: 200 }} placeholder="Custom position, e.g. Youth Representative…" value={customName} onChange={(e) => setCustomName(e.target.value)} />
              <select className="input" style={{ width: 160 }} value={customLevel} onChange={(e) => setCustomLevel(e.target.value as Level)}>
                {(["county", "constituency", "ward"] as Level[]).filter(inPlay).map((l) => <option key={l} value={l}>{cap(l)} level</option>)}
              </select>
              <button className="btn secondary" disabled={!customName.trim()} onClick={() => { setCustom([...custom, { name: customName.trim(), level: customLevel }]); setCustomName(""); }}>Add</button>
            </div>
          </>
        )}
        {step === 3 && (
          <div className="alert teal">Candidates are added per race after the election is created — under Set up › Positions & candidates. They can be added or replaced even while the election is live.</div>
        )}
        {step === 4 && (
          <div className="stack">
            <div className="row spread"><span className="muted">Name</span><strong>{f.name}</strong></div>
            <div className="row spread"><span className="muted">Code · date</span><strong>{f.code.toUpperCase()} · {f.election_date}</strong></div>
            <div className="row spread"><span className="muted">Scope</span><strong>{f.constituency ? `${f.constituency} Constituency` : f.county ? `${f.county} County` : "All regions"}</strong></div>
            <div className="row spread"><span className="muted">Positions</span><strong>{positions.map((p) => p.name).join(" · ")}</strong></div>
            <p className="muted">The election is created as a draft with every polling station in scope from the register. Activate it when you're ready.</p>
          </div>
        )}
        <div className="modal-actions">
          {step > 0 && <button className="btn secondary" onClick={() => setStep(step - 1)}>Back</button>}
          {step < steps.length - 1 ? (
            <button className="btn" disabled={!valid[step]} onClick={() => setStep(step + 1)}>Continue</button>
          ) : (
            <button className="btn" disabled={busy} onClick={create}>{busy ? "Creating…" : "Create election"}</button>
          )}
        </div>
      </Card>
    </>
  );
}

const cap = (s: string) => s[0]!.toUpperCase() + s.slice(1);
