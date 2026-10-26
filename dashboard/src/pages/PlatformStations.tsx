import { useEffect, useState, type FormEvent } from "react";
import { api, type RegisterStation } from "../api";
import { Card, Empty, ErrorNote, Field, Kpi, Loading, Modal, PageHeader } from "../components/ui";
import { num } from "../format";
import { Pager } from "../ops/components";
import { useAsync } from "../useAsync";

/** Platform › Polling stations: the shared register, listed per area, with add / edit / delete. */
export default function PlatformStations() {
  const regions = useAsync(api.platformRegions, []);
  const [county, setCounty] = useState("");
  const [constituency, setConstituency] = useState("");
  const [ward, setWard] = useState("");
  const [q, setQ] = useState("");
  const [dq, setDq] = useState("");
  const [page, setPage] = useState(1);
  const [editing, setEditing] = useState<RegisterStation | "new" | null>(null);
  const [msg, setMsg] = useState<{ tone: "green" | "red"; text: string } | null>(null);
  useEffect(() => {
    const t = setTimeout(() => setDq(q), 250);
    return () => clearTimeout(t);
  }, [q]);
  const list = useAsync(() => api.platformStations({ county, constituency, ward, q: dq, page }), [county, constituency, ward, dq, page]);

  const counties = regions.data ?? [];
  const inCounty = counties.find((c) => c.name === county);
  const inConstituency = inCounty?.constituencies.find((k) => k.name === constituency);
  const area = ward ? `${ward} Ward` : constituency ? `${constituency} Constituency` : county ? `${county} County` : "Kenya";
  const reload = () => { list.reload(); regions.reload(); };

  async function remove(st: RegisterStation) {
    if (!confirm(`Delete ${st.name} (${st.code}) from the register?${st.elections ? ` It also leaves ${st.elections} election(s) not yet held.` : ""}`)) return;
    try {
      await api.deleteStation(st.code);
      setMsg({ tone: "green", text: `${st.name} deleted.` });
      reload();
    } catch (e) {
      setMsg({ tone: "red", text: (e as Error).message });
    }
  }

  return (
    <>
      <PageHeader title="Polling stations" subtitle="The national register, shared by every organization — changes apply to all clients"
        actions={<button className="btn" onClick={() => setEditing("new")}>+ Add station</button>} />
      {msg && <div className={`alert ${msg.tone}`}>{msg.text}</div>}
      <ErrorNote error={regions.error ?? list.error} />
      <div className="toolbar">
        <select className="input" value={county} onChange={(e) => { setCounty(e.target.value); setConstituency(""); setWard(""); setPage(1); }}>
          <option value="">All counties</option>
          {counties.map((c) => <option key={c.name} value={c.name}>{c.name} ({num(c.stations)})</option>)}
        </select>
        <select className="input" value={constituency} disabled={!inCounty} onChange={(e) => { setConstituency(e.target.value); setWard(""); setPage(1); }}>
          <option value="">{inCounty ? "All constituencies" : "Pick a county first"}</option>
          {inCounty?.constituencies.map((k) => <option key={k.name} value={k.name}>{k.name} ({num(k.stations)})</option>)}
        </select>
        <select className="input" value={ward} disabled={!inConstituency} onChange={(e) => { setWard(e.target.value); setPage(1); }}>
          <option value="">{inConstituency ? "All wards" : "Pick a constituency first"}</option>
          {inConstituency?.wards.map((w) => <option key={w.name} value={w.name}>{w.name} ({num(w.stations)})</option>)}
        </select>
        <input className="input" placeholder="Search name or code…" value={q} onChange={(e) => { setQ(e.target.value); setPage(1); }} />
      </div>
      <div className="grid kpis">
        <Kpi label={`Stations — ${area}`} value={list.data ? num(list.data.total) : "–"} tone="teal" />
        <Kpi label="Registered voters" value={list.data ? num(list.data.registered_voters) : "–"} />
      </div>
      <Card>
        {!list.data ? <Loading /> : list.data.items.length === 0 ? <Empty>No stations in {area}{dq && " match"}.</Empty> : (
          <>
            <div className="table-wrap">
              <table className="cards">
                <thead><tr><th>Station</th><th>Ward</th><th>Constituency</th>{!county && <th>County</th>}<th className="num">Reg. voters</th><th className="num">Elections</th><th /></tr></thead>
                <tbody>
                  {list.data.items.map((s) => (
                    <tr key={s.code}>
                      <td data-label="Station"><div style={{ fontWeight: 600 }}>{s.name}</div><small className="muted">{s.code}</small></td>
                      <td data-label="Ward">{s.ward}</td>
                      <td data-label="Constituency">{s.constituency}</td>
                      {!county && <td data-label="County">{s.county}</td>}
                      <td data-label="Reg. voters" className="num">{num(s.registered_voters)}</td>
                      <td data-label="Elections" className="num">{num(s.elections)}</td>
                      <td className="num">
                        <span className="row gap" style={{ justifyContent: "flex-end" }}>
                          <button className="btn small secondary" onClick={() => setEditing(s)}>Edit</button>
                          <button className="btn small ghost" disabled={s.in_use} onClick={() => remove(s)}
                            title={s.in_use ? "Has election records — edit it instead" : "Delete from the register"}>Delete</button>
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <Pager page={page} pageSize={list.data.page_size} total={list.data.total} onPage={setPage} />
          </>
        )}
      </Card>
      {editing && (
        <StationForm station={editing === "new" ? null : editing} counties={regions.data ?? []} defaults={{ county, constituency, ward }}
          onClose={() => setEditing(null)}
          onSaved={(text) => { setEditing(null); setMsg({ tone: "green", text }); reload(); }} />
      )}
    </>
  );
}

function StationForm({ station, counties, defaults, onClose, onSaved }: {
  station: RegisterStation | null;
  counties: { name: string; constituencies: { name: string; wards: { name: string }[] }[] }[];
  defaults: { county: string; constituency: string; ward: string };
  onClose: () => void;
  onSaved: (message: string) => void;
}) {
  const [f, setF] = useState({
    name: station?.name ?? "",
    county: station?.county ?? defaults.county,
    constituency: station?.constituency ?? defaults.constituency,
    ward: station?.ward ?? defaults.ward,
    registered: String(station?.registered_voters ?? ""),
  });
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value });
  const constituencies = counties.find((c) => c.name === f.county)?.constituencies ?? [];
  const wards = constituencies.find((k) => k.name === f.constituency)?.wards ?? [];
  const known = wards.some((w) => w.name.toLowerCase() === f.ward.trim().toLowerCase());

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const registered = Number(f.registered);
    try {
      if (station) {
        await api.updateStation(station.code, { name: f.name.trim(), ward: f.ward.trim(), registered_voters: registered });
        onSaved(`${f.name.trim()} updated.`);
      } else {
        const r = await api.createStation({ name: f.name.trim(), county: f.county, constituency: f.constituency, ward: f.ward.trim(), registered_voters: registered });
        onSaved(`${r.station.name} added as ${r.station.code}${r.added_to_elections ? ` — also added to ${r.added_to_elections} election(s) not yet held` : ""}.`);
      }
    } catch (x) {
      setError((x as Error).message);
      setBusy(false);
    }
  }

  return (
    <Modal title={station ? `Edit ${station.name}` : "Add polling station"} onClose={onClose}>
      <form onSubmit={submit}>
        {station && <p className="muted modal-sub">{station.code} · {station.constituency}, {station.county}. The code stays the same, so elections keep their records.</p>}
        <ErrorNote error={error} />
        <div className="form-grid">
          {!station && (
            <>
              <Field label="County">
                <select required value={f.county} onChange={(e) => setF({ ...f, county: e.target.value, constituency: "", ward: "" })}>
                  <option value="">Choose…</option>
                  {counties.map((c) => <option key={c.name}>{c.name}</option>)}
                </select>
              </Field>
              <Field label="Constituency">
                <select required value={f.constituency} disabled={!f.county} onChange={(e) => setF({ ...f, constituency: e.target.value, ward: "" })}>
                  <option value="">Choose…</option>
                  {constituencies.map((k) => <option key={k.name}>{k.name}</option>)}
                </select>
              </Field>
            </>
          )}
          <Field label="Ward" hint={f.ward.trim() && !known && f.constituency ? "New ward — it will be created in this constituency." : undefined}>
            <input required list="ward-options" value={f.ward} disabled={!station && !f.constituency} onChange={set("ward")} placeholder="Pick or type a ward" />
            <datalist id="ward-options">{wards.map((w) => <option key={w.name} value={w.name} />)}</datalist>
          </Field>
          <Field label="Registered voters">
            <input required type="number" min={0} inputMode="numeric" value={f.registered} onChange={set("registered")} />
          </Field>
          <div className="full"><Field label="Polling station name"><input required value={f.name} onChange={set("name")} placeholder="e.g. Kakrao Primary School" /></Field></div>
        </div>
        <div className="modal-actions">
          <button type="button" className="btn secondary" onClick={onClose}>Cancel</button>
          <button className="btn" disabled={busy}>{busy ? "Saving…" : station ? "Save changes" : "Add station"}</button>
        </div>
      </form>
    </Modal>
  );
}
