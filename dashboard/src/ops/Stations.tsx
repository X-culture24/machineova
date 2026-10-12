import { useEffect, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { useAuth } from "../auth";
import { Card, Empty, ErrorNote, Field, Loading, Modal } from "../components/ui";
import { num, pct } from "../format";
import { useAsync } from "../useAsync";
import { ops, statusLabel, type StationStatus } from "./api";
import { NoElection, OpsHeader, Pager, StatusBadge } from "./components";
import { StationDrawer } from "./StationDrawer";

const chips: { key: string; label: string; dot: string }[] = [
  { key: "open", label: "Open", dot: "green" },
  { key: "reporting", label: "Reporting", dot: "teal" },
  { key: "issue", label: "Issue", dot: "red" },
  { key: "closed", label: "Closed", dot: "grey" },
  { key: "uncovered", label: "Uncovered", dot: "amber" },
];

export default function StationsPage() {
  const { me } = useAuth();
  const [params, setParams] = useSearchParams();
  const status = params.get("status") ?? "";
  const open = params.get("station");
  const [q, setQ] = useState("");
  const [dq, setDq] = useState("");
  const [constituency, setConstituency] = useState("");
  const [ward, setWard] = useState("");
  const [page, setPage] = useState(1);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [bulk, setBulk] = useState(false);
  useEffect(() => {
    const t = setTimeout(() => setDq(q), 250);
    return () => clearTimeout(t);
  }, [q]);
  const list = useAsync(() => ops.stations({ status, q: dq, constituency, ward, page }), [status, dq, constituency, ward, page]);
  const regions = useAsync(ops.regions, []);

  const setParam = (k: string, v: string | null) => {
    const n = new URLSearchParams(params);
    if (v) n.set(k, v);
    else n.delete(k);
    setParams(n);
  };
  if (list.error?.includes("No active election")) return (<><OpsHeader title="Station operations" /><NoElection canSetup={me?.role === "owner" || me?.role === "admin"} /></>);

  const constituencies = regions.data?.counties.flatMap((c) => c.constituencies) ?? [];
  const wards = constituencies.find((c) => c.name === constituency)?.wards ?? (constituencies.length === 1 ? constituencies[0]!.wards : []);
  const d = list.data;
  const pageCodes = d?.items.map((s) => s.code) ?? [];
  const allOnPage = pageCodes.length > 0 && pageCodes.every((c) => selected.has(c));
  const canBulk = me?.role !== "executive" && me?.role !== "agent";

  return (
    <>
      <OpsHeader title="Station operations" subtitle="The do surface — status, turnout, assignments, incidents, results" scopeLabel={d?.scope_label} />
      <ErrorNote error={list.error} />
      <div className="chip-row">
        {chips.map((c) => (
          <button key={c.key} className={`count-chip ${status === c.key ? "on" : ""}`} onClick={() => { setParam("status", status === c.key ? null : c.key); setPage(1); }}>
            <span className={`dot ${c.dot}`} /> <strong>{d?.counts[c.key] ?? "–"}</strong> {c.label}
          </button>
        ))}
      </div>
      <div className="toolbar">
        <input className="input" placeholder="Search stations…" value={q} onChange={(e) => { setQ(e.target.value); setPage(1); }} />
        {!me?.scope.constituency && (
          <select className="input" value={constituency} onChange={(e) => { setConstituency(e.target.value); setWard(""); setPage(1); }}>
            <option value="">All constituencies</option>
            {constituencies.map((c) => <option key={c.name}>{c.name}</option>)}
          </select>
        )}
        {!me?.scope.ward && (
          <select className="input" value={ward} onChange={(e) => { setWard(e.target.value); setPage(1); }}>
            <option value="">All wards</option>
            {wards.map((w) => <option key={w.name}>{w.name}</option>)}
          </select>
        )}
        <span className="muted" style={{ alignSelf: "center" }}>{d ? `${d.total} of ${d.in_scope} stations` : ""}</span>
        {selected.size > 0 && canBulk && (
          <button className="btn" style={{ marginLeft: "auto" }} onClick={() => setBulk(true)}>Update {selected.size} selected</button>
        )}
      </div>
      <Card>
        {!d ? <Loading /> : d.items.length === 0 ? <Empty>No stations match.</Empty> : (
          <>
            <div className="table-wrap">
              <table className="cards">
                <thead>
                  <tr>
                    {canBulk && (
                      <th style={{ width: 32 }}>
                        <input type="checkbox" aria-label="Select page" checked={allOnPage} onChange={() => {
                          const n = new Set(selected);
                          pageCodes.forEach((c) => (allOnPage ? n.delete(c) : n.add(c)));
                          setSelected(n);
                        }} />
                      </th>
                    )}
                    <th>Station</th><th>Ward</th><th className="num">Voters</th><th className="num">Turnout</th><th>Agents</th><th>Status</th><th />
                  </tr>
                </thead>
                <tbody>
                  {d.items.map((s) => (
                    <tr key={s.code} className="clickable" onClick={() => setParam("station", s.code)}>
                      {canBulk && (
                        <td onClick={(e) => e.stopPropagation()}>
                          <input type="checkbox" aria-label={`Select ${s.name}`} checked={selected.has(s.code)} onChange={() => {
                            const n = new Set(selected);
                            if (n.has(s.code)) n.delete(s.code);
                            else n.add(s.code);
                            setSelected(n);
                          }} />
                        </td>
                      )}
                      <td data-label="Station"><div style={{ fontWeight: 600 }}>{s.name}</div><small className="muted">{s.code} · {s.constituency}</small></td>
                      <td data-label="Ward">{s.ward}</td>
                      <td data-label="Voters" className="num">{num(s.registered)}</td>
                      <td data-label="Turnout" className="num accent-text">{s.turnout == null ? "—" : pct(s.turnout)}</td>
                      <td data-label="Agents">{s.agents === 0 ? <span className="badge red">Uncovered</span> : <span className="badge green">{s.agents} agent{s.agents > 1 ? "s" : ""}</span>}</td>
                      <td data-label="Status"><StatusBadge status={s.status} /></td>
                      <td><button className="btn small secondary">Manage</button></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <Pager page={page} pageSize={d.page_size} total={d.total} onPage={setPage} />
          </>
        )}
      </Card>
      {open && <StationDrawer code={open} onClose={() => setParam("station", null)} onChanged={list.reload} />}
      {bulk && (
        <BulkStatus codes={[...selected]} onClose={() => setBulk(false)} onDone={() => { setBulk(false); setSelected(new Set()); list.reload(); }} />
      )}
    </>
  );
}

function BulkStatus({ codes, onClose, onDone }: { codes: string[]; onClose: () => void; onDone: () => void }) {
  const [status, setStatus] = useState<StationStatus>("open");
  const [note, setNote] = useState("");
  const [progress, setProgress] = useState<string | null>(null);
  const [errors, setErrors] = useState<string[]>([]);
  async function run() {
    const failed: string[] = [];
    for (let i = 0; i < codes.length; i++) {
      setProgress(`${i + 1} of ${codes.length}…`);
      try {
        await ops.setStatus(codes[i]!, status, note);
      } catch (e) {
        failed.push(`${codes[i]}: ${(e as Error).message}`);
      }
    }
    if (failed.length) {
      setErrors(failed);
      setProgress(null);
    } else onDone();
  }
  return (
    <Modal title={`Update ${codes.length} stations`} onClose={errors.length ? onDone : onClose}>
      {errors.length > 0 && <div className="alert red">{errors.map((e) => <div key={e}>{e}</div>)}</div>}
      <Field label="New status">
        <select value={status} onChange={(e) => setStatus(e.target.value as StationStatus)}>
          {(["open", "reporting", "closed", "issue"] as StationStatus[]).map((s) => <option key={s} value={s}>{statusLabel[s]}</option>)}
        </select>
      </Field>
      <Field label="Note (optional)"><input value={note} onChange={(e) => setNote(e.target.value)} /></Field>
      <div className="modal-actions">
        <button className="btn secondary" onClick={errors.length ? onDone : onClose}>{errors.length ? "Close" : "Cancel"}</button>
        {!errors.length && <button className="btn" disabled={!!progress} onClick={run}>{progress ?? "Update status"}</button>}
      </div>
    </Modal>
  );
}
