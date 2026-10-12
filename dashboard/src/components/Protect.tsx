import { useEffect, useState } from "react";

/**
 * Deterrents for screenshots and printing of voter data. Browsers cannot block OS-level
 * screenshots, so this layers what a web page can do:
 *  - content blurs whenever the window loses focus (most snipping tools take focus) and on
 *    the Print Screen key (which also clears the clipboard);
 *  - printing the app prints a notice instead of data (report exports open their own window);
 *  - a faint watermark with the signed-in user and time makes any leaked image traceable.
 */
export default function Protect({ who }: { who: string }) {
  const [hidden, setHidden] = useState(false);
  const [now, setNow] = useState(() => new Date());

  useEffect(() => {
    const blur = () => setHidden(true);
    const focus = () => setHidden(false);
    const vis = () => setHidden(document.visibilityState !== "visible");
    const key = (e: KeyboardEvent) => {
      if (e.key === "PrintScreen" || (e.metaKey && e.shiftKey && ["3", "4", "5"].includes(e.key))) {
        setHidden(true);
        navigator.clipboard?.writeText("").catch(() => {});
        setTimeout(() => setHidden(!document.hasFocus()), 1500);
      }
    };
    window.addEventListener("blur", blur);
    window.addEventListener("focus", focus);
    document.addEventListener("visibilitychange", vis);
    window.addEventListener("keyup", key);
    window.addEventListener("keydown", key);
    const t = setInterval(() => setNow(new Date()), 60_000);
    return () => {
      window.removeEventListener("blur", blur);
      window.removeEventListener("focus", focus);
      document.removeEventListener("visibilitychange", vis);
      window.removeEventListener("keyup", key);
      window.removeEventListener("keydown", key);
      clearInterval(t);
    };
  }, []);

  useEffect(() => {
    document.documentElement.classList.toggle("privacy-blur", hidden);
  }, [hidden]);

  const stamp = `${who} · ${now.toLocaleString([], { dateStyle: "medium", timeStyle: "short" })}`;
  return (
    <>
      <div className="watermark" aria-hidden>
        {Array.from({ length: 24 }, (_, i) => (
          <span key={i}>{stamp}</span>
        ))}
      </div>
      {hidden && (
        <div className="privacy-shield" role="status">
          <strong>Voter data hidden</strong>
          <span>Click back into this window to continue.</span>
        </div>
      )}
      <div className="print-notice">Printing is disabled — this page contains voter data. Use Reports to export.</div>
    </>
  );
}
