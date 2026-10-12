import { useEffect, useState } from "react";
import { api } from "../api";
import { Card, ErrorNote, Loading, PageHeader } from "../components/ui";

/** The Checkin field app is distributed privately: signed-in members download it here. */
export default function FieldAppPage() {
  const [info, setInfo] = useState<{ available: boolean; size?: number; updated_at?: string } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => { api.appInfo().then(setInfo, (e: Error) => setError(e.message)); }, []);

  return (
    <>
      <PageHeader title="Field app" subtitle="The Checkin Android app for check-ins and mobilization. Not on the public app store — download it here." />
      <ErrorNote error={error} />
      <Card>
        {!info ? <Loading /> : info.available ? (
          <div className="stack">
            <div>
              <strong>Checkin for Android</strong>
              <div className="muted">
                {info.size ? `${(info.size / 1_048_576).toFixed(0)} MB` : ""}
                {info.updated_at ? ` · updated ${new Date(info.updated_at).toLocaleDateString()}` : ""}
              </div>
            </div>
            <button className="btn" disabled={busy} onClick={() => { setBusy(true); api.downloadApp().catch((e: Error) => setError(e.message)).finally(() => setBusy(false)); }}>
              {busy ? "Downloading…" : "Download the app (.apk)"}
            </button>
            <ol className="muted" style={{ margin: 0, paddingLeft: 18, lineHeight: 1.8 }}>
              <li>Open the downloaded file on your Android phone (or send it to the phone).</li>
              <li>Allow “Install unknown apps” when Android asks.</li>
              <li>Open Checkin and sign in with the same email and password you use here.</li>
            </ol>
          </div>
        ) : (
          <div className="muted">The field app hasn't been published on this server yet. Ask your platform administrator.</div>
        )}
      </Card>
    </>
  );
}
