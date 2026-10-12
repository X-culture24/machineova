package api

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// dbtx is satisfied by both the pool and a transaction.
type dbtx interface {
	execer
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

var statusLabels = map[string]string{"not_open": "Not open", "open": "Open", "reporting": "Reporting", "closed": "Closed", "issue": "Issue"}

// listStations powers Operate › Polling stations: status chips, scope filters, search and pages.
func (s *Server) listStations(w http.ResponseWriter, r *http.Request, p *Principal) {
	e, sc, ok := s.opsContext(w, r, p)
	if !ok {
		return
	}
	q := r.URL.Query()
	view := sc.narrow(q.Get("constituency"), q.Get("ward"))
	all, err := s.loadStations(r.Context(), e.ID, view)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	counts := map[string]int{"not_open": 0, "open": 0, "reporting": 0, "closed": 0, "issue": 0, "uncovered": 0}
	status, search := q.Get("status"), strings.ToLower(strings.TrimSpace(q.Get("q")))
	filtered := []stationRow{}
	for _, st := range all {
		counts[st.Status]++
		if st.Uncovered() {
			counts["uncovered"]++
		}
		if status == "uncovered" && !st.Uncovered() || status != "" && status != "uncovered" && st.Status != status {
			continue
		}
		if search != "" && !strings.Contains(strings.ToLower(st.Name+" "+st.Code+" "+st.Ward), search) {
			continue
		}
		filtered = append(filtered, st)
	}
	pg := pageParams(q.Get("page"), q.Get("page_size"))
	start := min(pg.offset(), len(filtered))
	end := min(start+pg.size, len(filtered))
	resp := pg.response(filtered[start:end], len(filtered))
	resp["counts"] = counts
	resp["in_scope"] = len(all)
	resp["scope"] = view
	resp["scope_label"] = view.label()
	writeJSON(w, http.StatusOK, resp)
}

type stationAgent struct {
	ID         string  `json:"id"`
	Name       string  `json:"name"`
	Phone      *string `json:"phone"`
	NationalID *string `json:"national_id"`
}

type stationEvent struct {
	Kind    string    `json:"kind"`
	Message string    `json:"message"`
	By      *string   `json:"by"`
	At      time.Time `json:"at"`
}

type incident struct {
	ID          string     `json:"id"`
	Type        string     `json:"type"`
	Description string     `json:"description"`
	ReportedBy  string     `json:"reported_by"`
	CreatedAt   time.Time  `json:"created_at"`
	ResolvedAt  *time.Time `json:"resolved_at"`
	Resolution  *string    `json:"resolution"`
}

// getStation powers the station drawer: record, agents, incidents, results status and activity.
func (s *Server) getStation(w http.ResponseWriter, r *http.Request, p *Principal) {
	e, sc, ok := s.opsContext(w, r, p)
	if !ok {
		return
	}
	st, err := s.loadStation(r.Context(), e, sc, r.PathValue("code"))
	if errors.Is(err, errNotFound) {
		writeErr(w, http.StatusNotFound, "station not found in your scope")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	ctx := r.Context()
	rows, err := s.db.Query(ctx, `
		SELECT u.id, u.name, u.phone, u.national_id FROM station_agents a JOIN users u ON u.id = a.user_id
		WHERE a.election_id=$1 AND a.station_code=$2 ORDER BY u.name`, e.ID, st.Code)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	agents, err := collect(rows, func(row pgx.Row) (stationAgent, error) {
		var a stationAgent
		return a, row.Scan(&a.ID, &a.Name, &a.Phone, &a.NationalID)
	})
	if err != nil {
		s.internal(w, r, err)
		return
	}
	rows, err = s.db.Query(ctx, `
		SELECT se.kind, se.message, u.name, se.at FROM station_events se LEFT JOIN users u ON u.id = se.user_id
		WHERE se.election_id=$1 AND se.station_code=$2 ORDER BY se.at DESC LIMIT 50`, e.ID, st.Code)
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
	rows, err = s.db.Query(ctx, `
		SELECT i.id, i.type, i.description, u.name, i.created_at, i.resolved_at, i.resolution
		FROM incidents i JOIN users u ON u.id = i.reported_by
		WHERE i.election_id=$1 AND i.station_code=$2 ORDER BY i.resolved_at IS NULL DESC, i.created_at DESC`, e.ID, st.Code)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	incidents, err := collect(rows, func(row pgx.Row) (incident, error) {
		var i incident
		return i, row.Scan(&i.ID, &i.Type, &i.Description, &i.ReportedBy, &i.CreatedAt, &i.ResolvedAt, &i.Resolution)
	})
	if err != nil {
		s.internal(w, r, err)
		return
	}
	rows, err = s.db.Query(ctx, `SELECT slot_hour, cumulative FROM turnout_reports WHERE election_id=$1 AND station_code=$2 ORDER BY slot_hour`,
		e.ID, st.Code)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	turnout, err := collect(rows, func(row pgx.Row) (hourCount, error) {
		var h hourCount
		return h, row.Scan(&h.Hour, &h.Count)
	})
	if err != nil {
		s.internal(w, r, err)
		return
	}
	positions, err := s.loadPositions(ctx, e.ID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	type posResult struct {
		Position    position   `json:"position"`
		SubmittedAt *time.Time `json:"submitted_at"`
	}
	results := []posResult{}
	for _, pos := range positions {
		var at *time.Time
		err := s.db.QueryRow(ctx, `SELECT submitted_at FROM result_submissions WHERE election_id=$1 AND station_code=$2 AND position_id=$3`,
			e.ID, st.Code, pos.ID).Scan(&at)
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			s.internal(w, r, err)
			return
		}
		results = append(results, posResult{Position: pos, SubmittedAt: at})
	}
	canAct, err := s.canActOn(ctx, p, e, st.Code)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"station": st, "agents": agents, "events": events, "incidents": incidents, "turnout": turnout,
		"results": results, "can_act": canAct, "can_assign": canAct && p.Role != "agent",
		"turnout_slots": turnoutSlots,
	})
}

var turnoutSlots = []int{7, 9, 11, 13, 15, 17}

// stationAction loads the station and checks the principal may act on it.
func (s *Server) stationAction(w http.ResponseWriter, r *http.Request, p *Principal) (election, *stationRow, bool) {
	e, sc, ok := s.opsContext(w, r, p)
	if !ok {
		return e, nil, false
	}
	if !p.OrgActive {
		writeErrCode(w, http.StatusForbidden, "org_inactive", "This organization is inactive")
		return e, nil, false
	}
	st, err := s.loadStation(r.Context(), e, sc, r.PathValue("code"))
	if errors.Is(err, errNotFound) {
		writeErr(w, http.StatusNotFound, "station not found in your scope")
		return e, nil, false
	}
	if err != nil {
		s.internal(w, r, err)
		return e, nil, false
	}
	canAct, err := s.canActOn(r.Context(), p, e, st.Code)
	if err != nil {
		s.internal(w, r, err)
		return e, nil, false
	}
	if !canAct {
		msg := "you can't change this station"
		if e.Status != "active" {
			msg = "this election is not active"
		} else if p.Role == "agent" {
			msg = "agents can only update the station they're assigned to"
		}
		writeErr(w, http.StatusForbidden, msg)
		return e, nil, false
	}
	return e, st, true
}

func (s *Server) updateStationStatus(w http.ResponseWriter, r *http.Request, p *Principal) {
	e, st, ok := s.stationAction(w, r, p)
	if !ok {
		return
	}
	var in struct {
		Status string `json:"status"`
		Note   string `json:"note"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	label, valid := statusLabels[in.Status]
	if !valid || in.Status == "not_open" {
		writeErr(w, http.StatusBadRequest, "status must be open, reporting, closed or issue")
		return
	}
	msg := map[string]string{
		"open": "Polls opened — status set to Open", "reporting": "Status set to Reporting",
		"closed": "Polls closed — awaiting verification", "issue": "Flagged as Issue",
	}[in.Status]
	if st.Status == in.Status {
		msg = "Status confirmed as " + label
	}
	if note := strings.TrimSpace(in.Note); note != "" {
		msg += ". " + note
	}
	if err := s.inTx(r.Context(), func(tx pgx.Tx) error {
		if _, err := tx.Exec(r.Context(), `UPDATE election_stations SET status=$3, updated_at=$4 WHERE election_id=$1 AND station_code=$2`,
			e.ID, st.Code, in.Status, recordedAt(r)); err != nil {
			return err
		}
		return logStationEvent(r.Context(), tx, e, st.Code, "status", msg, p.UserID, recordedAt(r))
	}); err != nil {
		s.internal(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) recordTurnout(w http.ResponseWriter, r *http.Request, p *Principal) {
	e, st, ok := s.stationAction(w, r, p)
	if !ok {
		return
	}
	var in struct {
		SlotHour   int `json:"slot_hour"`
		Cumulative int `json:"cumulative"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	validSlot := false
	for _, h := range turnoutSlots {
		validSlot = validSlot || h == in.SlotHour
	}
	if !validSlot {
		writeErr(w, http.StatusBadRequest, "pick a time slot")
		return
	}
	if in.Cumulative < 0 || (st.Registered > 0 && in.Cumulative > st.Registered) {
		writeErr(w, http.StatusBadRequest, fmt.Sprintf("turnout must be between 0 and %d registered voters", st.Registered))
		return
	}
	// Cumulative figures can't go down over the day.
	var before, after *int
	if err := s.db.QueryRow(r.Context(), `
		SELECT (SELECT max(cumulative) FROM turnout_reports WHERE election_id=$1 AND station_code=$2 AND slot_hour < $3),
		       (SELECT min(cumulative) FROM turnout_reports WHERE election_id=$1 AND station_code=$2 AND slot_hour > $3)`,
		e.ID, st.Code, in.SlotHour).Scan(&before, &after); err != nil {
		s.internal(w, r, err)
		return
	}
	if before != nil && in.Cumulative < *before {
		writeErr(w, http.StatusBadRequest, fmt.Sprintf("turnout is cumulative — an earlier slot already recorded %d", *before))
		return
	}
	if after != nil && in.Cumulative > *after {
		writeErr(w, http.StatusBadRequest, fmt.Sprintf("a later slot already recorded %d", *after))
		return
	}
	pct := ""
	if st.Registered > 0 {
		pct = fmt.Sprintf(" (%d%%)", in.Cumulative*100/st.Registered)
	}
	if err := s.inTx(r.Context(), func(tx pgx.Tx) error {
		if _, err := tx.Exec(r.Context(), `
			INSERT INTO turnout_reports (election_id, station_code, slot_hour, cumulative, recorded_by, recorded_at) VALUES ($1,$2,$3,$4,$5,$6)
			ON CONFLICT (election_id, station_code, slot_hour) DO UPDATE SET cumulative = EXCLUDED.cumulative,
				recorded_by = EXCLUDED.recorded_by, recorded_at = EXCLUDED.recorded_at`,
			e.ID, st.Code, in.SlotHour, in.Cumulative, p.UserID, recordedAt(r)); err != nil {
			return err
		}
		// First figures move an open station to Reporting; Issue/Closed are left alone.
		if _, err := tx.Exec(r.Context(), `UPDATE election_stations SET updated_at = now(),
			status = CASE WHEN status IN ('not_open', 'open') THEN 'reporting'::station_status ELSE status END
			WHERE election_id=$1 AND station_code=$2`, e.ID, st.Code); err != nil {
			return err
		}
		return logStationEvent(r.Context(), tx, e, st.Code, "turnout",
			fmt.Sprintf("Turnout recorded for %s — %d%s", slotLabel(in.SlotHour), in.Cumulative, pct), p.UserID, recordedAt(r))
	}); err != nil {
		s.internal(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func slotLabel(h int) string {
	suffix := "AM"
	if h >= 12 {
		suffix = "PM"
	}
	if h%12 == 0 {
		return "12 " + suffix
	}
	return fmt.Sprintf("%d %s", h%12, suffix)
}

var incidentTypes = []string{"KIEMS kit failure", "Ballot paper shortage", "Security concern", "Agent absent", "Voter intimidation", "Other"}

func (s *Server) reportIncident(w http.ResponseWriter, r *http.Request, p *Principal) {
	e, st, ok := s.stationAction(w, r, p)
	if !ok {
		return
	}
	var in struct {
		Type        string `json:"type"`
		Description string `json:"description"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	valid := false
	for _, t := range incidentTypes {
		valid = valid || t == in.Type
	}
	if !valid {
		writeErr(w, http.StatusBadRequest, "pick an incident type")
		return
	}
	desc := strings.TrimSpace(in.Description)
	if in.Type == "Other" && desc == "" {
		writeErr(w, http.StatusBadRequest, "describe what happened")
		return
	}
	var id string
	if err := s.inTx(r.Context(), func(tx pgx.Tx) error {
		if err := tx.QueryRow(r.Context(), `
			INSERT INTO incidents (election_id, station_code, type, description, reported_by, created_at) VALUES ($1,$2,$3,$4,$5,$6) RETURNING id`,
			e.ID, st.Code, in.Type, desc, p.UserID, recordedAt(r)).Scan(&id); err != nil {
			return err
		}
		// Reporting flags the station as Issue instantly.
		if _, err := tx.Exec(r.Context(), `UPDATE election_stations SET status='issue', updated_at=now() WHERE election_id=$1 AND station_code=$2`,
			e.ID, st.Code); err != nil {
			return err
		}
		msg := "Incident reported — " + in.Type
		if desc != "" {
			msg += ". " + desc
		}
		return logStationEvent(r.Context(), tx, e, st.Code, "incident", msg, p.UserID, recordedAt(r))
	}); err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]string{"id": id})
}

func (s *Server) resolveIncident(w http.ResponseWriter, r *http.Request, p *Principal) {
	e, st, ok := s.stationAction(w, r, p)
	if !ok {
		return
	}
	if p.Role == "agent" {
		writeErr(w, http.StatusForbidden, "a manager resolves incidents")
		return
	}
	var in struct {
		Resolution string `json:"resolution"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	res := strings.TrimSpace(in.Resolution)
	if res == "" {
		writeErr(w, http.StatusBadRequest, "say how it was resolved")
		return
	}
	notFound := false
	if err := s.inTx(r.Context(), func(tx pgx.Tx) error {
		var typ string
		err := tx.QueryRow(r.Context(), `
			UPDATE incidents SET resolved_at=now(), resolved_by=$4, resolution=$5
			WHERE election_id=$1 AND station_code=$2 AND id::text=$3 AND resolved_at IS NULL RETURNING type`,
			e.ID, st.Code, r.PathValue("id"), p.UserID, res).Scan(&typ)
		if errors.Is(err, pgx.ErrNoRows) {
			notFound = true
			return nil
		}
		if err != nil {
			return err
		}
		// Once nothing is open, an Issue station goes back to Reporting (or Open if no figures yet).
		if _, err := tx.Exec(r.Context(), `
			UPDATE election_stations es SET updated_at = now(), status = CASE
				WHEN EXISTS (SELECT 1 FROM turnout_reports t WHERE t.election_id = es.election_id AND t.station_code = es.station_code)
				THEN 'reporting'::station_status ELSE 'open'::station_status END
			WHERE es.election_id=$1 AND es.station_code=$2 AND es.status='issue'
			  AND NOT EXISTS (SELECT 1 FROM incidents i WHERE i.election_id=$1 AND i.station_code=$2 AND i.resolved_at IS NULL)`,
			e.ID, st.Code); err != nil {
			return err
		}
		return logStationEvent(r.Context(), tx, e, st.Code, "resolved", "Resolved — "+typ+". "+res, p.UserID, recordedAt(r))
	}); err != nil {
		s.internal(w, r, err)
		return
	}
	if notFound {
		writeErr(w, http.StatusNotFound, "open incident not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ---- agents ----

// agentPool lists agents registered in the station's ward, with where they're currently assigned.
func (s *Server) agentPool(w http.ResponseWriter, r *http.Request, p *Principal) {
	e, sc, ok := s.opsContext(w, r, p)
	if !ok {
		return
	}
	st, err := s.loadStation(r.Context(), e, sc, r.PathValue("code"))
	if errors.Is(err, errNotFound) {
		writeErr(w, http.StatusNotFound, "station not found in your scope")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	rows, err := s.db.Query(r.Context(), `
		SELECT u.id, u.name, u.phone, u.national_id, sa.station_code
		FROM users u LEFT JOIN station_agents sa ON sa.user_id = u.id AND sa.election_id = $2
		WHERE u.org_id = $1 AND u.role = 'agent' AND u.active AND u.scope_ward = $3 AND u.scope_constituency = $4
		  AND ($5::text IS NULL OR u.name ILIKE $5 OR u.national_id ILIKE $5)
		ORDER BY (sa.station_code IS NULL) DESC, u.name`,
		p.OrgID, e.ID, st.Ward, st.Constituency, likePattern(r.URL.Query().Get("q")))
	if err != nil {
		s.internal(w, r, err)
		return
	}
	type poolAgent struct {
		stationAgent
		AssignedTo *string `json:"assigned_to"`
	}
	out, err := collect(rows, func(row pgx.Row) (poolAgent, error) {
		var a poolAgent
		return a, row.Scan(&a.ID, &a.Name, &a.Phone, &a.NationalID, &a.AssignedTo)
	})
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ward": st.Ward, "agents": out})
}

func (s *Server) assignStationAgent(w http.ResponseWriter, r *http.Request, p *Principal) {
	e, st, ok := s.stationAction(w, r, p)
	if !ok {
		return
	}
	if p.Role == "agent" {
		writeErr(w, http.StatusForbidden, "agents can't assign agents")
		return
	}
	var agentScope scope
	err := s.db.QueryRow(r.Context(), `SELECT scope_county, scope_constituency, scope_ward FROM users
		WHERE id::text=$1 AND org_id=$2 AND role='agent' AND active`, r.PathValue("user"), p.OrgID).
		Scan(&agentScope.County, &agentScope.Constituency, &agentScope.Ward)
	if errors.Is(err, pgx.ErrNoRows) {
		writeErr(w, http.StatusNotFound, "agent not found")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	var msg string
	if err := s.inTx(r.Context(), func(tx pgx.Tx) error {
		var err error
		msg, err = assignAgent(r.Context(), tx, e, st.Code, r.PathValue("user"), agentScope, p.UserID)
		return err
	}); err != nil {
		s.internal(w, r, err)
		return
	}
	if msg != "" {
		writeErr(w, http.StatusBadRequest, msg)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// assignAgent moves an agent to a station (an agent covers one station per election).
func assignAgent(ctx context.Context, q dbtx, e election, code, userID string, agentScope scope, by string) (string, error) {
	var name, ward, constituency string
	err := q.QueryRow(ctx, `
		SELECT s.name, s.ward, s.constituency FROM election_stations es JOIN polling_stations s ON s.code = es.station_code
		WHERE es.election_id=$1 AND es.station_code=$2`, e.ID, code).Scan(&name, &ward, &constituency)
	if errors.Is(err, pgx.ErrNoRows) {
		return "station " + code + " is not part of this election", nil
	}
	if err != nil {
		return "", err
	}
	if !agentScope.contains(scope{County: agentScope.County, Constituency: &constituency, Ward: &ward}) {
		return "this agent is registered in another ward", nil
	}
	var agentName string
	if err := q.QueryRow(ctx, `
		INSERT INTO station_agents (election_id, station_code, user_id) VALUES ($1,$2,$3)
		ON CONFLICT (election_id, user_id) DO UPDATE SET station_code = EXCLUDED.station_code, assigned_at = now()
		RETURNING (SELECT name FROM users WHERE id = $3)`, e.ID, code, userID).Scan(&agentName); err != nil {
		return "", err
	}
	return "", logStationEvent(ctx, q, e, code, "assign", agentName+" assigned as agent", by, time.Now())
}

func (s *Server) unassignStationAgent(w http.ResponseWriter, r *http.Request, p *Principal) {
	e, st, ok := s.stationAction(w, r, p)
	if !ok {
		return
	}
	if p.Role == "agent" {
		writeErr(w, http.StatusForbidden, "agents can't change assignments")
		return
	}
	if err := s.inTx(r.Context(), func(tx pgx.Tx) error {
		var name string
		err := tx.QueryRow(r.Context(), `
			DELETE FROM station_agents sa USING users u
			WHERE sa.election_id=$1 AND sa.station_code=$2 AND sa.user_id::text=$3 AND u.id = sa.user_id RETURNING u.name`,
			e.ID, st.Code, r.PathValue("user")).Scan(&name)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil
		}
		if err != nil {
			return err
		}
		return logStationEvent(r.Context(), tx, e, st.Code, "assign", name+" removed from this station", p.UserID, recordedAt(r))
	}); err != nil {
		s.internal(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ---- results (Form 37A) ----

// raceCandidates returns the candidates standing at this station for a position.
func (s *Server) raceCandidates(ctx context.Context, e election, st *stationRow, positionID string) (position, []candidate, error) {
	positions, err := s.loadPositions(ctx, e.ID)
	if err != nil {
		return position{}, nil, err
	}
	var pos *position
	for i := range positions {
		if positions[i].ID == positionID {
			pos = &positions[i]
		}
	}
	if pos == nil {
		return position{}, nil, errNotFound
	}
	all, err := s.loadCandidates(ctx, e.ID)
	if err != nil {
		return *pos, nil, err
	}
	var region *string
	if pos.Level != "national" {
		r := regionOf(st, pos.Level)
		region = &r
	}
	out := []candidate{}
	for _, c := range all {
		if c.PositionID == pos.ID && ptrEq(c.Region, region) {
			out = append(out, c)
		}
	}
	return *pos, out, nil
}

func (s *Server) getStationResults(w http.ResponseWriter, r *http.Request, p *Principal) {
	e, sc, ok := s.opsContext(w, r, p)
	if !ok {
		return
	}
	st, err := s.loadStation(r.Context(), e, sc, r.PathValue("code"))
	if errors.Is(err, errNotFound) {
		writeErr(w, http.StatusNotFound, "station not found in your scope")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	pos, cands, err := s.raceCandidates(r.Context(), e, st, r.URL.Query().Get("position_id"))
	if errors.Is(err, errNotFound) {
		writeErr(w, http.StatusNotFound, "position not found")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	votes := map[string]int{}
	rows, err := s.db.Query(r.Context(), `SELECT candidate_id, votes FROM result_votes WHERE election_id=$1 AND station_code=$2 AND position_id=$3`,
		e.ID, st.Code, pos.ID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	for rows.Next() {
		var id string
		var v int
		if err := rows.Scan(&id, &v); err != nil {
			s.internal(w, r, err)
			return
		}
		votes[id] = v
	}
	var rejected *int
	var submittedAt *time.Time
	err = s.db.QueryRow(r.Context(), `SELECT rejected, submitted_at FROM result_submissions WHERE election_id=$1 AND station_code=$2 AND position_id=$3`,
		e.ID, st.Code, pos.ID).Scan(&rejected, &submittedAt)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"position": pos, "candidates": cands, "votes": votes, "rejected": rejected, "submitted_at": submittedAt,
		"turnout": st.Cast, "registered": st.Registered,
	})
}

func (s *Server) submitStationResults(w http.ResponseWriter, r *http.Request, p *Principal) {
	e, st, ok := s.stationAction(w, r, p)
	if !ok {
		return
	}
	var in struct {
		PositionID string         `json:"position_id"`
		Votes      map[string]int `json:"votes"` // candidate_id → votes
		Rejected   int            `json:"rejected"`
		Confirm    bool           `json:"confirm"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	if !in.Confirm {
		writeErr(w, http.StatusBadRequest, "confirm the figures match the signed Form 37A")
		return
	}
	pos, cands, err := s.raceCandidates(r.Context(), e, st, in.PositionID)
	if errors.Is(err, errNotFound) {
		writeErr(w, http.StatusBadRequest, "unknown position")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if len(cands) == 0 {
		writeErr(w, http.StatusBadRequest, "no candidates are set up for this race yet")
		return
	}
	total := in.Rejected
	for _, c := range cands {
		v, ok := in.Votes[c.ID]
		if !ok || v < 0 {
			writeErr(w, http.StatusBadRequest, "enter votes (0 or more) for every candidate")
			return
		}
		total += v
	}
	if len(in.Votes) != len(cands) || in.Rejected < 0 {
		writeErr(w, http.StatusBadRequest, "votes must cover exactly this race's candidates")
		return
	}
	if st.Registered > 0 && total > st.Registered {
		writeErr(w, http.StatusBadRequest, fmt.Sprintf("total ballots %d exceed the %d registered voters", total, st.Registered))
		return
	}
	if err := s.inTx(r.Context(), func(tx pgx.Tx) error {
		if _, err := tx.Exec(r.Context(), `DELETE FROM result_submissions WHERE election_id=$1 AND station_code=$2 AND position_id=$3`,
			e.ID, st.Code, pos.ID); err != nil {
			return err
		}
		if _, err := tx.Exec(r.Context(), `
			INSERT INTO result_submissions (election_id, station_code, position_id, rejected, submitted_by, submitted_at) VALUES ($1,$2,$3,$4,$5,$6)`,
			e.ID, st.Code, pos.ID, in.Rejected, p.UserID, recordedAt(r)); err != nil {
			return err
		}
		for _, c := range cands {
			if _, err := tx.Exec(r.Context(), `
				INSERT INTO result_votes (election_id, station_code, position_id, candidate_id, votes) VALUES ($1,$2,$3,$4,$5)`,
				e.ID, st.Code, pos.ID, c.ID, in.Votes[c.ID]); err != nil {
				return err
			}
		}
		return logStationEvent(r.Context(), tx, e, st.Code, "results",
			fmt.Sprintf("Form 37A verified — %s · %d ballots", pos.Name, total), p.UserID, recordedAt(r))
	}); err != nil {
		s.internal(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) inTx(ctx context.Context, fn func(pgx.Tx) error) error {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
