import { useState } from "react";
import { api } from "../api";
import { num, turnoutPercent } from "../format";
import { useAsync } from "../useAsync";
import SearchInput, { matchesSearch } from "./SearchInput";
import { Card, Empty, ErrorNote, Kpi, Loading } from "./ui";
import { useTable } from "./TableTools";

const pageSize = 25;
type StationView = "all" | "reached" | "zero";

export default function EventStationCoverage({ eventId }: { eventId: string }) {
  const stations = useAsync(() => api.eventStationCoverage(eventId), [eventId]);
  const [query, setQuery] = useState("");
  const [view, setView] = useState<StationView>("all");
  const [page, setPage] = useState(0);
  const all = stations.data ?? [];
  const totals = all.reduce((acc, station) => {
    acc.registered += station.registered;
    acc.reached += station.reached;
    if (station.reached > 0) acc.stationsReached++;
    return acc;
  }, { reached: 0, registered: 0, stationsReached: 0 });
  const matches = all.filter((station) =>
    (view === "all" || (view === "reached" ? station.reached > 0 : station.reached === 0))
    && matchesSearch(query, station.code, station.name, station.county, station.constituency, station.ward),
  );
  const table = useTable(matches, [
    { key: "name", label: "Polling station", sort: (s) => s.name },
    { key: "county", label: "County", sort: (s) => s.county, filter: (s) => s.county },
    { key: "constituency", label: "Constituency", sort: (s) => s.constituency, filter: (s) => s.constituency },
    { key: "ward", label: "Ward", sort: (s) => s.ward, filter: (s) => s.ward },
    { key: "reached", label: "Members checked in", num: true, sort: (s) => s.reached },
    { key: "registered", label: "Registered voters", num: true, sort: (s) => s.registered },
    { key: "turnout", label: "Turnout", num: true, sort: (s) => (s.registered > 0 ? s.reached / s.registered : null) },
  ]);
  const shown = table.rows;
  const offset = Math.min(page * pageSize, Math.max(0, Math.ceil(shown.length / pageSize) - 1) * pageSize);
  const changeView = (next: StationView) => { setView(next); setPage(0); };

  return (
    <Card title="Polling-station turnout">
      <ErrorNote error={stations.error} />
      {stations.loading && <Loading />}
      {stations.data && <>
        <p className="muted">Turnout is unique members checked in from each polling station divided by its registered voters, across the event’s selected vying area.</p>
        <div className="grid kpis">
          <Kpi label="Overall turnout" value={turnoutPercent(totals.reached, totals.registered)}
            caption={`${num(totals.reached)} of ${num(totals.registered)} registered voters`} onClick={() => changeView("all")} pressed={view === "all"} />
          <Kpi label="Stations with turnout" value={num(totals.stationsReached)} caption="View stations with check-ins"
            tone="teal" onClick={() => changeView("reached")} pressed={view === "reached"} />
          <Kpi label="Stations with zero check-ins" value={num(all.length - totals.stationsReached)}
            caption="View stations with zero check-ins" onClick={() => changeView("zero")} pressed={view === "zero"} />
        </div>
        <div className="toolbar">
          <SearchInput label="Search station or area" value={query} onChange={(q) => { setQuery(q); setPage(0); }} />
          <select className="input" aria-label="Filter polling stations" value={view} onChange={(e) => changeView(e.target.value as StationView)}>
            <option value="all">All stations ({num(all.length)})</option>
            <option value="reached">With check-ins</option>
            <option value="zero">With zero check-ins</option>
          </select>
        </div>
        {table.filterBar}
        {shown.length === 0 ? <Empty>No polling stations match.</Empty> : <>
          <div className="table-wrap">
            <table>
              <thead>{table.head}</thead>
              <tbody>{shown.slice(offset, offset + pageSize).map((station) =>
                <tr key={station.code}>
                  <td>{station.name} <small className="muted">{station.code}</small></td>
                  <td>{station.county}</td><td>{station.constituency}</td><td>{station.ward}</td>
                  <td className="num">{num(station.reached)}</td><td className="num">{num(station.registered)}</td>
                  <td className="num">{turnoutPercent(station.reached, station.registered)}</td>
                </tr>,
              )}</tbody>
            </table>
          </div>
          <div className="toolbar">
            <button className="btn small secondary" disabled={offset === 0} onClick={() => setPage(offset / pageSize - 1)}>Previous</button>
            <small>{num(offset + 1)}–{num(Math.min(offset + pageSize, shown.length))} of {num(shown.length)}</small>
            <button className="btn small secondary" disabled={offset + pageSize >= shown.length} onClick={() => setPage(offset / pageSize + 1)}>Next</button>
          </div>
        </>}
      </>}
    </Card>
  );
}
