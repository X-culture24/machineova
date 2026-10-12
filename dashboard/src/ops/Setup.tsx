import { useState, type FormEvent } from "react";
import { useAuth } from "../auth";
import { Badge, Card, Empty, ErrorNote, Field, Loading, Modal, Toggle } from "../components/ui";
import { initials, num } from "../format";
import { useAsync } from "../useAsync";
import { ops, type Level, type Race } from "./api";
import { NoElection, OpsHeader, Pager, PartyDot } from "./components";

const levelLabel: Record<Level, string> = { national: "National level", county: "County level", constituency: "Constituency level", ward: "Ward level" };

export function PositionsPage() {
  const { me } = useAuth();
  const canSetup = me?.role === "owner" || me?.role === "admin";
  const races = useAsync(ops.races, []);
  const parties = useAsync(ops.parties, []);
  const [adding, setAdding] = useState<Race | "pick" | null>(null);
  const [filter, setFilter] = useState("");
  const [err, setErr] = useState<string | null>(null);
  const colour = (code: string | null) => parties.data?.find((p) => p.code === code)?.colour;

  if (races.error?.includes("No active election")) return (<><OpsHeader title="Positions & candidates" /><NoElection canSetup={canSetup} /></>);
  const d = races.data;
  const shown = d?.races.filter((r) => !filter || r.position.id === filter) ?? [];

  return (
    <>
      <OpsHeader title="Positions & candidates" subtitle={d ? `Scoped to ${d.election.name} · editable while the election is live` : undefined}
        election={d?.election} scopeLabel={d?.election.scope_label}
        actions={canSetup && <button className="btn" onClick={() => setAdding("pick")}>+ Add candidate</button>} />
      <ErrorNote error={races.error ?? err} />
      {!d ? <Loading /> : (
        <>
          <div className="toolbar">
            <select className="input" value={filter} onChange={(e) => setFilter(e.target.value)}>
              <option value="">All positions</option>
              {d.positions.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
            {canSetup && <AddPosition onAdded={races.reload} />}
          </div>
          <p className="muted">Candidates can be added or replaced while the election is live. Mark your own candidate with ★ so monitoring can show where you lead.</p>
          <div className="grid race-grid">
            {shown.map((r) => (
              <Card key={r.position.id + (r.region ?? "")} title={r.position.level === "county" || r.position.level === "national" ? r.position.name : `${r.position.name} — ${r.region}`}
                extra={canSetup && <button className="btn small secondary" onClick={() => setAdding(r)}>Add</button>}>
                <div className="row spread" style={{ marginTop: -8, marginBottom: 10 }}>
                  <small className="muted">{levelLabel[r.position.level]}</small>
                  <small className="muted">{r.candidates.length} candidate{r.candidates.length === 1 ? "" : "s"}</small>
                </div>
                {r.candidates.length === 0 ? <Empty>No candidates yet.</Empty> : (
                  <div className="stack" style={{ gap: 8 }}>
                    {r.candidates.map((c) => (
                      <div key={c.id} className="agent-row">
                        <span className="avatar">{initials(c.name)}</span>
                        <div style={{ flex: 1 }}>
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

function CandidateModal({ races, initial, parties, onClose, onAdded }: {
  races: Race[];
  initial: Race | null;
  parties: { code: string; name: string }[];
  onClose: () => void;
  onAdded: () => void;
}) {
  const key = (r: Race) => r.position.id + "|" + (r.region ?? "");
  const [raceKey, setRaceKey] = useState(initial ? key(initial) : key(races[0]!));
  const [name, setName] = useState("");
  const [party, setParty] = useState("");
  const [ours, setOurs] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const race = races.find((r) => key(r) === raceKey)!;
  function submit(e: FormEvent) {
    e.preventDefault();
    ops.addCandidate({ position_id: race.position.id, region: race.region, name, party_code: party || undefined, is_ours: ours }).then(onAdded, (x: Error) => setError(x.message));
  }
  return (
    <Modal title="Add candidate" onClose={onClose}>
      <form onSubmit={submit}>
        <ErrorNote error={error} />
        <div className="form-grid">
          <div className="full">
            <Field label="Race">
              <select value={raceKey} onChange={(e) => setRaceKey(e.target.value)}>
                {races.map((r) => <option key={key(r)} value={key(r)}>{r.position.name}{r.region && r.position.level !== "county" ? ` — ${r.region}` : ""}</option>)}
              </select>
            </Field>
          </div>
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
      <div className="alert teal"><Badge tone="teal">READ-ONLY</Badge> Official register — picked during setup; not editable here. Updates come from the statutory import.</div>
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
