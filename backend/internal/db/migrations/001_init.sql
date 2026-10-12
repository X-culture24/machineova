-- Checkin core schema: tenants, users, register, events/check-ins, drives/mobilizations.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE organizations (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name          TEXT NOT NULL,
    slug          TEXT NOT NULL UNIQUE,
    -- Geographic boundary the org may work within. NULL at a level = unrestricted below the level above.
    boundary_county       TEXT,
    boundary_constituency TEXT,
    active        BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TYPE org_role AS ENUM ('owner', 'admin', 'member', 'viewer');

CREATE TABLE users (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id            UUID REFERENCES organizations(id) ON DELETE CASCADE, -- NULL for platform admins
    email             TEXT NOT NULL UNIQUE,
    name              TEXT NOT NULL,
    phone             TEXT,
    password_hash     TEXT NOT NULL,
    role              org_role NOT NULL DEFAULT 'member',
    is_platform_admin BOOLEAN NOT NULL DEFAULT FALSE,
    module_events       BOOLEAN NOT NULL DEFAULT TRUE,
    module_mobilization BOOLEAN NOT NULL DEFAULT TRUE,
    active            BOOLEAN NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX users_org_idx ON users(org_id);
-- Only one owner per organization.
CREATE UNIQUE INDEX users_one_owner_per_org ON users(org_id) WHERE role = 'owner';

-- Statutory voter register (read-only reference, shared across orgs).
CREATE TABLE register_voters (
    national_id    TEXT PRIMARY KEY,
    name           TEXT NOT NULL,
    sex            CHAR(1) NOT NULL CHECK (sex IN ('F', 'M')),
    dob            DATE NOT NULL,
    county         TEXT NOT NULL,
    constituency   TEXT NOT NULL,
    ward           TEXT NOT NULL,
    polling_center TEXT NOT NULL
);

CREATE TABLE events (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id            UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name              TEXT NOT NULL,
    venue             TEXT NOT NULL DEFAULT '',
    county            TEXT,
    constituency      TEXT,
    ward              TEXT,
    starts_at         TIMESTAMPTZ NOT NULL,
    ends_at           TIMESTAMPTZ,
    active            BOOLEAN NOT NULL DEFAULT TRUE,
    region_restricted BOOLEAN NOT NULL DEFAULT FALSE,
    list_only         BOOLEAN NOT NULL DEFAULT FALSE,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX events_org_idx ON events(org_id);

CREATE TABLE event_assignments (
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    user_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    PRIMARY KEY (event_id, user_id)
);

CREATE TABLE event_participants (
    event_id    UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    national_id TEXT NOT NULL,
    PRIMARY KEY (event_id, national_id)
);

CREATE TABLE checkins (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id        UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    event_id      UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    national_id   TEXT NOT NULL,
    name          TEXT NOT NULL,
    sex           CHAR(1) NOT NULL CHECK (sex IN ('F', 'M')),
    dob           DATE,
    phone         TEXT,
    county        TEXT NOT NULL,
    constituency  TEXT NOT NULL,
    ward          TEXT NOT NULL,
    in_region     BOOLEAN NOT NULL,
    checked_in_by UUID NOT NULL REFERENCES users(id),
    checked_in_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    checkin_day   DATE NOT NULL DEFAULT (now() AT TIME ZONE 'Africa/Nairobi')::date,
    -- "Already checked in today": one check-in per voter per event per day.
    UNIQUE (event_id, national_id, checkin_day)
);
CREATE INDEX checkins_event_idx ON checkins(event_id, checked_in_at);
CREATE INDEX checkins_org_time_idx ON checkins(org_id, checked_in_at);

-- Mobilization drives (a.k.a. mobilization regions) with registration targets.
CREATE TABLE drives (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id       UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name         TEXT NOT NULL,
    county       TEXT,
    constituency TEXT,
    ward         TEXT,
    target       INTEGER NOT NULL DEFAULT 0 CHECK (target >= 0),
    target_date  DATE,
    active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX drives_org_idx ON drives(org_id);

CREATE TABLE drive_assignments (
    drive_id UUID NOT NULL REFERENCES drives(id) ON DELETE CASCADE,
    user_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    PRIMARY KEY (drive_id, user_id)
);

CREATE TABLE mobilizations (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id       UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    drive_id     UUID NOT NULL REFERENCES drives(id) ON DELETE CASCADE,
    national_id  TEXT NOT NULL,
    name         TEXT NOT NULL,
    sex          CHAR(1) NOT NULL CHECK (sex IN ('F', 'M')),
    dob          DATE,
    phone        TEXT,
    county       TEXT NOT NULL,
    constituency TEXT NOT NULL,
    ward         TEXT NOT NULL,
    mobilized_by UUID NOT NULL REFERENCES users(id),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- A voter can be mobilized once per organization.
    UNIQUE (org_id, national_id)
);
CREATE INDEX mobilizations_drive_idx ON mobilizations(drive_id, created_at);
