import SearchInput from "../components/SearchInput";
import { useEffect, useState, type FormEvent } from "react";
import { api, issueCategoryLabel, type Issue, type IssueCategory, type IssueInput } from "../api";
import { useAuth } from "../auth";
import { Badge, Card, Empty, ErrorNote, Field, Loading, PageHeader } from "../components/ui";
import { openIssuesReport } from "../components/issuesReportPdf";
import { useAsync, useDebounced } from "../useAsync";

// Field issues: the team types each problem reported at an event as it happens (device internet,
// device malfunction, a member's location, sign-in, the app, …), with the member concerned; the
// report compiles them with a summary of every event, exportable as PDF.

const cats = Object.keys(issueCategoryLabel) as IssueCategory[];
const blank = (eventId: string | null = null): IssueInput => ({
  event_id: eventId, category: "", chief_name: "", national_id: "", phone: "", location: "", description: "", action_taken: "", status: "open",
});
const when = (s: string) => new Date(s).toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });

export default function IssuesPage() {
  const { me } = useAuth();
  const events = useAsync(() => api.events(), []);
  const [filter, setFilter] = useState<{ event_id?: string; category?: string; status?: string }>({});
  const [query, setQuery] = useState("");
  const search = useDebounced(query);
  const list = useAsync(() => api.issues({ ...filter, q: search }), [filter.event_id, filter.category, filter.status, search]);
  const [f, setF] = useState<IssueInput>(blank());
  const [editing, setEditing] = useState<Issue | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [lookup, setLookup] = useState<string | null>(null);
  const [reportBusy, setReportBusy] = useState(false);
  const canWrite = me?.role !== "viewer";
  const admin = me?.role !== "member";

  // Start a new issue at the event in progress, when there is one.
  const trainings = events.data?.items ?? [];
  useEffect(() => {
    if (!editing && f.event_id === null && trainings.length > 0) {
      const live = trainings.find((t) => t.active);
      if (live) setF((p) => ({ ...p, event_id: live.id }));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [events.data]);

  const set = (k: keyof IssueInput) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value });

  async function findChief() {
    setLookup(null);
    if (!f.event_id || !f.national_id.trim()) return;
    try {
      const c = await api.issueChief(f.event_id, f.national_id);
      setF((p) => ({ ...p, chief_name: p.chief_name || c.name, phone: p.phone || c.phone, location: p.location || c.location }));
      setLookup(`Filled from their check-in: ${c.name}`);
    } catch {
      setLookup("Not checked in at this event: type their details.");
    }
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setErr(null);
    setNote(null);
    try {
      if (editing) {
        await api.updateIssue(editing.id, f);
        setNote("Issue updated.");
      } else {
        await api.createIssue(f);
        setNote("Issue recorded.");
      }
      setEditing(null);
      setF(blank(f.event_id));
      setLookup(null);
      list.reload();
    } catch (x) {
      setErr((x as Error).message);
    } finally {
      setBusy(false);
    }
  }

  function edit(i: Issue) {
    setEditing(i);
    setF({ event_id: i.event_id, category: i.category, chief_name: i.chief_name, national_id: i.national_id, phone: i.phone,
      location: i.location, description: i.description, action_taken: i.action_taken, status: i.status });
    setNote(null);
    setErr(null);
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  async function report() {
    setReportBusy(true);
    try {
      await openIssuesReport(api.issuesReport());
    } catch (x) {
      setErr((x as Error).message);
    } finally {
      setReportBusy(false);
    }
  }

  const items = list.data?.items ?? [];
  const open = items.filter((i) => i.status === "open").length;

  return (
    <>
      <PageHeader
        title="Field issues"
        subtitle="Record problems reported at events and the members affected."
        actions={admin && (
          <button className="btn" onClick={report} disabled={reportBusy}>{reportBusy ? "Preparing…" : "Event issues report (PDF)"}</button>
        )}
      />
      <div className="grid cols-even" style={{ alignItems: "start" }}>
        {canWrite && (
          <Card title={editing ? "Edit issue" : "Record a problem"} extra={editing && (
            <button className="btn small secondary" onClick={() => { setEditing(null); setF(blank(f.event_id)); }}>New instead</button>
          )}>
            <form onSubmit={submit} className="stack">
              <ErrorNote error={err} />
              {note && <div className="alert green">{note}</div>}
              <Field label="Event">
                <select value={f.event_id ?? ""} onChange={(e) => setF({ ...f, event_id: e.target.value || null })}>
                  <option value="">Not linked to an event</option>
                  {trainings.map((t) => <option key={t.id} value={t.id}>{t.name}{t.active ? " (open)" : ""}</option>)}
                </select>
              </Field>
              <div className="field" role="group" aria-label="Problem">
                <span>Problem</span>
                <div className="issue-cats">
                  {cats.map((c) => (
                    <button type="button" key={c} className={`issue-cat${f.category === c ? " on" : ""}`} onClick={() => setF({ ...f, category: c })}>
                      {issueCategoryLabel[c]}
                    </button>
                  ))}
                </div>
              </div>
              <div className="form-grid">
                <Field label="Member’s ID number" hint={lookup ?? (f.event_id ? "Fills the rest if they checked in here." : undefined)}>
                  <div className="row gap">
                    <input value={f.national_id} onChange={set("national_id")} onBlur={findChief} inputMode="numeric" style={{ flex: 1 }} />
                    <button type="button" className="btn small secondary" onClick={findChief} disabled={!f.event_id || !f.national_id.trim()}>Find</button>
                  </div>
                </Field>
                <Field label="Member’s name"><input value={f.chief_name} onChange={set("chief_name")} /></Field>
                <Field label="Phone number"><input value={f.phone} onChange={set("phone")} inputMode="tel" /></Field>
                <Field label="Location"><input value={f.location} onChange={set("location")} placeholder="e.g. Kapropita, Kabarnet" /></Field>
              </div>
              <Field label="What happened">
                <textarea required rows={4} value={f.description} onChange={set("description")}
                  placeholder="Describe the problem as it is: what the member saw, what was tried, error messages…" />
              </Field>
              <Field label="Action taken (optional)">
                <textarea rows={2} value={f.action_taken} onChange={set("action_taken")} placeholder="e.g. Shared a hotspot; sent to HQ to correct the location" />
              </Field>
              <Field label="Status">
                <select value={f.status} onChange={(e) => setF({ ...f, status: e.target.value as IssueInput["status"] })}>
                  <option value="open">Open: still to sort out</option>
                  <option value="resolved">Resolved</option>
                </select>
              </Field>
              <button className="btn" disabled={busy || !f.category || !f.description.trim()}>
                {busy ? "Saving…" : editing ? "Save changes" : "Record problem"}
              </button>
            </form>
          </Card>
        )}
        <Card title={`Recorded problems${items.length ? ` · ${items.length}` : ""}${open ? ` · ${open} open` : ""}`}>
          <div className="row gap" style={{ flexWrap: "wrap", marginBottom: 12 }}>
            <SearchInput label="Search issues by name, ID, phone or text" value={query} onChange={setQuery} />
            <select className="input" style={{ width: "auto", minWidth: 150 }} value={filter.event_id ?? ""} onChange={(e) => setFilter({ ...filter, event_id: e.target.value || undefined })}>
              <option value="">All events</option>
              {trainings.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
            </select>
            <select className="input" style={{ width: "auto", minWidth: 150 }} value={filter.category ?? ""} onChange={(e) => setFilter({ ...filter, category: e.target.value || undefined })}>
              <option value="">All problems</option>
              {cats.map((c) => <option key={c} value={c}>{issueCategoryLabel[c]}</option>)}
            </select>
            <select className="input" style={{ width: "auto", minWidth: 150 }} value={filter.status ?? ""} onChange={(e) => setFilter({ ...filter, status: e.target.value || undefined })}>
              <option value="">Open and resolved</option>
              <option value="open">Open</option>
              <option value="resolved">Resolved</option>
            </select>
          </div>
          <ErrorNote error={list.error} />
          {list.loading && !list.data ? <Loading /> : items.length === 0 ? <Empty>No problems recorded{filter.event_id || filter.category || filter.status || search ? " for this filter" : " yet"}.</Empty> : (
            <div className="issue-list">
              {items.map((i) => (
                <div key={i.id} className="issue-item">
                  <div className="row spread gap">
                    <strong>{issueCategoryLabel[i.category]}</strong>
                    <Badge tone={i.status === "open" ? "amber" : "green"}>{i.status === "open" ? "OPEN" : "RESOLVED"}</Badge>
                  </div>
                  <small className="muted">{i.event_name ?? "Not linked to an event"} · {when(i.reported_at)} · by {i.reported_by}</small>
                  {(i.chief_name || i.national_id || i.phone || i.location) && (
                    <div className="issue-chief">
                      {[i.chief_name, i.national_id && `ID ${i.national_id}`, i.phone, i.location].filter(Boolean).join(" · ")}
                    </div>
                  )}
                  <p className="issue-text">{i.description}</p>
                  {i.action_taken && <p className="issue-text muted"><b>Action:</b> {i.action_taken}</p>}
                  {canWrite && <button className="btn small secondary" onClick={() => edit(i)}>Edit</button>}
                </div>
              ))}
            </div>
          )}
        </Card>
      </div>
    </>
  );
}
