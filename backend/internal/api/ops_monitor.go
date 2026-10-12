package api

import (
	"context"
	"math"
	"net/http"
	"sort"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5"
)

// ---- shared tallies ----

// turnoutBySlot maps station code → slot hour → cumulative voters.
type turnoutBySlot map[string]map[int]int

func (s *Server) loadTurnout(ctx context.Context, electionID string) (turnoutBySlot, error) {
	rows, err := s.db.Query(ctx, `SELECT station_code, slot_hour, cumulative FROM turnout_reports WHERE election_id=$1`, electionID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := turnoutBySlot{}
	for rows.Next() {
		var code string
		var h, c int
		if err := rows.Scan(&code, &h, &c); err != nil {
			return nil, err
		}
		if out[code] == nil {
			out[code] = map[int]int{}
		}
		out[code][h] = c
	}
	return out, rows.Err()
}

// at returns a station's cumulative turnout as of the given hour (latest slot at or before it).
func (t turnoutBySlot) at(code string, hour int) (int, bool) {
	best, found := -1, false
	val := 0
	for h, c := range t[code] {
		if h <= hour && h > best {
			best, val, found = h, c, true
		}
	}
	return val, found
}

type tally struct {
	votes     map[string]map[string]int // station → candidate → votes
	submitted map[string]bool           // station reported this position
}

// loadTally returns votes for one position, optionally only submissions made before `until`.
func (s *Server) loadTally(ctx context.Context, electionID, positionID string, until *time.Time) (tally, error) {
	t := tally{votes: map[string]map[string]int{}, submitted: map[string]bool{}}
	rows, err := s.db.Query(ctx, `
		SELECT rs.station_code, rv.candidate_id, rv.votes
		FROM result_submissions rs JOIN result_votes rv
		  ON rv.election_id = rs.election_id AND rv.station_code = rs.station_code AND rv.position_id = rs.position_id
		WHERE rs.election_id=$1 AND rs.position_id=$2 AND rs.verified_at IS NOT NULL
		  AND ($3::timestamptz IS NULL OR rs.verified_at <= $3)`,
		electionID, positionID, until)
	if err != nil {
		return t, err
	}
	defer rows.Close()
	for rows.Next() {
		var code, cand string
		var v int
		if err := rows.Scan(&code, &cand, &v); err != nil {
			return t, err
		}
		if t.votes[code] == nil {
			t.votes[code] = map[string]int{}
		}
		t.votes[code][cand] += v
		t.submitted[code] = true
	}
	return t, rows.Err()
}

type candidateTotal struct {
	Candidate candidate `json:"candidate"`
	Votes     int       `json:"votes"`
	Share     float64   `json:"share"`
}

// sumCandidates totals votes over a set of stations, ranked by votes.
func sumCandidates(t tally, stations []*stationRow, cands map[string]candidate) []candidateTotal {
	totals := map[string]int{}
	all := 0
	for _, st := range stations {
		for c, v := range t.votes[st.Code] {
			totals[c] += v
			all += v
		}
	}
	out := []candidateTotal{}
	for id, v := range totals {
		ct := candidateTotal{Candidate: cands[id], Votes: v}
		if all > 0 {
			ct.Share = round2(float64(v) / float64(all))
		}
		out = append(out, ct)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Votes != out[j].Votes {
			return out[i].Votes > out[j].Votes
		}
		return out[i].Candidate.Name < out[j].Candidate.Name
	})
	return out
}

// focusPosition is the race monitoring follows: the widest race we field a candidate in, else the first position.
func focusPosition(positions []position, cands []candidate) *position {
	var best *position
	for i := range positions {
		ours := false
		for _, c := range cands {
			ours = ours || (c.PositionID == positions[i].ID && c.IsOurs)
		}
		if ours && (best == nil || levelRank[positions[i].Level] < levelRank[best.Level]) {
			best = &positions[i]
		}
	}
	if best == nil && len(positions) > 0 {
		best = &positions[0]
	}
	return best
}

func candidateMap(cands []candidate) map[string]candidate {
	m := map[string]candidate{}
	for _, c := range cands {
		m[c.ID] = c
	}
	return m
}

type group struct {
	Name     string
	Stations []*stationRow
}

// groupBy splits stations into child regions, preserving first-seen order.
func groupBy(stations []stationRow, level string) []group {
	idx := map[string]int{}
	var out []group
	for i := range stations {
		name := regionOf(&stations[i], level)
		j, ok := idx[name]
		if !ok {
			j = len(out)
			idx[name] = j
			out = append(out, group{Name: name})
		}
		out[j].Stations = append(out[j].Stations, &stations[i])
	}
	return out
}

func turnoutOf(stations []*stationRow, t turnoutBySlot, hour int) (cast, registered int) {
	for _, st := range stations {
		registered += st.Registered
		if c, ok := t.at(st.Code, hour); ok {
			cast += c
		}
	}
	return
}

func share(a, b int) float64 {
	if b == 0 {
		return 0
	}
	return round2(float64(a) / float64(b))
}

func ptrs(stations []stationRow) []*stationRow {
	out := make([]*stationRow, len(stations))
	for i := range stations {
		out[i] = &stations[i]
	}
	return out
}

type trendPoint struct {
	Hour    int     `json:"hour"`
	Cast    int     `json:"cast"`
	Turnout float64 `json:"turnout"`
}

func trend(stations []*stationRow, t turnoutBySlot, upTo int) []trendPoint {
	out := []trendPoint{}
	for _, h := range turnoutSlots {
		if h > upTo {
			break
		}
		cast, reg := turnoutOf(stations, t, h)
		out = append(out, trendPoint{Hour: h, Cast: cast, Turnout: share(cast, reg)})
	}
	return out
}

// lastSlotWithData is the latest slot any station in view has reported.
func lastSlotWithData(stations []*stationRow, t turnoutBySlot) int {
	last := 0
	for _, st := range stations {
		for h := range t[st.Code] {
			last = max(last, h)
		}
	}
	return last
}

// ---- overview ----

type attentionItem struct {
	Code   string `json:"code"`
	Name   string `json:"name"`
	Area   string `json:"area"`
	Reason string `json:"reason"`
	Kind   string `json:"kind"`   // issue | uncovered | verify
	Action string `json:"action"` // Review | Assign agent | Verify results
}

func (s *Server) opsOverview(w http.ResponseWriter, r *http.Request, p *Principal) {
	e, sc, ok := s.opsContext(w, r, p)
	if !ok {
		return
	}
	ctx := r.Context()
	stations, err := s.loadStations(ctx, e.ID, sc)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	positions, err := s.loadPositions(ctx, e.ID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	t, err := s.loadTurnout(ctx, e.ID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	var out struct {
		Election   election        `json:"election"`
		Scope      scope           `json:"scope"`
		ScopeLabel string          `json:"scope_label"`
		Stations   int             `json:"stations"`
		Reported   int             `json:"reported"`
		Open       int             `json:"open"`
		Closed     int             `json:"closed"`
		Cast       int             `json:"cast"`
		Registered int             `json:"registered"`
		Turnout    float64         `json:"turnout"`
		Issues     int             `json:"issues"`
		Uncovered  int             `json:"uncovered"`
		ToVerify   int             `json:"to_verify"`
		Attention  []attentionItem `json:"attention"`
		Trend      []trendPoint    `json:"trend"`
		Agents     int             `json:"agents"`
		LastUpdate *time.Time      `json:"last_update"`
	}
	out.Election, out.Scope, out.ScopeLabel, out.Stations = e, sc, sc.label(), len(stations)
	out.Attention = []attentionItem{}
	var issues, uncovered, verify []attentionItem
	for i := range stations {
		st := &stations[i]
		out.Registered += st.Registered
		if st.Cast != nil {
			out.Cast += *st.Cast
		}
		if st.UpdatedAt != nil && (out.LastUpdate == nil || st.UpdatedAt.After(*out.LastUpdate)) {
			out.LastUpdate = st.UpdatedAt
		}
		area := st.Ward + " Ward · " + st.Constituency
		switch st.Status {
		case "reporting":
			out.Reported++
		case "closed":
			out.Reported++
			out.Closed++
			if st.Results < len(positions) || st.Pending > 0 {
				out.ToVerify++
				verify = append(verify, attentionItem{st.Code, st.Name, area, "Results to verify", "verify", "Verify results"})
			}
		case "open":
			out.Open++
		case "issue":
			out.Issues++
			reason := "Issue reported"
			if st.LastIncident != nil {
				reason = *st.LastIncident
			}
			issues = append(issues, attentionItem{st.Code, st.Name, area, reason, "issue", "Review"})
		}
		if st.Uncovered() {
			out.Uncovered++
			uncovered = append(uncovered, attentionItem{st.Code, st.Name, area, "No agent assigned", "uncovered", "Assign agent"})
		}
	}
	out.Attention = append(append(append(out.Attention, issues...), uncovered...), verify...)
	out.Turnout = share(out.Cast, out.Registered)
	out.Trend = trend(ptrs(stations), t, 23)
	if err := s.db.QueryRow(ctx, `
		SELECT count(*) FROM users WHERE org_id=$1 AND role='agent' AND active
		  AND ($2::text IS NULL OR scope_county=$2) AND ($3::text IS NULL OR scope_constituency=$3) AND ($4::text IS NULL OR scope_ward=$4)`,
		p.OrgID, sc.County, sc.Constituency, sc.Ward).Scan(&out.Agents); err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

// ---- turnout monitor ----

type leader struct {
	Candidate candidate `json:"candidate"`
	Share     float64   `json:"share"`
}

type turnoutArea struct {
	Name      string    `json:"name"`
	Turnout   float64   `json:"turnout"`
	VsAvg     float64   `json:"vs_avg"` // percentage points
	Leading   *leader   `json:"leading"`
	WeLead    *bool     `json:"we_lead"`
	Signal    string    `json:"signal"`
	Attention bool      `json:"attention"`
	Hourly    []float64 `json:"hourly"` // cumulative turnout at each slot
	Drillable bool      `json:"drillable"`
}

func signalFor(below bool, weLead *bool, hasResults bool) (string, bool) {
	switch {
	case !hasResults || weLead == nil:
		if below {
			return "Below average", true
		}
		return "On pace", false
	case *weLead && below:
		return "Push GOTV", true
	case !*weLead && below:
		return "Behind + low turnout", true
	case !*weLead:
		return "Opponent ahead", true
	}
	return "Strong", false
}

func (s *Server) opsTurnout(w http.ResponseWriter, r *http.Request, p *Principal) {
	e, sc, ok := s.opsContext(w, r, p)
	if !ok {
		return
	}
	ctx := r.Context()
	view := sc.narrow(r.URL.Query().Get("constituency"), r.URL.Query().Get("ward"))
	stations, err := s.loadStations(ctx, e.ID, view)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	t, err := s.loadTurnout(ctx, e.ID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	positions, err := s.loadPositions(ctx, e.ID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	cands, err := s.loadCandidates(ctx, e.ID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	focus := focusPosition(positions, cands)
	var tl tally
	if focus != nil {
		if tl, err = s.loadTally(ctx, e.ID, focus.ID, nil); err != nil {
			s.internal(w, r, err)
			return
		}
	}
	cmap := candidateMap(cands)
	all := ptrs(stations)
	cast, reg := turnoutOf(all, t, 23)
	avg := share(cast, reg)
	child := view.childLevel()

	areas := []turnoutArea{}
	attention := 0
	for _, g := range groupBy(stations, child) {
		c, rg := turnoutOf(g.Stations, t, 23)
		a := turnoutArea{Name: g.Name, Turnout: share(c, rg), Drillable: child != "station"}
		a.VsAvg = math.Round((a.Turnout - avg) * 100)
		for _, h := range turnoutSlots {
			hc, hr := turnoutOf(g.Stations, t, h)
			a.Hourly = append(a.Hourly, share(hc, hr))
		}
		if focus != nil {
			if ranked := sumCandidates(tl, g.Stations, cmap); len(ranked) > 0 {
				a.Leading = &leader{Candidate: ranked[0].Candidate, Share: ranked[0].Share}
				anyOurs := false
				for _, rc := range ranked {
					anyOurs = anyOurs || rc.Candidate.IsOurs
				}
				if anyOurs {
					lead := ranked[0].Candidate.IsOurs
					a.WeLead = &lead
				}
			}
		}
		a.Signal, a.Attention = signalFor(a.Turnout < avg, a.WeLead, a.Leading != nil)
		if a.Attention {
			attention++
		}
		areas = append(areas, a)
	}
	var ours *candidate
	if focus != nil {
		for _, c := range cands {
			if c.PositionID == focus.ID && c.IsOurs {
				cc := c
				ours = &cc
				break
			}
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"election": e, "scope": view, "scope_label": view.label(), "child_level": child,
		"cast": cast, "registered": reg, "turnout": avg, "trend": trend(all, t, 23),
		"focus_position": focus, "our_candidate": ours, "areas": areas, "attention_count": attention,
		"slots": turnoutSlots,
	})
}

// ---- results monitor ----

type resultArea struct {
	Name      string   `json:"name"`
	Leading   *leader  `json:"leading"`
	Reporting float64  `json:"reporting"` // share of stations with a Form 37A for this position
	Stations  int      `json:"stations"`
	Margin    *float64 `json:"margin"` // leader minus runner-up, percentage points
	Drillable bool     `json:"drillable"`
}

func (s *Server) opsResults(w http.ResponseWriter, r *http.Request, p *Principal) {
	e, sc, ok := s.opsContext(w, r, p)
	if !ok {
		return
	}
	ctx := r.Context()
	positions, err := s.loadPositions(ctx, e.ID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if len(positions) == 0 {
		writeErr(w, http.StatusNotFound, "this election has no positions yet")
		return
	}
	pos := positions[0]
	for _, ps := range positions {
		if ps.ID == r.URL.Query().Get("position_id") {
			pos = ps
		}
	}
	view := sc.narrow(r.URL.Query().Get("constituency"), r.URL.Query().Get("ward"))
	stations, err := s.loadStations(ctx, e.ID, view)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	cands, err := s.loadCandidates(ctx, e.ID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	tl, err := s.loadTally(ctx, e.ID, pos.ID, nil)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	cmap := candidateMap(cands)
	all := ptrs(stations)
	reporting := 0
	races := map[string]bool{}
	for _, st := range all {
		if tl.submitted[st.Code] {
			reporting++
		}
		key := "national"
		if pos.Level != "national" {
			key = regionOf(st, pos.Level)
		}
		races[key] = true
	}
	// Candidate totals only make sense when the view holds a single race.
	var totals []candidateTotal
	var raceName *string
	if len(races) == 1 {
		totals = sumCandidates(tl, all, cmap)
		for k := range races {
			raceName = &k
		}
	}
	child := view.childLevel()
	areas := []resultArea{}
	for _, g := range groupBy(stations, child) {
		a := resultArea{Name: g.Name, Stations: len(g.Stations), Drillable: child != "station"}
		rep := 0
		for _, st := range g.Stations {
			if tl.submitted[st.Code] {
				rep++
			}
		}
		a.Reporting = share(rep, len(g.Stations))
		if ranked := sumCandidates(tl, g.Stations, cmap); len(ranked) > 0 {
			a.Leading = &leader{Candidate: ranked[0].Candidate, Share: ranked[0].Share}
			if len(ranked) > 1 {
				m := math.Round((ranked[0].Share - ranked[1].Share) * 100)
				a.Margin = &m
			}
		}
		areas = append(areas, a)
	}
	var lastAt *time.Time
	if err := s.db.QueryRow(ctx, `SELECT max(verified_at) FROM result_submissions WHERE election_id=$1 AND position_id=$2`, e.ID, pos.ID).
		Scan(&lastAt); err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"election": e, "positions": positions, "position": pos, "scope": view, "scope_label": view.label(),
		"child_level": child, "stations": len(stations), "stations_reporting": reporting,
		"single_race": len(races) == 1, "race": raceName, "totals": totals, "areas": areas, "last_update": lastAt,
	})
}

// ---- replay ----

// opsReplay reconstructs election day at a given hour from the recorded figures and activity.
func (s *Server) opsReplay(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOps(w, p) {
		return
	}
	ctx := r.Context()
	e, err := s.loadElection(ctx, p, r.URL.Query().Get("election_id"))
	if err != nil {
		writeErr(w, http.StatusNotFound, "election not found")
		return
	}
	hour, err := strconv.Atoi(r.URL.Query().Get("hour"))
	if err != nil || hour < 0 || hour > 23 {
		hour = 15
	}
	day, _ := time.ParseInLocation(time.DateOnly, e.ElectionDate, nairobi)
	until := day.Add(time.Duration(hour)*time.Hour + 59*time.Minute)

	sc := p.userScope().orElse(e.Scope)
	stations, err := s.loadStations(ctx, e.ID, sc)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	t, err := s.loadTurnout(ctx, e.ID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	positions, err := s.loadPositions(ctx, e.ID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	cands, err := s.loadCandidates(ctx, e.ID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	cmap := candidateMap(cands)
	focus := focusPosition(positions, cands)
	tl := tally{votes: map[string]map[string]int{}, submitted: map[string]bool{}}
	if focus != nil {
		if tl, err = s.loadTally(ctx, e.ID, focus.ID, &until); err != nil {
			s.internal(w, r, err)
			return
		}
	}
	all := ptrs(stations)
	cast, reg := turnoutOf(all, t, hour)
	reporting := 0
	for _, st := range all {
		if _, ok := t.at(st.Code, hour); ok {
			reporting++
		}
	}
	type replayArea struct {
		Name    string   `json:"name"`
		Turnout float64  `json:"turnout"`
		Leading *leader  `json:"leading"`
		Ours    *bool    `json:"ours"`
		Margin  *float64 `json:"margin"`
	}
	margin := func(ranked []candidateTotal) (*leader, *bool, *float64) {
		if len(ranked) == 0 {
			return nil, nil, nil
		}
		l := &leader{Candidate: ranked[0].Candidate, Share: ranked[0].Share}
		if len(ranked) < 2 {
			return l, &ranked[0].Candidate.IsOurs, nil
		}
		m := math.Round((ranked[0].Share - ranked[1].Share) * 100)
		return l, &ranked[0].Candidate.IsOurs, &m
	}
	lead, ours, marg := margin(sumCandidates(tl, all, cmap))
	areas := []replayArea{}
	for _, g := range groupBy(stations, sc.childLevel()) {
		c, rg := turnoutOf(g.Stations, t, hour)
		a := replayArea{Name: g.Name, Turnout: share(c, rg)}
		a.Leading, a.Ours, a.Margin = margin(sumCandidates(tl, g.Stations, cmap))
		areas = append(areas, a)
	}
	rows, err := s.db.Query(ctx, `
		SELECT se.kind, se.message || ' — ' || ps.name, u.name, se.at
		FROM station_events se JOIN polling_stations ps ON ps.code = se.station_code LEFT JOIN users u ON u.id = se.user_id
		WHERE se.election_id = $1 AND se.at <= $2
		  AND ($3::text IS NULL OR ps.county=$3) AND ($4::text IS NULL OR ps.constituency=$4) AND ($5::text IS NULL OR ps.ward=$5)
		ORDER BY se.at DESC LIMIT 25`, e.ID, until, sc.County, sc.Constituency, sc.Ward)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	events, err := collect(rows, func(row pgx.Row) (stationEvent, error) {
		var ev stationEvent
		return ev, row.Scan(&ev.Kind, &ev.Message, &ev.By, &ev.At)
	})
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"election": e, "hour": hour, "at": until, "turnout": share(cast, reg), "cast": cast, "registered": reg,
		"stations": len(stations), "stations_reporting": reporting, "focus_position": focus,
		"leading": lead, "we_lead": ours, "margin": marg, "areas": areas, "child_level": sc.childLevel(), "events": events,
	})
}
