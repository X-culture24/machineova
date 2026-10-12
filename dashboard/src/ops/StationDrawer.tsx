import { useEffect, useState, type FormEvent } from "react";
import { ErrorNote, Field, Loading, Modal } from "../components/ui";
import { dateTime, initials, num, pct, time } from "../format";
import { useAsync } from "../useAsync";
import { ops, slotLabel, statusLabel, type StationDetail, type StationStatus } from "./api";
import { ContactLinks, StatusBadge } from "./components";

export type DrawerAction = "status" | "assign" | "turnout" | "incident" | "results";

/** Right-hand drawer (full-screen sheet on phones) for one polling station. */
export function StationDrawer({ code, initialAction, onClose, onChanged }: {
  code: string;
  initialAction?: DrawerAction | null;
  onClose: () => void;
  onChanged: () => void;
}) {
  const detail = useAsync(() => ops.station(code), [code]);
  const [action, setAction] = useState<DrawerAction | null>(initialAction ?? null);
  const [resolving, setResolving] = useState<string | null>(null);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && !action && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [action, onClose]);

  const done = () => {
    setAction(null);
    setResolving(null);
    detail.reload();
    onChanged();
  };
  const d = detail.data;
  const st = d?.station;

  return (
    <div className="drawer-backdrop" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <aside className="drawer" role="dialog" aria-label="Station record">
        <ErrorNote error={detail.error} />
        {!d || !st ? (
          <Loading />
        ) : (
          <>
            <div className="card-head" style={{ alignItems: "flex-start" }}>
              <div>
                <h2 style={{ fontSize: 18 }}>{st.name}</h2>
                <small className="muted">{st.code} · {st.ward} Ward · {st.constituency}</small>
                <div className="row gap" style={{ marginTop: 8 }}>
                  <StatusBadge status={st.status} />
                  {st.agents === 0 ? (
                    <span className="badge red">Uncovered</span>
                  ) : (
                    <span className="badge green">{st.agents} agent{st.agents > 1 ? "s" : ""} assigned</span>
                  )}
                </div>
              </div>
              <button className="btn ghost" onClick={onClose} aria-label="Close">✕</button>
            </div>

            <div className="stat-grid">
              <div className="stat"><small>REGISTERED</small><strong>{num(st.registered)}</strong></div>
              <div className="stat">
                <small>TURNOUT</small>
                <strong className="accent-text">{st.turnout == null ? "—" : pct(st.turnout)}</strong>
                {st.cast != null && <small className="muted">{num(st.cast)} cast</small>}
              </div>
              <div className="stat"><small>AGENTS</small><strong>{st.agents}</strong></div>
              <div className="stat"><small>LAST UPDATE</small><strong>{st.updated_at ? time(st.updated_at) : "—"}</strong></div>
            </div>

            {d.can_act && (
              <>
                <div className="section-label">QUICK ACTIONS</div>
                <div className="actions-grid">
                  <ActionTile title="Update status" sub="Open · Reporting · Closed · Issue" onClick={() => setAction("status")} />
                  {d.can_assign && <ActionTile title="Assign agent" sub="Two taps from the ward pool" onClick={() => setAction("assign")} />}
                  <ActionTile title="Record turnout" sub="Cumulative, by time slot" onClick={() => setAction("turnout")} />
                  <ActionTile title="Report incident" sub="Flags as Issue instantly" onClick={() => setAction("incident")} />
                  <ActionTile wide title="Submit & verify results" sub="Enter the Form 37A figures per candidate" onClick={() => setAction("results")} />
                </div>
              </>
            )}

            {d.incidents.some((i) => !i.resolved_at) && (
              <>
                <div className="section-label">OPEN INCIDENTS</div>
                {d.incidents.filter((i) => !i.resolved_at).map((i) => (
                  <div key={i.id} className="incident">
                    <div>
                      <strong>{i.type}</strong>
                      {i.description && <div>{i.description}</div>}
                      <small className="muted">{i.reported_by} · {time(i.created_at)}</small>
                    </div>
                    {d.can_assign && <button className="btn small secondary" onClick={() => setResolving(i.id)}>Resolve</button>}
                  </div>
                ))}
              </>
            )}

            <div className="section-label">ASSIGNED AGENTS</div>
            {d.agents.length === 0 ? (
              <p className="muted">No agent assigned yet.</p>
            ) : (
              d.agents.map((a) => (
                <div key={a.id} className="agent-row">
                  <span className="avatar">{initials(a.name)}</span>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontWeight: 600 }}>{a.name}</div>
                    <small className="muted">{a.phone ?? "—"} · ID {a.national_id ?? "—"}</small>
                  </div>
                  <ContactLinks phone={a.phone} />
                </div>
              ))
            )}

            <div className="section-label">FORM 37A</div>
            <div className="stack" style={{ gap: 6 }}>
              {d.results.map((r) => (
                <div key={r.position.id} className="row spread">
                  <span>{r.position.name}</span>
                  {r.submitted_at ? <span className="badge green">Verified {time(r.submitted_at)}</span> : <span className="badge grey">Pending</span>}
                </div>
              ))}
            </div>

            <div className="section-label">ACTIVITY</div>
            {d.events.length === 0 ? (
              <p className="muted">Nothing yet.</p>
            ) : (
              <ol className="timeline">
                {d.events.map((ev, i) => (
                  <li key={i} className={`tl-${ev.kind}`}>
                    <div>{ev.message}</div>
                    <small className="muted">{dateTime(ev.at)}{ev.by && ` · ${ev.by}`}</small>
                  </li>
                ))}
              </ol>
            )}
          </>
        )}
      </aside>
      {d && action === "status" && <StatusDialog d={d} onClose={() => setAction(null)} onDone={done} />}
      {d && action === "assign" && <AssignDialog d={d} onClose={() => setAction(null)} onDone={done} />}
      {d && action === "turnout" && <TurnoutDialog d={d} onClose={() => setAction(null)} onDone={done} />}
      {d && action === "incident" && <IncidentDialog d={d} onClose={() => setAction(null)} onDone={done} />}
      {d && action === "results" && <ResultsDialog d={d} onClose={() => setAction(null)} onDone={done} />}
      {d && resolving && <ResolveDialog code={d.station.code} incidentId={resolving} onClose={() => setResolving(null)} onDone={done} />}
    </div>
  );
}

function ActionTile({ title, sub, onClick, wide }: { title: string; sub: string; onClick: () => void; wide?: boolean }) {
  return (
    <button className={`action-tile ${wide ? "wide" : ""}`} onClick={onClick}>
      <strong>{title}</strong>
      <small className="muted">{sub}</small>
    </button>
  );
}

const subtitle = (d: StationDetail) => `${d.station.name} · ${d.station.code} · ${d.station.ward} Ward`;

function useSubmit(onDone: () => void) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const run = async (fn: () => Promise<unknown>) => {
    setBusy(true);
    setError(null);
    try {
      await fn();
      onDone();
    } catch (e) {
      setError((e as Error).message);
      setBusy(false);
    }
  };
  return { busy, error, run };
}

const statusHelp: Record<Exclude<StationStatus, "not_open">, string> = {
  open: "Voting in progress",
  reporting: "Figures coming in from the agent",
  closed: "Polls closed — awaiting verification",
  issue: "Needs attention now",
};

function StatusDialog({ d, onClose, onDone }: { d: StationDetail; onClose: () => void; onDone: () => void }) {
  const [status, setStatus] = useState<StationStatus>(d.station.status === "not_open" ? "open" : d.station.status);
  const [note, setNote] = useState("");
  const { busy, error, run } = useSubmit(onDone);
  return (
    <Modal title="Update station status" onClose={onClose}>
      <p className="muted modal-sub">{subtitle(d)}</p>
      <ErrorNote error={error} />
      <div className="choice-list">
        {(Object.keys(statusHelp) as (keyof typeof statusHelp)[]).map((s) => (
          <label key={s} className={`choice ${status === s ? "on" : ""}`}>
            <input type="radio" name="status" checked={status === s} onChange={() => setStatus(s)} />
            <div>
              <strong>{statusLabel[s]}</strong>
              <small className="muted">{statusHelp[s]}</small>
            </div>
          </label>
        ))}
      </div>
      <Field label="Note (optional)">
        <input placeholder="e.g. Queue cleared, closing on schedule" value={note} onChange={(e) => setNote(e.target.value)} />
      </Field>
      <div className="modal-actions">
        <button className="btn secondary" onClick={onClose}>Cancel</button>
        <button className="btn" disabled={busy} onClick={() => run(() => ops.setStatus(d.station.code, status, note))}>Update status</button>
      </div>
    </Modal>
  );
}

function AssignDialog({ d, onClose, onDone }: { d: StationDetail; onClose: () => void; onDone: () => void }) {
  const [q, setQ] = useState("");
  const pool = useAsync(() => ops.agentPool(d.station.code, q), [d.station.code, q]);
  const [error, setError] = useState<string | null>(null);
  const [changed, setChanged] = useState(false);
  const toggle = async (id: string, here: boolean) => {
    setError(null);
    try {
      if (here) await ops.unassignAgent(d.station.code, id);
      else await ops.assignAgent(d.station.code, id);
      setChanged(true);
      pool.reload();
    } catch (e) {
      setError((e as Error).message);
    }
  };
  return (
    <Modal title="Assign agents" onClose={changed ? onDone : onClose}>
      <p className="muted modal-sub">{subtitle(d)}</p>
      <ErrorNote error={error ?? pool.error} />
      <input className="input" placeholder="Search agents by name or ID…" value={q} onChange={(e) => setQ(e.target.value)} />
      <div className="stack" style={{ marginTop: 12, gap: 8 }}>
        {pool.data?.agents.length === 0 && <p className="muted">No agents registered in {pool.data.ward} Ward yet — add them in the Directory.</p>}
        {pool.data?.agents.map((a) => {
          const here = a.assigned_to === d.station.code;
          return (
            <div key={a.id} className="agent-row">
              <span className="avatar">{initials(a.name)}</span>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontWeight: 600 }}>{a.name}</div>
                <small className="muted">{a.phone ?? "—"} · ID {a.national_id ?? "—"}</small>
                <div>
                  {a.assigned_to ? <span className={`badge ${here ? "green" : "grey"}`}>At {a.assigned_to}</span> : <span className="badge teal">Available</span>}
                </div>
              </div>
              <button className={`btn small ${here ? "secondary" : ""}`} onClick={() => toggle(a.id, here)}>{here ? "Remove" : "Assign"}</button>
            </div>
          );
        })}
      </div>
      <p className="muted" style={{ fontSize: 12 }}>Agents registered in {d.station.ward} Ward. Assigning moves an agent from their current station.</p>
      <div className="modal-actions">
        <button className="btn" onClick={changed ? onDone : onClose}>Done</button>
      </div>
    </Modal>
  );
}

function TurnoutDialog({ d, onClose, onDone }: { d: StationDetail; onClose: () => void; onDone: () => void }) {
  const recorded = new Map(d.turnout.map((t) => [t.hour, t.count]));
  const nowHour = new Date().getHours();
  const defaultSlot = [...d.turnout_slots].reverse().find((h) => h <= nowHour) ?? d.turnout_slots[0]!;
  const [slot, setSlot] = useState(defaultSlot);
  const [value, setValue] = useState(recorded.get(defaultSlot)?.toString() ?? "");
  const { busy, error, run } = useSubmit(onDone);
  const latest = d.station.cast;
  const submit = (e: FormEvent) => {
    e.preventDefault();
    run(() => ops.recordTurnout(d.station.code, slot, Number(value)));
  };
  return (
    <Modal title="Record voter turnout" onClose={onClose}>
      <form onSubmit={submit}>
        <p className="muted modal-sub">{subtitle(d)}</p>
        <ErrorNote error={error} />
        <div className="field"><span>Time slot</span></div>
        <div className="slot-chips">
          {d.turnout_slots.map((h) => (
            <button type="button" key={h} className={`chip ${slot === h ? "on" : ""}`}
              onClick={() => { setSlot(h); setValue(recorded.get(h)?.toString() ?? ""); }}>
              {slotLabel(h)}{recorded.has(h) ? " ✓" : ""}
            </button>
          ))}
        </div>
        <Field label="Cumulative voters who have voted">
          <input className="big-input" type="number" inputMode="numeric" min={0} max={d.station.registered} required placeholder="e.g. 412"
            value={value} onChange={(e) => setValue(e.target.value)} autoFocus />
        </Field>
        <p className="muted" style={{ fontSize: 13 }}>
          Registered {num(d.station.registered)} · recorded so far {latest == null ? "—" : `${num(latest)} (${pct(latest / Math.max(1, d.station.registered))})`}
        </p>
        <div className="modal-actions">
          <button type="button" className="btn secondary" onClick={onClose}>Cancel</button>
          <button className="btn" disabled={busy || value === ""}>Save turnout</button>
        </div>
      </form>
    </Modal>
  );
}

const incidentTypes = ["KIEMS kit failure", "Ballot paper shortage", "Security concern", "Agent absent", "Voter intimidation", "Other"];

function IncidentDialog({ d, onClose, onDone }: { d: StationDetail; onClose: () => void; onDone: () => void }) {
  const [type, setType] = useState(incidentTypes[0]!);
  const [desc, setDesc] = useState("");
  const { busy, error, run } = useSubmit(onDone);
  return (
    <Modal title="Report an incident" onClose={onClose}>
      <p className="muted modal-sub">{subtitle(d)}</p>
      <ErrorNote error={error} />
      <div className="field"><span>Incident type</span></div>
      <div className="slot-chips">
        {incidentTypes.map((t) => (
          <button type="button" key={t} className={`chip ${type === t ? "on danger" : ""}`} onClick={() => setType(t)}>{t}</button>
        ))}
      </div>
      <Field label="What happened?">
        <textarea rows={4} placeholder="Brief description — who is affected, what's needed…" value={desc} onChange={(e) => setDesc(e.target.value)} />
      </Field>
      <p className="muted" style={{ fontSize: 13 }}>Reporting flags this station as Issue, puts it at the top of the action list, and notifies your admin.</p>
      <div className="modal-actions">
        <button className="btn secondary" onClick={onClose}>Cancel</button>
        <button className="btn danger" disabled={busy} onClick={() => run(() => ops.reportIncident(d.station.code, type, desc))}>Report incident</button>
      </div>
    </Modal>
  );
}

function ResolveDialog({ code, incidentId, onClose, onDone }: { code: string; incidentId: string; onClose: () => void; onDone: () => void }) {
  const [text, setText] = useState("");
  const { busy, error, run } = useSubmit(onDone);
  return (
    <Modal title="Resolve incident" onClose={onClose}>
      <ErrorNote error={error} />
      <Field label="How was it resolved?">
        <textarea rows={3} value={text} onChange={(e) => setText(e.target.value)} placeholder="e.g. Replacement kit delivered, voting resumed" autoFocus />
      </Field>
      <div className="modal-actions">
        <button className="btn secondary" onClick={onClose}>Cancel</button>
        <button className="btn" disabled={busy || !text.trim()} onClick={() => run(() => ops.resolveIncident(code, incidentId, text))}>Mark resolved</button>
      </div>
    </Modal>
  );
}

function ResultsDialog({ d, onClose, onDone }: { d: StationDetail; onClose: () => void; onDone: () => void }) {
  const firstPending = d.results.find((r) => !r.submitted_at) ?? d.results[0];
  const [positionId, setPositionId] = useState(firstPending?.position.id ?? "");
  const form = useAsync(() => (positionId ? ops.stationResults(d.station.code, positionId) : Promise.resolve(null)), [positionId]);
  const [votes, setVotes] = useState<Record<string, string>>({});
  const [rejected, setRejected] = useState("0");
  const [confirm, setConfirm] = useState(false);
  const { busy, error, run } = useSubmit(onDone);

  useEffect(() => {
    if (!form.data) return;
    setVotes(Object.fromEntries(form.data.candidates.map((c) => [c.id, String(form.data!.votes[c.id] ?? 0)])));
    setRejected(String(form.data.rejected ?? 0));
    setConfirm(false);
  }, [form.data]);

  const f = form.data;
  const candTotal = Object.values(votes).reduce((s, v) => s + (Number(v) || 0), 0);
  const total = candTotal + (Number(rejected) || 0);
  const mismatch = f?.turnout != null && total !== f.turnout;

  return (
    <Modal title="Submit & verify results" onClose={onClose}>
      <p className="muted modal-sub">{subtitle(d)} · Form 37A</p>
      <ErrorNote error={error ?? form.error} />
      {d.results.length === 0 ? (
        <p className="muted">This election has no positions yet.</p>
      ) : (
        <>
          <Field label="Position">
            <select value={positionId} onChange={(e) => setPositionId(e.target.value)}>
              {d.results.map((r) => (
                <option key={r.position.id} value={r.position.id}>{r.position.name}{r.submitted_at ? " ✓" : ""}</option>
              ))}
            </select>
          </Field>
          {!f ? (
            <Loading />
          ) : f.candidates.length === 0 ? (
            <div className="alert amber" style={{ marginTop: 12 }}>No candidates are set up for this race yet (Set up › Positions & candidates).</div>
          ) : (
            <>
              <div className="field" style={{ marginTop: 12 }}><span>Votes per candidate — {f.position.name} race</span></div>
              <div className="stack" style={{ gap: 8 }}>
                {f.candidates.map((c) => (
                  <div key={c.id} className="row spread vote-row">
                    <span>{c.name} <small className="muted">· {c.party_code ?? "IND"}</small></span>
                    <input className="input" type="number" min={0} style={{ width: 110 }} value={votes[c.id] ?? "0"}
                      onChange={(e) => setVotes({ ...votes, [c.id]: e.target.value })} />
                  </div>
                ))}
                <div className="row spread vote-row">
                  <span>Rejected / spoilt ballots</span>
                  <input className="input" type="number" min={0} style={{ width: 110 }} value={rejected} onChange={(e) => setRejected(e.target.value)} />
                </div>
              </div>
              <p className={mismatch ? "alert amber" : "muted"} style={{ fontSize: 13, marginTop: 10 }}>
                Candidate total {num(candTotal)} + rejected {num(Number(rejected) || 0)} = {num(total)} · recorded turnout {f.turnout == null ? "—" : num(f.turnout)}
                {mismatch && " — check the figures against the form"}
              </p>
              {f.submitted_at && <p className="muted" style={{ fontSize: 13 }}>Already verified {dateTime(f.submitted_at)} — saving replaces it.</p>}
              <label className="row gap" style={{ alignItems: "flex-start", marginTop: 8 }}>
                <input type="checkbox" checked={confirm} onChange={(e) => setConfirm(e.target.checked)} style={{ marginTop: 3 }} />
                <span>I confirm these figures match the signed Form 37A from this station.</span>
              </label>
            </>
          )}
          <div className="modal-actions">
            <button className="btn secondary" onClick={onClose}>Cancel</button>
            <button className="btn" disabled={busy || !confirm || !f || f.candidates.length === 0}
              onClick={() => run(() => ops.submitResults(d.station.code, {
                position_id: positionId,
                votes: Object.fromEntries(Object.entries(votes).map(([k, v]) => [k, Number(v) || 0])),
                rejected: Number(rejected) || 0,
                confirm,
              }))}>
              Submit & verify
            </button>
          </div>
        </>
      )}
    </Modal>
  );
}
