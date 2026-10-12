// Typed client for the Election Ops endpoints (/api/ops/*).
import { ApiError, token } from "../api";

export type OpsRole = "owner" | "executive" | "admin" | "chief_agent" | "manager" | "agent";
export type StationStatus = "not_open" | "open" | "reporting" | "closed" | "issue";
export type Level = "national" | "county" | "constituency" | "ward";

export interface Scope {
  county: string | null;
  constituency: string | null;
  ward: string | null;
}

export interface Election {
  id: string;
  name: string;
  code: string;
  election_date: string;
  scope: Scope;
  scope_label: string;
  status: "draft" | "active" | "completed";
  created_at: string;
}

export interface ElectionSummary extends Election {
  positions: number;
  counties: number;
  constituencies: number;
  wards: number;
  stations: number;
  registered: number;
  stations_reported: number;
  reported_share: number;
}

export interface Position {
  id: string;
  name: string;
  level: Level;
  sort: number;
}

export interface Candidate {
  id: string;
  position_id: string;
  region: string | null;
  name: string;
  party_code: string | null;
  party_name: string | null;
  is_ours: boolean;
}

export interface Race {
  position: Position;
  region: string | null;
  candidates: Candidate[];
}

export interface Station {
  code: string;
  name: string;
  county: string;
  constituency: string;
  ward: string;
  registered: number;
  status: StationStatus;
  updated_at: string | null;
  agents: number;
  cast: number | null;
  turnout: number | null;
  open_incidents: number;
  last_incident: string | null;
  results_submitted: number;
}

export interface Paged<T> {
  items: T[];
  total: number;
  page: number;
  page_size: number;
}

export interface Person {
  id: string;
  name: string;
  role: OpsRole;
  phone: string | null;
  email: string | null;
  national_id: string | null;
  scope: Scope;
  area: string;
  active: boolean;
  can_sign_in: boolean;
  station_code: string | null;
  station_name: string | null;
}

export interface StationAgent {
  id: string;
  name: string;
  phone: string | null;
  national_id: string | null;
}

export interface StationEvent {
  kind: string;
  message: string;
  by: string | null;
  at: string;
}

export interface Incident {
  id: string;
  type: string;
  description: string;
  reported_by: string;
  created_at: string;
  resolved_at: string | null;
  resolution: string | null;
}

export interface StationDetail {
  station: Station;
  agents: StationAgent[];
  events: StationEvent[];
  incidents: Incident[];
  turnout: { hour: number; count: number }[];
  results: { position: Position; submitted_at: string | null }[];
  can_act: boolean;
  can_assign: boolean;
  turnout_slots: number[];
}

export interface TrendPoint {
  hour: number;
  cast: number;
  turnout: number;
}

export interface AttentionItem {
  code: string;
  name: string;
  area: string;
  reason: string;
  kind: "issue" | "uncovered" | "verify";
  action: string;
}

export interface Overview {
  election: Election;
  scope: Scope;
  scope_label: string;
  stations: number;
  reported: number;
  open: number;
  closed: number;
  cast: number;
  registered: number;
  turnout: number;
  issues: number;
  uncovered: number;
  to_verify: number;
  attention: AttentionItem[];
  trend: TrendPoint[];
  agents: number;
  last_update: string | null;
}

export interface Leader {
  candidate: Candidate;
  share: number;
}

export interface TurnoutArea {
  name: string;
  turnout: number;
  vs_avg: number;
  leading: Leader | null;
  we_lead: boolean | null;
  signal: string;
  attention: boolean;
  hourly: number[];
  drillable: boolean;
}

export interface TurnoutMonitor {
  election: Election;
  scope: Scope;
  scope_label: string;
  child_level: string;
  cast: number;
  registered: number;
  turnout: number;
  trend: TrendPoint[];
  focus_position: Position | null;
  our_candidate: Candidate | null;
  areas: TurnoutArea[];
  attention_count: number;
  slots: number[];
}

export interface CandidateTotal {
  candidate: Candidate;
  votes: number;
  share: number;
}

export interface ResultsMonitor {
  election: Election;
  positions: Position[];
  position: Position;
  scope: Scope;
  scope_label: string;
  child_level: string;
  stations: number;
  stations_reporting: number;
  single_race: boolean;
  race: string | null;
  totals: CandidateTotal[] | null;
  areas: { name: string; leading: Leader | null; reporting: number; stations: number; margin: number | null; drillable: boolean }[];
  last_update: string | null;
}

export interface Replay {
  election: Election;
  hour: number;
  turnout: number;
  cast: number;
  registered: number;
  stations: number;
  stations_reporting: number;
  focus_position: Position | null;
  leading: Leader | null;
  we_lead: boolean | null;
  margin: number | null;
  areas: { name: string; turnout: number; leading: Leader | null; ours: boolean | null; margin: number | null }[];
  child_level: string;
  events: StationEvent[];
}

export interface Regions {
  scope: Scope;
  counties: { name: string; constituencies: { name: string; wards: { name: string; stations: { code: string; name: string }[] }[] }[] }[];
}

export interface Party {
  code: string;
  name: string;
  colour: string | null;
}

const BASE = import.meta.env.VITE_API_URL ?? "";

async function req<T>(method: string, path: string, body?: unknown): Promise<T> {
  const headers: Record<string, string> = {};
  const t = token.get();
  if (t) headers.Authorization = `Bearer ${t}`;
  if (body !== undefined) headers["Content-Type"] = "application/json";
  const res = await fetch(BASE + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  if (res.status === 204) return undefined as T;
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new ApiError(res.status, data.error ?? res.statusText, data.code, data);
  return data as T;
}

const qs = (p: Record<string, string | number | undefined | null>) => {
  const u = new URLSearchParams();
  for (const [k, v] of Object.entries(p)) if (v !== undefined && v !== null && v !== "") u.set(k, String(v));
  const s = u.toString();
  return s ? `?${s}` : "";
};

export type Drill = { constituency?: string; ward?: string };

export const ops = {
  elections: () => req<ElectionSummary[]>("GET", "/api/ops/elections"),
  election: (id: string, drill: Drill = {}) =>
    req<{
      election: Election;
      positions: Position[];
      levels: { level: Level; positions: string[]; regions: string[] }[];
      drill: { scope: Scope; label: string; child_level: string; rows: { name: string; races: string; stations: number; registered: number }[] };
    }>("GET", `/api/ops/elections/${id}${qs(drill)}`),
  createElection: (body: {
    name: string;
    code: string;
    election_date: string;
    scope_county?: string;
    scope_constituency?: string;
    positions: { name: string; level: Level }[];
  }) => req<ElectionSummary>("POST", "/api/ops/elections", body),
  setElectionStatus: (id: string, status: Election["status"]) => req<ElectionSummary>("POST", `/api/ops/elections/${id}/status`, { status }),
  deleteElection: (id: string) => req<void>("DELETE", `/api/ops/elections/${id}`),

  races: () => req<{ election: Election; positions: Position[]; races: Race[] }>("GET", "/api/ops/races"),
  addPosition: (name: string, level: Level) => req<Position>("POST", "/api/ops/positions", { name, level }),
  deletePosition: (id: string) => req<void>("DELETE", `/api/ops/positions/${id}`),
  addCandidate: (body: { position_id: string; region: string | null; name: string; party_code?: string; is_ours?: boolean }) =>
    req<Candidate>("POST", "/api/ops/candidates", body),
  updateCandidate: (id: string, body: { name?: string; party_code?: string; is_ours?: boolean }) =>
    req<void>("PATCH", `/api/ops/candidates/${id}`, body),
  deleteCandidate: (id: string) => req<void>("DELETE", `/api/ops/candidates/${id}`),

  registryStations: (q: string, page: number) => req<Paged<Station>>("GET", `/api/ops/registry/stations${qs({ q, page, page_size: 25 })}`),
  parties: () => req<Party[]>("GET", "/api/ops/registry/parties"),
  regions: () => req<Regions>("GET", "/api/ops/registry/regions"),

  people: (p: { role?: string; q?: string; page?: number }) => req<Paged<Person>>("GET", `/api/ops/people${qs({ ...p, page_size: 25 })}`),
  addPerson: (body: Record<string, string | undefined>) => req<Person>("POST", "/api/ops/people", body),
  updatePerson: (id: string, body: { active?: boolean; email?: string; password?: string; phone?: string }) =>
    req<void>("PATCH", `/api/ops/people/${id}`, body),

  overview: () => req<Overview>("GET", "/api/ops/overview"),
  stations: (p: { status?: string; q?: string; constituency?: string; ward?: string; page?: number }) =>
    req<Paged<Station> & { counts: Record<string, number>; in_scope: number; scope: Scope; scope_label: string }>(
      "GET",
      `/api/ops/stations${qs({ ...p, page_size: 10 })}`,
    ),
  station: (code: string) => req<StationDetail>("GET", `/api/ops/stations/${encodeURIComponent(code)}`),
  setStatus: (code: string, status: StationStatus, note: string) =>
    req<void>("POST", `/api/ops/stations/${encodeURIComponent(code)}/status`, { status, note }),
  recordTurnout: (code: string, slot_hour: number, cumulative: number) =>
    req<void>("POST", `/api/ops/stations/${encodeURIComponent(code)}/turnout`, { slot_hour, cumulative }),
  reportIncident: (code: string, type: string, description: string) =>
    req<{ id: string }>("POST", `/api/ops/stations/${encodeURIComponent(code)}/incidents`, { type, description }),
  resolveIncident: (code: string, id: string, resolution: string) =>
    req<void>("POST", `/api/ops/stations/${encodeURIComponent(code)}/incidents/${id}/resolve`, { resolution }),
  agentPool: (code: string, q: string) =>
    req<{ ward: string; agents: (StationAgent & { assigned_to: string | null })[] }>(
      "GET",
      `/api/ops/stations/${encodeURIComponent(code)}/agent-pool${qs({ q })}`,
    ),
  assignAgent: (code: string, userId: string) => req<void>("PUT", `/api/ops/stations/${encodeURIComponent(code)}/agents/${userId}`),
  unassignAgent: (code: string, userId: string) => req<void>("DELETE", `/api/ops/stations/${encodeURIComponent(code)}/agents/${userId}`),
  stationResults: (code: string, positionId: string) =>
    req<{
      position: Position;
      candidates: Candidate[];
      votes: Record<string, number>;
      rejected: number | null;
      submitted_at: string | null;
      turnout: number | null;
      registered: number;
    }>("GET", `/api/ops/stations/${encodeURIComponent(code)}/results${qs({ position_id: positionId })}`),
  submitResults: (code: string, body: { position_id: string; votes: Record<string, number>; rejected: number; confirm: boolean }) =>
    req<void>("POST", `/api/ops/stations/${encodeURIComponent(code)}/results`, body),

  turnout: (drill: Drill) => req<TurnoutMonitor>("GET", `/api/ops/turnout${qs(drill)}`),
  results: (positionId: string | undefined, drill: Drill) =>
    req<ResultsMonitor>("GET", `/api/ops/results${qs({ position_id: positionId, ...drill })}`),
  replay: (electionId: string, hour: number) => req<Replay>("GET", `/api/ops/replay${qs({ election_id: electionId, hour })}`),

  /** Downloads a CSV export with the bearer token (plain links can't carry it). */
  async downloadReport(kind: string, filename: string) {
    const res = await fetch(`${BASE}/api/ops/reports/${kind}`, { headers: { Authorization: `Bearer ${token.get()}` } });
    if (!res.ok) throw new ApiError(res.status, (await res.json().catch(() => ({}))).error ?? "Export failed");
    const url = URL.createObjectURL(await res.blob());
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
  },
  async reportText(kind: string) {
    const res = await fetch(`${BASE}/api/ops/reports/${kind}`, { headers: { Authorization: `Bearer ${token.get()}` } });
    if (!res.ok) throw new ApiError(res.status, (await res.json().catch(() => ({}))).error ?? "Export failed");
    return res.text();
  },

  settings: () => req<{ name: string; accent_color: string; contact_email: string | null; boundary: Scope }>("GET", "/api/settings"),
  updateSettings: (body: { name?: string; accent_color?: string; contact_email?: string }) =>
    req<{ name: string; accent_color: string; contact_email: string | null; boundary: Scope }>("PATCH", "/api/settings", body),
};

export const roleLabel: Record<string, string> = {
  owner: "Owner",
  executive: "Executive",
  admin: "Admin",
  chief_agent: "Chief Agent",
  manager: "Manager",
  agent: "Agent",
  member: "Member",
  viewer: "Viewer",
};

export const statusLabel: Record<StationStatus, string> = {
  not_open: "Not open",
  open: "Open",
  reporting: "Reporting",
  closed: "Closed",
  issue: "Issue",
};

export const statusTone: Record<StationStatus, "green" | "teal" | "grey" | "red" | "blue"> = {
  not_open: "grey",
  open: "green",
  reporting: "teal",
  closed: "grey",
  issue: "red",
};

export const opsRoles = new Set(["owner", "executive", "admin", "chief_agent", "manager", "agent"]);
export const slotLabel = (h: number) => `${h % 12 === 0 ? 12 : h % 12} ${h < 12 ? "AM" : "PM"}`;
export const pp = (n: number) => `${n > 0 ? "+" : ""}${Math.round(n)}pp`;
