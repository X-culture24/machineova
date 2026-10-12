package api

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// ---- geography ----

// scope is a geographic area; nil at a level means "everything" at that level.
type scope struct {
	County       *string `json:"county"`
	Constituency *string `json:"constituency"`
	Ward         *string `json:"ward"`
}

func (p *Principal) userScope() scope {
	return scope{County: p.ScopeCounty, Constituency: p.ScopeConstituency, Ward: p.ScopeWard}
}

// orElse fills each unset level from the fallback (e.g. user scope inside an election's scope).
func (s scope) orElse(f scope) scope {
	pick := func(a, b *string) *string {
		if a != nil {
			return a
		}
		return b
	}
	return scope{County: pick(s.County, f.County), Constituency: pick(s.Constituency, f.Constituency), Ward: pick(s.Ward, f.Ward)}
}

// narrow applies drill-down filters, ignoring any that would widen the scope.
func (s scope) narrow(constituency, ward string) scope {
	if c := strings.TrimSpace(constituency); c != "" && s.Constituency == nil {
		s.Constituency = &c
	}
	if w := strings.TrimSpace(ward); w != "" && s.Ward == nil {
		s.Ward = &w
	}
	return s
}

// contains reports whether area o lies inside s.
func (s scope) contains(o scope) bool {
	in := func(a, b *string) bool { return a == nil || (b != nil && strings.EqualFold(*a, *b)) }
	return in(s.County, o.County) && in(s.Constituency, o.Constituency) && in(s.Ward, o.Ward)
}

func (s scope) containsStation(st *stationRow) bool {
	return s.contains(scope{County: &st.County, Constituency: &st.Constituency, Ward: &st.Ward})
}

// level is the most specific level set: "county", "constituency", "ward" or "" (unbounded).
func (s scope) level() string {
	switch {
	case s.Ward != nil:
		return "ward"
	case s.Constituency != nil:
		return "constituency"
	case s.County != nil:
		return "county"
	}
	return ""
}

func (s scope) label() string {
	switch s.level() {
	case "ward":
		return *s.Ward + " Ward"
	case "constituency":
		return *s.Constituency + " Constituency"
	case "county":
		return *s.County + " County"
	}
	return "All regions"
}

// childLevel is the level one step below the scope, used for drill-down tables.
func (s scope) childLevel() string {
	switch s.level() {
	case "":
		return "county"
	case "county":
		return "constituency"
	case "constituency":
		return "ward"
	}
	return "station"
}

func regionOf(st *stationRow, level string) string {
	switch level {
	case "county":
		return st.County
	case "constituency":
		return st.Constituency
	case "ward":
		return st.Ward
	}
	return st.Name
}

// ---- roles ----

var opsRank = map[string]int{"agent": 1, "manager": 2, "chief_agent": 3, "admin": 4, "executive": 5, "owner": 6}

func (p *Principal) InOps() bool { return opsRank[p.Role] > 0 }

// CanSetup: create/activate elections and edit positions & candidates.
func (p *Principal) CanSetup() bool { return p.Role == "owner" || p.Role == "admin" }

// CanOperate: act on stations (agents only on their own station; checked per station).
func (p *Principal) CanOperateStations() bool { return p.InOps() && p.Role != "executive" }

// CanAddRole: people may add roles strictly below their own (executives are read-only).
func (p *Principal) CanAddRole(role string) bool {
	if p.Role == "executive" || opsRank[role] == 0 {
		return false
	}
	return opsRank[p.Role] > opsRank[role]
}

func requireOps(w http.ResponseWriter, p *Principal) bool {
	if !requireOrg(w, p) {
		return false
	}
	if !p.InOps() {
		writeErr(w, http.StatusForbidden, "your role does not include Election Ops")
		return false
	}
	return true
}

// ---- elections ----

type election struct {
	ID           string    `json:"id"`
	Name         string    `json:"name"`
	Code         string    `json:"code"`
	ElectionDate string    `json:"election_date"`
	Scope        scope     `json:"scope"`
	ScopeLabel   string    `json:"scope_label"`
	Status       string    `json:"status"`
	CreatedAt    time.Time `json:"created_at"`
}

const electionCols = `id, name, code, to_char(election_date, 'YYYY-MM-DD'), scope_county, scope_constituency, status, created_at`

func scanElection(row pgx.Row) (election, error) {
	var e election
	err := row.Scan(&e.ID, &e.Name, &e.Code, &e.ElectionDate, &e.Scope.County, &e.Scope.Constituency, &e.Status, &e.CreatedAt)
	e.ScopeLabel = e.Scope.label()
	return e, err
}

var errNoActiveElection = errors.New("no active election")

// loadElection returns the election named by ?election_id, or the org's active one.
func (s *Server) loadElection(ctx context.Context, p *Principal, id string) (election, error) {
	var row pgx.Row
	if id == "" {
		row = s.db.QueryRow(ctx, `SELECT `+electionCols+` FROM elections WHERE org_id=$1 AND status='active'`, p.OrgID)
	} else {
		row = s.db.QueryRow(ctx, `SELECT `+electionCols+` FROM elections WHERE org_id=$1 AND id::text=$2`, p.OrgID, id)
	}
	e, err := scanElection(row)
	if errors.Is(err, pgx.ErrNoRows) {
		if id == "" {
			return e, errNoActiveElection
		}
		return e, errNotFound
	}
	return e, err
}

// opsContext loads the election and the principal's effective scope inside it.
// It writes the error response itself and returns ok=false on failure.
func (s *Server) opsContext(w http.ResponseWriter, r *http.Request, p *Principal) (election, scope, bool) {
	if !requireOps(w, p) {
		return election{}, scope{}, false
	}
	e, err := s.loadElection(r.Context(), p, r.URL.Query().Get("election_id"))
	switch {
	case errors.Is(err, errNoActiveElection):
		writeErrCode(w, http.StatusNotFound, "no_active_election", "No active election. Activate one under Set up › Election.")
		return e, scope{}, false
	case errors.Is(err, errNotFound):
		writeErr(w, http.StatusNotFound, "election not found")
		return e, scope{}, false
	case err != nil:
		s.internal(w, r, err)
		return e, scope{}, false
	}
	return e, p.userScope().orElse(e.Scope), true
}

// ---- stations ----

type stationRow struct {
	Code          string     `json:"code"`
	Name          string     `json:"name"`
	County        string     `json:"county"`
	Constituency  string     `json:"constituency"`
	Ward          string     `json:"ward"`
	Registered    int        `json:"registered"`
	Status        string     `json:"status"`
	UpdatedAt     *time.Time `json:"updated_at"`
	Agents        int        `json:"agents"`
	Cast          *int       `json:"cast"`    // latest cumulative turnout
	Turnout       *float64   `json:"turnout"` // cast / registered
	OpenIncidents int        `json:"open_incidents"`
	LastIncident  *string    `json:"last_incident"`
	Results       int        `json:"results_submitted"` // positions with a Form 37A
}

func (st *stationRow) Uncovered() bool { return st.Agents == 0 }

// loadStations returns every station of the election inside the scope.
func (s *Server) loadStations(ctx context.Context, electionID string, sc scope) ([]stationRow, error) {
	rows, err := s.db.Query(ctx, `
		SELECT s.code, s.name, s.county, s.constituency, s.ward, s.registered_voters, es.status, es.updated_at,
		       (SELECT count(*) FROM station_agents a WHERE a.election_id = es.election_id AND a.station_code = s.code),
		       (SELECT t.cumulative FROM turnout_reports t WHERE t.election_id = es.election_id AND t.station_code = s.code
		        ORDER BY t.slot_hour DESC LIMIT 1),
		       (SELECT count(*) FROM incidents i WHERE i.election_id = es.election_id AND i.station_code = s.code AND i.resolved_at IS NULL),
		       (SELECT i.type FROM incidents i WHERE i.election_id = es.election_id AND i.station_code = s.code AND i.resolved_at IS NULL
		        ORDER BY i.created_at DESC LIMIT 1),
		       (SELECT count(*) FROM result_submissions r WHERE r.election_id = es.election_id AND r.station_code = s.code)
		FROM election_stations es JOIN polling_stations s ON s.code = es.station_code
		WHERE es.election_id = $1
		  AND ($2::text IS NULL OR s.county = $2) AND ($3::text IS NULL OR s.constituency = $3) AND ($4::text IS NULL OR s.ward = $4)
		ORDER BY s.constituency, s.ward, s.name`, electionID, sc.County, sc.Constituency, sc.Ward)
	if err != nil {
		return nil, err
	}
	return collect(rows, func(row pgx.Row) (stationRow, error) {
		var st stationRow
		err := row.Scan(&st.Code, &st.Name, &st.County, &st.Constituency, &st.Ward, &st.Registered, &st.Status, &st.UpdatedAt,
			&st.Agents, &st.Cast, &st.OpenIncidents, &st.LastIncident, &st.Results)
		if st.Cast != nil && st.Registered > 0 {
			t := round2(float64(*st.Cast) / float64(st.Registered))
			st.Turnout = &t
		}
		return st, err
	})
}

// loadStation returns one station if it is in the principal's scope.
func (s *Server) loadStation(ctx context.Context, e election, sc scope, code string) (*stationRow, error) {
	all, err := s.loadStations(ctx, e.ID, sc)
	if err != nil {
		return nil, err
	}
	for i := range all {
		if strings.EqualFold(all[i].Code, code) {
			return &all[i], nil
		}
	}
	return nil, errNotFound
}

// canActOn checks the principal may change this station: field roles in scope, agents only where assigned.
func (s *Server) canActOn(ctx context.Context, p *Principal, e election, code string) (bool, error) {
	if !p.CanOperateStations() || e.Status != "active" {
		return false, nil
	}
	if p.Role != "agent" {
		return true, nil
	}
	var ok bool
	err := s.db.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM station_agents WHERE election_id=$1 AND station_code=$2 AND user_id=$3)`,
		e.ID, code, p.UserID).Scan(&ok)
	return ok, err
}

// execer is satisfied by both the pool and a transaction.
type execer interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
}

func logStationEvent(ctx context.Context, q execer, e election, code, kind, msg, userID string, at time.Time) error {
	_, err := q.Exec(ctx, `INSERT INTO station_events (election_id, station_code, kind, message, user_id, at) VALUES ($1,$2,$3,$4,$5,$6)`,
		e.ID, code, kind, msg, userID, at)
	return err
}
