import { useState, type FormEvent } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "../auth";
import { Field } from "../components/ui";
import { isSdicsBrand } from "../brand";

export default function Login() {
  const { signIn } = useAuth();
  const sdics = isSdicsBrand();
  const [login, setLogin] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await signIn(login, password);
    } catch (err) {
      setError((err as Error).message || "Login failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="login">
      <form className="card stack" onSubmit={submit}>
        {sdics ? (
          <div className="brand">
            <span className="brand-mark">SD</span>
            <span>SDICS Checkin<small className="brand-sub">Chiefs training · Republic of Kenya</small></span>
          </div>
        ) : (
          <div className="brand">
            <span className="brand-mark" style={{ color: "#fff" }}>✓</span> Checkin
          </div>
        )}
        <p className="muted" style={{ margin: 0 }}>{sdics ? "Sign in with the account your SDICS admin gave you." : "Sign in to your organization."}</p>
        {error && <div className="alert red">{error}</div>}
        <Field label="User ID or email">
          <input autoFocus autoComplete="username" value={login} onChange={(e) => setLogin(e.target.value)} required />
        </Field>
        <Field label="Password">
          <input type="password" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} required />
        </Field>
        <button className="btn" disabled={busy}>{busy ? "Signing in…" : "Sign In"}</button>
        <Link to="/forgot" className="muted" style={{ textAlign: "center" }}>Forgot password?</Link>
      </form>
    </div>
  );
}
