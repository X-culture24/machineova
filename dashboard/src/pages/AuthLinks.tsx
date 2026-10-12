import { useState, type FormEvent } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { api } from "../api";
import { Field } from "../components/ui";

/** "Forgot password?" — emails a single-use reset link (same answer whether or not the account exists). */
export function ForgotPage() {
  const [login, setLogin] = useState("");
  const [done, setDone] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      setDone((await api.forgotPassword(login)).message);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="login">
      <form className="card stack" onSubmit={submit}>
        <div className="brand"><span className="brand-mark" style={{ color: "#fff" }}>✓</span> Checkin</div>
        <h2 style={{ margin: 0 }}>Reset your password</h2>
        {done ? (
          <div className="alert green">{done}</div>
        ) : (
          <>
            <p className="muted" style={{ margin: 0 }}>Enter the email or user ID your account was created with.</p>
            {error && <div className="alert red">{error}</div>}
            <Field label="User ID or email">
              <input autoFocus value={login} onChange={(e) => setLogin(e.target.value)} required />
            </Field>
            <button className="btn" disabled={busy}>{busy ? "Sending…" : "Email me a reset link"}</button>
          </>
        )}
        <Link to="/" className="muted">← Back to sign in</Link>
      </form>
    </div>
  );
}

/** Lands from an emailed link: /reset?token=… or /accept?token=… (invitation). */
export function SetPasswordPage({ mode }: { mode: "reset" | "accept" }) {
  const [params] = useSearchParams();
  const tokenParam = params.get("token") ?? "";
  const [pw, setPw] = useState("");
  const [pw2, setPw2] = useState("");
  const [done, setDone] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (pw !== pw2) {
      setError("The passwords don't match.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const r = await api.redeemLink(tokenParam, pw);
      setDone(r.email);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="login">
      <form className="card stack" onSubmit={submit}>
        <div className="brand"><span className="brand-mark" style={{ color: "#fff" }}>✓</span> Checkin</div>
        <h2 style={{ margin: 0 }}>{mode === "accept" ? "Welcome — set your password" : "Choose a new password"}</h2>
        {done ? (
          <>
            <div className="alert green">Password set for {done}. You can sign in now, on the web or in the field app.</div>
            <Link to="/" className="btn">Go to sign in</Link>
          </>
        ) : !tokenParam ? (
          <div className="alert red">This link is incomplete. Open the link from your email again.</div>
        ) : (
          <>
            {error && <div className="alert red">{error}</div>}
            <Field label="New password" hint="At least 8 characters.">
              <input type="password" autoComplete="new-password" minLength={8} required value={pw} onChange={(e) => setPw(e.target.value)} />
            </Field>
            <Field label="Repeat password">
              <input type="password" autoComplete="new-password" minLength={8} required value={pw2} onChange={(e) => setPw2(e.target.value)} />
            </Field>
            <button className="btn" disabled={busy}>{busy ? "Saving…" : "Set password"}</button>
          </>
        )}
      </form>
    </div>
  );
}
