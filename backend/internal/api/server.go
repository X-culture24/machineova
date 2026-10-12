// Package api is the Checkin HTTP API.
package api

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/machinenova/checkin/backend/internal/auth"
	"github.com/machinenova/checkin/backend/internal/mail"
)

type Server struct {
	db          *pgxpool.Pool
	tokens      auth.Tokens
	corsOrigins map[string]bool
	mail        *mail.Mailer
	appURL      string
	apkPath     string
}

// Options are the optional extras; zero values disable each feature gracefully.
type Options struct {
	Mail    *mail.Mailer
	AppURL  string
	ApkPath string
}

// WithOptions sets the optional extras.
func (s *Server) WithOptions(o Options) *Server {
	s.mail, s.appURL, s.apkPath = o.Mail, strings.TrimRight(o.AppURL, "/"), o.ApkPath
	if s.mail == nil {
		s.mail = mail.FromEnv()
	}
	return s
}

func New(db *pgxpool.Pool, tokens auth.Tokens, corsOrigins string) *Server {
	origins := map[string]bool{}
	for _, o := range strings.Split(corsOrigins, ",") {
		if o = strings.TrimSpace(o); o != "" {
			origins[o] = true
		}
	}
	return &Server{db: db, tokens: tokens, corsOrigins: origins, mail: mail.FromEnv(), appURL: "http://localhost:5173"}
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})
	mux.HandleFunc("POST /api/auth/login", s.login)
	mux.HandleFunc("POST /api/auth/forgot", s.forgotPassword)
	mux.HandleFunc("POST /api/auth/redeem", s.redeemLink)

	// Authenticated org routes.
	a := func(pattern string, h func(http.ResponseWriter, *http.Request, *Principal)) {
		mux.Handle(pattern, s.authed(h))
	}
	a("GET /api/me", s.me)
	a("GET /api/audit", s.listAudit)
	a("GET /api/app", s.appInfo)
	a("GET /api/app/download", s.appDownload)
	a("POST /api/team/{id}/invite", s.sendInvite)
	a("POST /api/auth/change-password", s.changePassword)

	a("GET /api/dashboard", s.dashboard)
	a("GET /api/home", s.home)

	a("GET /api/events", s.listEvents)
	a("POST /api/events", s.createEvent)
	a("GET /api/events/{id}", s.getEvent)
	a("PATCH /api/events/{id}", s.updateEvent)
	a("PUT /api/events/{id}/assignments", s.setEventAssignments)
	a("PUT /api/events/{id}/participants", s.setEventParticipants)

	a("GET /api/checkins/lookup", s.checkinLookup)
	a("POST /api/checkins", s.createCheckin)
	a("GET /api/checkins", s.listCheckins)

	a("GET /api/drives", s.listDrives)
	a("POST /api/drives", s.createDrive)
	a("GET /api/drives/{id}", s.getDrive)
	a("PATCH /api/drives/{id}", s.updateDrive)
	a("PUT /api/drives/{id}/assignments", s.setDriveAssignments)

	a("GET /api/mobilizations/lookup", s.mobilizeLookup)
	a("POST /api/mobilizations", s.createMobilization)
	a("GET /api/mobilizations", s.listMobilizations)

	a("GET /api/insights/checkins", s.checkinInsights)
	a("GET /api/insights/mobilization", s.mobilizationInsights)
	a("GET /api/insights/coverage", s.coverage)
	a("GET /api/insights/registration", s.registrationStats)

	a("GET /api/team", s.listTeam)
	a("POST /api/team", s.createMember)
	a("PATCH /api/team/{id}", s.updateMember)

	// Election Ops.
	a("GET /api/ops/elections", s.listElections)
	a("POST /api/ops/elections", s.createElection)
	a("GET /api/ops/elections/{id}", s.getElection)
	a("POST /api/ops/elections/{id}/status", s.setElectionStatus)
	a("DELETE /api/ops/elections/{id}", s.deleteElection)
	a("GET /api/ops/races", s.listRaces)
	a("POST /api/ops/positions", s.addPosition)
	a("DELETE /api/ops/positions/{id}", s.deletePosition)
	a("POST /api/ops/candidates", s.addCandidate)
	a("PATCH /api/ops/candidates/{id}", s.updateCandidate)
	a("DELETE /api/ops/candidates/{id}", s.deleteCandidate)
	a("GET /api/ops/registry/stations", s.registryStations)
	a("GET /api/ops/registry/parties", s.registryParties)
	a("GET /api/ops/registry/regions", s.registryRegions)
	a("GET /api/ops/people", s.listPeople)
	a("POST /api/ops/people", s.addPerson)
	a("PATCH /api/ops/people/{id}", s.updatePerson)
	a("GET /api/ops/overview", s.opsOverview)
	a("GET /api/ops/stations", s.listStations)
	a("GET /api/ops/stations/{code}", s.getStation)
	a("POST /api/ops/stations/{code}/status", s.updateStationStatus)
	a("POST /api/ops/stations/{code}/turnout", s.recordTurnout)
	a("POST /api/ops/stations/{code}/incidents", s.reportIncident)
	a("POST /api/ops/stations/{code}/incidents/{id}/resolve", s.resolveIncident)
	a("GET /api/ops/stations/{code}/agent-pool", s.agentPool)
	a("PUT /api/ops/stations/{code}/agents/{user}", s.assignStationAgent)
	a("DELETE /api/ops/stations/{code}/agents/{user}", s.unassignStationAgent)
	a("GET /api/ops/stations/{code}/results", s.getStationResults)
	a("POST /api/ops/stations/{code}/results", s.submitStationResults)
	a("POST /api/ops/stations/{code}/results/verify", s.verifyStationResults)
	a("GET /api/ops/turnout", s.opsTurnout)
	a("GET /api/ops/results", s.opsResults)
	a("GET /api/ops/replay", s.opsReplay)
	a("GET /api/ops/reports/{kind}", s.opsReport)
	a("GET /api/settings", s.getSettings)
	a("PATCH /api/settings", s.updateSettings)

	// Platform console (MachineNova operators).
	a("GET /api/platform/overview", s.platformOverview)
	a("GET /api/platform/organizations/{id}", s.platformGetOrg)
	a("DELETE /api/platform/organizations/{id}", s.platformDeleteOrg)
	a("GET /api/platform/email-templates", s.platformTemplates)
	a("PUT /api/platform/email-templates/{key}", s.platformSaveTemplate)
	a("GET /api/platform/organizations", s.platformListOrgs)
	a("POST /api/platform/organizations", s.platformCreateOrg)
	a("PATCH /api/platform/organizations/{id}", s.platformUpdateOrg)

	return s.recoverer(s.logger(s.cors(mux)))
}

// ---- principal & permissions ----

type Principal struct {
	UserID          string
	OrgID           string // empty for platform admins
	Name            string
	Email           string
	Role            string
	PlatformAdmin   bool
	ModEvents       bool
	ModMobilization bool
	OrgActive       bool
	// Geographic scope for Election Ops roles (nil = unrestricted at that level).
	ScopeCounty       *string
	ScopeConstituency *string
	ScopeWard         *string
}

func (p *Principal) IsManager() bool  { return p.Role == "owner" || p.Role == "admin" }
func (p *Principal) CanOperate() bool { return p.Role != "viewer" }

// SeesAll reports whether the user sees every event/drive in the org, not just assigned ones.
func (p *Principal) SeesAll() bool { return p.Role != "member" }

type ctxKey struct{}

func (s *Server) authed(h func(http.ResponseWriter, *http.Request, *Principal)) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !ok {
			writeErr(w, http.StatusUnauthorized, "missing bearer token")
			return
		}
		uid, err := s.tokens.Verify(raw)
		if err != nil {
			writeErrCode(w, http.StatusUnauthorized, "token_invalid", "invalid or expired token")
			return
		}
		p, err := s.loadPrincipal(r.Context(), uid)
		if errors.Is(err, pgx.ErrNoRows) {
			// Distinct code: field apps erase their offline data when an account is revoked.
			writeErrCode(w, http.StatusUnauthorized, "account_inactive", "account not found or inactive")
			return
		}
		if err != nil {
			s.internal(w, r, err)
			return
		}
		r = r.WithContext(context.WithValue(r.Context(), ctxKey{}, p))
		s.auditChanges(w, r, p, func(w http.ResponseWriter) { s.withIdempotency(w, r, p, h) })
	})
}

func (s *Server) loadPrincipal(ctx context.Context, uid string) (*Principal, error) {
	var p Principal
	var orgID *string
	var orgActive *bool
	err := s.db.QueryRow(ctx, `
		SELECT u.id, u.org_id, u.name, COALESCE(u.email, ''), u.role, u.is_platform_admin,
		       u.module_events, u.module_mobilization, o.active,
		       u.scope_county, u.scope_constituency, u.scope_ward
		FROM users u LEFT JOIN organizations o ON o.id = u.org_id
		WHERE u.id = $1 AND u.active`, uid).
		Scan(&p.UserID, &orgID, &p.Name, &p.Email, &p.Role, &p.PlatformAdmin,
			&p.ModEvents, &p.ModMobilization, &orgActive,
			&p.ScopeCounty, &p.ScopeConstituency, &p.ScopeWard)
	if err != nil {
		return nil, err
	}
	if orgID != nil {
		p.OrgID = *orgID
	}
	p.OrgActive = orgActive != nil && *orgActive
	return &p, nil
}

// requireOrg rejects platform-only accounts from tenant endpoints.
func requireOrg(w http.ResponseWriter, p *Principal) bool {
	if p.OrgID == "" {
		writeErr(w, http.StatusForbidden, "this endpoint requires an organization account")
		return false
	}
	return true
}

func requireManager(w http.ResponseWriter, p *Principal) bool {
	if !requireOrg(w, p) {
		return false
	}
	if !p.IsManager() {
		writeErr(w, http.StatusForbidden, "only owners and admins can do this")
		return false
	}
	return true
}

// ---- middleware ----

func (s *Server) cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if o := r.Header.Get("Origin"); s.corsOrigins[o] || s.corsOrigins["*"] {
			w.Header().Set("Access-Control-Allow-Origin", o)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, Idempotency-Key, X-Recorded-At")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(code int) { w.status = code; w.ResponseWriter.WriteHeader(code) }

func (s *Server) logger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(sw, r)
		slog.Info("http", "method", r.Method, "path", r.URL.Path, "status", sw.status, "dur", time.Since(start).Round(time.Microsecond))
	})
}

func (s *Server) recoverer(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if v := recover(); v != nil {
				slog.Error("panic", "err", v, "path", r.URL.Path)
				writeErr(w, http.StatusInternalServerError, "internal error")
			}
		}()
		next.ServeHTTP(w, r)
	})
}

// ---- JSON helpers ----

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

type apiError struct {
	Error string `json:"error"`
	Code  string `json:"code,omitempty"`
}

func writeErr(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, apiError{Error: msg})
}

func writeErrCode(w http.ResponseWriter, status int, code, msg string) {
	writeJSON(w, status, apiError{Error: msg, Code: code})
}

func (s *Server) internal(w http.ResponseWriter, r *http.Request, err error) {
	slog.Error("internal error", "err", err, "path", r.URL.Path)
	writeErr(w, http.StatusInternalServerError, "internal error")
}

func readJSON(w http.ResponseWriter, r *http.Request, v any) bool {
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 2<<20))
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid JSON body: "+err.Error())
		return false
	}
	return true
}

// rows collects a pgx result into a slice using a per-row scan function.
func collect[T any](rows pgx.Rows, scan func(pgx.Row) (T, error)) ([]T, error) {
	defer rows.Close()
	out := []T{}
	for rows.Next() {
		v, err := scan(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, rows.Err()
}
