// Typed client for the Checkin Go API.

export type Role = "owner" | "admin" | "member" | "viewer" | "executive" | "chief_agent" | "manager" | "agent";

export interface Me {
  id: string;
  name: string;
  email: string;
  role: Role;
  platform_admin: boolean;
  module_events: boolean;
  module_mobilization: boolean;
  organization: {
    id: string;
    name: string;
    active: boolean;
    accent_color: string;
    boundary: { county: string | null; constituency: string | null; ward: string | null };
  } | null;
  scope: { county: string | null; constituency: string | null; ward: string | null };
  scope_label: string;
}

export interface EventItem {
  id: string;
  name: string;
  venue: string;
  county: string | null;
  constituency: string | null;
  ward: string | null;
  starts_at: string;
  ends_at: string | null;
  active: boolean;
  region_restricted: boolean;
  list_only: boolean;
  checkins: number;
  unique: number;
  out_of_region: number;
  assigned: number;
  participants: number;
}

export interface Drive {
  id: string;
  name: string;
  county: string | null;
  constituency: string | null;
  ward: string | null;
  target: number;
  target_date: string | null;
  active: boolean;
  mobilized: number;
  remaining: number;
  progress: number;
  assigned: number;
}

export interface Member {
  id: string;
  name: string;
  email: string;
  phone: string | null;
  role: Role;
  module_events: boolean;
  module_mobilization: boolean;
  active: boolean;
}

export interface Voter {
  national_id: string;
  name: string;
  sex: "F" | "M" | "";
  dob: string;
  age: number;
  county: string;
  constituency: string;
  ward: string;
  polling_center?: string;
  /** Voter registration date (YYYY-MM-DD), registered voters only. */
  registered_on?: string;
  /** Which reference resolved the ID: the voter register, or national ID records only. */
  source: "voter_register" | "id_registry";
}

export interface Prior {
  at: string;
  by: string;
  where?: string;
}

export interface Lookup {
  status: "ready" | "already_checked_in" | "not_on_list" | "already_mobilized";
  voter: Voter | null;
  in_register: boolean;
  /** On the voter register specifically (false for ID-registry-only matches). */
  registered_voter?: boolean;
  in_region?: boolean;
  previous?: Prior | null;
}

export interface PersonRecord {
  id: string;
  national_id: string;
  name: string;
  sex: "F" | "M";
  phone: string | null;
  county: string;
  constituency: string;
  ward: string;
  in_region?: boolean;
  at: string;
  by: string;
  group_id: string;
  group_name: string;
}

export interface NameCount {
  name: string;
  count: number;
}

export interface Dashboard {
  total_events: number;
  active_events: number;
  voters_mobilized: number;
  active_regions: number;
  team_members: number;
  checkins_7d: number;
  top_regions: NameCount[];
  recent_events: EventItem[];
}

export interface CheckinInsights {
  event: EventItem;
  day: string;
  total: number;
  unique: number;
  in_region_rate: number;
  peak_hour: number | null;
  by_hour: { hour: number; count: number }[];
  female: number;
  male: number;
}

export interface Pace {
  days_left: number;
  to_hit_target: number;
  pace_needed: number;
  current_pace: number;
  status: "ahead" | "on_track" | "behind" | "reached";
  momentum: "rising" | "steady" | "cooling";
}

export interface MobilizationInsights {
  drive: Drive;
  today: number;
  top_mobilizers: NameCount[];
  daily: { day: string; count: number }[];
  pace: Pace | null;
}

export interface OrgSummary {
  id: string;
  name: string;
  slug: string;
  boundary_county: string | null;
  boundary_constituency: string | null;
  active: boolean;
  trial: boolean;
  accent_color: string;
  members: number;
  events: number;
  mobilized: number;
}

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
    public code?: string,
    public body?: Record<string, unknown>,
  ) {
    super(message);
  }
}

const TOKEN_KEY = "checkin.token";

export const token = {
  get(): string | null {
    try {
      return localStorage.getItem(TOKEN_KEY);
    } catch {
      return null;
    }
  },
  set(t: string | null) {
    try {
      if (t) localStorage.setItem(TOKEN_KEY, t);
      else localStorage.removeItem(TOKEN_KEY);
    } catch {
      /* storage unavailable: session lasts for this tab only */
    }
  },
};

let onUnauthorized: () => void = () => {};
export function setUnauthorizedHandler(fn: () => void) {
  onUnauthorized = fn;
}

const BASE = import.meta.env.VITE_API_URL ?? "";

async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  const headers: Record<string, string> = {};
  const t = token.get();
  if (t) headers.Authorization = `Bearer ${t}`;
  if (body !== undefined) headers["Content-Type"] = "application/json";
  const res = await fetch(BASE + path, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (res.status === 204) return undefined as T;
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    if (res.status === 401 && path !== "/api/auth/login") onUnauthorized();
    throw new ApiError(res.status, data.error ?? res.statusText, data.code, data);
  }
  return data as T;
}

const qs = (params: Record<string, string | undefined>) => {
  const p = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) if (v) p.set(k, v);
  const s = p.toString();
  return s ? `?${s}` : "";
};

export type PersonInput = {
  national_id: string;
  name?: string;
  sex?: string;
  dob?: string;
  phone?: string;
  county?: string;
  constituency?: string;
  ward?: string;
};

export const api = {
  login: (login: string, password: string) =>
    request<{ token: string; expires_at: string; user: Me }>("POST", "/api/auth/login", { login, password }),
  me: () => request<Me>("GET", "/api/me"),
  changePassword: (current_password: string, new_password: string) =>
    request<void>("POST", "/api/auth/change-password", { current_password, new_password }),

  dashboard: () => request<Dashboard>("GET", "/api/dashboard"),

  events: (activeOnly = false) =>
    request<{ summary: { total: number; active: number; closed: number; checkins: number }; items: EventItem[] }>(
      "GET",
      `/api/events${qs({ active: activeOnly ? "true" : undefined })}`,
    ),
  event: (id: string) => request<{ event: EventItem; assigned_users: Member[] }>("GET", `/api/events/${id}`),
  createEvent: (body: Partial<EventItem>) => request<EventItem>("POST", "/api/events", body),
  updateEvent: (id: string, body: Partial<EventItem>) => request<EventItem>("PATCH", `/api/events/${id}`, body),
  setEventAssignments: (id: string, user_ids: string[]) =>
    request<{ assigned: number }>("PUT", `/api/events/${id}/assignments`, { user_ids }),
  setEventParticipants: (id: string, national_ids: string[]) =>
    request<{ participants: number }>("PUT", `/api/events/${id}/participants`, { national_ids }),

  checkinLookup: (event_id: string, national_id: string) =>
    request<Lookup>("GET", `/api/checkins/lookup${qs({ event_id, national_id })}`),
  checkin: (event_id: string, p: PersonInput) =>
    request<{ id: string; in_region: boolean; name: string }>("POST", "/api/checkins", { event_id, ...p }),
  checkins: (params: { event_id?: string; q?: string } = {}) =>
    request<PersonRecord[]>("GET", `/api/checkins${qs(params)}`),

  drives: (activeOnly = false) =>
    request<{
      summary: {
        active_regions: number;
        mobilized: number;
        target: number;
        boundary_county: string | null;
        boundary_constituency: string | null;
        org_active: boolean;
      };
      items: Drive[];
    }>("GET", `/api/drives${qs({ active: activeOnly ? "true" : undefined })}`),
  drive: (id: string) => request<{ drive: Drive; assigned_users: Member[] }>("GET", `/api/drives/${id}`),
  createDrive: (body: Partial<Drive>) => request<Drive>("POST", "/api/drives", body),
  updateDrive: (id: string, body: Partial<Drive>) => request<Drive>("PATCH", `/api/drives/${id}`, body),
  setDriveAssignments: (id: string, user_ids: string[]) =>
    request<{ assigned: number }>("PUT", `/api/drives/${id}/assignments`, { user_ids }),

  mobilizeLookup: (national_id: string) =>
    request<Lookup>("GET", `/api/mobilizations/lookup${qs({ national_id })}`),
  mobilize: (drive_id: string, p: PersonInput) =>
    request<{ id: string; name: string }>("POST", "/api/mobilizations", { drive_id, ...p }),
  mobilizations: (params: { drive_id?: string; q?: string } = {}) =>
    request<PersonRecord[]>("GET", `/api/mobilizations${qs(params)}`),

  checkinInsights: (event_id: string, day?: string) =>
    request<CheckinInsights>("GET", `/api/insights/checkins${qs({ event_id, day })}`),
  mobilizationInsights: (drive_id: string) =>
    request<MobilizationInsights>("GET", `/api/insights/mobilization${qs({ drive_id })}`),

  team: () => request<Member[]>("GET", "/api/team"),
  createMember: (body: Partial<Member> & { password: string }) => request<Member>("POST", "/api/team", body),
  updateMember: (id: string, body: Partial<Member>) => request<Member>("PATCH", `/api/team/${id}`, body),

  orgs: () => request<OrgSummary[]>("GET", "/api/platform/organizations"),
  createOrg: (body: {
    name: string;
    boundary_county?: string;
    boundary_constituency?: string;
    owner_name: string;
    owner_email: string;
    owner_password: string;
    contact_email?: string;
    accent_color?: string;
    trial?: boolean;
  }) => request<OrgSummary>("POST", "/api/platform/organizations", body),
  platformOverview: () =>
    request<{ organizations: number; active: number; trial: number; members: number; stations: number; agents: number }>(
      "GET",
      "/api/platform/overview",
    ),
  org: (id: string) =>
    request<{
      organization: OrgSummary;
      details: { accent_color: string; contact_email: string | null; trial: boolean; stations: number; agents: number };
      admins: Member[];
    }>("GET", `/api/platform/organizations/${id}`),
  deleteOrg: (id: string, confirm_name: string) => request<void>("DELETE", `/api/platform/organizations/${id}`, { confirm_name }),
  templates: () =>
    request<{
      templates: { key: string; name: string; purpose: string; subject: string; body: string; updated_at: string }[];
      merge_fields: string[];
    }>("GET", "/api/platform/email-templates"),
  saveTemplate: (key: string, subject: string, body: string) =>
    request<void>("PUT", `/api/platform/email-templates/${key}`, { subject, body }),
  updateOrg: (id: string, body: { active?: boolean; name?: string; trial?: boolean }) =>
    request<OrgSummary>("PATCH", `/api/platform/organizations/${id}`, body),
};
