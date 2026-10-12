-- Offline sync: replay-safe writes. A client retrying a queued request with the same
-- Idempotency-Key gets the original response instead of a second write.
CREATE TABLE idempotency_keys (
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    key          TEXT NOT NULL,
    method       TEXT NOT NULL,
    path         TEXT NOT NULL,
    status       INTEGER,          -- NULL while the first request is still running
    content_type TEXT,
    body         BYTEA,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, key)
);
CREATE INDEX idempotency_keys_created ON idempotency_keys(created_at);
