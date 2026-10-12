import { useState, type FormEvent } from "react";
import { api } from "../api";
import { useAuth } from "../auth";
import { Card, Field, PageHeader } from "../components/ui";

export default function AccountPage() {
  const { me, signOut } = useAuth();
  const [f, setF] = useState({ current: "", next: "", confirm: "" });
  const [msg, setMsg] = useState<{ tone: "green" | "red"; text: string } | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (f.next !== f.confirm) return setMsg({ tone: "red", text: "New passwords don't match." });
    try {
      await api.changePassword(f.current, f.next);
      setF({ current: "", next: "", confirm: "" });
      setMsg({ tone: "green", text: "Password changed." });
    } catch (err) {
      setMsg({ tone: "red", text: (err as Error).message });
    }
  }

  return (
    <>
      <PageHeader title="Account" />
      <div className="grid cols-even" style={{ alignItems: "start" }}>
        <Card title="Profile">
          <div className="stack">
            <div className="row spread"><span className="muted">Name</span><strong>{me?.name}</strong></div>
            <div className="row spread"><span className="muted">Email</span><strong>{me?.email}</strong></div>
            <div className="row spread"><span className="muted">Role</span><strong>{me?.platform_admin && !me.organization ? "Platform admin" : me?.role}</strong></div>
            {me?.organization && <div className="row spread"><span className="muted">Organization</span><strong>{me.organization.name}</strong></div>}
            <button className="btn secondary" onClick={signOut}>Sign out</button>
          </div>
        </Card>
        <Card title="Change password">
          <form className="stack" onSubmit={submit}>
            {msg && <div className={`alert ${msg.tone}`}>{msg.text}</div>}
            <Field label="Current password"><input type="password" required autoComplete="current-password" value={f.current} onChange={(e) => setF({ ...f, current: e.target.value })} /></Field>
            <Field label="New password"><input type="password" required minLength={8} autoComplete="new-password" value={f.next} onChange={(e) => setF({ ...f, next: e.target.value })} /></Field>
            <Field label="Confirm new password"><input type="password" required minLength={8} autoComplete="new-password" value={f.confirm} onChange={(e) => setF({ ...f, confirm: e.target.value })} /></Field>
            <button className="btn">Change password</button>
          </form>
        </Card>
      </div>
    </>
  );
}
