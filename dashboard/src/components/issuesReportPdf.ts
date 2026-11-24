import { issueCategoryLabel, type Issue, type IssueCategory, type IssuesReport } from "../api";

// The field training report as a printable page in its own window (the browser's "Save as PDF"):
// a summary of every event, the problems by kind, and every problem recorded, grouped by
// training. The app itself can't be printed (voter-data protection), so the report opens apart.

const esc = (v: unknown) => String(v ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]!);
const day = (s: string | null) => (s ? new Date(s + (s.length === 10 ? "T12:00:00" : "")).toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short", year: "numeric" }) : "Not held yet");
const time = (s: string | null) => (s ? new Date(s).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" }) : "");
const when = (s: string) => new Date(s).toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
const cats = Object.keys(issueCategoryLabel) as IssueCategory[];

function issueRows(list: Issue[]) {
  if (list.length === 0) return `<p class="none">No problems recorded.</p>`;
  return `<table class="issues"><thead><tr><th>When</th><th>Problem</th><th>Member</th><th>ID no.</th><th>Phone</th><th>Location</th>
    <th>What happened</th><th>Action taken</th><th>Status</th><th>Recorded by</th></tr></thead><tbody>${list.map((i) => `
    <tr><td class="nw">${esc(when(i.reported_at))}</td><td>${esc(issueCategoryLabel[i.category])}</td><td>${esc(i.chief_name || "—")}</td>
    <td class="nw">${esc(i.national_id || "—")}</td><td class="nw">${esc(i.phone || "—")}</td><td>${esc(i.location || "—")}</td>
    <td class="text">${esc(i.description)}</td><td class="text">${esc(i.action_taken || "—")}</td>
    <td><span class="st ${i.status}">${i.status === "resolved" ? "Resolved" : "Open"}</span></td><td>${esc(i.reported_by)}</td></tr>`).join("")}
    </tbody></table>`;
}

/** The coat of arms as a data URL, so the report window (about:blank) shows it and it prints. */
async function logoData(): Promise<string> {
  try {
    const b = await (await fetch("/sdics-logo.jpeg")).blob();
    return await new Promise<string>((ok) => {
      const fr = new FileReader();
      fr.onload = () => ok(String(fr.result));
      fr.onerror = () => ok("");
      fr.readAsDataURL(b);
    });
  } catch {
    return "";
  }
}

export async function openIssuesReport(report: Promise<IssuesReport>) {
  // Opened before any await, so pop-up blockers see the click.
  const w = window.open("", "_blank");
  if (!w) {
    alert("Allow pop-ups for this site to open the report.");
    return;
  }
  w.document.write("<p style=\"font:14px sans-serif;padding:24px\">Preparing the report…</p>");
  let r: IssuesReport;
  try {
    r = await report;
  } catch (e) {
    w.close();
    throw e;
  }
  const held = r.trainings.filter((t) => t.held_on);
  const present = r.trainings.reduce((a, t) => a + t.present, 0);
  const phones = r.trainings.reduce((a, t) => a + t.phones, 0);
  const total = r.issues.length;
  const byEvent = new Map<string, Issue[]>();
  const unlinked: Issue[] = [];
  for (const i of r.issues) {
    if (i.event_id && r.trainings.some((t) => t.event_id === i.event_id)) {
      byEvent.set(i.event_id, [...(byEvent.get(i.event_id) ?? []), i]);
    } else unlinked.push(i);
  }
  const logo = await logoData();
  const generated = new Date(r.generated_at).toLocaleString("en-GB", { dateStyle: "full", timeStyle: "short" });

  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Event issues report — ${esc(r.organization)}</title>
<style>
  @page { size: A4 landscape; margin: 12mm; }
  * { box-sizing: border-box; }
  body { font: 11px/1.45 "Helvetica Neue", Arial, sans-serif; color: #111827; margin: 0; padding: 18px; }
  .flag { display: flex; height: 5px; margin: -18px -18px 16px; } .flag i { flex: 1; } .flag i:nth-child(1){background:#000} .flag i:nth-child(2){background:#bb0000} .flag i:nth-child(3){background:#006600}
  header { display: flex; align-items: center; gap: 14px; border-bottom: 2px solid #00875a; padding-bottom: 12px; margin-bottom: 16px; }
  header img { width: 54px; height: 54px; object-fit: contain; }
  header .k { font-size: 10px; letter-spacing: 2px; color: #4b5563; }
  h1 { font-size: 20px; margin: 2px 0; color: #0f1419; }
  header .sub { color: #4b5563; }
  h2.newpage { page-break-before: always; }
  h2, h3 { page-break-after: avoid; }
  h2 { font-size: 14px; margin: 22px 0 8px; color: #00875a; border-bottom: 1px solid #d5dae1; padding-bottom: 4px; }
  h3 { font-size: 12.5px; margin: 16px 0 6px; }
  h3 small { font-weight: 400; color: #4b5563; font-size: 11px; }
  .kpis { display: grid; grid-template-columns: repeat(6, 1fr); gap: 10px; }
  .kpi { border: 1px solid #d5dae1; border-radius: 8px; padding: 10px 12px; }
  .kpi b { display: block; font-size: 20px; color: #0f1419; } .kpi span { color: #4b5563; font-size: 10px; text-transform: uppercase; letter-spacing: .5px; }
  .kpi.warn b { color: #b45309; }
  table { width: 100%; border-collapse: collapse; margin-top: 4px; page-break-inside: auto; }
  tr { page-break-inside: avoid; }
  th, td { border: 1px solid #d5dae1; padding: 5px 6px; text-align: left; vertical-align: top; }
  th { background: #eef1f5; font-size: 10px; text-transform: uppercase; letter-spacing: .3px; }
  td.n, th.n { text-align: right; } .nw { white-space: nowrap; } td.text { min-width: 160px; white-space: pre-wrap; }
  .st { font-weight: 700; } .st.open { color: #b45309; } .st.resolved { color: #00875a; }
  .none { color: #6b7280; font-style: italic; margin: 4px 0; }
  .training { page-break-inside: avoid; }
  footer { margin-top: 24px; color: #6b7280; font-size: 10px; border-top: 1px solid #d5dae1; padding-top: 6px; }
  .noprint { margin-bottom: 12px; } .noprint button { font: inherit; padding: 6px 14px; border-radius: 6px; border: 0; background: #00875a; color: #fff; cursor: pointer; }
  @media print { .noprint { display: none; } }
</style></head><body>
<div class="flag"><i></i><i></i><i></i></div>
<div class="noprint"><button onclick="window.print()">Save as PDF / print</button></div>
<header>${logo ? `<img src="${logo}" alt="">` : ""}<div><div class="k">REPUBLIC OF KENYA · SDICS</div><h1>Event issues report</h1>
<div class="sub">${esc(r.organization)} · problems recorded and a summary of every event · generated ${esc(generated)}</div></div></header>

<h2>Summary</h2>
<div class="kpis">
  <div class="kpi"><span>Events with check-ins</span><b>${held.length} of ${r.trainings.length}</b></div>
  <div class="kpi"><span>Members checked in</span><b>${present.toLocaleString()}</b></div>
  <div class="kpi"><span>Phone numbers</span><b>${phones.toLocaleString()}</b></div>
  <div class="kpi"><span>Problems recorded</span><b>${total}</b></div>
  <div class="kpi ${r.open ? "warn" : ""}"><span>Still open</span><b>${r.open}</b></div>
  <div class="kpi"><span>Resolved</span><b>${total - r.open}</b></div>
</div>

<h2>Problems by kind</h2>
<table><thead><tr><th>Problem</th><th class="n">Recorded</th><th class="n">Share</th></tr></thead><tbody>
${cats.map((c) => `<tr><td>${esc(issueCategoryLabel[c])}</td><td class="n">${r.by_category[c] ?? 0}</td><td class="n">${total ? Math.round(((r.by_category[c] ?? 0) / total) * 100) : 0}%</td></tr>`).join("")}
</tbody></table>

<h2>Events</h2>
<table><thead><tr><th>Event</th><th>County</th><th>Venue</th><th>Held on</th><th>Time</th><th class="n">Members checked in</th><th class="n">Phones</th>
<th class="n">Out of region</th><th class="n">Problems</th><th class="n">Open</th><th>Main problems</th></tr></thead><tbody>
${r.trainings.map((t) => {
    const top = cats.filter((c) => t.by_category[c]).sort((a, b) => (t.by_category[b] ?? 0) - (t.by_category[a] ?? 0))
      .map((c) => `${issueCategoryLabel[c]} (${t.by_category[c]})`).join(", ");
    return `<tr><td>${esc(t.name)}</td><td>${esc(t.county)}</td><td>${esc(t.venue || "—")}</td><td class="nw">${esc(day(t.held_on))}</td>
    <td class="nw">${t.first_at ? `${esc(time(t.first_at))}–${esc(time(t.last_at))}` : "—"}</td><td class="n">${t.present}</td><td class="n">${t.phones}</td>
    <td class="n">${t.out_region}</td><td class="n">${t.issues}</td><td class="n">${t.open}</td><td>${esc(top || "—")}</td></tr>`;
  }).join("")}
</tbody></table>

<h2 class="newpage">Problems recorded, by event</h2>
${r.trainings.filter((t) => byEvent.has(t.event_id)).map((t) => `<div class="training">
  <h3>${esc(t.name)} <small>· ${esc(t.county)} · ${esc(day(t.held_on))} · ${t.present} members checked in · ${t.issues} problem${t.issues === 1 ? "" : "s"}</small></h3>
  ${issueRows(byEvent.get(t.event_id)!)}</div>`).join("") || `<p class="none">No problems recorded at any event.</p>`}
${unlinked.length ? `<div class="training"><h3>Not linked to an event</h3>${issueRows(unlinked)}</div>` : ""}

<footer>SDICS Checkin · ${esc(r.organization)} · confidential: contains members’ ID and phone numbers.</footer>
</body></html>`;
  w.document.open();
  w.document.write(html);
  w.document.close();
  w.focus();
  w.onload = () => w.print();
}
