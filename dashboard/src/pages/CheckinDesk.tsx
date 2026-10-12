import { useEffect, useRef, useState, type FormEvent } from "react";
import { useSearchParams } from "react-router-dom";
import { ApiError, api, type Lookup } from "../api";
import { Badge, Card, Empty, ErrorNote, Field, Loading, PageHeader, RegionBadge, Toggle } from "../components/ui";
import { area, initials, time } from "../format";
import { useAsync } from "../useAsync";

type Flash = { tone: "green" | "amber" | "red"; text: string } | null;

export default function CheckinDesk() {
  const [params, setParams] = useSearchParams();
  const events = useAsync(() => api.events(true), []);
  const items = events.data?.items ?? [];
  const eventId = params.get("event") ?? (items.length === 1 ? items[0]!.id : "");
  const event = items.find((e) => e.id === eventId);

  const [nid, setNid] = useState("");
  const [lookup, setLookup] = useState<Lookup | null>(null);
  const [busy, setBusy] = useState(false);
  const [flash, setFlash] = useState<Flash>(null);
  const idRef = useRef<HTMLInputElement>(null);

  // Confirm form state.
  const [phone, setPhone] = useState("");
  const [manual, setManual] = useState({ name: "", sex: "", dob: "" });
  const [outside, setOutside] = useState(false);
  const [loc, setLoc] = useState({ county: "", constituency: "", ward: "" });

  const reset = () => {
    setNid("");
    setLookup(null);
    setPhone("");
    setManual({ name: "", sex: "", dob: "" });
    setOutside(false);
    setLoc({ county: "", constituency: "", ward: "" });
    idRef.current?.focus();
  };
  useEffect(reset, [eventId]);

  async function doLookup(e: FormEvent) {
    e.preventDefault();
    if (!eventId || !nid.trim()) return;
    setBusy(true);
    setFlash(null);
    try {
      setLookup(await api.checkinLookup(eventId, nid));
    } catch (err) {
      setLookup(null);
      setFlash({ tone: "red", text: `Can't look up: ${(err as Error).message}` });
    } finally {
      setBusy(false);
    }
  }

  async function doCheckin(e: FormEvent) {
    e.preventDefault();
    if (!lookup) return;
    setBusy(true);
    try {
      const res = await api.checkin(eventId, {
        national_id: nid,
        phone,
        ...(lookup.in_register ? {} : manual),
        ...(outside || !lookup.in_register ? loc : {}),
      });
      setFlash({ tone: "green", text: `✓ ${res.name} checked in${res.in_region ? "" : " (out of region)"}` });
      reset();
    } catch (err) {
      const code = err instanceof ApiError ? err.code : undefined;
      setFlash({ tone: code === "already_checked_in" ? "amber" : "red", text: (err as Error).message });
    } finally {
      setBusy(false);
    }
  }

  const v = lookup?.voter;
  return (
    <>
      <PageHeader title="Check-in" subtitle="Scan or enter an ID to mark a voter present." />
      <ErrorNote error={events.error} />
      {!events.data ? (
        <Loading />
      ) : items.length === 0 ? (
        <Card><Empty>You're not assigned to any active event. Ask an admin to assign you.</Empty></Card>
      ) : (
        <div className="grid cols-even" style={{ alignItems: "start" }}>
          <Card title="Find a voter">
            <div className="stack">
              {items.length > 1 ? (
                <Field label="Event">
                  <select value={eventId} onChange={(e) => setParams(e.target.value ? { event: e.target.value } : {})}>
                    <option value="">Select your event…</option>
                    {items.map((e) => <option key={e.id} value={e.id}>{e.name}</option>)}
                  </select>
                </Field>
              ) : (
                <div className="alert teal">Selected event: <strong>{event?.name}</strong></div>
              )}
              {event && (
                <div className="row gap">
                  {event.region_restricted && <Badge tone="amber">Region-restricted · {area(event.county, event.constituency, event.ward)}</Badge>}
                  {event.list_only && <Badge tone="blue">List-only</Badge>}
                </div>
              )}
              <form onSubmit={doLookup} className="stack">
                <Field label="ID number">
                  <input ref={idRef} className="big-input" inputMode="numeric" autoComplete="off" value={nid}
                    onChange={(e) => { setNid(e.target.value); setLookup(null); }} disabled={!eventId} />
                </Field>
                <button className="btn" disabled={busy || !eventId || !nid.trim()}>Look up</button>
              </form>
              {flash && <div className={`alert ${flash.tone}`}>{flash.text}</div>}
            </div>
          </Card>

          <Card title="Confirm & check in">
            {!lookup ? (
              <Empty>Look up an ID to see the voter's details.</Empty>
            ) : lookup.status === "not_on_list" ? (
              <div className="alert red">Not on the participant list — this event is list-only and this ID isn't approved.</div>
            ) : lookup.status === "already_checked_in" ? (
              <div className="alert amber">
                Already checked in today{lookup.previous && ` at ${time(lookup.previous.at)} by ${lookup.previous.by}`}. Move on to the next voter.
                <div style={{ marginTop: 10 }}><button className="btn small secondary" onClick={reset}>Next voter</button></div>
              </div>
            ) : (
              <form onSubmit={doCheckin} className="stack">
                {v ? (
                  <div className="voter-card">
                    <span className="avatar">{initials(v.name)}</span>
                    <div style={{ flex: 1 }}>
                      <div style={{ fontWeight: 700, fontSize: 16 }}>{v.name}</div>
                      <small className="muted">
                        {[`ID ${v.national_id}`, v.sex === "F" ? "Female" : v.sex === "M" ? "Male" : "Sex unknown", v.dob && `${v.age} yrs`]
                          .filter(Boolean)
                          .join(" · ")}
                      </small>
                      <div><small>{area(v.county, v.constituency, v.ward, v.polling_center)}</small></div>
                      {v.registered_on && <div><small className="muted">Registered {v.registered_on}</small></div>}
                      {v.source === "id_registry" && <div><small className="muted">Identity from national ID records</small></div>}
                    </div>
                    <div className="stack" style={{ gap: 4, alignItems: "flex-end" }}>
                      {v.source === "id_registry" ? (
                        <Badge tone="amber">NOT REGISTERED TO VOTE</Badge>
                      ) : (
                        <Badge tone="teal">REGISTERED VOTER</Badge>
                      )}
                      <RegionBadge inRegion={lookup.in_region ?? true} />
                    </div>
                  </div>
                ) : (
                  <>
                    <div className="alert amber">Not found in the register — fill in their details.</div>
                    <div className="form-grid">
                      <div className="full"><Field label="Full name"><input required value={manual.name} onChange={(e) => setManual({ ...manual, name: e.target.value })} /></Field></div>
                      <Field label="Sex">
                        <select required value={manual.sex} onChange={(e) => setManual({ ...manual, sex: e.target.value })}>
                          <option value="">—</option><option value="F">Female</option><option value="M">Male</option>
                        </select>
                      </Field>
                      <Field label="Date of birth"><input type="date" value={manual.dob} onChange={(e) => setManual({ ...manual, dob: e.target.value })} /></Field>
                    </div>
                  </>
                )}
                <Field label="Phone"><input type="tel" placeholder="+254…" value={phone} onChange={(e) => setPhone(e.target.value)} /></Field>
                {v && <Toggle label="Registered outside this region" checked={outside} onChange={setOutside} />}
                {(outside || !v) && (
                  <div className="form-grid">
                    <Field label="County"><input required value={loc.county} onChange={(e) => setLoc({ ...loc, county: e.target.value })} /></Field>
                    <Field label="Constituency"><input required value={loc.constituency} onChange={(e) => setLoc({ ...loc, constituency: e.target.value })} /></Field>
                    <div className="full"><Field label="Ward"><input required value={loc.ward} onChange={(e) => setLoc({ ...loc, ward: e.target.value })} /></Field></div>
                  </div>
                )}
                <button className="btn" disabled={busy}>{busy ? "Checking in…" : "Check in"}</button>
              </form>
            )}
          </Card>
        </div>
      )}
    </>
  );
}
