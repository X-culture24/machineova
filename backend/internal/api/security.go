package api

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/machinenova/checkin/backend/internal/auth"
	"github.com/machinenova/checkin/backend/internal/mail"
)

// Account lockout: this many wrong passwords in a row locks sign-in for lockFor.
const (
	maxFailedLogins = 5
	lockFor         = 15 * time.Minute
	inviteTTL       = 72 * time.Hour
	resetTTL        = time.Hour
)

// ---- audit trail -------------------------------------------------------------------

// statusRecorder captures the response status for the audit log.
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func (r *statusRecorder) Write(b []byte) (int, error) {
	if r.status == 0 {
		r.status = http.StatusOK
	}
	return r.ResponseWriter.Write(b)
}

// audit appends one entry. Request bodies are never logged (they carry voter data).
func (s *Server) audit(ctx context.Context, orgID, userID, actor, action, path string, status int, ip string) {
	_, err := s.db.Exec(ctx, `
		INSERT INTO audit_log (org_id, user_id, actor, action, path, status, ip)
		VALUES (NULLIF($1,'')::uuid, NULLIF($2,'')::uuid, $3, $4, $5, $6, $7)`,
		orgID, userID, actor, action, path, status, ip)
	if err != nil {
		slog.Error("audit log write failed", "err", err, "action", action)
	}
}

func clientIP(r *http.Request) string {
	if f := r.Header.Get("X-Forwarded-For"); f != "" {
		return strings.TrimSpace(strings.Split(f, ",")[0])
	}
	if h, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		return h
	}
	return r.RemoteAddr
}

// auditChanges wraps an authenticated handler: every non-GET request is recorded with who,
// what (route), when, from where and the outcome.
func (s *Server) auditChanges(w http.ResponseWriter, r *http.Request, p *Principal, next func(http.ResponseWriter)) {
	// Voter lookups ("scans") are reads, but who looked people up is part of the trail.
	// The ID number itself is never written to the log.
	lookup := r.Pattern == "GET /api/checkins/lookup" || r.Pattern == "GET /api/mobilizations/lookup"
	if !lookup && (r.Method == http.MethodGet || r.Method == http.MethodHead || r.Method == http.MethodOptions) {
		next(w)
		return
	}
	rec := &statusRecorder{ResponseWriter: w}
	next(rec)
	if rec.status == 0 {
		rec.status = http.StatusOK
	}
	action := r.Pattern
	if action == "" {
		action = r.Method + " " + r.URL.Path
	}
	s.audit(context.WithoutCancel(r.Context()), p.OrgID, p.UserID, p.Email, action, r.URL.Path, rec.status, clientIP(r))
}

type auditEntry struct {
	At     time.Time `json:"at"`
	Actor  *string   `json:"actor"`
	Action string    `json:"action"`
	Path   string    `json:"path"`
	Status int       `json:"status"`
	IP     *string   `json:"ip"`
}

// listAudit: owners and admins see their organization's trail; platform admins see everything.
func (s *Server) listAudit(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !p.PlatformAdmin && !p.IsManager() {
		writeErr(w, http.StatusForbidden, "only owners and admins can view the activity log")
		return
	}
	q := r.URL.Query()
	limit := limitParam(q.Get("limit"))
	var before *time.Time
	if b := q.Get("before"); b != "" {
		if t, err := time.Parse(time.RFC3339Nano, b); err == nil {
			before = &t
		}
	}
	org := p.OrgID
	if p.PlatformAdmin {
		org = q.Get("org_id")
	}
	rows, err := s.db.Query(r.Context(), `
		SELECT at, actor, action, path, status, ip FROM audit_log
		WHERE ($1 = '' OR org_id = NULLIF($1,'')::uuid) AND ($2::timestamptz IS NULL OR at < $2)
		  AND ($3 = '' OR actor ILIKE '%' || $3 || '%' OR action ILIKE '%' || $3 || '%')
		ORDER BY at DESC LIMIT $4`, org, before, strings.TrimSpace(q.Get("q")), limit)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	out, err := collect(rows, func(row pgx.Row) (auditEntry, error) {
		var e auditEntry
		return e, row.Scan(&e.At, &e.Actor, &e.Action, &e.Path, &e.Status, &e.IP)
	})
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

// ---- sign-in with lockout ----------------------------------------------------------

// checkLogin verifies credentials with lockout. It returns the user id, or an HTTP status and
// message to send.
func (s *Server) checkLogin(ctx context.Context, login, password, ip string) (string, int, string, string) {
	var id, email string
	var orgID *string
	var hash *string
	var failed int
	var lockedUntil *time.Time
	err := s.db.QueryRow(ctx, `
		SELECT id, email, org_id, password_hash, failed_logins, locked_until FROM users
		WHERE active AND (lower(email) = $1 OR id::text = $1)`, login).
		Scan(&id, &email, &orgID, &hash, &failed, &lockedUntil)
	if errors.Is(err, pgx.ErrNoRows) {
		s.audit(ctx, "", "", login, "LOGIN failed (unknown account)", "/api/auth/login", http.StatusUnauthorized, ip)
		return "", http.StatusUnauthorized, "", "Login failed"
	}
	if err != nil {
		return "", http.StatusInternalServerError, "", err.Error()
	}
	org := ""
	if orgID != nil {
		org = *orgID
	}
	if lockedUntil != nil && lockedUntil.After(time.Now()) {
		mins := int(time.Until(*lockedUntil).Minutes()) + 1
		s.audit(ctx, org, id, email, "LOGIN blocked (locked)", "/api/auth/login", http.StatusTooManyRequests, ip)
		return "", http.StatusTooManyRequests, "account_locked",
			fmt.Sprintf("Too many failed sign-ins. Try again in %d minute%s, or reset your password.", mins, plural(mins))
	}
	if hash == nil || !auth.CheckPassword(*hash, password) {
		failed++
		if failed >= maxFailedLogins {
			_, err = s.db.Exec(ctx, `UPDATE users SET failed_logins = 0, locked_until = now() + $2::interval WHERE id = $1`,
				id, fmt.Sprintf("%d seconds", int(lockFor.Seconds())))
			s.audit(ctx, org, id, email, "LOGIN failed — account locked", "/api/auth/login", http.StatusTooManyRequests, ip)
			if err != nil {
				return "", http.StatusInternalServerError, "", err.Error()
			}
			return "", http.StatusTooManyRequests, "account_locked",
				fmt.Sprintf("Too many failed sign-ins. Try again in %d minutes, or reset your password.", int(lockFor.Minutes()))
		}
		_, _ = s.db.Exec(ctx, `UPDATE users SET failed_logins = $2 WHERE id = $1`, id, failed)
		s.audit(ctx, org, id, email, "LOGIN failed", "/api/auth/login", http.StatusUnauthorized, ip)
		return "", http.StatusUnauthorized, "", "Login failed"
	}
	_, _ = s.db.Exec(ctx, `UPDATE users SET failed_logins = 0, locked_until = NULL WHERE id = $1`, id)
	s.audit(ctx, org, id, email, "LOGIN", "/api/auth/login", http.StatusOK, ip)
	return id, http.StatusOK, "", ""
}

func plural(n int) string {
	if n == 1 {
		return ""
	}
	return "s"
}

// ---- invite & reset links ----------------------------------------------------------

func newToken() (raw, hash string, err error) {
	b := make([]byte, 32)
	if _, err = rand.Read(b); err != nil {
		return "", "", err
	}
	raw = hex.EncodeToString(b)
	sum := sha256.Sum256([]byte(raw))
	return raw, hex.EncodeToString(sum[:]), nil
}

func hashToken(raw string) string {
	sum := sha256.Sum256([]byte(strings.TrimSpace(raw)))
	return hex.EncodeToString(sum[:])
}

// recipient is what the email templates need about a user.
type recipient struct {
	ID, Name, Email, OrgName, Election string
}

func (s *Server) loadRecipient(ctx context.Context, userID string) (recipient, error) {
	var rc recipient
	var org, election *string
	err := s.db.QueryRow(ctx, `
		SELECT u.id, u.name, u.email, o.name,
		       (SELECT name FROM elections e WHERE e.org_id = u.org_id AND e.status = 'active' LIMIT 1)
		FROM users u LEFT JOIN organizations o ON o.id = u.org_id WHERE u.id = $1`, userID).
		Scan(&rc.ID, &rc.Name, &rc.Email, &org, &election)
	if org != nil {
		rc.OrgName = *org
	} else {
		rc.OrgName = "MachineNova"
	}
	if election != nil {
		rc.Election = *election
	} else {
		rc.Election = "your campaign"
	}
	return rc, err
}

// sendTemplate renders a platform email template for one recipient and sends it.
func (s *Server) sendTemplate(ctx context.Context, key string, rc recipient, extra map[string]string) error {
	if strings.HasSuffix(rc.Email, ".invalid") || !strings.Contains(rc.Email, "@") {
		return nil // directory-only people have placeholder addresses
	}
	var subject, body string
	if err := s.db.QueryRow(ctx, `SELECT subject, body FROM email_templates WHERE key = $1`, key).
		Scan(&subject, &body); err != nil {
		return fmt.Errorf("template %s: %w", key, err)
	}
	fields := map[string]string{"recipient_name": rc.Name, "org_name": rc.OrgName, "election_name": rc.Election,
		"sign_in_link": s.appURL}
	for k, v := range extra {
		fields[k] = v
	}
	return s.mail.Send(rc.Email, mail.Render(subject, fields), mail.Render(body, fields))
}

// issueLink creates a single-use link and emails it. kind is "invite" or "reset".
func (s *Server) issueLink(ctx context.Context, userID, kind string) error {
	raw, hash, err := newToken()
	if err != nil {
		return err
	}
	ttl, tpl, page := inviteTTL, "agent_invite", "/accept"
	if kind == "reset" {
		ttl, tpl, page = resetTTL, "password_reset", "/reset"
	}
	if _, err := s.db.Exec(ctx, `INSERT INTO auth_tokens (token_hash, user_id, kind, expires_at) VALUES ($1,$2,$3,$4)`,
		hash, userID, kind, time.Now().Add(ttl)); err != nil {
		return err
	}
	rc, err := s.loadRecipient(ctx, userID)
	if err != nil {
		return err
	}
	return s.sendTemplate(ctx, tpl, rc, map[string]string{"sign_in_link": s.appURL + page + "?token=" + raw})
}

// forgotPassword always answers the same way, so it can't be used to discover accounts.
func (s *Server) forgotPassword(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Login string `json:"login"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	login := strings.TrimSpace(strings.ToLower(in.Login))
	var id, org string
	err := s.db.QueryRow(r.Context(), `
		SELECT u.id, coalesce(u.org_id::text, '') FROM users u
		WHERE u.active AND (lower(u.email) = $1 OR u.id::text = $1)
		  AND (SELECT count(*) FROM auth_tokens t WHERE t.user_id = u.id AND t.kind = 'reset'
		       AND t.created_at > now() - interval '1 hour') < 3`, login).Scan(&id, &org)
	if err == nil {
		if err := s.issueLink(r.Context(), id, "reset"); err != nil {
			slog.Error("password reset email", "err", err)
		}
		s.audit(r.Context(), org, id, login, "PASSWORD reset requested", r.URL.Path, http.StatusOK, clientIP(r))
	} else if !errors.Is(err, pgx.ErrNoRows) {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true,
		"message": "If that account exists, we've emailed a link to reset the password. It expires in 1 hour."})
}

// redeemLink sets a password from an invite or reset link (single use, expiring).
func (s *Server) redeemLink(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Token    string `json:"token"`
		Password string `json:"password"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	if len(in.Password) < 8 {
		writeErr(w, http.StatusBadRequest, "password must be at least 8 characters")
		return
	}
	hash, err := auth.HashPassword(in.Password)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	tx, err := s.db.Begin(r.Context())
	if err != nil {
		s.internal(w, r, err)
		return
	}
	defer tx.Rollback(r.Context())
	var userID, kind, email, org string
	err = tx.QueryRow(r.Context(), `
		UPDATE auth_tokens t SET used_at = now() FROM users u
		WHERE t.token_hash = $1 AND t.used_at IS NULL AND t.expires_at > now() AND u.id = t.user_id AND u.active
		RETURNING t.user_id, t.kind, u.email, coalesce(u.org_id::text, '')`, hashToken(in.Token)).
		Scan(&userID, &kind, &email, &org)
	if errors.Is(err, pgx.ErrNoRows) {
		writeErrCode(w, http.StatusBadRequest, "link_invalid", "This link is invalid, already used or expired. Ask for a new one.")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if _, err := tx.Exec(r.Context(), `
		UPDATE users SET password_hash = $2, failed_logins = 0, locked_until = NULL WHERE id = $1`, userID, hash); err != nil {
		s.internal(w, r, err)
		return
	}
	// Any other outstanding links for this user stop working.
	if _, err := tx.Exec(r.Context(), `UPDATE auth_tokens SET used_at = now() WHERE user_id = $1 AND used_at IS NULL`, userID); err != nil {
		s.internal(w, r, err)
		return
	}
	if err := tx.Commit(r.Context()); err != nil {
		s.internal(w, r, err)
		return
	}
	s.audit(r.Context(), org, userID, email, "PASSWORD set via "+kind+" link", r.URL.Path, http.StatusOK, clientIP(r))
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "email": email})
}

// sendInvite (re)sends an invitation to a member of the caller's organization.
func (s *Server) sendInvite(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	if !p.IsManager() {
		writeErr(w, http.StatusForbidden, "only owners and admins can send invitations")
		return
	}
	id := r.PathValue("id")
	var email string
	err := s.db.QueryRow(r.Context(), `SELECT email FROM users WHERE id::text = $1 AND org_id = $2 AND active`, id, p.OrgID).Scan(&email)
	if errors.Is(err, pgx.ErrNoRows) {
		writeErr(w, http.StatusNotFound, "person not found")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if strings.HasSuffix(email, ".invalid") {
		writeErr(w, http.StatusBadRequest, "add an email address for this person first")
		return
	}
	if err := s.issueLink(r.Context(), id, "invite"); err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "sent_to": email, "email_configured": s.mail.Configured()})
}

// ---- field app download ------------------------------------------------------------

// appDownload serves the field app APK to signed-in organization members (not public).
func (s *Server) appDownload(w http.ResponseWriter, r *http.Request, p *Principal) {
	if s.apkPath == "" {
		writeErrCode(w, http.StatusNotFound, "app_unavailable", "The field app isn't published on this server yet")
		return
	}
	f, err := os.Open(s.apkPath)
	if err != nil {
		writeErrCode(w, http.StatusNotFound, "app_unavailable", "The field app isn't published on this server yet")
		return
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		s.internal(w, r, err)
		return
	}
	w.Header().Set("Content-Type", "application/vnd.android.package-archive")
	w.Header().Set("Content-Disposition", `attachment; filename="Checkin.apk"`)
	w.Header().Set("Content-Length", strconv.FormatInt(st.Size(), 10))
	s.audit(r.Context(), p.OrgID, p.UserID, p.Email, "APP downloaded", r.URL.Path, http.StatusOK, clientIP(r))
	http.ServeContent(w, r, "Checkin.apk", st.ModTime(), f)
}

func (s *Server) appInfo(w http.ResponseWriter, r *http.Request, p *Principal) {
	out := map[string]any{"available": false}
	if s.apkPath != "" {
		if st, err := os.Stat(s.apkPath); err == nil {
			out = map[string]any{"available": true, "size": st.Size(), "updated_at": st.ModTime()}
		}
	}
	writeJSON(w, http.StatusOK, out)
}
