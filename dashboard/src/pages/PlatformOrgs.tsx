import { useEffect, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { api } from "../api";
import { Badge, Card, Empty, ErrorNote, Field, Kpi, Loading, PageHeader, Toggle } from "../components/ui";
import { area, initials, num } from "../format";
import { useAsync } from "../useAsync";

const orgStatus = (o: { active: boolean; trial: boolean }) =>
  !o.active ? <Badge tone="red">Inactive</Badge> : o.trial ? <Badge tone="amber">Trial</Badge> : <Badge tone="green">Active</Badge>;

export default function PlatformOrgs() {
  const nav = useNavigate();
  const ov = useAsync(api.platformOverview, []);
  const { data, error } = useAsync(api.orgs, []);
  return (
    <>
      <PageHeader title="Platform overview" subtitle="MachineNova operator console — every tenant"
        actions={<Link className="btn" to="/platform/new">+ New organization</Link>} />
      <ErrorNote error={error ?? ov.error} />
      {ov.data && (
        <div className="grid kpis">
          <Kpi label="Organizations" value={num(ov.data.organizations)} caption={`${ov.data.active} active · ${ov.data.trial} trial`} />
          <Kpi label="Members" value={num(ov.data.members)} caption="Across all tenants" />
          <Kpi label="Polling stations" value={num(ov.data.stations)} caption="In active elections" tone="teal" />
          <Kpi label="Field agents" value={num(ov.data.agents)} caption="Across all tenants" tone="amber" />
        </div>
      )}
      <Card title="Organizations">
        {!data ? <Loading /> : data.length === 0 ? <Empty>No organizations yet.</Empty> : (
          <div className="table-wrap">
            <table className="cards">
              <thead><tr><th>Organization</th><th>Boundary</th><th className="num">Members</th><th className="num">Events</th><th className="num">Mobilized</th><th>Status</th><th /></tr></thead>
              <tbody>
                {data.map((o) => (
                  <tr key={o.id} className="clickable" onClick={() => nav(`/platform/orgs/${o.id}`)}>
                    <td data-label="Organization">
                      <div className="person">
                        <span className="avatar" style={{ background: o.accent_color, color: "#fff" }}>{initials(o.name)}</span>
                        <div><div style={{ fontWeight: 600 }}>{o.name}</div><small className="muted">{o.slug}</small></div>
                      </div>
                    </td>
                    <td data-label="Boundary">{area(o.boundary_county, o.boundary_constituency)}</td>
                    <td data-label="Members" className="num">{num(o.members)}</td>
                    <td data-label="Events" className="num">{num(o.events)}</td>
                    <td data-label="Mobilized" className="num">{num(o.mobilized)}</td>
                    <td data-label="Status">{orgStatus(o)}</td>
                    <td><button className="btn small secondary">Open</button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </>
  );
}

export function PlatformOrgDetail() {
  const { id = "" } = useParams();
  const nav = useNavigate();
  const d = useAsync(() => api.org(id), [id]);
  const [err, setErr] = useState<string | null>(null);
  const [confirmName, setConfirmName] = useState("");
  if (d.error) return <ErrorNote error={d.error} />;
  if (!d.data) return <Loading />;
  const { organization: o, details, admins } = d.data;
  const update = (body: { active?: boolean; trial?: boolean }) => api.updateOrg(o.id, body).then(d.reload, (e: Error) => setErr(e.message));
  return (
    <>
      <PageHeader title={o.name} subtitle={`Organization detail — bounded to ${area(o.boundary_county, o.boundary_constituency)}`}
        actions={<><Link className="btn secondary" to="/platform">‹ All organizations</Link>{orgStatus({ active: o.active, trial: details.trial })}</>} />
      <ErrorNote error={err} />
      <div className="alert teal">
        White-label accent <span className="party-dot" style={{ background: details.accent_color }} /> {details.accent_color} · Geographic boundary:{" "}
        <strong>{area(o.boundary_county, o.boundary_constituency)}</strong> — set at creation, everything inside the org is scoped to it.
      </div>
      <div className="grid kpis">
        <Kpi label="Members" value={num(o.members)} />
        <Kpi label="Stations" value={num(details.stations)} caption="in the active election" tone="teal" />
        <Kpi label="Agents" value={num(details.agents)} tone="amber" />
        <Kpi label="Voters mobilized" value={num(o.mobilized)} />
      </div>
      <div className="grid cols-even" style={{ alignItems: "start" }}>
        <Card title="Owners & admins">
          <div className="stack">
            {admins.map((a) => (
              <div key={a.id} className="agent-row">
                <span className="avatar">{initials(a.name)}</span>
                <div style={{ flex: 1 }}><div style={{ fontWeight: 600 }}>{a.name}</div><small className="muted">{a.email} · {a.role}</small></div>
              </div>
            ))}
          </div>
          <div className="stack" style={{ marginTop: 16 }}>
            <Toggle label="Active" checked={o.active} onChange={(v) => update({ active: v })} />
            <Toggle label="Trial" checked={details.trial} onChange={(v) => update({ trial: v })} />
          </div>
        </Card>
        <Card title="Danger zone" className="danger-zone">
          <p className="muted" style={{ marginTop: -6 }}>Deleting removes the organization, its members and its election data. This cannot be undone.</p>
          <Field label={`Type "${o.name}" to confirm`}><input value={confirmName} onChange={(e) => setConfirmName(e.target.value)} /></Field>
          <button className="btn danger" style={{ marginTop: 12 }} disabled={confirmName !== o.name}
            onClick={() => api.deleteOrg(o.id, confirmName).then(() => nav("/platform"), (e: Error) => setErr(e.message))}>Delete organization</button>
        </Card>
      </div>
    </>
  );
}

const steps = ["Organization", "Boundary", "Branding", "First admin", "Review"];

export function NewOrgWizard() {
  const nav = useNavigate();
  const [step, setStep] = useState(0);
  const [f, setF] = useState({
    name: "", contact_email: "", boundary_county: "", boundary_constituency: "", accent_color: "#0F8A7A", trial: false,
    owner_name: "", owner_email: "", owner_password: "",
  });
  const [error, setError] = useState<string | null>(null);
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value });
  const valid = [f.name.trim() !== "", true, /^#[0-9a-fA-F]{6}$/.test(f.accent_color),
    f.owner_name.trim() !== "" && f.owner_email.includes("@") && f.owner_password.length >= 8, true];
  return (
    <>
      <PageHeader title="New organization" subtitle="Bounded to a geography from day one" />
      <Card>
        <ol className="stepper">
          {steps.map((s, i) => <li key={s} className={i < step ? "done" : i === step ? "on" : ""}><span>{i < step ? "✓" : i + 1}</span>{s}</li>)}
        </ol>
        <ErrorNote error={error} />
        {step === 0 && (
          <div className="form-grid">
            <p className="full muted">Members simply sign in — there are no subdomains to configure.</p>
            <Field label="Organization name"><input value={f.name} placeholder="e.g. Kisii Democracy Forum" onChange={set("name")} /></Field>
            <Field label="Contact email"><input type="email" value={f.contact_email} placeholder="ops@organization.org" onChange={set("contact_email")} /></Field>
          </div>
        )}
        {step === 1 && (
          <div className="form-grid">
            <Field label="County" hint="Leave blank for a nationwide organization."><input value={f.boundary_county} onChange={set("boundary_county")} /></Field>
            <Field label="Constituency (optional)"><input value={f.boundary_constituency} disabled={!f.boundary_county} onChange={set("boundary_constituency")} /></Field>
            <p className="full muted">Names must match the polling-station register exactly. Everything inside the organization is scoped to this boundary.</p>
          </div>
        )}
        {step === 2 && (
          <div className="stack">
            <Field label="Accent color">
              <div className="row gap">
                <input type="color" value={f.accent_color} onChange={set("accent_color")} style={{ width: 52, height: 38, padding: 2 }} />
                <input value={f.accent_color} onChange={set("accent_color")} />
              </div>
            </Field>
            <Toggle label="Trial organization" checked={f.trial} onChange={(v) => setF({ ...f, trial: v })} />
          </div>
        )}
        {step === 3 && (
          <div className="form-grid">
            <div className="full"><Field label="Owner name"><input value={f.owner_name} onChange={set("owner_name")} /></Field></div>
            <Field label="Owner email"><input type="email" value={f.owner_email} onChange={set("owner_email")} /></Field>
            <Field label="Initial password" hint="8+ characters. Share securely; they can change it under Account."><input value={f.owner_password} onChange={set("owner_password")} /></Field>
          </div>
        )}
        {step === 4 && (
          <div className="stack">
            <div className="row spread"><span className="muted">Organization</span><strong>{f.name}</strong></div>
            <div className="row spread"><span className="muted">Boundary</span><strong>{area(f.boundary_county || null, f.boundary_constituency || null)}</strong></div>
            <div className="row spread"><span className="muted">Accent</span><strong><span className="party-dot" style={{ background: f.accent_color }} /> {f.accent_color}{f.trial && " · trial"}</strong></div>
            <div className="row spread"><span className="muted">Owner</span><strong>{f.owner_name} · {f.owner_email}</strong></div>
          </div>
        )}
        <div className="modal-actions">
          {step > 0 && <button className="btn secondary" onClick={() => setStep(step - 1)}>Back</button>}
          {step < steps.length - 1 ? (
            <button className="btn" disabled={!valid[step]} onClick={() => setStep(step + 1)}>Continue</button>
          ) : (
            <button className="btn" onClick={() => api.createOrg({ ...f, boundary_county: f.boundary_county || undefined, boundary_constituency: f.boundary_constituency || undefined, contact_email: f.contact_email || undefined })
              .then((o) => nav(`/platform/orgs/${o.id}`), (e: Error) => setError(e.message))}>Create organization</button>
          )}
        </div>
      </Card>
    </>
  );
}

export function EmailTemplates() {
  const t = useAsync(api.templates, []);
  const [key, setKey] = useState<string | null>(null);
  const [subject, setSubject] = useState("");
  const [body, setBody] = useState("");
  const [msg, setMsg] = useState<{ tone: "green" | "red"; text: string } | null>(null);
  const current = t.data?.templates.find((x) => x.key === (key ?? t.data?.templates[0]?.key));
  useEffect(() => {
    if (current) {
      setSubject(current.subject);
      setBody(current.body);
      setMsg(null);
    }
  }, [current?.key]); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <>
      <PageHeader title="Email templates" subtitle="Platform library" />
      <ErrorNote error={t.error} />
      {!t.data || !current ? <Loading /> : (
        <div className="grid cols-templates">
          <Card title="Platform library">
            <div className="stack" style={{ gap: 4 }}>
              {t.data.templates.map((x) => (
                <button key={x.key} className={`template-item ${x.key === current.key ? "on" : ""}`} onClick={() => setKey(x.key)}>
                  <strong>{x.name}</strong><small className="muted">{x.purpose}</small>
                </button>
              ))}
            </div>
          </Card>
          <Card title={current.name} extra={<button className="btn small" onClick={() => api.saveTemplate(current.key, subject, body)
            .then(() => { setMsg({ tone: "green", text: "Template saved." }); t.reload(); }, (e: Error) => setMsg({ tone: "red", text: e.message }))}>Save template</button>}>
            {msg && <div className={`alert ${msg.tone}`}>{msg.text}</div>}
            <div className="stack">
              <Field label="Subject"><input value={subject} onChange={(e) => setSubject(e.target.value)} /></Field>
              <Field label="Body"><textarea rows={10} value={body} onChange={(e) => setBody(e.target.value)} /></Field>
              <div>
                <small className="muted">MERGE FIELDS — click to insert</small>
                <div className="slot-chips">{t.data.merge_fields.map((m) => <button key={m} className="chip" onClick={() => setBody(body + m)}>{m}</button>)}</div>
              </div>
            </div>
          </Card>
        </div>
      )}
    </>
  );
}
