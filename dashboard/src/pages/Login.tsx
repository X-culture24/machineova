import { useState, type FormEvent } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "../auth";
import { Field } from "../components/ui";
import { isSdicsBrand } from "../brand";
import type { OtpChallenge } from "../api";

export default function Login() {
  const { signIn, verifyOtp } = useAuth();
  const [challenge, setChallenge] = useState<OtpChallenge | null>(null);
  const [code, setCode] = useState("");
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
      if (challenge) {
        await verifyOtp(challenge.otp_token, code.trim());
        return;
      }
      const res = await signIn(login, password);
      if ("otp_required" in res) {
        setChallenge(res);
        setCode("");
      }
    } catch (err) {
      // An expired code (or too many wrong ones) needs a fresh sign-in.
      if (challenge && (err as { code?: string }).code === "otp_expired") {
        setChallenge(null);
        setPassword("");
      }
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
        {challenge ? (
          <>
            <p style={{ margin: 0 }}>
              A 6-digit sign-in code was emailed to <b>{challenge.sent_to}</b>. Enter it below. It works once, for{" "}
              {Math.round(challenge.expires_in / 60)} minutes.
            </p>
            <Field label="Sign-in code">
              <input
                autoFocus
                inputMode="numeric"
                autoComplete="one-time-code"
                pattern="[0-9]{6}"
                maxLength={6}
                value={code}
                onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
                required
              />
            </Field>
            <button className="btn" disabled={busy || code.length !== 6}>{busy ? "Checking…" : "Verify and sign in"}</button>
            <button type="button" className="btn ghost" onClick={() => { setChallenge(null); setPassword(""); setError(null); }}>
              Back
            </button>
          </>
        ) : (
          <>
            <Field label="User ID or email">
              <input autoFocus autoComplete="username" value={login} onChange={(e) => setLogin(e.target.value)} required />
            </Field>
            <Field label="Password">
              <input type="password" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} required />
            </Field>
            <button className="btn" disabled={busy}>{busy ? "Signing in…" : "Sign In"}</button>
            <Link to="/forgot" className="muted" style={{ textAlign: "center" }}>Forgot password?</Link>
          </>
        )}
      </form>
    </div>
  );
}
