import { useEffect, useState, type FormEvent } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "../auth";
import { Field } from "../components/ui";
import { isSdicsBrand } from "../brand";
import BrandMark from "../components/BrandMark";
import ThemeToggle from "../components/ThemeToggle";
import { Icon } from "../components/icons";
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
  const [showPw, setShowPw] = useState(false);
  const [now, setNow] = useState(new Date());
  useEffect(() => {
    const t = setInterval(() => setNow(new Date()), 30_000);
    return () => clearInterval(t);
  }, []);

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

  const otpStep = challenge && (
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
      <button className={sdics ? "sd-submit" : "btn"} disabled={busy || code.length !== 6}>{busy ? "Checking…" : "Verify and sign in"}</button>
      <button type="button" className="btn ghost" onClick={() => { setChallenge(null); setPassword(""); setError(null); }}>
        Back
      </button>
    </>
  );

  if (sdics) {
    // As the other SDICS dashboards (analytics, RRI): the brand panel on the left, the sign-in card on the right.
    const features: [Parameters<typeof Icon>[0]["name"], string, string][] = [
      ["check", "Check in member", "Check in by ID number at each event."],
      ["calendar", "Events by area", "See attendance for each event."],
      ["chart", "Event report", "Who attended, with their phone numbers, ready to export."],
    ];
    return (
      <div className="sd-login">
        <aside className="sd-login-brand">
          <span className="sd-ring sd-ring-1" aria-hidden />
          <span className="sd-ring sd-ring-2" aria-hidden />
          <div className="sd-login-org">
            <img className="sd-coat" src="/sdics-logo.jpeg" alt="Kenya coat of arms" />
            <div>
              <div className="sd-kicker">REPUBLIC OF KENYA</div>
              <div>Registration Drive Monitoring</div>
            </div>
          </div>
          <div className="sd-login-pitch">
            <h1>SDICS CHECKIN</h1>
            <p className="sd-tagline">Track attendance at SDICS events.</p>
            <div className="sd-features">
              {features.map(([icon, title, text]) => (
                <div key={title} className="sd-feature">
                  <span className="sd-feature-icon"><Icon name={icon} size={20} /></span>
                  <div><b>{title}</b><span>{text}</span></div>
                </div>
              ))}
            </div>
          </div>
          <div className="sd-login-foot">
            <div>{now.toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long", year: "numeric" })} · {now.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" })}</div>
            <div className="sd-flag" aria-hidden><i /><i /><i /></div>
          </div>
        </aside>
        <section className="sd-login-side">
          <div className="sd-theme-corner"><ThemeToggle /></div>
          <form className="sd-login-card" onSubmit={submit}>
            <div className="sd-flag sd-flag-thin" aria-hidden><i /><i /><i /></div>
            <div className="sd-login-body stack">
              <div className="sd-login-mobile-head">
                <img className="sd-coat" src="/sdics-logo.jpeg" alt="Kenya coat of arms" />
                <strong>SDICS CHECKIN</strong>
              </div>
              <div>
                <h2>{challenge ? "Verify sign-in" : "Sign in"}</h2>
                <p className="sub">{challenge ? "This account needs a one-time code." : "Use your SDICS Checkin account to continue."}</p>
              </div>
              {error && <div className="alert red">{error}</div>}
              {challenge ? otpStep : (
                <>
                  <div className="sd-field">
                    <label htmlFor="sd-login">User ID or email</label>
                    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinejoin="round" aria-hidden>
                      <rect x="3" y="5" width="18" height="14" rx="2" /><path d="m4 7 8 6 8-6" />
                    </svg>
                    <input id="sd-login" autoFocus autoComplete="username" value={login} onChange={(e) => setLogin(e.target.value)} required />
                  </div>
                  <div className="sd-field">
                    <label htmlFor="sd-password">Password</label>
                    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinejoin="round" aria-hidden>
                      <rect x="5" y="10.5" width="14" height="10" rx="2" /><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5" /><path d="M12 14.5v2" />
                    </svg>
                    <input id="sd-password" type={showPw ? "text" : "password"} autoComplete="current-password" value={password}
                      onChange={(e) => setPassword(e.target.value)} required />
                    <button type="button" className="sd-eye" onClick={() => setShowPw((v) => !v)} aria-label={showPw ? "Hide password" : "Show password"}>
                      <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
                        {showPw
                          ? <path d="M12 7c2.8 0 5 2.2 5 5 0 .6-.1 1.3-.4 1.8l2.9 2.9c1.5-1.3 2.7-2.9 3.4-4.7-1.7-4.4-6-7.5-11-7.5-1.4 0-2.7.3-4 .7l2.2 2.2c.6-.3 1.2-.4 1.9-.4ZM2 4.3l2.3 2.3.5.5C3.1 8.4 1.8 10.1 1 12c1.7 4.4 6 7.5 11 7.5 1.5 0 3-.3 4.4-.8l.4.4 2.9 2.9 1.3-1.3L3.3 3 2 4.3Zm5.5 5.5 1.5 1.5c0 .2-.1.5-.1.7 0 1.7 1.3 3 3 3 .2 0 .5 0 .7-.1l1.5 1.5c-.7.3-1.4.6-2.2.6-2.8 0-5-2.2-5-5 0-.8.2-1.5.6-2.2Zm4.3-.8 3.1 3.1V12c0-1.7-1.3-3-3-3h-.1Z" />
                          : <path d="M12 4.5C7 4.5 2.7 7.6 1 12c1.7 4.4 6 7.5 11 7.5s9.3-3.1 11-7.5c-1.7-4.4-6-7.5-11-7.5ZM12 17c-2.8 0-5-2.2-5-5s2.2-5 5-5 5 2.2 5 5-2.2 5-5 5Zm0-8c-1.7 0-3 1.3-3 3s1.3 3 3 3 3-1.3 3-3-1.3-3-3-3Z" />}
                      </svg>
                    </button>
                  </div>
                  <button className="sd-submit" disabled={busy}>{busy ? "Signing in…" : "Sign in"}</button>
                  <Link to="/forgot" className="muted" style={{ textAlign: "center" }}>Forgot password?</Link>
                </>
              )}
              <div className="sd-note">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinejoin="round" aria-hidden>
                  <path d="M12 3 5 6v5.5c0 4.3 3 8 7 9.5 4-1.5 7-5.2 7-9.5V6l-7-3Z" />
                </svg>
                Authorised personnel only. Sign-ins and changes are logged.
              </div>
            </div>
          </form>
        </section>
      </div>
    );
  }

  return (
    <div className="login">
      <form className="card stack" onSubmit={submit}>
        <div className="brand">
          <BrandMark text="✓" /> Checkin
        </div>
        <p className="muted" style={{ margin: 0 }}>Sign in to your organization.</p>
        {error && <div className="alert red">{error}</div>}
        {challenge ? otpStep : (
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
