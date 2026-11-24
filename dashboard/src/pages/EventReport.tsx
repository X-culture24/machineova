import { useState } from "react";
import { Link } from "react-router-dom";
import { api } from "../api";
import SearchInput, { matchesSearch } from "../components/SearchInput";
import { Badge, Card, Empty, ErrorNote, Kpi, Loading, PageHeader } from "../components/ui";
import { area, dateTime, num } from "../format";
import { useAsync } from "../useAsync";

type ReportView = "all" | "active" | "closed" | "attendance";

export default function EventReportPage() {
  const { data, error, loading } = useAsync(() => api.events(), []);
  const [query, setQuery] = useState("");
  const [view, setView] = useState<ReportView>("all");
  const events = (data?.items ?? []).filter((event) =>
    matchesSearch(query, event.name, event.venue, event.county, event.constituency, event.ward)
    && (view === "all" || (view === "active" && event.active) || (view === "closed" && !event.active)
      || (view === "attendance" && event.checkins > 0)),
  );

  return (
    <>
      <PageHeader title="Event report" subtitle="Compare attendance and open polling-station turnout for each event." />
      <ErrorNote error={error} />
      {loading && !data && <Loading />}
      {data && <>
        <div className="grid kpis">
          <Kpi label="Total events" value={num(data.summary.total)} caption="View all events"
            onClick={() => setView("all")} pressed={view === "all"} />
          <Kpi label="Active events" value={num(data.summary.active)} caption="View active events" tone="teal"
            onClick={() => setView("active")} pressed={view === "active"} />
          <Kpi label="Closed events" value={num(data.summary.closed)} caption="View closed events"
            onClick={() => setView("closed")} pressed={view === "closed"} />
          <Kpi label="Total check-ins" value={num(data.summary.checkins)} caption="View events with attendance" tone="teal"
            onClick={() => setView("attendance")} pressed={view === "attendance"} />
        </div>
        <Card title="Event summaries">
          <div className="toolbar">
            <SearchInput label="Search events or areas" value={query} onChange={setQuery} />
            <select className="input" aria-label="Filter event summaries" value={view} onChange={(e) => setView(e.target.value as ReportView)}>
              <option value="all">All events</option><option value="active">Active events</option>
              <option value="closed">Closed events</option><option value="attendance">Events with attendance</option>
            </select>
          </div>
          {events.length === 0 ? <Empty>No events match.</Empty> : (
            <div className="table-wrap">
              <table>
                <thead><tr><th>Event</th><th>Area</th><th>Starts</th><th>Status</th><th>Admission</th>
                  <th className="num">Check-ins</th><th className="num">Unique members</th><th className="num">Out-of-region check-ins</th><th>Insights</th></tr></thead>
                <tbody>
                  {events.map((event) => (
                    <tr key={event.id}>
                      <td><Link to={`/events/${event.id}`}>{event.name}</Link>{event.venue && <div className="muted">{event.venue}</div>}</td>
                      <td>{area(event.county, event.constituency, event.ward)}</td>
                      <td>{dateTime(event.starts_at)}</td>
                      <td><Badge tone={event.active ? "green" : "grey"}>{event.active ? "Active" : "Closed"}</Badge></td>
                      <td>{event.list_only ? "Selected participants only" : "General participants"}</td>
                      <td className="num">{num(event.checkins)}</td>
                      <td className="num">{num(event.unique)}</td>
                      <td className="num">{num(event.out_of_region)}</td>
                      <td><Link to={`/events/${event.id}?section=stations`}>Polling-station turnout</Link></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      </>}
    </>
  );
}
