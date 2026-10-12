import { useEffect, useState, type FormEvent } from "react";
import { useSearchParams } from "react-router-dom";
import { useAuth } from "../auth";
import { Badge, Card, Empty, ErrorNote, Field, Loading, Modal } from "../components/ui";
import { initials } from "../format";
import { useAsync } from "../useAsync";
import { ops, roleLabel, type OpsRole } from "./api";
import { ContactLinks, OpsHeader, Pager } from "./components";
import { maskId } from "../mask";

const rank: Record<string, number> = { agent: 1, manager: 2, chief_agent: 3, admin: 4, executive: 5, owner: 6 };
const tabs: { role: string; label: string }[] = [
  { role: "", label: "All" },
  { role: "admin", label: "Admins" },
  { role: "chief_agent", label: "Chief Agents" },
  { role: "manager", label: "Managers" },
  { role: "agent", label: "Agents" },
];
const roleTone: Record<string, "teal" | "blue" | "amber" | "grey" | "green"> = {
  owner: "teal", executive: "blue", admin: "blue", chief_agent: "amber", manager: "green", agent: "grey",
};

export default function PeoplePage() {
  const { me } = useAuth();
  const [params, setParams] = useSearchParams();
  const role = params.get("role") ?? "";
  const [q, setQ] = useState("");
  const [dq, setDq] = useState("");
  const [page, setPage] = useState(1);
  const [adding, setAdding] = useState(false);
  useEffect(() => {
    const t = setTimeout(() => setDq(q), 300);
    return () => clearTimeout(t);
  }, [q]);
  const list = useAsync(() => ops.people({ role, q: dq, page }), [role, dq, page]);
  const myRank = rank[me?.role ?? ""] ?? 0;
  const canAdd = myRank > 1 && me?.role !== "executive";

  return (
    <>
      <OpsHeader title="People" subtitle={`Everyone in ${me?.scope_label ?? "your area"} — one directory`} scopeLabel={me?.scope_label}
        actions={canAdd && <button className="btn" onClick={() => setAdding(true)}>+ Add person</button>} />
      <div className="toolbar">
        <div className="tabs">
          {tabs.map((t) => (
            <button key={t.role} className={role === t.role ? "on" : ""} onClick={() => { setParams(t.role ? { role: t.role } : {}); setPage(1); }}>{t.label}</button>
          ))}
        </div>
        <input className="input" placeholder="Search name, phone or national ID…" value={q} onChange={(e) => { setQ(e.target.value); setPage(1); }} />
      </div>
      <ErrorNote error={list.error} />
      <Card>
        {!list.data ? <Loading /> : list.data.items.length === 0 ? <Empty>No one here yet.</Empty> : (
          <>
            <div className="table-wrap">
              <table className="cards">
                <thead><tr><th>Name</th><th>Role</th><th>Area</th><th>Contact</th><th>National ID</th></tr></thead>
                <tbody>
                  {list.data.items.map((p) => (
                    <tr key={p.id} style={{ opacity: p.active ? 1 : 0.55 }}>
                      <td data-label="Name">
                        <div className="person">
                          <span className="avatar">{initials(p.name)}</span>
                          <div>
                            <div style={{ fontWeight: 600 }}>{p.name}</div>
                            {p.station_code && <small className="muted">At {p.station_name ?? p.station_code}</small>}
                            {!p.active && <small className="muted"> · inactive</small>}
                          </div>
                        </div>
                      </td>
                      <td data-label="Role"><Badge tone={roleTone[p.role]}>{roleLabel[p.role]}</Badge></td>
                      <td data-label="Area">{p.area}</td>
                      <td data-label="Contact"><div className="stack" style={{ gap: 4 }}><span>{p.phone ?? "—"}</span><ContactLinks phone={p.phone} /></div></td>
                      <td data-label="National ID">
                        {maskId(p.national_id)}
                        {myRank > (rank[p.role] ?? 9) && me?.role !== "executive" && (
                          <button className="btn small ghost" onClick={() => ops.updatePerson(p.id, { active: !p.active }).then(list.reload)}>
                            {p.active ? "Deactivate" : "Reactivate"}
                          </button>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <Pager page={page} pageSize={list.data.page_size} total={list.data.total} onPage={setPage} />
          </>
        )}
      </Card>
      {adding && <AddPersonModal onClose={() => setAdding(false)} onAdded={() => { setAdding(false); list.reload(); }} />}
    </>
  );
}

const needs: Record<string, "none" | "constituency" | "ward"> = {
  executive: "none", admin: "constituency", chief_agent: "constituency", manager: "ward", agent: "ward",
};

function AddPersonModal({ onClose, onAdded }: { onClose: () => void; onAdded: () => void }) {
  const { me } = useAuth();
  const myRank = rank[me?.role ?? ""] ?? 0;
  const roles = (["executive", "admin", "chief_agent", "manager", "agent"] as OpsRole[]).filter((r) => rank[r]! < myRank);
  const regions = useAsync(ops.regions, []);
  const [f, setF] = useState({
    role: roles[roles.length - 1] ?? "agent", name: "", phone: "", national_id: "", email: "", password: "",
    county: me?.scope.county ?? me?.organization?.boundary.county ?? "", constituency: me?.scope.constituency ?? "", ward: me?.scope.ward ?? "", station_code: "",
  });
  const [error, setError] = useState<string | null>(null);
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value });

  const counties = regions.data?.counties ?? [];
  const county = counties.find((c) => c.name === f.county) ?? (counties.length === 1 ? counties[0] : undefined);
  const constituencies = county?.constituencies ?? [];
  const wards = constituencies.find((c) => c.name === f.constituency)?.wards ?? [];
  const stations = wards.find((w) => w.name === f.ward)?.stations ?? [];
  const need = needs[f.role]!;
  const area = need === "none" ? me?.scope_label : need === "constituency" ? (f.constituency && `${f.constituency} Constituency`) : (f.ward && `${f.ward} Ward`);

  function submit(e: FormEvent) {
    e.preventDefault();
    ops.addPerson({
      role: f.role, name: f.name, phone: f.phone, national_id: f.national_id,
      email: f.email || undefined, password: f.password || undefined,
      county: need !== "none" ? county?.name : undefined,
      constituency: need !== "none" ? f.constituency || undefined : undefined,
      ward: need === "ward" ? f.ward || undefined : undefined,
      station_code: f.role === "agent" ? f.station_code || undefined : undefined,
    }).then(onAdded, (x: Error) => setError(x.message));
  }

  return (
    <Modal title="Add person" onClose={onClose}>
      <form onSubmit={submit}>
        <p className="muted modal-sub">Role and area decide exactly what they see</p>
        <ErrorNote error={error ?? regions.error} />
        <div className="form-grid">
          <Field label="Role">
            <select value={f.role} onChange={set("role")}>{roles.map((r) => <option key={r} value={r}>{roleLabel[r]}</option>)}</select>
          </Field>
          <Field label="Full name"><input required placeholder="As on national ID" value={f.name} onChange={set("name")} /></Field>
          <Field label="Phone"><input required type="tel" placeholder="+254 7…" value={f.phone} onChange={set("phone")} /></Field>
          <Field label="National ID"><input required inputMode="numeric" placeholder="8 digits" value={f.national_id} onChange={set("national_id")} /></Field>
          {need !== "none" && counties.length > 1 && (
            <Field label="County">
              <select required value={f.county} onChange={(e) => setF({ ...f, county: e.target.value, constituency: "", ward: "", station_code: "" })}>
                <option value="">Choose…</option>
                {counties.map((c) => <option key={c.name}>{c.name}</option>)}
              </select>
            </Field>
          )}
          {need !== "none" && (
            <Field label="Constituency">
              <select required value={f.constituency} disabled={!!me?.scope.constituency} onChange={(e) => setF({ ...f, constituency: e.target.value, ward: "", station_code: "" })}>
                <option value="">Choose…</option>
                {constituencies.map((c) => <option key={c.name}>{c.name}</option>)}
              </select>
            </Field>
          )}
          {need === "ward" && (
            <Field label="Ward">
              <select required value={f.ward} disabled={!!me?.scope.ward || !f.constituency} onChange={(e) => setF({ ...f, ward: e.target.value, station_code: "" })}>
                <option value="">Choose…</option>
                {wards.map((w) => <option key={w.name}>{w.name}</option>)}
              </select>
            </Field>
          )}
          {f.role === "agent" && (
            <div className="full">
              <Field label="Polling station (optional — can be assigned later)">
                <select value={f.station_code} disabled={!f.ward} onChange={set("station_code")}>
                  <option value="">Unassigned</option>
                  {stations.map((s) => <option key={s.code} value={s.code}>{s.name} · {s.code}</option>)}
                </select>
              </Field>
            </div>
          )}
          <Field label="Email (for sign-in, optional)"><input type="email" value={f.email} onChange={set("email")} /></Field>
          <Field label="Initial password (optional)" hint="Leave blank: with an email they get a single-use invitation link; without one they are a directory-only contact.">
            <input type="text" minLength={8} value={f.password} onChange={set("password")} />
          </Field>
        </div>
        {area && <div className="alert teal" style={{ marginTop: 12 }}>This {roleLabel[f.role]} will only see {area}.</div>}
        <div className="modal-actions">
          <button type="button" className="btn secondary" onClick={onClose}>Cancel</button>
          <button className="btn">Add person</button>
        </div>
      </form>
    </Modal>
  );
}
