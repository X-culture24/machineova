package api

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

type event struct {
	ID               string     `json:"id"`
	Name             string     `json:"name"`
	Venue            string     `json:"venue"`
	County           *string    `json:"county"`
	Constituency     *string    `json:"constituency"`
	Ward             *string    `json:"ward"`
	StartsAt         time.Time  `json:"starts_at"`
	EndsAt           *time.Time `json:"ends_at"`
	Active           bool       `json:"active"`
	RegionRestricted bool       `json:"region_restricted"`
	ListOnly         bool       `json:"list_only"`
	Checkins         int        `json:"checkins"`
	Unique           int        `json:"unique"`
	OutOfRegion      int        `json:"out_of_region"`
	Assigned         int        `json:"assigned"`
	Participants     int        `json:"participants"`
}

const eventSelect = `
	SELECT e.id, e.name, e.venue, e.county, e.constituency, e.ward, e.starts_at, e.ends_at,
	       e.active, e.region_restricted, e.list_only,
	       (SELECT count(*) FROM checkins c WHERE c.event_id = e.id),
	       (SELECT count(DISTINCT national_id) FROM checkins c WHERE c.event_id = e.id),
	       (SELECT count(*) FROM checkins c WHERE c.event_id = e.id AND NOT c.in_region),
	       (SELECT count(*) FROM event_assignments a WHERE a.event_id = e.id),
	       (SELECT count(*) FROM event_participants pp WHERE pp.event_id = e.id)
	FROM events e`

func scanEvent(row pgx.Row) (event, error) {
	var e event
	err := row.Scan(&e.ID, &e.Name, &e.Venue, &e.County, &e.Constituency, &e.Ward, &e.StartsAt, &e.EndsAt,
		&e.Active, &e.RegionRestricted, &e.ListOnly, &e.Checkins, &e.Unique, &e.OutOfRegion, &e.Assigned, &e.Participants)
	return e, err
}

// visibleEvents is the WHERE clause limiting events to the org, and for members, to assigned events.
// Callers pass $1 = org ID, $2 = user ID, $3 = sees-all flag.
const visibleEvents = ` WHERE e.org_id = $1 AND ($3 OR EXISTS (
	SELECT 1 FROM event_assignments a WHERE a.event_id = e.id AND a.user_id = $2))`

var errNotFound = errors.New("not found")

// loadEvent returns an event the principal is allowed to see.
func (s *Server) loadEvent(ctx context.Context, p *Principal, id string) (event, error) {
	e, err := scanEvent(s.db.QueryRow(ctx, eventSelect+visibleEvents+` AND e.id = $4`, p.OrgID, p.UserID, p.SeesAll(), id))
	if errors.Is(err, pgx.ErrNoRows) || isInvalidUUID(err) {
		return e, errNotFound
	}
	return e, err
}

func (s *Server) listEvents(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	q := eventSelect + visibleEvents
	if r.URL.Query().Get("active") == "true" {
		q += ` AND e.active`
	}
	rows, err := s.db.Query(r.Context(), q+` ORDER BY e.active DESC, e.starts_at DESC`, p.OrgID, p.UserID, p.SeesAll())
	if err != nil {
		s.internal(w, r, err)
		return
	}
	items, err := collect(rows, scanEvent)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	var summary struct {
		Total    int `json:"total"`
		Active   int `json:"active"`
		Closed   int `json:"closed"`
		Checkins int `json:"checkins"`
	}
	for _, e := range items {
		summary.Total++
		summary.Checkins += e.Checkins
		if e.Active {
			summary.Active++
		} else {
			summary.Closed++
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"summary": summary, "items": items})
}

type eventInput struct {
	Name             *string    `json:"name"`
	Venue            *string    `json:"venue"`
	County           *string    `json:"county"`
	Constituency     *string    `json:"constituency"`
	Ward             *string    `json:"ward"`
	StartsAt         *time.Time `json:"starts_at"`
	EndsAt           *time.Time `json:"ends_at"`
	Active           *bool      `json:"active"`
	RegionRestricted *bool      `json:"region_restricted"`
	ListOnly         *bool      `json:"list_only"`
}

func (s *Server) createEvent(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireManager(w, p) {
		return
	}
	var in eventInput
	if !readJSON(w, r, &in) {
		return
	}
	if in.Name == nil || strings.TrimSpace(*in.Name) == "" || in.StartsAt == nil {
		writeErr(w, http.StatusBadRequest, "name and starts_at are required")
		return
	}
	var id string
	err := s.db.QueryRow(r.Context(), `
		INSERT INTO events (org_id, name, venue, county, constituency, ward, starts_at, ends_at, region_restricted, list_only)
		VALUES ($1,$2,COALESCE($3,''),$4,$5,$6,$7,$8,COALESCE($9,false),COALESCE($10,false)) RETURNING id`,
		p.OrgID, strings.TrimSpace(*in.Name), in.Venue, emptyNil(in.County), emptyNil(in.Constituency), emptyNil(in.Ward),
		in.StartsAt, in.EndsAt, in.RegionRestricted, in.ListOnly).Scan(&id)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	e, err := s.loadEvent(r.Context(), p, id)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, e)
}

func (s *Server) getEvent(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	e, err := s.loadEvent(r.Context(), p, r.PathValue("id"))
	if errors.Is(err, errNotFound) {
		writeErr(w, http.StatusNotFound, "event not found")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	rows, err := s.db.Query(r.Context(), `
		SELECT `+memberColsAs("u")+`
		FROM event_assignments a JOIN users u ON u.id = a.user_id WHERE a.event_id = $1 ORDER BY u.name`, e.ID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	assigned, err := collect(rows, scanMember)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"event": e, "assigned_users": assigned})
}

func (s *Server) updateEvent(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireManager(w, p) {
		return
	}
	var in eventInput
	if !readJSON(w, r, &in) {
		return
	}
	tag, err := s.db.Exec(r.Context(), `
		UPDATE events SET
			name = COALESCE($3, name), venue = COALESCE($4, venue),
			county = COALESCE($5, county), constituency = COALESCE($6, constituency), ward = COALESCE($7, ward),
			starts_at = COALESCE($8, starts_at), ends_at = COALESCE($9, ends_at),
			active = COALESCE($10, active),
			region_restricted = COALESCE($11, region_restricted), list_only = COALESCE($12, list_only)
		WHERE id = $1 AND org_id = $2`,
		r.PathValue("id"), p.OrgID, in.Name, in.Venue, in.County, in.Constituency, in.Ward,
		in.StartsAt, in.EndsAt, in.Active, in.RegionRestricted, in.ListOnly)
	if err != nil && !isInvalidUUID(err) {
		s.internal(w, r, err)
		return
	}
	if err != nil || tag.RowsAffected() == 0 {
		writeErr(w, http.StatusNotFound, "event not found")
		return
	}
	e, err := s.loadEvent(r.Context(), p, r.PathValue("id"))
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, e)
}

// setEventAssignments replaces the set of operators assigned to an event.
func (s *Server) setEventAssignments(w http.ResponseWriter, r *http.Request, p *Principal) {
	s.replaceAssignments(w, r, p, "events", "event_assignments", "event_id")
}

func (s *Server) replaceAssignments(w http.ResponseWriter, r *http.Request, p *Principal, table, assignTable, fk string) {
	if !requireManager(w, p) {
		return
	}
	var in struct {
		UserIDs []string `json:"user_ids"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	id := r.PathValue("id")
	tx, err := s.db.Begin(r.Context())
	if err != nil {
		s.internal(w, r, err)
		return
	}
	defer tx.Rollback(r.Context())
	var exists bool
	if err := tx.QueryRow(r.Context(), `SELECT EXISTS(SELECT 1 FROM `+table+` WHERE id::text=$1 AND org_id=$2)`, id, p.OrgID).Scan(&exists); err != nil {
		s.internal(w, r, err)
		return
	}
	if !exists {
		writeErr(w, http.StatusNotFound, "not found")
		return
	}
	if _, err := tx.Exec(r.Context(), `DELETE FROM `+assignTable+` WHERE `+fk+`=$1`, id); err != nil {
		s.internal(w, r, err)
		return
	}
	// Only users from the same org can be assigned; others are silently ignored.
	tag, err := tx.Exec(r.Context(), `
		INSERT INTO `+assignTable+` (`+fk+`, user_id)
		SELECT $1, u.id FROM users u WHERE u.org_id = $2 AND u.id::text = ANY($3)`, id, p.OrgID, in.UserIDs)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if err := tx.Commit(r.Context()); err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]int64{"assigned": tag.RowsAffected()})
}

// setEventParticipants replaces the approved participant list for list-only events.
func (s *Server) setEventParticipants(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireManager(w, p) {
		return
	}
	var in struct {
		NationalIDs []string `json:"national_ids"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	id := r.PathValue("id")
	ids := make([]string, 0, len(in.NationalIDs))
	for _, n := range in.NationalIDs {
		if n = normalizeID(n); n != "" {
			ids = append(ids, n)
		}
	}
	tx, err := s.db.Begin(r.Context())
	if err != nil {
		s.internal(w, r, err)
		return
	}
	defer tx.Rollback(r.Context())
	var exists bool
	if err := tx.QueryRow(r.Context(), `SELECT EXISTS(SELECT 1 FROM events WHERE id::text=$1 AND org_id=$2)`, id, p.OrgID).Scan(&exists); err != nil {
		s.internal(w, r, err)
		return
	}
	if !exists {
		writeErr(w, http.StatusNotFound, "event not found")
		return
	}
	if _, err := tx.Exec(r.Context(), `DELETE FROM event_participants WHERE event_id=$1`, id); err != nil {
		s.internal(w, r, err)
		return
	}
	tag, err := tx.Exec(r.Context(), `
		INSERT INTO event_participants (event_id, national_id)
		SELECT $1, DISTINCT_ID FROM (SELECT DISTINCT unnest($2::text[]) AS DISTINCT_ID) t`, id, ids)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if err := tx.Commit(r.Context()); err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]int64{"participants": tag.RowsAffected()})
}

func emptyNil(s *string) *string {
	if s == nil || strings.TrimSpace(*s) == "" {
		return nil
	}
	t := strings.TrimSpace(*s)
	return &t
}

// normalizeID strips spaces so "28 651 234" and "28651234" are the same ID.
func normalizeID(s string) string {
	return strings.Join(strings.Fields(s), "")
}
