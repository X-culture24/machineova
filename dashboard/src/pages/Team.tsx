import SearchInput, { matchesSearch } from "../components/SearchInput";
import { useState, type FormEvent } from "react";
import { api, type Member, type Role } from "../api";
import { useAuth } from "../auth";
import { Badge, Card, ErrorNote, Field, Loading, Modal, PageHeader, Toggle } from "../components/ui";
import { initials } from "../format";
import { useAsync } from "../useAsync";
import { useTable } from "../components/TableTools";

const roleTone: Partial<Record<Role, "teal" | "blue" | "grey" | "amber">> = { owner: "teal", admin: "blue", member: "grey", viewer: "amber" };
// Field roles (managers, agents…) are managed in Election Ops › Directory.
const checkinRoles = new Set<Role>(["owner", "admin", "member", "viewer"]);

export default function TeamPage() {
  const { me } = useAuth();
  const { data, error, reload } = useAsync(api.team, []);
  const [query, setQuery] = useState("");
  const [adding, setAdding] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const members = (data ?? []).filter((m) => checkinRoles.has(m.role) && matchesSearch(query, m.name, m.email, m.phone, m.role));
  const table = useTable(members, [
    { key: "name", label: "Name", sort: (m) => m.name },
    { key: "role", label: "Role", sort: (m) => m.role, filter: (m) => m.role },
    { key: "events", label: "Events", sort: (m) => m.module_events, filter: (m) => (m.module_events ? "On" : "Off"), filterLabel: "Events access" },
    { key: "mobilization", label: "Mobilization", sort: (m) => m.module_mobilization, filter: (m) => (m.module_mobilization ? "On" : "Off"), filterLabel: "Mobilization access" },
    { key: "status", label: "Status", sort: (m) => m.active, filter: (m) => (m.active ? "Active" : "Inactive") },
  ]);
  const canEdit = (m: Member) => m.role !== "owner" && m.id !== me?.id && (m.role !== "admin" || me?.role === "owner");
  const update = (m: Member, body: Partial<Member>) => {
    setErr(null);
    api.updateMember(m.id, body).then(reload, (e: Error) => setErr(e.message));
  };

  return (
    <>
      <PageHeader title="Team" subtitle="Roles decide what each person can see and change." actions={<button className="btn" onClick={() => setAdding(true)}>+ Add member</button>} />
      <ErrorNote error={error ?? err} />
      <Card>
        <div className="toolbar"><SearchInput label="Search team members" value={query} onChange={setQuery} /></div>
        {table.filterBar}
        {!data ? <Loading /> : (
          <div className="table-wrap">
            <table>
              <thead>{table.head}</thead>
              <tbody>
                {table.rows.map((m) => (
                  <tr key={m.id}>
                    <td>
                      <div className="person">
                        <span className="avatar">{initials(m.name)}</span>
                        <div><div style={{ fontWeight: 600 }}>{m.name}</div><small className="muted">{m.email}{m.phone && ` · ${m.phone}`}</small></div>
                        {canEdit(m) && m.active && (
                          <button className="btn small secondary" style={{ marginLeft: "auto" }} onClick={() =>
                            api.sendInvite(m.id).then((r) => window.alert(`Invitation emailed to ${r.sent_to}.`), (e: Error) => setErr(e.message))}>
                            Send invite
                          </button>
                        )}
                      </div>
                    </td>
                    <td>
                      {canEdit(m) ? (
                        <select className="input" style={{ width: 120 }} value={m.role} onChange={(e) => update(m, { role: e.target.value as Role })}>
                          {me?.role === "owner" && <option value="admin">admin</option>}
                          <option value="member">member</option>
                          <option value="viewer">viewer</option>
                        </select>
                      ) : <Badge tone={roleTone[m.role]}>{m.role}</Badge>}
                    </td>
                    <td><Toggle label="" checked={m.module_events} disabled={!canEdit(m)} onChange={(v) => update(m, { module_events: v })} /></td>
                    <td><Toggle label="" checked={m.module_mobilization} disabled={!canEdit(m)} onChange={(v) => update(m, { module_mobilization: v })} /></td>
                    <td>
                      {canEdit(m) ? (
                        <button className={`btn small ${m.active ? "secondary" : ""}`} onClick={() => update(m, { active: !m.active })}>
                          {m.active ? "Deactivate" : "Reactivate"}
                        </button>
                      ) : m.active ? <Badge tone="green">Active</Badge> : <Badge>Inactive</Badge>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
      {adding && <AddMemberModal ownerView={me?.role === "owner"} onClose={() => setAdding(false)} onAdded={() => { setAdding(false); reload(); }} />}
    </>
  );
}

function AddMemberModal({ ownerView, onClose, onAdded }: { ownerView: boolean; onClose: () => void; onAdded: () => void }) {
  const [f, setF] = useState({ name: "", email: "", phone: "", role: "member" as Role, password: "" });
  const [error, setError] = useState<string | null>(null);
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value });

  function submit(e: FormEvent) {
    e.preventDefault();
    api.createMember({ ...f, phone: f.phone || null, password: f.password || undefined }).then((m) => {
      if (m.invited) window.alert(`Invitation emailed to ${m.email}. The link works once and expires in 3 days.`);
      onAdded();
    }, (err: Error) => setError(err.message));
  }

  return (
    <Modal title="Add team member" onClose={onClose}>
      <form onSubmit={submit}>
        <ErrorNote error={error} />
        <div className="form-grid">
          <div className="full"><Field label="Full name"><input required value={f.name} onChange={set("name")} /></Field></div>
          <Field label="Email"><input type="email" required value={f.email} onChange={set("email")} /></Field>
          <Field label="Phone"><input type="tel" value={f.phone} onChange={set("phone")} /></Field>
          <Field label="Role">
            <select value={f.role} onChange={set("role")}>
              {ownerView && <option value="admin">Admin — full access to events & mobilization</option>}
              <option value="member">Member — day-to-day field work</option>
              <option value="viewer">Viewer — read-only</option>
            </select>
          </Field>
          <Field label="Initial password (optional)" hint="Leave blank to email them a single-use invitation link (expires in 3 days).">
            <input type="text" minLength={8} value={f.password} onChange={set("password")} placeholder="Blank = send invitation" />
          </Field>
        </div>
        <div className="modal-actions">
          <button type="button" className="btn secondary" onClick={onClose}>Cancel</button>
          <button className="btn">Add member</button>
        </div>
      </form>
    </Modal>
  );
}
