import { Link } from "react-router-dom";
import { api } from "../api";
import { useAuth } from "../auth";
import { Badge, Card, Empty, ErrorNote, Kpi, Loading, PageHeader, RankList } from "../components/ui";
import { area, date, num } from "../format";
import { useAsync } from "../useAsync";

function greeting() {
  const h = new Date().getHours();
  return h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening";
}

export default function DashboardPage() {
  const { me } = useAuth();
  const { data, error, loading } = useAsync(api.dashboard, []);

  return (
    <>
      <PageHeader
        title={`${greeting()}, ${me?.organization?.name ?? me?.name}`}
        subtitle="Here's how mobilization and check-in are tracking."
        actions={me?.role !== "viewer" && me?.module_events && <Link className="btn" to="/checkin">Open check-in</Link>}
      />
      <ErrorNote error={error} />
      {loading && !data && <Loading />}
      {data && (
        <>
          <div className="grid kpis">
            <Kpi label="Total events" value={num(data.total_events)} caption={`${num(data.active_events)} active right now`} tone="teal" />
            <Kpi label="Voters mobilized" value={num(data.voters_mobilized)} caption={`across ${num(data.active_regions)} active regions`} tone="amber" />
            <Kpi label="Team members" value={num(data.team_members)} caption={<Link to="/team">Manage team →</Link>} />
            <Kpi label="Check-ins · 7 days" value={num(data.checkins_7d)} caption="across all events" tone="teal" />
          </div>
          <div className="grid cols-2">
            <Card title="Top regions by mobilization" extra={<Link to="/mobilization">View all</Link>}>
              <RankList tone="teal" items={data.top_regions} />
            </Card>
            <Card title="Recent events" extra={<Link to="/events">View all</Link>}>
              {data.recent_events.length === 0 ? (
                <Empty>No events yet.</Empty>
              ) : (
                <div className="stack">
                  {data.recent_events.map((e) => (
                    <Link key={e.id} to={`/events/${e.id}`} className="row spread" style={{ color: "inherit" }}>
                      <div>
                        <div style={{ fontWeight: 600 }}>{e.name}</div>
                        <small className="muted">{area(e.venue, e.ward ?? e.constituency ?? e.county)} · {date(e.starts_at)}</small>
                      </div>
                      {e.active ? <Badge tone="green">Active</Badge> : <Badge>Closed</Badge>}
                    </Link>
                  ))}
                </div>
              )}
            </Card>
          </div>
        </>
      )}
    </>
  );
}
