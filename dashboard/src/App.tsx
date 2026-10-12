import { useEffect } from "react";
import { Navigate, NavLink, Outlet, Route, Routes, useLocation, useNavigate } from "react-router-dom";
import type { Me } from "./api";
import { isManager, useAuth } from "./auth";
import { Loading } from "./components/ui";
import { initials } from "./format";
import Login from "./pages/Login";
import DashboardPage from "./pages/Dashboard";
import EventsPage from "./pages/Events";
import EventDetail from "./pages/EventDetail";
import CheckinDesk from "./pages/CheckinDesk";
import MobilizationPage from "./pages/Mobilization";
import DriveDetail from "./pages/DriveDetail";
import PeoplePage from "./pages/People";
import TeamPage from "./pages/Team";
import AccountPage from "./pages/Account";
import PlatformOrgs, { EmailTemplates, NewOrgWizard, PlatformOrgDetail } from "./pages/PlatformOrgs";
import { opsRoles, roleLabel } from "./ops/api";
import OpsOverview from "./ops/Overview";
import ElectionPage, { NewElectionWizard } from "./ops/Election";
import { PositionsPage, RegistryPage } from "./ops/Setup";
import OpsPeople from "./ops/People";
import StationsPage from "./ops/Stations";
import { ReplayPage, ResultsPage, TurnoutPage } from "./ops/Monitor";
import { ReportsPage, SettingsPage } from "./ops/Workspace";

const checkinRoles = new Set(["owner", "admin", "member", "viewer"]);
const hasCheckin = (me: Me) => !!me.organization && checkinRoles.has(me.role);
const hasOps = (me: Me) => !!me.organization && opsRoles.has(me.role);
const canSetup = (me: Me) => me.role === "owner" || me.role === "admin" || me.role === "executive";

export default function App() {
  const { me, loading } = useAuth();

  // White-label: the org's accent colour drives every accent token.
  useEffect(() => {
    const accent = me?.organization?.accent_color;
    if (accent) document.documentElement.style.setProperty("--teal", accent);
    else document.documentElement.style.removeProperty("--teal");
  }, [me?.organization?.accent_color]);

  if (loading) return <Loading />;
  if (!me) {
    return (
      <Routes>
        <Route path="*" element={<Login />} />
      </Routes>
    );
  }
  const home = hasCheckin(me) ? "/" : hasOps(me) ? "/ops" : "/platform";
  return (
    <Routes>
      <Route element={<Shell />}>
        {hasCheckin(me) && (
          <>
            <Route index element={<DashboardPage />} />
            <Route path="events" element={<EventsPage />} />
            <Route path="events/:id" element={<EventDetail />} />
            <Route path="checkin" element={<CheckinDesk />} />
            <Route path="mobilization" element={<MobilizationPage />} />
            <Route path="mobilization/:id" element={<DriveDetail />} />
            <Route path="people" element={<PeoplePage />} />
            <Route path="team" element={<TeamPage />} />
          </>
        )}
        {hasOps(me) && (
          <>
            <Route path="ops" element={<OpsOverview />} />
            {canSetup(me) && (
              <>
                <Route path="ops/election" element={<ElectionPage />} />
                <Route path="ops/election/new" element={<NewElectionWizard />} />
                <Route path="ops/positions" element={<PositionsPage />} />
                <Route path="ops/registry" element={<RegistryPage />} />
              </>
            )}
            <Route path="ops/replay/:id" element={<ReplayPage />} />
            <Route path="ops/people" element={<OpsPeople />} />
            <Route path="ops/stations" element={<StationsPage />} />
            <Route path="ops/turnout" element={<TurnoutPage />} />
            <Route path="ops/results" element={<ResultsPage />} />
            <Route path="ops/reports" element={<ReportsPage />} />
            <Route path="ops/settings" element={<SettingsPage />} />
          </>
        )}
        {me.platform_admin && (
          <>
            <Route path="platform" element={<PlatformOrgs />} />
            <Route path="platform/new" element={<NewOrgWizard />} />
            <Route path="platform/orgs/:id" element={<PlatformOrgDetail />} />
            <Route path="platform/templates" element={<EmailTemplates />} />
          </>
        )}
        <Route path="account" element={<AccountPage />} />
        <Route path="*" element={<Navigate to={home} replace />} />
      </Route>
    </Routes>
  );
}

/** Phone reflow: the sidebar's main destinations become a bottom tab bar. */
function TabBar({ inOps, me }: { inOps: boolean; me: Me }) {
  const tabs: [string, string, string][] = !me.organization
    ? [["/platform", "Overview", "⌂"], ["/platform/new", "New org", "+"], ["/platform/templates", "Emails", "✉"], ["/account", "Account", "☺"]]
    : inOps
      ? [["/ops", "Home", "⌂"], ["/ops/stations", "Stations", "⚑"], ...(me.role !== "agent" ? [["/ops/people", "Agents", "☺"] as [string, string, string]] : []),
         ["/ops/turnout", "Turnout", "↗"], ["/account", "Account", "⚙"]]
      : [["/", "Home", "◧"], ["/events", "Events", "▦"], ["/mobilization", "Mobilize", "➚"], ["/people", "People", "☰"], ["/account", "Account", "⚙"]];
  return (
    <nav className="tabbar" aria-label="Sections">
      {tabs.map(([to, label, icon]) => (
        <NavLink key={to} to={to} end={to === "/" || to === "/ops" || to === "/platform"} className={({ isActive }) => (isActive ? "on" : "")}>
          <span aria-hidden>{icon}</span>
          {label}
        </NavLink>
      ))}
    </nav>
  );
}

function Shell() {
  const { me, signOut } = useAuth();
  const loc = useLocation();
  const nav = useNavigate();
  if (!me) return null;
  const inOps = loc.pathname.startsWith("/ops") || (!hasCheckin(me) && hasOps(me) && !loc.pathname.startsWith("/platform"));
  const both = hasCheckin(me) && hasOps(me);
  const link = (to: string, label: string, icon: string, end = false) => (
    <NavLink to={to} end={end} className={({ isActive }) => `nav-link${isActive ? " active" : ""}`}>
      <span aria-hidden className="nav-icon">{icon}</span>
      {label}
    </NavLink>
  );
  const section = (label: string) => <div className="nav-section">{label}</div>;

  return (
    <div className="shell">
      <nav className="sidebar" aria-label="Main">
        <div className="brand">
          <span className="brand-mark">{me.organization ? initials(me.organization.name) : "M"}</span>
          <span>
            {me.organization?.name ?? "MachineNova"}
            <small className="brand-sub">{me.organization ? me.scope_label + (me.organization.boundary.county ? " · bounded" : "") : "Platform console"}</small>
          </span>
        </div>
        {both && (
          <div className="workspace-switch" role="tablist" aria-label="Workspace">
            <button className={!inOps ? "on" : ""} onClick={() => nav("/")}>Checkin</button>
            <button className={inOps ? "on" : ""} onClick={() => nav("/ops")}>Election Ops</button>
          </div>
        )}
        {me.organization && !inOps && hasCheckin(me) && (
          <>
            {link("/", "Dashboard", "◧", true)}
            {section("Operate")}
            {me.module_events && link("/events", "Events", "▦")}
            {me.module_events && me.role !== "viewer" && link("/checkin", "Check-in", "✓")}
            {me.module_mobilization && link("/mobilization", "Mobilization", "➚")}
            {section("People")}
            {link("/people", "People reached", "☰")}
            {isManager(me) && link("/team", "Team", "☺")}
          </>
        )}
        {me.organization && inOps && hasOps(me) && (
          <>
            {link("/ops", "Overview", "⌂", true)}
            {canSetup(me) && (
              <>
                {section("Set up")}
                {link("/ops/election", "Election", "▣")}
                {link("/ops/positions", "Positions & candidates", "☷")}
                {link("/ops/registry", "Registry", "▤")}
              </>
            )}
            {me.role !== "agent" && (<>{section("People")}{link("/ops/people", "Directory", "☺")}</>)}
            {section("Operate")}
            {link("/ops/stations", "Polling stations", "⚑")}
            {section("Monitor")}
            {link("/ops/turnout", "Voter turnout", "↗")}
            {link("/ops/results", "Results", "▥")}
            {me.role !== "agent" && (
              <>
                {section("Workspace")}
                {link("/ops/reports", "Reports", "⎙")}
                {me.role === "owner" && link("/ops/settings", "Settings", "⚙")}
              </>
            )}
          </>
        )}
        {me.platform_admin && (
          <>
            {section("Platform")}
            {link("/platform", "Platform overview", "⌂", true)}
            {link("/platform/new", "New organization", "+")}
            {link("/platform/templates", "Email templates", "✉")}
          </>
        )}
        <div className="sidebar-foot">
          <div className="row gap">
            <span className="avatar">{initials(me.name)}</span>
            <div>
              <div className="who">{me.name}</div>
              <small>{me.platform_admin && !me.organization ? "Platform admin" : `${roleLabel[me.role] ?? me.role}${me.organization ? " · " + me.scope_label : ""}`}</small>
            </div>
          </div>
          <NavLink to="/account" className="nav-link" style={{ padding: "8px 0 0" }}>Account</NavLink>
          <button onClick={signOut}>Sign out</button>
        </div>
      </nav>
      <TabBar inOps={inOps} me={me} />
      <main className="main">
        {me.organization && !me.organization.active && (
          <div className="alert red">This organization is inactive. Field actions are disabled — contact the platform administrator.</div>
        )}
        <Outlet />
      </main>
    </div>
  );
}
