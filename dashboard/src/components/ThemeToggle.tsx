import { useState } from "react";
import { sdTheme, setSdTheme } from "../brand";

/** Sun / moon button switching the SDICS look between dark and light (as the other dashboards). */
export default function ThemeToggle() {
  const [t, setT] = useState(sdTheme());
  const flip = () => {
    const n = t === "dark" ? "light" : "dark";
    setSdTheme(n);
    setT(n);
  };
  return (
    <button type="button" className="sd-icon-btn" onClick={flip} aria-label={t === "dark" ? "Switch to light mode" : "Switch to dark mode"}
      title={t === "dark" ? "Light mode" : "Dark mode"}>
      {t === "dark" ? (
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" aria-hidden>
          <circle cx="12" cy="12" r="4" />
          <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
        </svg>
      ) : (
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
          <path d="M20 14.5A8 8 0 0 1 9.5 4 8 8 0 1 0 20 14.5Z" />
        </svg>
      )}
    </button>
  );
}
