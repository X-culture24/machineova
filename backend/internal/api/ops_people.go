package api

import (
	"errors"
	"net/http"
	"regexp"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"github.com/machinenova/checkin/backend/internal/auth"
)

type person struct {
	ID          string  `json:"id"`
	Name        string  `json:"name"`
	Role        string  `json:"role"`
	Phone       *string `json:"phone"`
	Email       *string `json:"email"`
	NationalID  *string `json:"national_id"`
	Scope       scope   `json:"scope"`
	AreaLabel   string  `json:"area"`
	Active      bool    `json:"active"`
	CanSignIn   bool    `json:"can_sign_in"`
	StationCode *string `json:"station_code"` // assignment in the active election
	StationName *string `json:"station_name"`
}

const personSelect = `
	SELECT u.id, u.name, u.role, u.phone, u.email, u.national_id, u.scope_county, u.scope_constituency, u.scope_ward,
	       u.active, u.password_hash IS NOT NULL, sa.station_code, ps.name, count(*) OVER ()
	FROM users u
	LEFT JOIN elections el ON el.org_id = u.org_id AND el.status = 'active'
	LEFT JOIN station_agents sa ON sa.election_id = el.id AND sa.user_id = u.id
	LEFT JOIN polling_stations ps ON ps.code = sa.station_code`

func scanPerson(row pgx.Row, total *int) (person, error) {
	var pr person
	err := row.Scan(&pr.ID, &pr.Name, &pr.Role, &pr.Phone, &pr.Email, &pr.NationalID,
		&pr.Scope.County, &pr.Scope.Constituency, &pr.Scope.Ward, &pr.Active, &pr.CanSignIn, &pr.StationCode, &pr.StationName, total)
	pr.AreaLabel = pr.Scope.label()
	return pr, err
}

var opsRoleList = []string{"owner", "executive", "admin", "chief_agent", "manager", "agent"}

// listPeople is the one directory: everyone in the principal's geography with an Election Ops role.
func (s *Server) listPeople(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOps(w, p) {
		return
	}
	b, err := s.orgBoundary(r.Context(), p.OrgID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	sc := p.userScope()
	q := r.URL.Query()
	pg := pageParams(q.Get("page"), q.Get("page_size"))
	roles := opsRoleList
	if role := q.Get("role"); role != "" {
		roles = []string{role}
	}
	var total int
	rows, err := s.db.Query(r.Context(), personSelect+`
		WHERE u.org_id = $1 AND u.role::text = ANY($2)
		  AND ($3::text IS NULL OR u.scope_county = $3) AND ($4::text IS NULL OR u.scope_constituency = $4)
		  AND ($5::text IS NULL OR u.scope_ward = $5)
		  AND ($6::text IS NULL OR u.name ILIKE $6 OR u.phone ILIKE $6 OR u.national_id ILIKE $6)
		ORDER BY array_position($2, u.role::text), u.name LIMIT $7 OFFSET $8`,
		p.OrgID, roles, sc.County, sc.Constituency, sc.Ward, likePattern(q.Get("q")), pg.size, pg.offset())
	if err != nil {
		s.internal(w, r, err)
		return
	}
	items, err := collect(rows, func(row pgx.Row) (person, error) { return scanPerson(row, &total) })
	if err != nil {
		s.internal(w, r, err)
		return
	}
	for i := range items {
		// Owners/executives without an explicit scope cover the whole organization.
		items[i].AreaLabel = items[i].Scope.orElse(b).label()
	}
	writeJSON(w, http.StatusOK, pg.response(items, total))
}

var phoneRe = regexp.MustCompile(`^\+?[0-9 ]{9,15}$`)

func (s *Server) addPerson(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOps(w, p) {
		return
	}
	var in struct {
		Role         string  `json:"role"`
		Name         string  `json:"name"`
		Phone        string  `json:"phone"`
		NationalID   string  `json:"national_id"`
		Email        *string `json:"email"`
		Password     *string `json:"password"`
		County       *string `json:"county"`
		Constituency *string `json:"constituency"`
		Ward         *string `json:"ward"`
		StationCode  *string `json:"station_code"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	if !p.CanAddRole(in.Role) {
		writeErr(w, http.StatusForbidden, "you can't add people with this role")
		return
	}
	in.Name, in.NationalID = strings.TrimSpace(in.Name), normalizeID(in.NationalID)
	in.Phone = strings.TrimSpace(in.Phone)
	if in.Name == "" || !phoneRe.MatchString(in.Phone) {
		writeErr(w, http.StatusBadRequest, "full name and a valid phone number are required")
		return
	}
	if len(in.NationalID) < 7 || len(in.NationalID) > 9 {
		writeErr(w, http.StatusBadRequest, "national ID must be 7–9 digits")
		return
	}
	email := emptyNil(in.Email)
	if email != nil {
		e := strings.ToLower(*email)
		email = &e
	}
	var hash *string
	if pw := emptyNil(in.Password); pw != nil {
		if email == nil || len(*pw) < 8 {
			writeErr(w, http.StatusBadRequest, "sign-in needs an email and an 8+ character password")
			return
		}
		h, err := auth.HashPassword(*pw)
		if err != nil {
			s.internal(w, r, err)
			return
		}
		hash = &h
	}

	// Cascading scope: the new person's area must sit inside the adder's, at the depth the role needs.
	b, err := s.orgBoundary(r.Context(), p.OrgID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	mine := p.userScope().orElse(b)
	theirs := scope{County: emptyNil(in.County), Constituency: emptyNil(in.Constituency), Ward: emptyNil(in.Ward)}.orElse(mine)
	need := map[string]string{"executive": "", "admin": "constituency", "chief_agent": "constituency", "manager": "ward", "agent": "ward"}[in.Role]
	if scopeRank[theirs.level()] < scopeRank[need] {
		writeErr(w, http.StatusBadRequest, "pick a "+need+" for this "+strings.ReplaceAll(in.Role, "_", " "))
		return
	}
	if !mine.contains(theirs) {
		writeErr(w, http.StatusForbidden, "that area is outside your scope ("+mine.label()+")")
		return
	}
	var known bool
	if err := s.db.QueryRow(r.Context(), `SELECT EXISTS(SELECT 1 FROM polling_stations
		WHERE ($1::text IS NULL OR county=$1) AND ($2::text IS NULL OR constituency=$2) AND ($3::text IS NULL OR ward=$3))`,
		theirs.County, theirs.Constituency, theirs.Ward).Scan(&known); err != nil {
		s.internal(w, r, err)
		return
	}
	if !known {
		writeErr(w, http.StatusBadRequest, theirs.label()+" is not in the station register")
		return
	}

	tx, err := s.db.Begin(r.Context())
	if err != nil {
		s.internal(w, r, err)
		return
	}
	defer tx.Rollback(r.Context())
	var id string
	err = tx.QueryRow(r.Context(), `
		INSERT INTO users (org_id, name, email, phone, national_id, password_hash, role, scope_county, scope_constituency, scope_ward,
		                   module_events, module_mobilization)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,false,false) RETURNING id`,
		p.OrgID, in.Name, email, in.Phone, in.NationalID, hash, in.Role, theirs.County, theirs.Constituency, theirs.Ward).Scan(&id)
	if isUniqueViolation(err) {
		var pg *pgconn.PgError
		errors.As(err, &pg)
		if strings.Contains(pg.ConstraintName, "national_id") {
			writeErr(w, http.StatusConflict, "someone with this national ID is already in the directory")
		} else {
			writeErr(w, http.StatusConflict, "a user with this email already exists")
		}
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if code := emptyNil(in.StationCode); code != nil && in.Role == "agent" {
		e, err := s.loadElection(r.Context(), p, "")
		if errors.Is(err, errNoActiveElection) {
			writeErr(w, http.StatusBadRequest, "no active election to assign a station in")
			return
		}
		if err != nil {
			s.internal(w, r, err)
			return
		}
		if msg, err := assignAgent(r.Context(), tx, e, *code, id, theirs, p.UserID); err != nil {
			s.internal(w, r, err)
			return
		} else if msg != "" {
			writeErr(w, http.StatusBadRequest, msg)
			return
		}
	}
	if err := tx.Commit(r.Context()); err != nil {
		s.internal(w, r, err)
		return
	}
	var total int
	pr, err := scanPerson(s.db.QueryRow(r.Context(), personSelect+` WHERE u.id = $1`, id), &total)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	pr.AreaLabel = pr.Scope.orElse(b).label()
	writeJSON(w, http.StatusCreated, pr)
}

// updatePerson toggles active status (and can grant sign-in) for someone below you in your scope.
func (s *Server) updatePerson(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOps(w, p) {
		return
	}
	var in struct {
		Active   *bool   `json:"active"`
		Email    *string `json:"email"`
		Password *string `json:"password"`
		Phone    *string `json:"phone"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	var role string
	var sc scope
	err := s.db.QueryRow(r.Context(), `SELECT role, scope_county, scope_constituency, scope_ward FROM users WHERE id::text=$1 AND org_id=$2`,
		r.PathValue("id"), p.OrgID).Scan(&role, &sc.County, &sc.Constituency, &sc.Ward)
	if errors.Is(err, pgx.ErrNoRows) {
		writeErr(w, http.StatusNotFound, "person not found")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	b, err := s.orgBoundary(r.Context(), p.OrgID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if !p.CanAddRole(role) || !p.userScope().orElse(b).contains(sc.orElse(b)) {
		writeErr(w, http.StatusForbidden, "you can't change this person")
		return
	}
	var hash *string
	if pw := emptyNil(in.Password); pw != nil {
		if len(*pw) < 8 {
			writeErr(w, http.StatusBadRequest, "password must be at least 8 characters")
			return
		}
		h, err := auth.HashPassword(*pw)
		if err != nil {
			s.internal(w, r, err)
			return
		}
		hash = &h
	}
	email := emptyNil(in.Email)
	if email != nil {
		e := strings.ToLower(*email)
		email = &e
	}
	_, err = s.db.Exec(r.Context(), `
		UPDATE users SET active = COALESCE($2, active), email = COALESCE($3, email),
		       password_hash = COALESCE($4, password_hash), phone = COALESCE($5, phone)
		WHERE id::text = $1`, r.PathValue("id"), in.Active, email, hash, emptyNil(in.Phone))
	if isUniqueViolation(err) {
		writeErr(w, http.StatusConflict, "a user with this email already exists")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
