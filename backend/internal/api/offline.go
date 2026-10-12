package api

import (
	"bytes"
	"context"
	"errors"
	"math/rand/v2"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
)

// ---- idempotent writes ----

// captureWriter buffers a handler's response so it can be stored and replayed.
type captureWriter struct {
	header http.Header
	status int
	body   bytes.Buffer
}

func (c *captureWriter) Header() http.Header         { return c.header }
func (c *captureWriter) Write(b []byte) (int, error) { return c.body.Write(b) }
func (c *captureWriter) WriteHeader(code int)        { c.status = code }

const maxIdempotencyKey = 100

// withIdempotency runs a write once per (user, Idempotency-Key); retries replay the stored response.
// Requests without the header, and GETs, pass straight through.
func (s *Server) withIdempotency(w http.ResponseWriter, r *http.Request, p *Principal, h func(http.ResponseWriter, *http.Request, *Principal)) {
	key := r.Header.Get("Idempotency-Key")
	if key == "" || r.Method == http.MethodGet {
		h(w, r, p)
		return
	}
	if len(key) > maxIdempotencyKey {
		writeErr(w, http.StatusBadRequest, "Idempotency-Key is too long")
		return
	}
	ctx := r.Context()
	if rand.IntN(200) == 0 {
		s.db.Exec(context.WithoutCancel(ctx), `DELETE FROM idempotency_keys WHERE created_at < now() - interval '14 days'`)
	}
	tag, err := s.db.Exec(ctx, `INSERT INTO idempotency_keys (user_id, key, method, path) VALUES ($1,$2,$3,$4) ON CONFLICT DO NOTHING`,
		p.UserID, key, r.Method, r.URL.Path)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if tag.RowsAffected() == 0 {
		var method, path string
		var status *int
		var ctype *string
		var body []byte
		err := s.db.QueryRow(ctx, `SELECT method, path, status, content_type, body FROM idempotency_keys WHERE user_id=$1 AND key=$2`,
			p.UserID, key).Scan(&method, &path, &status, &ctype, &body)
		if errors.Is(err, pgx.ErrNoRows) { // expired between the two statements: run it fresh
			h(w, r, p)
			return
		}
		if err != nil {
			s.internal(w, r, err)
			return
		}
		if method != r.Method || path != r.URL.Path {
			writeErr(w, http.StatusUnprocessableEntity, "Idempotency-Key was already used for a different request")
			return
		}
		if status == nil {
			writeErrCode(w, http.StatusConflict, "in_progress", "the original request is still being processed — retry shortly")
			return
		}
		w.Header().Set("Idempotent-Replay", "true")
		if ctype != nil {
			w.Header().Set("Content-Type", *ctype)
		}
		w.WriteHeader(*status)
		w.Write(body)
		return
	}

	cw := &captureWriter{header: w.Header(), status: http.StatusOK}
	h(cw, r, p)
	if cw.status >= 500 {
		// Server errors are not final: let the client's retry run the handler again.
		s.db.Exec(context.WithoutCancel(ctx), `DELETE FROM idempotency_keys WHERE user_id=$1 AND key=$2`, p.UserID, key)
	} else if _, err := s.db.Exec(context.WithoutCancel(ctx), `UPDATE idempotency_keys SET status=$3, content_type=$4, body=$5 WHERE user_id=$1 AND key=$2`,
		p.UserID, key, cw.status, cw.header.Get("Content-Type"), cw.body.Bytes()); err != nil {
		s.internal(w, r, err)
		return
	}
	w.WriteHeader(cw.status)
	w.Write(cw.body.Bytes())
}

// ---- device time ----

// Records captured offline carry the time they really happened in X-Recorded-At (RFC 3339).
// Clocks that are clearly wrong (future, or older than a week) fall back to server time.
const (
	maxClockAhead = 5 * time.Minute
	maxOfflineAge = 7 * 24 * time.Hour
)

func recordedAt(r *http.Request) time.Time {
	now := time.Now()
	t, err := time.Parse(time.RFC3339, r.Header.Get("X-Recorded-At"))
	if err != nil || t.After(now.Add(maxClockAhead)) || t.Before(now.Add(-maxOfflineAge)) {
		return now
	}
	if t.After(now) {
		return now
	}
	return t
}
