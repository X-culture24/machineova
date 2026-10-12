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

	"github.com/machinenova/checkin/backend/internal/places"
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
	// RegisteredOn is the voter registration date (voter-register matches only).
	RegisteredOn *string `json:"registered_on,omitempty"`
	// Source is which reference resolved the ID: sourceVoterRegister or sourceIDRegistry.
	Source string `json:"source"`
	// Home is where the person comes from per their national ID record (NRB), for any match
	// the ID records know — shown when someone is outside the event/drive area.
	Home *homeArea `json:"home,omitempty"`
}

type homeArea struct {
	County      *string `json:"county,omitempty"`
	SubCounty   *string `json:"sub_county,omitempty"`
	Division    *string `json:"division,omitempty"`
	Location    *string `json:"location,omitempty"`
	SubLocation *string `json:"sub_location,omitempty"`
	Village     *string `json:"village,omitempty"`
}

// tidy puts NRB upper-case names into display case (county names into their official form).
func (h *homeArea) tidy() {
	if h.County != nil {
		c := places.CountyName(*h.County)
		h.County = &c
	}
	for _, f := range []**string{&h.SubCounty, &h.Division, &h.Location, &h.SubLocation, &h.Village} {
		if *f != nil {
			t := places.TitleCase(**f)
			*f = &t
		}
	}
}

func str(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}

const (
	sourceVoterRegister = "voter_register"
	sourceIDRegistry    = "id_registry"
)

// registerLookup resolves an ID against the voter register, falling back to the national
// ID registry (NRB). It returns nil when neither knows the ID.
func (s *Server) registerLookup(ctx context.Context, nationalID string) (*voter, error) {
	var v voter
	var name, sex *string
	var dob, regOn *time.Time
	var pc string
	err := s.db.QueryRow(ctx, `
		SELECT national_id, name, sex, dob, county, constituency, ward, polling_center, registered_on
		FROM register_voters WHERE national_id IN ($1, $2)
		ORDER BY national_id = $1 DESC LIMIT 1`, nationalID, registryKey(nationalID)).
		Scan(&v.NationalID, &name, &sex, &dob, &v.County, &v.Constituency, &v.Ward, &pc, &regOn)
	if err == nil {
		v.PollingCenter = &pc
		v.Source = sourceVoterRegister
		if regOn != nil {
			d := regOn.Format(time.DateOnly)
			v.RegisteredOn = &d
		}
		// Home area from the ID records; also fills identity some register rows lack.
		id, err := s.idRegistryLookup(ctx, nationalID)
		if err != nil {
			return nil, err
		}
		if id != nil {
			v.Home = id.Home
		}
		if name == nil || sex == nil || dob == nil {
			if id != nil {
				if name == nil {
					name = &id.Name
				}
				if sex == nil && id.Sex != "" {
					sex = &id.Sex
				}
				if dob == nil && id.DOB != "" {
					if t, err := time.Parse(time.DateOnly, id.DOB); err == nil {
						dob = &t
					}
				}
			}
		}
		if name != nil {
			v.Name = *name
		}
		if sex != nil {
			v.Sex = *sex
		}
		if dob != nil {
			v.DOB = dob.Format(time.DateOnly)
			v.Age = ageOn(*dob, time.Now())
		}
		return &v, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return nil, err
	}
	return s.idRegistryLookup(ctx, nationalID)
}

func (s *Server) idRegistryLookup(ctx context.Context, nationalID string) (*voter, error) {
	key := registryKey(nationalID)
	if key == "" {
		return nil, nil
	}
	var v voter
	var sex *string
	var dob *time.Time
	h := homeArea{}
	err := s.db.QueryRow(ctx, `
		SELECT name, sex, dob, county, sub_county, division, location, sub_location, village
		FROM id_registry WHERE national_id = $1`, key).
		Scan(&v.Name, &sex, &dob, &h.County, &h.SubCounty, &h.Division, &h.Location, &h.SubLocation, &h.Village)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	h.tidy()
	v.NationalID = nationalID
	v.Source = sourceIDRegistry
	v.Home = &h
	if sex != nil {
		v.Sex = *sex
	}
	if dob != nil {
		v.DOB = dob.Format(time.DateOnly)
		v.Age = ageOn(*dob, time.Now())
	}
	// NRB has no electoral geography. Its county, sub-county and location stand in for
	// county, constituency and ward so records still carry a location; region checks for
	// these records compare county only (see regionMatch).
	v.County = str(h.County)
	v.Constituency = str(h.SubCounty)
	v.Ward = str(h.Location)
	return &v, nil
}

// registryKey normalises an ID for id_registry: digits only, no leading zeros
// (matches cmd/import-idregistry).
func registryKey(s string) string {
	var b strings.Builder
	for _, r := range s {
		if r >= '0' && r <= '9' {
			b.WriteRune(r)
		}
	}
	return strings.TrimLeft(b.String(), "0")
}

// regionMatch decides in/out of region. ID-registry records only know the county reliably.
func regionMatch(source, county, constituency, ward string, aCounty, aConst, aWard *string) bool {
	if source == sourceIDRegistry {
		return inArea(county, "", "", aCounty, nil, nil)
	}
	return inArea(county, constituency, ward, aCounty, aConst, aWard)
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
	eq := func(a *string, v string) bool { return a == nil || places.Key(*a) == places.Key(v) }
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
	// in_register: a reference register knows this ID (the client can skip manual entry).
	// registered_voter: specifically on the voter register.
	resp := map[string]any{"status": statusReady, "voter": v, "in_register": v != nil,
		"registered_voter": v != nil && v.Source == sourceVoterRegister, "in_region": true}
	if v != nil {
		resp["in_region"] = regionMatch(v.Source, v.County, v.Constituency, v.Ward, e.County, e.Constituency, e.Ward)
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
	// Set from the registers, never from the request body.
	source string
	home   *homeArea
}

// homeArgs are the home_* column values (all NULL when the ID records don't know the person).
func (in *personInput) homeArgs() []any {
	h := in.home
	if h == nil {
		return []any{nil, nil, nil, nil, nil}
	}
	return []any{h.County, h.SubCounty, h.Location, h.SubLocation, h.Village}
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
		in.source = v.Source
		in.home = v.Home
		fill := func(dst *string, src string) {
			if strings.TrimSpace(*dst) == "" {
				*dst = src
			}
		}
		// The registers decide where a known person is from — not what the agent types,
		// so an out-of-area person can't be recorded as local.
		set := func(dst *string, src string) {
			if src != "" {
				*dst = src
			}
		}
		fill(&in.Name, v.Name)
		fill(&in.Sex, v.Sex)
		set(&in.County, v.County)
		set(&in.Constituency, v.Constituency)
		set(&in.Ward, v.Ward)
		if (in.DOB == nil || *in.DOB == "") && v.DOB != "" {
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
	inRegion := regionMatch(in.source, in.County, in.Constituency, in.Ward, e.County, e.Constituency, e.Ward)

	var id string
	var at time.Time
	err = s.db.QueryRow(r.Context(), `
		INSERT INTO checkins (org_id, event_id, national_id, name, sex, dob, phone, county, constituency, ward, in_region, checked_in_by,
		                      checked_in_at, checkin_day,
		                      home_county, home_sub_county, home_location, home_sub_location, home_village)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,($13::timestamptz AT TIME ZONE 'Africa/Nairobi')::date,
		        $14,$15,$16,$17,$18)
		RETURNING id, checked_in_at`,
		append([]any{p.OrgID, e.ID, in.NationalID, in.Name, in.Sex, in.DOB, emptyNil(in.Phone), in.County, in.Constituency, in.Ward,
			inRegion, p.UserID, recordedAt(r)}, in.homeArgs()...)...).Scan(&id, &at)
	if isUniqueViolation(err) {
		writeErrCode(w, http.StatusConflict, statusAlreadyCheckedIn, "Already checked in today")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"id": id, "checked_in_at": at, "in_region": inRegion, "name": in.Name,
		"home": in.home})
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
	HomeCounty   *string   `json:"home_county,omitempty"`
	HomeLocation *string   `json:"home_location,omitempty"`
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
		       c.home_county, c.home_location, c.checked_in_at, u.name, e.id, e.name
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
			&inRegion, &pr.HomeCounty, &pr.HomeLocation, &pr.At, &pr.By, &pr.GroupID, &pr.GroupName)
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
