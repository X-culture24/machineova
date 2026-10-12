package api

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

type voter struct {
	NationalID    string  `json:"national_id"`
	Name          string  `json:"name"`
	Sex           string  `json:"sex"`
	DOB           string  `json:"dob"`
	Age           int     `json:"age"`
	County        string  `json:"county"`
	Constituency  string  `json:"constituency"`
	Ward          string  `json:"ward"`
	PollingCenter *string `json:"polling_center,omitempty"`
}

func (s *Server) registerLookup(ctx context.Context, nationalID string) (*voter, error) {
	var v voter
	var dob time.Time
	var pc string
	err := s.db.QueryRow(ctx, `
		SELECT national_id, name, sex, dob, county, constituency, ward, polling_center
		FROM register_voters WHERE national_id = $1`, nationalID).
		Scan(&v.NationalID, &v.Name, &v.Sex, &dob, &v.County, &v.Constituency, &v.Ward, &pc)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	v.DOB = dob.Format(time.DateOnly)
	v.Age = ageOn(dob, time.Now())
	v.PollingCenter = &pc
	return &v, nil
}

func ageOn(dob, now time.Time) int {
	age := now.Year() - dob.Year()
	if now.YearDay() < dob.YearDay() {
		age--
	}
	return age
}

// inArea reports whether a location falls within an area; nil area levels match anything.
func inArea(county, constituency, ward string, aCounty, aConst, aWard *string) bool {
	eq := func(a *string, v string) bool { return a == nil || strings.EqualFold(*a, v) }
	return eq(aCounty, county) && eq(aConst, constituency) && eq(aWard, ward)
}

type priorRecord struct {
	At    time.Time `json:"at"`
	By    string    `json:"by"`
	Where string    `json:"where,omitempty"`
}

// Lookup statuses, mirroring what operators see in the app.
const (
	statusReady            = "ready"
	statusAlreadyCheckedIn = "already_checked_in"
	statusNotOnList        = "not_on_list"
)

func (s *Server) checkinLookup(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	nid := normalizeID(r.URL.Query().Get("national_id"))
	if nid == "" {
		writeErr(w, http.StatusBadRequest, "national_id is required")
		return
	}
	e, err := s.loadEvent(r.Context(), p, r.URL.Query().Get("event_id"))
	if errors.Is(err, errNotFound) {
		writeErrCode(w, http.StatusForbidden, "not_assigned", "You are not assigned to this event")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	v, err := s.registerLookup(r.Context(), nid)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	resp := map[string]any{"status": statusReady, "voter": v, "in_register": v != nil, "in_region": true}
	if v != nil {
		resp["in_region"] = inArea(v.County, v.Constituency, v.Ward, e.County, e.Constituency, e.Ward)
	}

	if e.ListOnly {
		var ok bool
		if err := s.db.QueryRow(r.Context(), `SELECT EXISTS(SELECT 1 FROM event_participants WHERE event_id=$1 AND national_id=$2)`,
			e.ID, nid).Scan(&ok); err != nil {
			s.internal(w, r, err)
			return
		}
		if !ok {
			resp["status"] = statusNotOnList
			writeJSON(w, http.StatusOK, resp)
			return
		}
	}

	var prior priorRecord
	err = s.db.QueryRow(r.Context(), `
		SELECT c.checked_in_at, u.name FROM checkins c JOIN users u ON u.id = c.checked_in_by
		WHERE c.event_id = $1 AND c.national_id = $2 AND c.checkin_day = (now() AT TIME ZONE 'Africa/Nairobi')::date`,
		e.ID, nid).Scan(&prior.At, &prior.By)
	if err == nil {
		resp["status"] = statusAlreadyCheckedIn
		resp["previous"] = prior
	} else if !errors.Is(err, pgx.ErrNoRows) {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

type personInput struct {
	NationalID   string  `json:"national_id"`
	Name         string  `json:"name"`
	Sex          string  `json:"sex"`
	DOB          *string `json:"dob"`
	Phone        *string `json:"phone"`
	County       string  `json:"county"`
	Constituency string  `json:"constituency"`
	Ward         string  `json:"ward"`
}

// resolve fills blanks from the register and validates the result.
func (s *Server) resolvePerson(ctx context.Context, in *personInput) (string, error) {
	in.NationalID = normalizeID(in.NationalID)
	if in.NationalID == "" {
		return "national_id is required", nil
	}
	v, err := s.registerLookup(ctx, in.NationalID)
	if err != nil {
		return "", err
	}
	if v != nil {
		fill := func(dst *string, src string) {
			if strings.TrimSpace(*dst) == "" {
				*dst = src
			}
		}
		fill(&in.Name, v.Name)
		fill(&in.Sex, v.Sex)
		fill(&in.County, v.County)
		fill(&in.Constituency, v.Constituency)
		fill(&in.Ward, v.Ward)
		if in.DOB == nil || *in.DOB == "" {
			in.DOB = &v.DOB
		}
	}
	in.Sex = strings.ToUpper(strings.TrimSpace(in.Sex))
	if in.Name == "" || (in.Sex != "F" && in.Sex != "M") || in.County == "" || in.Constituency == "" || in.Ward == "" {
		return "name, sex (F/M), county, constituency and ward are required for voters not in the register", nil
	}
	if in.DOB != nil && *in.DOB == "" {
		in.DOB = nil
	}
	if in.DOB != nil {
		if _, err := time.Parse(time.DateOnly, *in.DOB); err != nil {
			return "dob must be YYYY-MM-DD", nil
		}
	}
	return "", nil
}

func (s *Server) createCheckin(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	if !p.OrgActive {
		writeErrCode(w, http.StatusForbidden, "org_inactive", "This organization is inactive")
		return
	}
	if !p.CanOperate() || !p.ModEvents {
		writeErr(w, http.StatusForbidden, "you do not have check-in access")
		return
	}
	var in struct {
		EventID string `json:"event_id"`
		personInput
	}
	if !readJSON(w, r, &in) {
		return
	}
	e, err := s.loadEvent(r.Context(), p, in.EventID)
	if errors.Is(err, errNotFound) {
		writeErrCode(w, http.StatusForbidden, "not_assigned", "You are not assigned to this event")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if !e.Active {
		writeErrCode(w, http.StatusConflict, "event_closed", "This event is closed")
		return
	}
	if msg, err := s.resolvePerson(r.Context(), &in.personInput); err != nil {
		s.internal(w, r, err)
		return
	} else if msg != "" {
		writeErr(w, http.StatusBadRequest, msg)
		return
	}
	if e.ListOnly {
		var ok bool
		if err := s.db.QueryRow(r.Context(), `SELECT EXISTS(SELECT 1 FROM event_participants WHERE event_id=$1 AND national_id=$2)`,
			e.ID, in.NationalID).Scan(&ok); err != nil {
			s.internal(w, r, err)
			return
		}
		if !ok {
			writeErrCode(w, http.StatusForbidden, statusNotOnList, "Not on the participant list")
			return
		}
	}
	inRegion := inArea(in.County, in.Constituency, in.Ward, e.County, e.Constituency, e.Ward)

	var id string
	var at time.Time
	err = s.db.QueryRow(r.Context(), `
		INSERT INTO checkins (org_id, event_id, national_id, name, sex, dob, phone, county, constituency, ward, in_region, checked_in_by,
		                      checked_in_at, checkin_day)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,($13::timestamptz AT TIME ZONE 'Africa/Nairobi')::date)
		RETURNING id, checked_in_at`,
		p.OrgID, e.ID, in.NationalID, in.Name, in.Sex, in.DOB, emptyNil(in.Phone), in.County, in.Constituency, in.Ward,
		inRegion, p.UserID, recordedAt(r)).Scan(&id, &at)
	if isUniqueViolation(err) {
		writeErrCode(w, http.StatusConflict, statusAlreadyCheckedIn, "Already checked in today")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"id": id, "checked_in_at": at, "in_region": inRegion, "name": in.Name})
}

type personRecord struct {
	ID           string    `json:"id"`
	NationalID   string    `json:"national_id"`
	Name         string    `json:"name"`
	Sex          string    `json:"sex"`
	Phone        *string   `json:"phone"`
	County       string    `json:"county"`
	Constituency string    `json:"constituency"`
	Ward         string    `json:"ward"`
	InRegion     *bool     `json:"in_region,omitempty"`
	At           time.Time `json:"at"`
	By           string    `json:"by"`
	GroupID      string    `json:"group_id"`
	GroupName    string    `json:"group_name"`
}

// listCheckins powers People › Check-ins. Members see only their own records.
func (s *Server) listCheckins(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	q := r.URL.Query()
	args := []any{p.OrgID, p.SeesAll(), p.UserID, nilIfEmpty(q.Get("event_id")), likePattern(q.Get("q"))}
	rows, err := s.db.Query(r.Context(), `
		SELECT c.id, c.national_id, c.name, c.sex, c.phone, c.county, c.constituency, c.ward, c.in_region,
		       c.checked_in_at, u.name, e.id, e.name
		FROM checkins c JOIN users u ON u.id = c.checked_in_by JOIN events e ON e.id = c.event_id
		WHERE c.org_id = $1 AND ($2 OR c.checked_in_by = $3)
		  AND ($4::uuid IS NULL OR c.event_id = $4::uuid)
		  AND ($5::text IS NULL OR c.name ILIKE $5 OR c.national_id LIKE $5)
		ORDER BY c.checked_in_at DESC LIMIT $6`, append(args, limitParam(q.Get("limit")))...)
	if err != nil {
		if isInvalidUUID(err) {
			writeErr(w, http.StatusBadRequest, "invalid event_id")
			return
		}
		s.internal(w, r, err)
		return
	}
	out, err := collect(rows, func(row pgx.Row) (personRecord, error) {
		var pr personRecord
		var inRegion bool
		err := row.Scan(&pr.ID, &pr.NationalID, &pr.Name, &pr.Sex, &pr.Phone, &pr.County, &pr.Constituency, &pr.Ward,
			&inRegion, &pr.At, &pr.By, &pr.GroupID, &pr.GroupName)
		pr.InRegion = &inRegion
		return pr, err
	})
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func nilIfEmpty(s string) *string {
	if s = strings.TrimSpace(s); s == "" {
		return nil
	}
	return &s
}

func likePattern(s string) *string {
	if s = strings.TrimSpace(s); s == "" {
		return nil
	}
	s = strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`).Replace(s)
	s = "%" + s + "%"
	return &s
}

func limitParam(s string) int {
	n, err := strconv.Atoi(s)
	if err != nil || n <= 0 || n > 500 {
		return 200
	}
	return n
}

func isInvalidUUID(err error) bool {
	var pg *pgconn.PgError
	return errors.As(err, &pg) && pg.Code == "22P02"
}
