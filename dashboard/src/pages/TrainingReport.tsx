// SDICS chiefs training report: how many chiefs were present at each county training, on the day
// it was actually held, and (when SDICS can be read) how many were onboarded to the SDICS app.
import { Link } from "react-router-dom";
import { api, type TrainingRow } from "../api";
import { Badge, Card, Empty, ErrorNote, Kpi, Loading, PageHeader, ProgressBar } from "../components/ui";
import { LineChart } from "../components/LineChart";
import { num, pct } from "../format";
import { useAsync } from "../useAsync";

/** "2026-11-19" -> "Thu 19 Nov" (dates are Nairobi days from the server). */
export const dayLabel = (d: string, withYear = false) =>
  new Date(`${d}T12:00:00+03:00`).toLocaleDateString("en-KE", {
    weekday: "short", day: "numeric", month: "short", ...(withYear ? { year: "numeric" } : {}), timeZone: "Africa/Nairobi",
  });
const clock = (iso: string | null) =>
  iso ? new Date(iso).toLocaleTimeString("en-KE", { hour: "2-digit", minute: "2-digit", hour12: false, timeZone: "Africa/Nairobi" }) : "";
const hourLabel = (h: number) => `${String(h).padStart(2, "0")}:00`;

export default function TrainingReportPage() {
  const { data, error, loading } = useAsync(api.trainingReport, []);
  if (loading && !data) return <Loading />;
  if (!data) return <ErrorNote error={error} />;

  const held = data.trainings.filter((t) => t.held_on && t.present >= 5); // a stray test check-in isn't a training
  const notHeld = data.trainings.filter((t) => !held.includes(t));
  const present = held.reduce((a, t) => a + t.present, 0);
  const phones = held.reduce((a, t) => a + t.phones, 0);
  const signed = held.reduce((a, t) => a + (t.signed_in ?? 0), 0);
  const days = data.days.filter((d) => held.some((t) => t.held_on === d.day));

  // Arrivals by hour: one smooth line per training day.
  const hMin = Math.min(7, ...days.flatMap((d) => d.hours.map((h) => h.hour)));
  const hMax = Math.max(16, ...days.flatMap((d) => d.hours.map((h) => h.hour)));
  const hours = Array.from({ length: hMax - hMin + 1 }, (_, i) => hMin + i);
  const byHour = days.slice(-3).map((d) => ({
    name: dayLabel(d.day),
    values: hours.map((h) => d.hours.find((x) => x.hour === h)?.count ?? 0),
  }));

  // Per day: chiefs present at training, and (SDICS) chiefs who signed in to the SDICS app for the first time.
  const allDays = [...new Set([...days.map((d) => d.day), ...data.onboarding.map((o) => o.day)])].sort()
    .filter((d) => d >= (days[0]?.day ?? d));
  const today = new Date().toLocaleDateString("en-CA", { timeZone: "Africa/Nairobi" }); // YYYY-MM-DD
  const perDay = [{ name: "Present at training", values: allDays.map((d) => days.find((x) => x.day === d)?.total ?? 0) }];
  if (data.sdics) {
    perDay.push({ name: "First signed in to SDICS", values: allDays.map((d) => data.onboarding.filter((o) => o.day === d).reduce((a, o) => a + o.count, 0)) });
  }

  return (
    <>
      <PageHeader
        title="Event report"
        subtitle="SDICS app training for chiefs and sub-chiefs: who was present at each county training, on the day it was held."
      />
      <ErrorNote error={error} />
      <div className="grid kpis">
        <Kpi label="Chiefs present" value={num(present)} tone="teal"
          caption={held.length ? `${dayLabel(held[0].held_on!)} – ${dayLabel(held[held.length - 1].held_on!)}` : "No training yet"} />
        <Kpi label="County trainings held" value={`${held.length} of ${data.trainings.length}`}
          progress={data.trainings.length ? held.length / data.trainings.length : 0} tone="teal" />
        <Kpi label="Phone numbers collected" value={num(phones)} caption={present ? `${pct(phones / present)} of chiefs present` : undefined} />
        {data.sdics ? (
          <Kpi label="Onboarded to SDICS app" value={num(signed)} tone="amber"
            caption={present ? `${pct(signed / present)} of chiefs present have signed in` : undefined}
            progress={present ? signed / present : 0} />
        ) : (
          <Kpi label="SDICS chiefs reached" value="—" caption="SDICS figures not connected yet" />
        )}
      </div>

      <div className="grid cols-even">
        <Card title="Chiefs arriving, by hour">
          <LineChart labels={hours.map(hourLabel)} series={byHour} unit="chiefs" />
        </Card>
        <Card title={data.sdics ? "Each day: present at training and onboarded to SDICS" : "Chiefs present each day"}>
          <LineChart labels={allDays.map((d) => dayLabel(d) + (d === today ? " (so far)" : ""))} series={perDay} unit="chiefs" />
        </Card>
      </div>

      <Card title="By county" extra={data.sdics ? <small className="muted">Bars: chiefs present of the chiefs SDICS has in the county</small> : undefined}>
        {held.length === 0 ? <Empty>No county training has been held yet.</Empty> : (
          <div className="table-wrap">
            <table className="cards">
              <thead>
                <tr>
                  <th>County</th><th>Held on</th><th className="num">Chiefs present</th>
                  {data.sdics && <th style={{ width: "26%" }}>Of SDICS chiefs in the county</th>}
                  {data.sdics && <th style={{ width: "22%" }}>Onboarded to SDICS app</th>}
                  <th className="num">Phones</th><th className="num">Out of region</th>
                </tr>
              </thead>
              <tbody>
                {held.map((t) => <CountyRow key={t.event_id} t={t} sdics={data.sdics} />)}
              </tbody>
            </table>
          </div>
        )}
        {notHeld.length > 0 && (
          <p className="muted" style={{ margin: "14px 0 0" }}>
            <strong>Not held yet:</strong> {notHeld.map((t) => t.county + (t.present ? ` (${t.present} test check-in${t.present === 1 ? "" : "s"})` : "")).join(", ")}.
          </p>
        )}
      </Card>
      <p className="muted" style={{ fontSize: 12 }}>
        Dates and times are Nairobi time, taken from each training's first and last check-in.
        {data.sdics && " SDICS figures: chiefs with an active SDICS account in the county, and their first sign-in to the SDICS app."}
        {" "}Updated {clock(data.generated_at)}.
      </p>
    </>
  );
}

function CountyRow({ t, sdics }: { t: TrainingRow; sdics: boolean }) {
  const of = t.sdics_chiefs ?? 0;
  return (
    <tr>
      <td data-label="County"><Link to={`/events/${t.event_id}`} style={{ fontWeight: 600 }}>{t.county}</Link></td>
      <td data-label="Held on">{dayLabel(t.held_on!, true)}<br /><small className="muted">{clock(t.first_at)}–{clock(t.last_at)}</small></td>
      <td data-label="Chiefs present" className="num"><strong>{num(t.present)}</strong></td>
      {sdics && (
        <td data-label="Of SDICS chiefs">
          <div className="row gap"><div style={{ flex: 1 }}><ProgressBar value={of ? t.present / of : 0} /></div>
            <small>{of ? `${num(t.present)}/${num(of)} · ${pct(t.present / of)}` : "—"}</small></div>
        </td>
      )}
      {sdics && (
        <td data-label="Onboarded to SDICS">
          <div className="row gap"><div style={{ flex: 1 }}><ProgressBar value={t.present ? (t.signed_in ?? 0) / t.present : 0} tone="amber" /></div>
            <small>{num(t.signed_in ?? 0)} · {t.present ? pct((t.signed_in ?? 0) / t.present) : "—"}</small></div>
        </td>
      )}
      <td data-label="Phones" className="num">{num(t.phones)}</td>
      <td data-label="Out of region" className="num">{t.out_region ? <Badge tone="amber">{t.out_region}</Badge> : "0"}</td>
    </tr>
  );
}
