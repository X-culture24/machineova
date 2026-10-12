package api

import (
	"context"
	"errors"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

var levelRank = map[string]int{"national": 0, "county": 1, "constituency": 2, "ward": 3}
var scopeRank = map[string]int{"": 0, "county": 1, "constituency": 2, "ward": 3}

func (s *Server) orgBoundary(ctx context.Context, orgID string) (scope, error) {
	var b scope
	err := s.db.QueryRow(ctx, `SELECT boundary_county, boundary_constituency FROM organizations WHERE id=$1`, orgID).
		Scan(&b.County, &b.Constituency)
	return b, err
}

type electionSummary struct {
	election
	Positions        int     `json:"positions"`
	Counties         int     `json:"counties"`
	Constituencies   int     `json:"constituencies"`
	Wards            int     `json:"wards"`
	Stations         int     `json:"stations"`
	Registered       int     `json:"registered"`
	StationsReported int     `json:"stations_reported"`
	ReportedShare    float64 `json:"reported_share"`
}

const electionSummarySQL = `
	SELECT e.id, e.name, e.code, to_char(e.election_date, 'YYYY-MM-DD'), e.scope_county, e.scope_constituency, e.status, e.created_at,
	       (SELECT count(*) FROM positions p WHERE p.election_id = e.id),
	       count(DISTINCT s.county), count(DISTINCT s.county || '/' || s.constituency),
	       count(DISTINCT s.county || '/' || s.constituency || '/' || s.ward),
	       count(s.code), COALESCE(sum(s.registered_voters), 0),
	       count(*) FILTER (WHERE es.status IN ('reporting', 'closed'))
	FROM elections e
	LEFT JOIN election_stations es ON es.election_id = e.id
	LEFT JOIN polling_stations s ON s.code = es.station_code
	WHERE e.org_id = $1`

func scanElectionSummary(row pgx.Row) (electionSummary, error) {
	var e electionSummary
	err := row.Scan(&e.ID, &e.Name, &e.Code, &e.ElectionDate, &e.Scope.County, &e.Scope.Constituency, &e.Status, &e.CreatedAt,
		&e.Positions, &e.Counties, &e.Constituencies, &e.Wards, &e.Stations, &e.Registered, &e.StationsReported)
	e.ScopeLabel = e.Scope.label()
	if e.Stations > 0 {
		e.ReportedShare = round2(float64(e.StationsReported) / float64(e.Stations))
	}
	return e, err
}

func (s *Server) listElections(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOps(w, p) {
		return
	}
	rows, err := s.db.Query(r.Context(), electionSummarySQL+` GROUP BY e.id
		ORDER BY (e.status = 'active') DESC, (e.status = 'draft') DESC, e.election_date DESC`, p.OrgID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	out, err := collect(rows, scanElectionSummary)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

type positionInput struct {
	Name  string `json:"name"`
	Level string `json:"level"`
}

func (s *Server) createElection(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOps(w, p) {
		return
	}
	if !p.CanSetup() {
		writeErr(w, http.StatusForbidden, "only owners and admins can set up elections")
		return
	}
	var in struct {
		Name              string          `json:"name"`
		Code              string          `json:"code"`
		ElectionDate      string          `json:"election_date"`
		ScopeCounty       *string         `json:"scope_county"`
		ScopeConstituency *string         `json:"scope_constituency"`
		Positions         []positionInput `json:"positions"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	in.Name, in.Code = strings.TrimSpace(in.Name), strings.ToUpper(strings.TrimSpace(in.Code))
	if in.Name == "" || in.Code == "" {
		writeErr(w, http.StatusBadRequest, "name and code are required")
		return
	}
	if _, err := time.Parse(time.DateOnly, in.ElectionDate); err != nil {
		writeErr(w, http.StatusBadRequest, "election_date must be YYYY-MM-DD")
		return
	}
	boundary, err := s.orgBoundary(r.Context(), p.OrgID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	sc := scope{County: emptyNil(in.ScopeCounty), Constituency: emptyNil(in.ScopeConstituency)}.orElse(boundary)
	if sc.Constituency != nil && sc.County == nil {
		writeErr(w, http.StatusBadRequest, "pick a county before a constituency")
		return
	}
	if !boundary.contains(sc) {
		writeErr(w, http.StatusBadRequest, "the election scope must be inside your organization's boundary ("+boundary.label()+")")
		return
	}
	if len(in.Positions) == 0 {
		writeErr(w, http.StatusBadRequest, "add at least one position")
		return
	}
	for i, pos := range in.Positions {
		in.Positions[i].Name = strings.TrimSpace(pos.Name)
		rank, ok := levelRank[pos.Level]
		if !ok || in.Positions[i].Name == "" {
			writeErr(w, http.StatusBadRequest, "each position needs a name and a level (national, county, constituency, ward)")
			return
		}
		if rank < scopeRank[sc.level()] {
			writeErr(w, http.StatusBadRequest, pos.Name+" is above this election's scope")
			return
		}
	}

	tx, err := s.db.Begin(r.Context())
	if err != nil {
		s.internal(w, r, err)
		return
	}
	defer tx.Rollback(r.Context())
	var id string
	if err := tx.QueryRow(r.Context(), `
		INSERT INTO elections (org_id, name, code, election_date, scope_county, scope_constituency)
		VALUES ($1,$2,$3,$4::date,$5,$6) RETURNING id`, p.OrgID, in.Name, in.Code, in.ElectionDate, sc.County, sc.Constituency).Scan(&id); err != nil {
		s.internal(w, r, err)
		return
	}
	tag, err := tx.Exec(r.Context(), `
		INSERT INTO election_stations (election_id, station_code)
		SELECT $1, code FROM polling_stations
		WHERE ($2::text IS NULL OR county = $2) AND ($3::text IS NULL OR constituency = $3)`, id, sc.County, sc.Constituency)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if tag.RowsAffected() == 0 {
		writeErr(w, http.StatusBadRequest, "the register has no polling stations in "+sc.label()+" — import the station register first")
		return
	}
	for i, pos := range in.Positions {
		if _, err := tx.Exec(r.Context(), `INSERT INTO positions (election_id, name, level, sort) VALUES ($1,$2,$3,$4)`,
			id, pos.Name, pos.Level, i); err != nil {
			if isUniqueViolation(err) {
				writeErr(w, http.StatusBadRequest, "duplicate position "+pos.Name)
				return
			}
			s.internal(w, r, err)
			return
		}
	}
	if err := tx.Commit(r.Context()); err != nil {
		s.internal(w, r, err)
		return
	}
	e, err := scanElectionSummary(s.db.QueryRow(r.Context(), electionSummarySQL+` AND e.id = $2 GROUP BY e.id`, p.OrgID, id))
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, e)
}

// setElectionStatus handles activate / complete / reopen-as-draft.
func (s *Server) setElectionStatus(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOps(w, p) {
		return
	}
	if !p.CanSetup() {
		writeErr(w, http.StatusForbidden, "only owners and admins can change elections")
		return
	}
	var in struct {
		Status string `json:"status"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	if in.Status != "active" && in.Status != "completed" && in.Status != "draft" {
		writeErr(w, http.StatusBadRequest, "status must be draft, active or completed")
		return
	}
	tx, err := s.db.Begin(r.Context())
	if err != nil {
		s.internal(w, r, err)
		return
	}
	defer tx.Rollback(r.Context())
	if in.Status == "active" {
		// One active election at a time: the previously active one goes back to draft.
		if _, err := tx.Exec(r.Context(), `UPDATE elections SET status='draft' WHERE org_id=$1 AND status='active' AND id::text <> $2`,
			p.OrgID, r.PathValue("id")); err != nil {
			s.internal(w, r, err)
			return
		}
	}
	tag, err := tx.Exec(r.Context(), `UPDATE elections SET status=$3 WHERE org_id=$1 AND id::text=$2`, p.OrgID, r.PathValue("id"), in.Status)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if tag.RowsAffected() == 0 {
		writeErr(w, http.StatusNotFound, "election not found")
		return
	}
	if err := tx.Commit(r.Context()); err != nil {
		s.internal(w, r, err)
		return
	}
	e, err := scanElectionSummary(s.db.QueryRow(r.Context(), electionSummarySQL+` AND e.id::text = $2 GROUP BY e.id`, p.OrgID, r.PathValue("id")))
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, e)
}

func (s *Server) deleteElection(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOps(w, p) {
		return
	}
	if !p.CanSetup() {
		writeErr(w, http.StatusForbidden, "only owners and admins can delete elections")
		return
	}
	tag, err := s.db.Exec(r.Context(), `DELETE FROM elections WHERE org_id=$1 AND id::text=$2 AND status='draft'`, p.OrgID, r.PathValue("id"))
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if tag.RowsAffected() == 0 {
		writeErr(w, http.StatusConflict, "only draft elections can be deleted")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type position struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Level string `json:"level"`
	Sort  int    `json:"sort"`
}

func (s *Server) loadPositions(ctx context.Context, electionID string) ([]position, error) {
	rows, err := s.db.Query(ctx, `SELECT id, name, level, sort FROM positions WHERE election_id=$1 ORDER BY sort, name`, electionID)
	if err != nil {
		return nil, err
	}
	return collect(rows, func(row pgx.Row) (position, error) {
		var p position
		return p, row.Scan(&p.ID, &p.Name, &p.Level, &p.Sort)
	})
}

type candidate struct {
	ID         string  `json:"id"`
	PositionID string  `json:"position_id"`
	Region     *string `json:"region"`
	Name       string  `json:"name"`
	PartyCode  *string `json:"party_code"`
	PartyName  *string `json:"party_name"`
	IsOurs     bool    `json:"is_ours"`
}

func (s *Server) loadCandidates(ctx context.Context, electionID string) ([]candidate, error) {
	rows, err := s.db.Query(ctx, `
		SELECT c.id, c.position_id, c.region, c.name, c.party_code, pa.name, c.is_ours
		FROM candidates c JOIN positions p ON p.id = c.position_id LEFT JOIN parties pa ON pa.code = c.party_code
		WHERE p.election_id = $1 ORDER BY c.sort, c.name`, electionID)
	if err != nil {
		return nil, err
	}
	return collect(rows, func(row pgx.Row) (candidate, error) {
		var c candidate
		return c, row.Scan(&c.ID, &c.PositionID, &c.Region, &c.Name, &c.PartyCode, &c.PartyName, &c.IsOurs)
	})
}

type levelRegions struct {
	Level     string   `json:"level"`
	Positions []string `json:"positions"`
	Regions   []string `json:"regions"`
}

type regionRow struct {
	Name       string `json:"name"`
	Races      string `json:"races"`
	Stations   int    `json:"stations"`
	Registered int    `json:"registered"`
}

// getElection returns the election, its derived regions (positions decide where races are held)
// and a drill-down table one level below ?constituency / ?ward.
func (s *Server) getElection(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOps(w, p) {
		return
	}
	e, err := s.loadElection(r.Context(), p, r.PathValue("id"))
	if errors.Is(err, errNotFound) {
		writeErr(w, http.StatusNotFound, "election not found")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	positions, err := s.loadPositions(r.Context(), e.ID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	stations, err := s.loadStations(r.Context(), e.ID, e.Scope)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	// Derived regions per position level.
	var levels []levelRegions
	for _, lvl := range []string{"national", "county", "constituency", "ward"} {
		var names []string
		for _, pos := range positions {
			if pos.Level == lvl {
				names = append(names, pos.Name)
			}
		}
		if len(names) == 0 {
			continue
		}
		set := map[string]bool{}
		for i := range stations {
			if lvl == "national" {
				set["National"] = true
			} else {
				set[regionOf(&stations[i], lvl)] = true
			}
		}
		levels = append(levels, levelRegions{Level: lvl, Positions: names, Regions: sortedKeys(set)})
	}

	drill := e.Scope.narrow(r.URL.Query().Get("constituency"), r.URL.Query().Get("ward"))
	child := drill.childLevel()
	racesAt := map[string][]string{}
	for _, pos := range positions {
		racesAt[pos.Level] = append(racesAt[pos.Level], shortPosition(pos.Name))
	}
	above := 0
	for _, pos := range positions {
		if levelRank[pos.Level] < levelRank[child] || (child == "station" && pos.Level != "ward") {
			above++
		}
	}
	byRegion := map[string]*regionRow{}
	var order []string
	for i := range stations {
		st := &stations[i]
		if !drill.containsStation(st) {
			continue
		}
		name := regionOf(st, child)
		rr, ok := byRegion[name]
		if !ok {
			races := strings.Join(racesAt[child], " + ")
			if child == "station" {
				races = strings.Join(racesAt["ward"], " + ")
			}
			if above > 0 && child != "station" {
				if races != "" {
					races += " + "
				}
				races += strconv.Itoa(above) + " wider races"
			}
			rr = &regionRow{Name: name, Races: races}
			byRegion[name] = rr
			order = append(order, name)
		}
		rr.Stations++
		rr.Registered += st.Registered
	}
	table := make([]regionRow, 0, len(order))
	for _, n := range order {
		table = append(table, *byRegion[n])
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"election": e, "positions": positions, "levels": levels,
		"drill": map[string]any{"scope": drill, "label": drill.label(), "child_level": child, "rows": table},
	})
}

func shortPosition(name string) string {
	switch name {
	case "Member of Parliament":
		return "MP"
	case "Woman Representative":
		return "Woman Rep"
	}
	return name
}

func sortedKeys(m map[string]bool) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// ---- positions & candidates ----

type race struct {
	Position   position    `json:"position"`
	Region     *string     `json:"region"`
	Candidates []candidate `json:"candidates"`
}

func (s *Server) listRaces(w http.ResponseWriter, r *http.Request, p *Principal) {
	e, _, ok := s.opsContext(w, r, p)
	if !ok {
		return
	}
	positions, err := s.loadPositions(r.Context(), e.ID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	cands, err := s.loadCandidates(r.Context(), e.ID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	stations, err := s.loadStations(r.Context(), e.ID, e.Scope)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	races := []race{}
	for _, pos := range positions {
		var regions []*string
		if pos.Level == "national" {
			regions = []*string{nil}
		} else {
			set := map[string]bool{}
			for i := range stations {
				set[regionOf(&stations[i], pos.Level)] = true
			}
			for _, k := range sortedKeys(set) {
				regions = append(regions, &k)
			}
		}
		for _, reg := range regions {
			rc := race{Position: pos, Region: reg, Candidates: []candidate{}}
			for _, c := range cands {
				if c.PositionID == pos.ID && ptrEq(c.Region, reg) {
					rc.Candidates = append(rc.Candidates, c)
				}
			}
			races = append(races, rc)
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"election": e, "positions": positions, "races": races})
}

func ptrEq(a, b *string) bool {
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	return strings.EqualFold(*a, *b)
}

func (s *Server) addPosition(w http.ResponseWriter, r *http.Request, p *Principal) {
	e, _, ok := s.opsContext(w, r, p)
	if !ok {
		return
	}
	if !p.CanSetup() {
		writeErr(w, http.StatusForbidden, "only owners and admins can edit positions")
		return
	}
	var in positionInput
	if !readJSON(w, r, &in) {
		return
	}
	in.Name = strings.TrimSpace(in.Name)
	rank, valid := levelRank[in.Level]
	if in.Name == "" || !valid {
		writeErr(w, http.StatusBadRequest, "name and level are required")
		return
	}
	if rank < scopeRank[e.Scope.level()] {
		writeErr(w, http.StatusBadRequest, in.Name+" is above this election's scope")
		return
	}
	var pos position
	err := s.db.QueryRow(r.Context(), `
		INSERT INTO positions (election_id, name, level, sort)
		VALUES ($1,$2,$3,(SELECT COALESCE(max(sort)+1, 0) FROM positions WHERE election_id=$1))
		RETURNING id, name, level, sort`, e.ID, in.Name, in.Level).Scan(&pos.ID, &pos.Name, &pos.Level, &pos.Sort)
	if isUniqueViolation(err) {
		writeErr(w, http.StatusConflict, "this position already exists")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, pos)
}

func (s *Server) deletePosition(w http.ResponseWriter, r *http.Request, p *Principal) {
	e, _, ok := s.opsContext(w, r, p)
	if !ok {
		return
	}
	if !p.CanSetup() {
		writeErr(w, http.StatusForbidden, "only owners and admins can edit positions")
		return
	}
	tag, err := s.db.Exec(r.Context(), `DELETE FROM positions WHERE election_id=$1 AND id::text=$2
		AND NOT EXISTS (SELECT 1 FROM result_submissions rs WHERE rs.position_id = positions.id)`, e.ID, r.PathValue("id"))
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if tag.RowsAffected() == 0 {
		writeErr(w, http.StatusConflict, "position not found, or results have already been submitted for it")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type candidateInput struct {
	PositionID string  `json:"position_id"`
	Region     *string `json:"region"`
	Name       *string `json:"name"`
	PartyCode  *string `json:"party_code"`
	IsOurs     *bool   `json:"is_ours"`
}

// Candidates can be added or replaced while the election is live.
func (s *Server) addCandidate(w http.ResponseWriter, r *http.Request, p *Principal) {
	e, _, ok := s.opsContext(w, r, p)
	if !ok {
		return
	}
	if !p.CanSetup() {
		writeErr(w, http.StatusForbidden, "only owners and admins can edit candidates")
		return
	}
	var in candidateInput
	if !readJSON(w, r, &in) {
		return
	}
	if in.Name == nil || strings.TrimSpace(*in.Name) == "" {
		writeErr(w, http.StatusBadRequest, "name is required")
		return
	}
	var level string
	err := s.db.QueryRow(r.Context(), `SELECT level FROM positions WHERE id::text=$1 AND election_id=$2`, in.PositionID, e.ID).Scan(&level)
	if errors.Is(err, pgx.ErrNoRows) {
		writeErr(w, http.StatusBadRequest, "unknown position")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	region := emptyNil(in.Region)
	if level == "national" {
		region = nil
	} else {
		if region == nil {
			writeErr(w, http.StatusBadRequest, "region is required: the "+level+" this candidate stands in")
			return
		}
		var exists bool
		if err := s.db.QueryRow(r.Context(), `
			SELECT EXISTS(SELECT 1 FROM election_stations es JOIN polling_stations s ON s.code = es.station_code
			WHERE es.election_id = $1 AND lower(CASE $2 WHEN 'county' THEN s.county WHEN 'constituency' THEN s.constituency ELSE s.ward END) = lower($3))`,
			e.ID, level, *region).Scan(&exists); err != nil {
			s.internal(w, r, err)
			return
		}
		if !exists {
			writeErr(w, http.StatusBadRequest, *region+" is not a "+level+" in this election")
			return
		}
	}
	c := candidate{}
	err = s.db.QueryRow(r.Context(), `
		INSERT INTO candidates (position_id, region, name, party_code, is_ours, sort)
		VALUES ($1,$2,$3,$4,COALESCE($5,false),(SELECT COALESCE(max(sort)+1,0) FROM candidates WHERE position_id=$1))
		RETURNING id, position_id, region, name, party_code, is_ours`,
		in.PositionID, region, strings.TrimSpace(*in.Name), emptyNil(in.PartyCode), in.IsOurs).
		Scan(&c.ID, &c.PositionID, &c.Region, &c.Name, &c.PartyCode, &c.IsOurs)
	if isForeignKeyViolation(err) {
		writeErr(w, http.StatusBadRequest, "unknown party code — import parties into the registry first")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, c)
}

func (s *Server) updateCandidate(w http.ResponseWriter, r *http.Request, p *Principal) {
	e, _, ok := s.opsContext(w, r, p)
	if !ok {
		return
	}
	if !p.CanSetup() {
		writeErr(w, http.StatusForbidden, "only owners and admins can edit candidates")
		return
	}
	var in candidateInput
	if !readJSON(w, r, &in) {
		return
	}
	tag, err := s.db.Exec(r.Context(), `
		UPDATE candidates SET name = COALESCE($3, name), party_code = COALESCE($4, party_code), is_ours = COALESCE($5, is_ours)
		WHERE id::text = $2 AND position_id IN (SELECT id FROM positions WHERE election_id = $1)`,
		e.ID, r.PathValue("id"), emptyNil(in.Name), emptyNil(in.PartyCode), in.IsOurs)
	if isForeignKeyViolation(err) {
		writeErr(w, http.StatusBadRequest, "unknown party code")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if tag.RowsAffected() == 0 {
		writeErr(w, http.StatusNotFound, "candidate not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) deleteCandidate(w http.ResponseWriter, r *http.Request, p *Principal) {
	e, _, ok := s.opsContext(w, r, p)
	if !ok {
		return
	}
	if !p.CanSetup() {
		writeErr(w, http.StatusForbidden, "only owners and admins can edit candidates")
		return
	}
	tag, err := s.db.Exec(r.Context(), `
		DELETE FROM candidates WHERE id::text = $2 AND position_id IN (SELECT id FROM positions WHERE election_id = $1)
		AND NOT EXISTS (SELECT 1 FROM result_votes v WHERE v.candidate_id = candidates.id)`, e.ID, r.PathValue("id"))
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if tag.RowsAffected() == 0 {
		writeErr(w, http.StatusConflict, "candidate not found, or votes are already recorded for them")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ---- registry (statutory, read-only) ----

func (s *Server) registryStations(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOps(w, p) {
		return
	}
	b, err := s.orgBoundary(r.Context(), p.OrgID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	q := r.URL.Query()
	pg := pageParams(q.Get("page"), q.Get("page_size"))
	var total int
	rows, err := s.db.Query(r.Context(), `
		SELECT code, name, county, constituency, ward, registered_voters, count(*) OVER ()
		FROM polling_stations
		WHERE ($1::text IS NULL OR county = $1) AND ($2::text IS NULL OR constituency = $2)
		  AND ($3::text IS NULL OR name ILIKE $3 OR code ILIKE $3 OR ward ILIKE $3)
		ORDER BY constituency, ward, name LIMIT $4 OFFSET $5`,
		b.County, b.Constituency, likePattern(q.Get("q")), pg.size, pg.offset())
	if err != nil {
		s.internal(w, r, err)
		return
	}
	items, err := collect(rows, func(row pgx.Row) (stationRow, error) {
		var st stationRow
		return st, row.Scan(&st.Code, &st.Name, &st.County, &st.Constituency, &st.Ward, &st.Registered, &total)
	})
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, pg.response(items, total))
}

func (s *Server) registryParties(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOps(w, p) {
		return
	}
	rows, err := s.db.Query(r.Context(), `SELECT code, name, colour FROM parties ORDER BY name`)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	type party struct {
		Code   string  `json:"code"`
		Name   string  `json:"name"`
		Colour *string `json:"colour"`
	}
	out, err := collect(rows, func(row pgx.Row) (party, error) {
		var pa party
		return pa, row.Scan(&pa.Code, &pa.Name, &pa.Colour)
	})
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

// registryRegions lists the geography inside the principal's reach, for cascading pickers.
func (s *Server) registryRegions(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOps(w, p) {
		return
	}
	b, err := s.orgBoundary(r.Context(), p.OrgID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	sc := p.userScope().orElse(b)
	rows, err := s.db.Query(r.Context(), `
		SELECT county, constituency, ward, code, name FROM polling_stations
		WHERE ($1::text IS NULL OR county = $1) AND ($2::text IS NULL OR constituency = $2) AND ($3::text IS NULL OR ward = $3)
		ORDER BY county, constituency, ward, name`, sc.County, sc.Constituency, sc.Ward)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	type stationRef struct {
		Code string `json:"code"`
		Name string `json:"name"`
	}
	type ward struct {
		Name     string       `json:"name"`
		Stations []stationRef `json:"stations"`
	}
	type constituency struct {
		Name  string  `json:"name"`
		Wards []*ward `json:"wards"`
	}
	type county struct {
		Name           string          `json:"name"`
		Constituencies []*constituency `json:"constituencies"`
	}
	var out []*county
	for rows.Next() {
		var c, k, wd, code, name string
		if err := rows.Scan(&c, &k, &wd, &code, &name); err != nil {
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
		if len(kk.Wards) == 0 || kk.Wards[len(kk.Wards)-1].Name != wd {
			kk.Wards = append(kk.Wards, &ward{Name: wd})
		}
		ww := kk.Wards[len(kk.Wards)-1]
		ww.Stations = append(ww.Stations, stationRef{Code: code, Name: name})
	}
	if err := rows.Err(); err != nil {
		s.internal(w, r, err)
		return
	}
	if out == nil {
		out = []*county{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"scope": sc, "counties": out})
}

// ---- pagination ----

type page struct{ num, size int }

func pageParams(num, size string) page {
	p := page{num: 1, size: 25}
	if n, err := strconv.Atoi(num); err == nil && n > 0 {
		p.num = n
	}
	if n, err := strconv.Atoi(size); err == nil && n > 0 && n <= 200 {
		p.size = n
	}
	return p
}

func (p page) offset() int { return (p.num - 1) * p.size }

func (p page) response(items any, total int) map[string]any {
	return map[string]any{"items": items, "total": total, "page": p.num, "page_size": p.size}
}
