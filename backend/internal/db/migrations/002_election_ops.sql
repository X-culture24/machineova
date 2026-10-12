-- Election Ops: elections scoped to geography, positions/candidates, the statutory
-- station register, field roles with geographic scope, and election-day operations.

-- Field roles. Checkin roles (owner/admin/member/viewer) keep working unchanged.
ALTER TYPE org_role ADD VALUE IF NOT EXISTS 'executive';
ALTER TYPE org_role ADD VALUE IF NOT EXISTS 'chief_agent';
ALTER TYPE org_role ADD VALUE IF NOT EXISTS 'manager';
ALTER TYPE org_role ADD VALUE IF NOT EXISTS 'agent';

-- Geographic scope of a person; NULL at a level means "everything below the level above".
ALTER TABLE users
    ADD COLUMN scope_county       TEXT,
    ADD COLUMN scope_constituency TEXT,
    ADD COLUMN scope_ward         TEXT,
    ADD COLUMN national_id        TEXT,
    -- Agents may be directory-only (no sign-in) until invited.
    ALTER COLUMN password_hash DROP NOT NULL,
    ALTER COLUMN email DROP NOT NULL;
CREATE UNIQUE INDEX users_org_national_id ON users(org_id, national_id) WHERE national_id IS NOT NULL;

ALTER TABLE organizations
    ADD COLUMN accent_color  TEXT NOT NULL DEFAULT '#0F8A7A',
    ADD COLUMN contact_email TEXT,
    ADD COLUMN trial         BOOLEAN NOT NULL DEFAULT FALSE;

-- Statutory reference data (shared, read-only to tenants).
CREATE TABLE polling_stations (
    code              TEXT PRIMARY KEY,
    name              TEXT NOT NULL,
    county            TEXT NOT NULL,
    constituency      TEXT NOT NULL,
    ward              TEXT NOT NULL,
    registered_voters INTEGER NOT NULL DEFAULT 0 CHECK (registered_voters >= 0)
);
CREATE INDEX polling_stations_geo ON polling_stations(county, constituency, ward);

CREATE TABLE parties (
    code   TEXT PRIMARY KEY, -- short code, e.g. UA
    name   TEXT NOT NULL,
    colour TEXT
);

CREATE TYPE election_status AS ENUM ('draft', 'active', 'completed');

CREATE TABLE elections (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id             UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name               TEXT NOT NULL,
    code               TEXT NOT NULL,
    election_date      DATE NOT NULL,
    scope_county       TEXT,
    scope_constituency TEXT,
    status             election_status NOT NULL DEFAULT 'draft',
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- One active election per organization scopes the whole workspace.
CREATE UNIQUE INDEX elections_one_active ON elections(org_id) WHERE status = 'active';

CREATE TYPE position_level AS ENUM ('national', 'county', 'constituency', 'ward');

CREATE TABLE positions (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    election_id UUID NOT NULL REFERENCES elections(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    level       position_level NOT NULL,
    sort        INTEGER NOT NULL DEFAULT 0,
    UNIQUE (election_id, name)
);

CREATE TABLE candidates (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    position_id UUID NOT NULL REFERENCES positions(id) ON DELETE CASCADE,
    -- The race this candidate stands in: county/constituency/ward name at the position's level.
    region      TEXT,
    name        TEXT NOT NULL,
    party_code  TEXT REFERENCES parties(code),
    is_ours     BOOLEAN NOT NULL DEFAULT FALSE,
    sort        INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX candidates_position ON candidates(position_id, region);

CREATE TYPE station_status AS ENUM ('not_open', 'open', 'reporting', 'closed', 'issue');

-- Operational state of each station in an election (rows created for every station in scope).
CREATE TABLE election_stations (
    election_id  UUID NOT NULL REFERENCES elections(id) ON DELETE CASCADE,
    station_code TEXT NOT NULL REFERENCES polling_stations(code),
    status       station_status NOT NULL DEFAULT 'not_open',
    updated_at   TIMESTAMPTZ,
    PRIMARY KEY (election_id, station_code)
);

CREATE TABLE station_agents (
    election_id  UUID NOT NULL REFERENCES elections(id) ON DELETE CASCADE,
    station_code TEXT NOT NULL,
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    assigned_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (election_id, user_id), -- an agent covers one station per election
    FOREIGN KEY (election_id, station_code) REFERENCES election_stations(election_id, station_code) ON DELETE CASCADE
);
CREATE INDEX station_agents_station ON station_agents(election_id, station_code);

-- Cumulative turnout per reporting slot (hour of day, local time).
CREATE TABLE turnout_reports (
    election_id  UUID NOT NULL,
    station_code TEXT NOT NULL,
    slot_hour    SMALLINT NOT NULL CHECK (slot_hour BETWEEN 0 AND 23),
    cumulative   INTEGER NOT NULL CHECK (cumulative >= 0),
    recorded_by  UUID NOT NULL REFERENCES users(id),
    recorded_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (election_id, station_code, slot_hour),
    FOREIGN KEY (election_id, station_code) REFERENCES election_stations(election_id, station_code) ON DELETE CASCADE
);

CREATE TABLE incidents (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    election_id  UUID NOT NULL,
    station_code TEXT NOT NULL,
    type         TEXT NOT NULL,
    description  TEXT NOT NULL DEFAULT '',
    reported_by  UUID NOT NULL REFERENCES users(id),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at  TIMESTAMPTZ,
    resolved_by  UUID REFERENCES users(id),
    resolution   TEXT,
    FOREIGN KEY (election_id, station_code) REFERENCES election_stations(election_id, station_code) ON DELETE CASCADE
);
CREATE INDEX incidents_open ON incidents(election_id, station_code) WHERE resolved_at IS NULL;

-- Form 37A: one verified submission per station per position.
CREATE TABLE result_submissions (
    election_id  UUID NOT NULL,
    station_code TEXT NOT NULL,
    position_id  UUID NOT NULL REFERENCES positions(id) ON DELETE CASCADE,
    rejected     INTEGER NOT NULL DEFAULT 0 CHECK (rejected >= 0),
    submitted_by UUID NOT NULL REFERENCES users(id),
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (election_id, station_code, position_id),
    FOREIGN KEY (election_id, station_code) REFERENCES election_stations(election_id, station_code) ON DELETE CASCADE
);

CREATE TABLE result_votes (
    election_id  UUID NOT NULL,
    station_code TEXT NOT NULL,
    position_id  UUID NOT NULL,
    candidate_id UUID NOT NULL REFERENCES candidates(id) ON DELETE CASCADE,
    votes        INTEGER NOT NULL CHECK (votes >= 0),
    PRIMARY KEY (election_id, station_code, candidate_id),
    FOREIGN KEY (election_id, station_code, position_id)
        REFERENCES result_submissions(election_id, station_code, position_id) ON DELETE CASCADE
);

-- Station activity feed; also the timeline for election replay.
CREATE TABLE station_events (
    id           BIGSERIAL PRIMARY KEY,
    election_id  UUID NOT NULL,
    station_code TEXT NOT NULL,
    kind         TEXT NOT NULL, -- status | turnout | incident | resolved | assign | results
    message      TEXT NOT NULL,
    user_id      UUID REFERENCES users(id) ON DELETE SET NULL,
    at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (election_id, station_code) REFERENCES election_stations(election_id, station_code) ON DELETE CASCADE
);
CREATE INDEX station_events_time ON station_events(election_id, at);

-- Platform email template library.
CREATE TABLE email_templates (
    key        TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    purpose    TEXT NOT NULL,
    subject    TEXT NOT NULL,
    body       TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO email_templates (key, name, purpose, subject, body) VALUES
('agent_invite', 'Agent invite', 'Sent when a member is added', 'Welcome to {{org_name}}',
 E'Hello {{recipient_name}},\n\nYou have been added to {{org_name}} as an agent for {{election_name}}.\n\nSign in here: {{sign_in_link}}'),
('turnout_digest', 'Daily turnout digest', 'Evening summary to owners & admins', '{{election_name}} — turnout {{turnout_pct}}',
 E'Hello {{recipient_name}},\n\nTurnout across {{org_name}} stands at {{turnout_pct}}.'),
('password_reset', 'Password reset', 'Self-service reset link', 'Reset your {{org_name}} password',
 E'Hello {{recipient_name}},\n\nUse this link to set a new password: {{sign_in_link}}'),
('results_announcement', 'Results announcement', 'Provisional winner per race', '{{election_name}} — provisional results',
 E'Hello {{recipient_name}},\n\nProvisional results for {{election_name}} are now available: {{sign_in_link}}');
