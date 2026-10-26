package api

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"regexp"
	"strings"

	"github.com/jackc/pgx/v5"

	"github.com/machinenova/checkin/backend/internal/auth"
)

type orgSummary struct {
	ID                   string  `json:"id"`
	Name                 string  `json:"name"`
	Slug                 string  `json:"slug"`
	BoundaryCounty       *string `json:"boundary_county"`
	BoundaryConstituency *string `json:"boundary_constituency"`
	Active               bool    `json:"active"`
	Trial                bool    `json:"trial"`
	AccentColor          string  `json:"accent_color"`
	Members              int     `json:"members"`
	Events               int     `json:"events"`
	Mobilized            int     `json:"mobilized"`
}

func requirePlatform(w http.ResponseWriter, p *Principal) bool {
	if !p.PlatformAdmin {
		writeErr(w, http.StatusForbidden, "platform admins only")
		return false
	}
	return true
}

const orgSummarySQL = `
	SELECT o.id, o.name, o.slug, o.boundary_county, o.boundary_constituency, o.active, o.trial, o.accent_color,
	       (SELECT count(*) FROM users u WHERE u.org_id = o.id),
	       (SELECT count(*) FROM events e WHERE e.org_id = o.id),
	       (SELECT count(*) FROM mobilizations m WHERE m.org_id = o.id)
	FROM organizations o`

func scanOrgSummary(row pgx.Row) (orgSummary, error) {
	var o orgSummary
	err := row.Scan(&o.ID, &o.Name, &o.Slug, &o.BoundaryCounty, &o.BoundaryConstituency, &o.Active, &o.Trial, &o.AccentColor,
		&o.Members, &o.Events, &o.Mobilized)
	return o, err
}

func (s *Server) platformListOrgs(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requirePlatform(w, p) {
		return
	}
	rows, err := s.db.Query(r.Context(), orgSummarySQL+` ORDER BY o.name`)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	out, err := collect(rows, scanOrgSummary)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

var nonSlug = regexp.MustCompile(`[^a-z0-9]+`)

// platformCreateOrg creates an organization together with its owner account.
func (s *Server) platformCreateOrg(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requirePlatform(w, p) {
		return
	}
	var in struct {
		Name                 string  `json:"name"`
		BoundaryCounty       *string `json:"boundary_county"`
		BoundaryConstituency *string `json:"boundary_constituency"`
		OwnerName            string  `json:"owner_name"`
		OwnerEmail           string  `json:"owner_email"`
		OwnerPassword        string  `json:"owner_password"`
		ContactEmail         *string `json:"contact_email"`
		AccentColor          *string `json:"accent_color"`
		Trial                bool    `json:"trial"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	in.OwnerEmail = strings.TrimSpace(strings.ToLower(in.OwnerEmail))
	if in.Name == "" || in.OwnerName == "" || !strings.Contains(in.OwnerEmail, "@") || len(in.OwnerPassword) < 8 {
		writeErr(w, http.StatusBadRequest, "name, owner_name, owner_email and an 8+ character owner_password are required")
		return
	}
	if in.AccentColor != nil && !hexColor.MatchString(*in.AccentColor) {
		writeErr(w, http.StatusBadRequest, "accent color must be a hex value like #0D9488")
		return
	}
	county, constituency, msg, err := s.registerBoundary(r.Context(), emptyNil(in.BoundaryCounty), emptyNil(in.BoundaryConstituency))
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if msg != "" {
		writeErr(w, http.StatusBadRequest, msg)
		return
	}
	in.BoundaryCounty, in.BoundaryConstituency = county, constituency
	hash, err := auth.HashPassword(in.OwnerPassword)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	slug := strings.Trim(nonSlug.ReplaceAllString(strings.ToLower(in.Name), "-"), "-")

	tx, err := s.db.Begin(r.Context())
	if err != nil {
		s.internal(w, r, err)
		return
	}
	defer tx.Rollback(r.Context())
	var orgID string
	err = tx.QueryRow(r.Context(), `
		INSERT INTO organizations (name, slug, boundary_county, boundary_constituency, contact_email, accent_color, trial)
		VALUES ($1,$2,$3,$4,$5,COALESCE($6,'#0F8A7A'),$7) RETURNING id`,
		in.Name, slug, emptyNil(in.BoundaryCounty), emptyNil(in.BoundaryConstituency), emptyNil(in.ContactEmail), in.AccentColor, in.Trial).Scan(&orgID)
	if isUniqueViolation(err) {
		writeErr(w, http.StatusConflict, "an organization with this name already exists")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	_, err = tx.Exec(r.Context(), `
		INSERT INTO users (org_id, name, email, password_hash, role) VALUES ($1,$2,$3,$4,'owner')`,
		orgID, in.OwnerName, in.OwnerEmail, hash)
	if isUniqueViolation(err) {
		writeErr(w, http.StatusConflict, "a user with the owner email already exists")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if err := tx.Commit(r.Context()); err != nil {
		s.internal(w, r, err)
		return
	}
	o, err := scanOrgSummary(s.db.QueryRow(r.Context(), orgSummarySQL+` WHERE o.id=$1`, orgID))
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, o)
}

func (s *Server) platformUpdateOrg(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requirePlatform(w, p) {
		return
	}
	var in struct {
		Active *bool   `json:"active"`
		Name   *string `json:"name"`
		Trial  *bool   `json:"trial"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	tag, err := s.db.Exec(r.Context(), `UPDATE organizations SET active=COALESCE($2, active), name=COALESCE($3, name), trial=COALESCE($4, trial) WHERE id::text=$1`,
		r.PathValue("id"), in.Active, in.Name, in.Trial)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if tag.RowsAffected() == 0 {
		writeErr(w, http.StatusNotFound, "organization not found")
		return
	}
	o, err := scanOrgSummary(s.db.QueryRow(r.Context(), orgSummarySQL+` WHERE o.id=$1`, r.PathValue("id")))
	if errors.Is(err, pgx.ErrNoRows) {
		writeErr(w, http.StatusNotFound, "organization not found")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, o)
}

// registerBoundary checks an organization boundary against the polling-station register and
// returns the register's spelling ("nairobi" → "Nairobi"). msg explains a boundary that matches nothing.
func (s *Server) registerBoundary(ctx context.Context, county, constituency *string) (*string, *string, string, error) {
	if county == nil {
		if constituency != nil {
			return nil, nil, "pick the county before the constituency", nil
		}
		return nil, nil, "", nil
	}
	var c, k *string
	err := s.db.QueryRow(ctx, `
		SELECT county, CASE WHEN $2::text IS NULL THEN NULL ELSE constituency END FROM polling_stations
		WHERE lower(county) = lower($1) AND ($2::text IS NULL OR lower(constituency) = lower($2)) LIMIT 1`,
		strings.TrimSpace(*county), constituency).Scan(&c, &k)
	if errors.Is(err, pgx.ErrNoRows) {
		if constituency != nil {
			return nil, nil, fmt.Sprintf("%s is not a constituency of %s in the polling-station register", *constituency, *county), nil
		}
		return nil, nil, *county + " is not a county in the polling-station register", nil
	}
	return c, k, "", err
}

// platformRegions lists counties › constituencies › wards for the boundary picker and the
// polling-station register, with station counts.
func (s *Server) platformRegions(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requirePlatform(w, p) {
		return
	}
	rows, err := s.db.Query(r.Context(), `
		SELECT county, constituency, ward, count(*) FROM polling_stations GROUP BY 1, 2, 3 ORDER BY 1, 2, 3`)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	type ward struct {
		Name     string `json:"name"`
		Stations int    `json:"stations"`
	}
	type constituency struct {
		Name     string `json:"name"`
		Stations int    `json:"stations"`
		Wards    []ward `json:"wards"`
	}
	type county struct {
		Name           string          `json:"name"`
		Stations       int             `json:"stations"`
		Constituencies []*constituency `json:"constituencies"`
	}
	out := []*county{}
	for rows.Next() {
		var c, k, wd string
		var n int
		if err := rows.Scan(&c, &k, &wd, &n); err != nil {
			s.internal(w, r, err)
			return
		}
		if len(out) == 0 || out[len(out)-1].Name != c {
			out = append(out, &county{Name: c})
		}
		cc := out[len(out)-1]
		if len(cc.Constituencies) == 0 || cc.Constituencies[len(cc.Constituencies)-1].Name != k {
			cc.Constituencies = append(cc.Constituencies, &constituency{Name: k})
		}
		kk := cc.Constituencies[len(cc.Constituencies)-1]
		kk.Wards = append(kk.Wards, ward{Name: wd, Stations: n})
		kk.Stations += n
		cc.Stations += n
	}
	if err := rows.Err(); err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}
