import { useState } from "react";
import { api, type Member } from "../api";
import { useAsync } from "../useAsync";
import { ErrorNote, Loading, Modal } from "./ui";

/** Pick which team members are assigned to an event or drive. */
export function AssignModal({ title, current, save, onClose, onSaved }: {
  title: string;
  current: Member[];
  save: (ids: string[]) => Promise<unknown>;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { data: team, error } = useAsync(api.team, []);
  const [picked, setPicked] = useState(() => new Set(current.map((m) => m.id)));
  const [busy, setBusy] = useState(false);
  const [saveErr, setSaveErr] = useState<string | null>(null);
  const toggle = (id: string) => {
    const next = new Set(picked);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    setPicked(next);
  };

  return (
    <Modal title={title} onClose={onClose}>
      <ErrorNote error={error ?? saveErr} />
      {!team ? (
        <Loading />
      ) : (
        <div className="checklist">
          {team.filter((m) => m.active).map((m) => (
            <label key={m.id}>
              <input type="checkbox" checked={picked.has(m.id)} onChange={() => toggle(m.id)} />
              <span style={{ flex: 1 }}>
                {m.name} <small className="muted">· {m.role}</small>
              </span>
              <small className="muted">{m.email}</small>
            </label>
          ))}
        </div>
      )}
      <div className="modal-actions">
        <button className="btn secondary" onClick={onClose}>Cancel</button>
        <button
          className="btn"
          disabled={busy || !team}
          onClick={async () => {
            setBusy(true);
            try {
              await save([...picked]);
              onSaved();
            } catch (e) {
              setSaveErr((e as Error).message);
              setBusy(false);
            }
          }}
        >
          {busy ? "Saving…" : `Assign ${picked.size}`}
        </button>
      </div>
    </Modal>
  );
}
