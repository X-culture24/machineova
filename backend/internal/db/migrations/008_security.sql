-- Account lockout after repeated failed sign-ins.
ALTER TABLE users
    ADD COLUMN failed_logins INT NOT NULL DEFAULT 0,
    ADD COLUMN locked_until  TIMESTAMPTZ;

-- Single-use, expiring links: invitations (set your first password) and password resets.
-- Only a SHA-256 of the token is stored.
CREATE TABLE auth_tokens (
    token_hash TEXT PRIMARY KEY,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind       TEXT NOT NULL CHECK (kind IN ('invite', 'reset')),
    expires_at TIMESTAMPTZ NOT NULL,
    used_at    TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX auth_tokens_user ON auth_tokens(user_id, created_at);

-- Audit trail: every sign-in and every change, append-only (enforced below).
-- No foreign keys so entries outlive the users and organizations they describe.
CREATE TABLE audit_log (
    id      BIGSERIAL PRIMARY KEY,
    at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    org_id  UUID,
    user_id UUID,
    actor   TEXT,
    action  TEXT NOT NULL,
    path    TEXT NOT NULL,
    status  INT NOT NULL,
    ip      TEXT
);
CREATE INDEX audit_log_org_at ON audit_log(org_id, at DESC);
CREATE INDEX audit_log_at ON audit_log(at DESC);

CREATE FUNCTION audit_log_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'audit_log is append-only';
END $$;
CREATE TRIGGER audit_log_no_change BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW EXECUTE FUNCTION audit_log_append_only();
CREATE TRIGGER audit_log_no_truncate BEFORE TRUNCATE ON audit_log
    FOR EACH STATEMENT EXECUTE FUNCTION audit_log_append_only();

-- The daily turnout digest goes out once per organization per day.
CREATE TABLE digest_runs (
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    day    DATE NOT NULL,
    PRIMARY KEY (org_id, day)
);
