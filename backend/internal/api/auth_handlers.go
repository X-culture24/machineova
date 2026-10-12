package api

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/machinenova/checkin/backend/internal/auth"
)

const rememberTTL = 14 * 24 * time.Hour

type meResponse struct {
	ID              string  `json:"id"`
	Name            string  `json:"name"`
	Email           string  `json:"email"`
	Role            string  `json:"role"`
	PlatformAdmin   bool    `json:"platform_admin"`
	ModEvents       bool    `json:"module_events"`
	ModMobilization bool    `json:"module_mobilization"`
	Org             *orgRef `json:"organization"`
	Scope           scope   `json:"scope"`
	ScopeLabel      string  `json:"scope_label"`
}

type orgRef struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Active      bool   `json:"active"`
	AccentColor string `json:"accent_color"`
	Boundary    scope  `json:"boundary"`
}

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Login    string `json:"login"` // email or user ID
		Password string `json:"password"`
		// Field devices may be offline for days; they ask for a longer-lived session.
		Remember bool `json:"remember"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	login := strings.TrimSpace(strings.ToLower(in.Login))
	id, status, code, msg := s.checkLogin(r.Context(), login, in.Password, clientIP(r))
	if status == http.StatusInternalServerError {
		s.internal(w, r, errors.New(msg))
		return
	}
	if status != http.StatusOK {
		// Same message for unknown user and wrong password; lockout says so explicitly.
		if code != "" {
			writeErrCode(w, status, code, msg)
		} else {
			writeErr(w, status, msg)
		}
		return
	}
	tokens := s.tokens
	if in.Remember {
		tokens.TTL = rememberTTL
	}
	tok, exp, err := tokens.Issue(id)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	p, err := s.loadPrincipal(r.Context(), id)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	me, err := s.meFor(r, p)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"token": tok, "expires_at": exp.Format(time.RFC3339), "user": me})
}

func (s *Server) me(w http.ResponseWriter, r *http.Request, p *Principal) {
	me, err := s.meFor(r, p)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, me)
}

func (s *Server) meFor(r *http.Request, p *Principal) (meResponse, error) {
	me := meResponse{ID: p.UserID, Name: p.Name, Email: p.Email, Role: p.Role,
		PlatformAdmin: p.PlatformAdmin, ModEvents: p.ModEvents, ModMobilization: p.ModMobilization,
		Scope: p.userScope()}
	if p.OrgID != "" {
		var o orgRef
		if err := s.db.QueryRow(r.Context(), `
			SELECT id, name, active, accent_color, boundary_county, boundary_constituency FROM organizations WHERE id=$1`, p.OrgID).
			Scan(&o.ID, &o.Name, &o.Active, &o.AccentColor, &o.Boundary.County, &o.Boundary.Constituency); err != nil {
			return me, err
		}
		me.Org = &o
		me.ScopeLabel = p.userScope().orElse(o.Boundary).label()
	}
	return me, nil
}

func (s *Server) changePassword(w http.ResponseWriter, r *http.Request, p *Principal) {
	var in struct {
		Current string `json:"current_password"`
		New     string `json:"new_password"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	if len(in.New) < 8 {
		writeErr(w, http.StatusBadRequest, "new password must be at least 8 characters")
		return
	}
	var hash string
	if err := s.db.QueryRow(r.Context(), `SELECT COALESCE(password_hash, '') FROM users WHERE id=$1`, p.UserID).Scan(&hash); err != nil {
		s.internal(w, r, err)
		return
	}
	if !auth.CheckPassword(hash, in.Current) {
		writeErr(w, http.StatusBadRequest, "current password is incorrect")
		return
	}
	newHash, err := auth.HashPassword(in.New)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if _, err := s.db.Exec(r.Context(), `UPDATE users SET password_hash=$1 WHERE id=$2`, newHash, p.UserID); err != nil {
		s.internal(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
