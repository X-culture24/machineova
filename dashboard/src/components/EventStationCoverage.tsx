import { useState } from "react";
import { api } from "../api";
import { num, pct } from "../format";
import { useAsync } from "../useAsync";
import { Card, Empty, ErrorNote, Loading } from "./ui";

const pageSize = 50;

export default function EventStationCoverage({ eventId }: { eventId: string }) {
  const stations = useAsync(() => api.eventStationCoverage(eventId), [eventId]);
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(0);
  const search = query.trim().toLowerCase();
  const matches = stations.data?.filter((s) =>
    [s.code, s.name, s.county, s.constituency, s.ward].some((part) => part.toLowerCase().includes(search)),
  ) ?? [];
  const offset = Math.min(page * pageSize, Math.max(0, Math.ceil(matches.length / pageSize) - 1) * pageSize);

  return (
    <Card title="Polling station coverage" extra={stations.data && <small>{num(stations.data.length)} stations</small>}>
      <ErrorNote error={stations.error} />
      {stations.loading && <Loading />}
      {stations.data && <>
        <div className="toolbar">
          <input className="input" aria-label="Search polling stations" placeholder="Search station or area…" value={query}
            onChange={(e) => { setQuery(e.target.value); setPage(0); }} />
        </div>
        {matches.length === 0 ? <Empty>No polling stations match.</Empty> : <>
          <div className="table-wrap">
            <table>
              <thead><tr><th>Station</th><th>County</th><th>Constituency</th><th>Ward</th><th>Reached</th><th>Registered</th><th>Coverage</th></tr></thead>
              <tbody>{matches.slice(offset, offset + pageSize).map((s) =>
                <tr key={s.code}>
                  <td>{s.name} <small className="muted">{s.code}</small></td><td>{s.county}</td><td>{s.constituency}</td>
                  <td>{s.ward}</td><td>{num(s.reached)}</td><td>{num(s.registered)}</td>
                  <td>{s.registered ? pct(s.reached / s.registered) : "—"}</td>
                </tr>,
              )}</tbody>
            </table>
          </div>
          <div className="toolbar">
            <button className="btn small secondary" disabled={offset === 0} onClick={() => setPage(offset / pageSize - 1)}>Previous</button>
            <small>{num(offset + 1)}–{num(Math.min(offset + pageSize, matches.length))} of {num(matches.length)}</small>
            <button className="btn small secondary" disabled={offset + pageSize >= matches.length} onClick={() => setPage(offset / pageSize + 1)}>Next</button>
          </div>
        </>}
      </>}
    </Card>
  );
}
