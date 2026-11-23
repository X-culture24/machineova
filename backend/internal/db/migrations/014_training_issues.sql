-- Problems met during field trainings (no internet on the device, a device that fails, a chief's
-- location wrong in SDICS, sign-in trouble, …), typed by the team as they happen. Each may name the
-- chief concerned (as given: name, ID number, phone, location) and the training it happened at; the
-- issues report compiles them with a summary of every training.
CREATE TABLE training_issues (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id       UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    event_id     UUID REFERENCES events(id) ON DELETE SET NULL,
    category     TEXT NOT NULL CHECK (category IN ('internet', 'device', 'location', 'account', 'app', 'other')),
    chief_name   TEXT NOT NULL DEFAULT '',
    national_id  TEXT NOT NULL DEFAULT '',
    phone        TEXT NOT NULL DEFAULT '',
    location     TEXT NOT NULL DEFAULT '',
    description  TEXT NOT NULL,
    action_taken TEXT NOT NULL DEFAULT '',
    status       TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved')),
    reported_by  UUID NOT NULL REFERENCES users(id),
    reported_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at  TIMESTAMPTZ,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX training_issues_org_time_idx ON training_issues(org_id, reported_at DESC);
CREATE INDEX training_issues_event_idx ON training_issues(event_id);
