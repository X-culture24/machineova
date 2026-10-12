package api

import (
	"errors"
	"net/http"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"github.com/machinenova/checkin/backend/internal/auth"
)

type member struct {
	ID              string  `json:"id"`
	Name            string  `json:"name"`
	Email           string  `json:"email"`
	Phone           *string `json:"phone"`
	Role            string  `json:"role"`
	ModEvents       bool    `json:"module_events"`
	ModMobilization bool    `json:"module_mobilization"`
	Active          bool    `json:"active"`
}

func scanMember(row pgx.Row) (member, error) {
	var m member
	err := row.Scan(&m.ID, &m.Name, &m.Email, &m.Phone, &m.Role, &m.ModEvents, &m.ModMobilization, &m.Active)
	return m, err
}

const memberCols = `id, name, COALESCE(email, ''), phone, role, module_events, module_mobilization, active`

// memberColsAs is memberCols qualified with a table alias, for joins.
func memberColsAs(a string) string {
	return a + `.id, ` + a + `.name, COALESCE(` + a + `.email, ''), ` + a + `.phone, ` + a + `.role, ` +
		a + `.module_events, ` + a + `.module_mobilization, ` + a + `.active`
}

func (s *Server) listTeam(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	rows, err := s.db.Query(r.Context(), `SELECT `+memberCols+` FROM users WHERE org_id=$1 ORDER BY name`, p.OrgID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	out, err := collect(rows, scanMember)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

var validRoles = map[string]bool{"admin": true, "member": true, "viewer": true}

func (s *Server) createMember(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireManager(w, p) {
		return
	}
	var in struct {
		Name            string  `json:"name"`
		Email           string  `json:"email"`
		Phone           *string `json:"phone"`
		Role            string  `json:"role"`
		Password        string  `json:"password"`
		ModEvents       *bool   `json:"module_events"`
		ModMobilization *bool   `json:"module_mobilization"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	in.Email = strings.TrimSpace(strings.ToLower(in.Email))
	if in.Name == "" || !strings.Contains(in.Email, "@") {
		writeErr(w, http.StatusBadRequest, "name and a valid email are required")
		return
	}
	if !validRoles[in.Role] {
		writeErr(w, http.StatusBadRequest, "role must be admin, member or viewer")
		return
	}
	if in.Role == "admin" && p.Role != "owner" {
		writeErr(w, http.StatusForbidden, "only the owner can add admins")
		return
	}
	// TODO: replace with an emailed single-use invitation link once email delivery is wired up.
	if len(in.Password) < 8 {
		writeErr(w, http.StatusBadRequest, "initial password must be at least 8 characters")
		return
	}
	hash, err := auth.HashPassword(in.Password)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	m, err := scanMember(s.db.QueryRow(r.Context(), `
		INSERT INTO users (org_id, name, email, phone, role, password_hash, module_events, module_mobilization)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING `+memberCols,
		p.OrgID, in.Name, in.Email, in.Phone, in.Role, hash, boolOr(in.ModEvents, true), boolOr(in.ModMobilization, true)))
	if isUniqueViolation(err) {
		writeErr(w, http.StatusConflict, "a user with this email already exists")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, m)
}

func (s *Server) updateMember(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireManager(w, p) {
		return
	}
	var in struct {
		Role            *string `json:"role"`
		Active          *bool   `json:"active"`
		ModEvents       *bool   `json:"module_events"`
		ModMobilization *bool   `json:"module_mobilization"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	id := r.PathValue("id")
	var targetRole string
	err := s.db.QueryRow(r.Context(), `SELECT role FROM users WHERE id=$1 AND org_id=$2`, id, p.OrgID).Scan(&targetRole)
	if errors.Is(err, pgx.ErrNoRows) {
		writeErr(w, http.StatusNotFound, "member not found")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if targetRole == "owner" || (targetRole == "admin" && p.Role != "owner") {
		writeErr(w, http.StatusForbidden, "you cannot change this member")
		return
	}
	if in.Role != nil && (!validRoles[*in.Role] || (*in.Role == "admin" && p.Role != "owner")) {
		writeErr(w, http.StatusBadRequest, "invalid role")
		return
	}
	m, err := scanMember(s.db.QueryRow(r.Context(), `
		UPDATE users SET
			role = COALESCE($3::org_role, role),
			active = COALESCE($4, active),
			module_events = COALESCE($5, module_events),
			module_mobilization = COALESCE($6, module_mobilization)
		WHERE id=$1 AND org_id=$2 RETURNING `+memberCols,
		id, p.OrgID, in.Role, in.Active, in.ModEvents, in.ModMobilization))
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, m)
}

func boolOr(b *bool, def bool) bool {
	if b == nil {
		return def
	}
	return *b
}

func isForeignKeyViolation(err error) bool {
	var pg *pgconn.PgError
	return errors.As(err, &pg) && pg.Code == "23503"
}

func isUniqueViolation(err error) bool {
	var pg *pgconn.PgError
	return errors.As(err, &pg) && pg.Code == "23505"
}
