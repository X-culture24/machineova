import { useState, type FormEvent } from "react";
import { useAuth } from "../auth";
import { Badge, Card, Empty, ErrorNote, Field, Loading, Modal, Toggle } from "../components/ui";
import { initials, num } from "../format";
import { useAsync } from "../useAsync";
import { ops, regionLabel, type Level, type Race } from "./api";
import { ElectionPicker, NoElection, OpsHeader, Pager, PartyDot, PastElectionNote, usePickedElection } from "./components";

const levelLabel: Record<Level, string> = { national: "National level", county: "County level", constituency: "Constituency level", ward: "Ward level" };

const RACES_PER_PAGE = 24;
const countyOf = (r: Race) => (r.region ? r.region.split(" / ")[0]! : "");
const raceTitle = (r: Race) => (r.position.level === "national" || !r.region ? r.position.name : `${r.position.name} — ${regionLabel(r.region)}`);

export function PositionsPage() {
  const { me } = useAuth();
  const [electionId, setElectionId] = usePickedElection();
  const races = useAsync(() => ops.races(electionId), [electionId]);
  const past = races.data?.election.status === "completed";
  const canSetup = (me?.role === "owner" || me?.role === "admin") && !past;
  const parties = useAsync(ops.parties, []);
  const [adding, setAdding] = useState<Race | "pick" | null>(null);
  const [filter, setFilter] = useState("");
  const [county, setCounty] = useState("");
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const [err, setErr] = useState<string | null>(null);
  const colour = (code: string | null) => parties.data?.find((p) => p.code === code)?.colour;

  if (races.error?.includes("No active election")) return (<><OpsHeader title="Positions & candidates" /><NoElection canSetup={canSetup} /></>);
  const d = races.data;
  const counties = [...new Set(d?.races.map(countyOf).filter(Boolean))].sort();
  const needle = q.trim().toLowerCase();
  const shown = d?.races.filter((r) =>
    (!filter || r.position.id === filter) &&
    (!county || countyOf(r) === county || r.position.level === "national") &&
    (!needle || raceTitle(r).toLowerCase().includes(needle) || r.candidates.some((c) => c.name.toLowerCase().includes(needle)))) ?? [];
  const pageRaces = shown.slice((page - 1) * RACES_PER_PAGE, page * RACES_PER_PAGE);
  const withCandidates = d?.races.filter((r) => r.candidates.length > 0).length ?? 0;
  const reset = <T,>(set: (v: T) => void) => (v: T) => { set(v); setPage(1); };

  return (
    <>
      <OpsHeader title="Positions & candidates" subtitle={d ? `${d.election.name}${past ? " · completed" : " · editable while the election is live"}` : undefined}
        election={d?.election} scopeLabel={d?.election.scope_label}
        actions={<><ElectionPicker value={electionId} onChange={(id) => { setPage(1); setElectionId(id); }} />{canSetup && <button className="btn" onClick={() => setAdding("pick")}>+ Add candidate</button>}</>} />
      <PastElectionNote election={races.data?.election} onBack={() => setElectionId(undefined)} />
      <ErrorNote error={races.error ?? err} />
      {!d ? <Loading /> : (
        <>
          <div className="toolbar">
            <select className="input" value={filter} onChange={(e) => reset(setFilter)(e.target.value)}>
              <option value="">All positions</option>
              {d.positions.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
            {counties.length > 1 && (
              <select className="input" value={county} onChange={(e) => reset(setCounty)(e.target.value)}>
                <option value="">All counties</option>
                {counties.map((c) => <option key={c}>{c}</option>)}
              </select>
            )}
            <input className="input" placeholder="Search races or candidates…" value={q} onChange={(e) => reset(setQ)(e.target.value)} />
            {canSetup && <AddPosition onAdded={races.reload} />}
          </div>
          <p className="muted">
            {num(d.races.length)} races · {num(withCandidates)} with candidates.
            {past ? " Contestants as they stood on election day." : " Candidates can be added or replaced while the election is live. Mark your own candidate with ★ so monitoring can show where you lead."}
          </p>
          {shown.length === 0 ? <Card><Empty>No races match.</Empty></Card> : (
            <div className="grid race-grid">
              {pageRaces.map((r) => (
                <Card key={r.position.id + (r.region ?? "")} title={raceTitle(r)}
                  extra={canSetup && <button className="btn small secondary" onClick={() => setAdding(r)}>Add</button>}>
                  <div className="row spread" style={{ marginTop: -8, marginBottom: 10 }}>
                    <small className="muted">{levelLabel[r.position.level]}</small>
                    <small className="muted">{r.candidates.length} candidate{r.candidates.length === 1 ? "" : "s"}</small>
                  </div>
                  {r.candidates.length === 0 ? <small className="muted">No candidates yet.</small> : (
                    <div className="stack" style={{ gap: 8 }}>
                      {r.candidates.map((c) => (
                        <div key={c.id} className="agent-row">
                          <span className="avatar">{initials(c.name)}</span>
                          <div style={{ flex: 1, minWidth: 0 }}>
                            <div style={{ fontWeight: 600 }}>{c.name} {c.is_ours && <span title="Our candidate">★</span>}</div>
                            <small className="muted"><PartyDot colour={colour(c.party_code)} /> {c.party_name ?? "Independent"}</small>
                          </div>
                          {canSetup && (
                            <div className="row gap">
                              <button className="btn small ghost" title={c.is_ours ? "Unmark as ours" : "Mark as our candidate"}
                                onClick={() => ops.updateCandidate(c.id, { is_ours: !c.is_ours }).then(races.reload, (e: Error) => setErr(e.message))}>
                                {c.is_ours ? "★" : "☆"}
                              </button>
                              <button className="btn small ghost" onClick={() => {
                                if (confirm(`Remove ${c.name}?`)) ops.deleteCandidate(c.id).then(races.reload, (e: Error) => setErr(e.message));
                              }}>Remove</button>
                            </div>
                          )}
                        </div>
                      ))}
                    </div>
                  )}
                </Card>
              ))}
            </div>
          )}
          {shown.length > RACES_PER_PAGE && <Pager page={page} pageSize={RACES_PER_PAGE} total={shown.length} onPage={setPage} />}
        </>
      )}
      {adding && d && (
        <CandidateModal races={d.races} initial={adding === "pick" ? null : adding} parties={parties.data ?? []}
          onClose={() => setAdding(null)} onAdded={() => { setAdding(null); races.reload(); }} />
      )}
    </>
  );
}

function AddPosition({ onAdded }: { onAdded: () => void }) {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [level, setLevel] = useState<Level>("ward");
  const [error, setError] = useState<string | null>(null);
  if (!open) return <button className="btn secondary" onClick={() => setOpen(true)}>+ Custom position</button>;
  return (
    <Modal title="Custom position" onClose={() => setOpen(false)}>
      <ErrorNote error={error} />
      <div className="form-grid">
        <Field label="Name"><input value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Youth Representative" /></Field>
        <Field label="Level">
          <select value={level} onChange={(e) => setLevel(e.target.value as Level)}>
            <option value="county">County</option><option value="constituency">Constituency</option><option value="ward">Ward</option>
          </select>
        </Field>
      </div>
      <div className="modal-actions">
        <button className="btn secondary" onClick={() => setOpen(false)}>Cancel</button>
        <button className="btn" disabled={!name.trim()} onClick={() => ops.addPosition(name, level).then(() => { setOpen(false); setName(""); onAdded(); }, (e: Error) => setError(e.message))}>Add position</button>
      </div>
    </Modal>
  );
}

/** Add a candidate: position, then (for county-and-below races) county, then the race itself. */
function CandidateModal({ races, initial, parties, onClose, onAdded }: {
  races: Race[];
  initial: Race | null;
  parties: { code: string; name: string }[];
  onClose: () => void;
  onAdded: () => void;
}) {
  const first = initial ?? races[0]!;
  const [positionId, setPositionId] = useState(first.position.id);
  const [county, setCounty] = useState(countyOf(first));
  const [region, setRegion] = useState(first.region ?? "");
  const [name, setName] = useState("");
  const [party, setParty] = useState("");
  const [ours, setOurs] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const positions = [...new Map(races.map((r) => [r.position.id, r.position])).values()];
  const forPosition = races.filter((r) => r.position.id === positionId);
  const level = forPosition[0]?.position.level;
  const counties = [...new Set(forPosition.map(countyOf).filter(Boolean))].sort();
  const inCounty = level === "constituency" || level === "ward" ? forPosition.filter((r) => countyOf(r) === county) : forPosition;
  const race = forPosition.find((r) => (r.region ?? "") === region);
  // Inside a county, the race label drops the county part ("North Kamagambo, Rongo").
  const short = (r: Race) => regionLabel(r.region!.split(" / ").slice(1).join(" / "));

  function pickPosition(id: string) {
    setPositionId(id);
    const rs = races.filter((r) => r.position.id === id);
    const keep = rs.find((r) => countyOf(r) === county) ?? rs[0];
    setCounty(keep ? countyOf(keep) : "");
    setRegion(rs.length === 1 || rs[0]?.position.level === "county" ? (keep?.region ?? "") : "");
  }
  function submit(e: FormEvent) {
    e.preventDefault();
    if (!race) return setError("Pick the race this candidate stands in.");
    ops.addCandidate({ position_id: race.position.id, region: race.region, name, party_code: party || undefined, is_ours: ours }).then(onAdded, (x: Error) => setError(x.message));
  }
  return (
    <Modal title="Add candidate" onClose={onClose}>
      <form onSubmit={submit}>
        <ErrorNote error={error} />
        <div className="form-grid">
          <Field label="Position">
            <select value={positionId} onChange={(e) => pickPosition(e.target.value)}>
              {positions.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </Field>
          {level === "county" && (
            <Field label="County">
              <select required value={region} onChange={(e) => { setRegion(e.target.value); setCounty(e.target.value); }}>
                <option value="">Choose…</option>
                {forPosition.map((r) => <option key={r.region} value={r.region!}>{r.region}</option>)}
              </select>
            </Field>
          )}
          {(level === "constituency" || level === "ward") && (
            <>
              <Field label="County">
                <select required value={county} onChange={(e) => { setCounty(e.target.value); setRegion(""); }}>
                  <option value="">Choose…</option>
                  {counties.map((c) => <option key={c}>{c}</option>)}
                </select>
              </Field>
              <div className="full">
                <Field label={level === "ward" ? "Ward" : "Constituency"}>
                  <select required value={region} disabled={!county} onChange={(e) => setRegion(e.target.value)}>
                    <option value="">Choose…</option>
                    {inCounty.map((r) => <option key={r.region} value={r.region!}>{short(r)}</option>)}
                  </select>
                </Field>
              </div>
            </>
          )}
          <div className="full"><Field label="Candidate name"><input required value={name} onChange={(e) => setName(e.target.value)} /></Field></div>
          <Field label="Party" hint={parties.length === 0 ? "No parties in the registry yet." : undefined}>
            <select value={party} onChange={(e) => setParty(e.target.value)}>
              <option value="">Independent / none</option>
              {parties.map((p) => <option key={p.code} value={p.code}>{p.name} ({p.code})</option>)}
            </select>
          </Field>
          <div style={{ alignSelf: "end", paddingBottom: 8 }}><Toggle label="Our candidate" checked={ours} onChange={setOurs} /></div>
        </div>
        <div className="modal-actions">
          <button type="button" className="btn secondary" onClick={onClose}>Cancel</button>
          <button className="btn">Add candidate</button>
        </div>
      </form>
    </Modal>
  );
}

export function RegistryPage() {
  const [tab, setTab] = useState<"stations" | "parties">("stations");
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const stations = useAsync(() => ops.registryStations(q, page), [q, page]);
  const parties = useAsync(ops.parties, []);
  return (
    <>
      <OpsHeader title="Registry" subtitle="Official register — statutory, read-only" />
      <div className="alert teal"><Badge tone="teal">READ-ONLY</Badge> Official register, kept up to date by MachineNova. New stations join elections that haven't been held yet — ask MachineNova support to add or correct one.</div>
      <div className="toolbar">
        <div className="tabs">
          <button className={tab === "stations" ? "on" : ""} onClick={() => setTab("stations")}>Polling stations</button>
          <button className={tab === "parties" ? "on" : ""} onClick={() => setTab("parties")}>Parties</button>
        </div>
        {tab === "stations" && <input className="input" placeholder="Search the register…" value={q} onChange={(e) => { setQ(e.target.value); setPage(1); }} />}
      </div>
      <Card>
        {tab === "stations" ? (
          !stations.data ? <Loading /> : stations.data.items.length === 0 ? <Empty>No stations match.</Empty> : (
            <>
              <div className="table-wrap">
                <table className="cards">
                  <thead><tr><th>Code</th><th>Polling station</th><th>Ward</th><th>Constituency</th><th className="num">Reg. voters</th></tr></thead>
                  <tbody>
                    {stations.data.items.map((s) => (
                      <tr key={s.code}>
                        <td data-label="Code">{s.code}</td><td data-label="Station" style={{ fontWeight: 600 }}>{s.name}</td>
                        <td data-label="Ward">{s.ward}</td><td data-label="Constituency">{s.constituency}</td>
                        <td data-label="Reg. voters" className="num">{num(s.registered)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <Pager page={page} pageSize={stations.data.page_size} total={stations.data.total} onPage={setPage} />
            </>
          )
        ) : !parties.data ? <Loading /> : parties.data.length === 0 ? <Empty>No parties in the registry.</Empty> : (
          <div className="table-wrap">
            <table>
              <thead><tr><th>Code</th><th>Party</th></tr></thead>
              <tbody>{parties.data.map((p) => <tr key={p.code}><td>{p.code}</td><td><PartyDot colour={p.colour} /> {p.name}</td></tr>)}</tbody>
            </table>
          </div>
        )}
      </Card>
    </>
  );
}
