package api

import (
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
)

// Training issues: problems the team meets in the field (device internet, device malfunction, a
// chief's location, sign-in, the app, other), typed as they happen, optionally naming the chief
// and the training. Anyone who can check people in may log one; administrators see them all,
// members the ones they logged or that happened at their trainings. The issues report
// (GET /api/issues/report) compiles them with a summary of every training.

var issueCategories = map[string]bool{"internet": true, "device": true, "location": true, "account": true, "app": true, "other": true}

type issue struct {
	ID          string     `json:"id"`
	EventID     *string    `json:"event_id"`
	EventName   *string    `json:"event_name"`
	EventCounty *string    `json:"event_county"`
	Category    string     `json:"category"`
	ChiefName   string     `json:"chief_name"`
	NationalID  string     `json:"national_id"`
	Phone       string     `json:"phone"`
	Location    string     `json:"location"`
	Description string     `json:"description"`
	ActionTaken string     `json:"action_taken"`
	Status      string     `json:"status"`
	ReportedBy  string     `json:"reported_by"`
	ReportedAt  time.Time  `json:"reported_at"`
	ResolvedAt  *time.Time `json:"resolved_at"`
}

const issueSelect = `
	SELECT i.id, i.event_id, e.name, e.county, i.category, i.chief_name, i.national_id, i.phone, i.location,
	       i.description, i.action_taken, i.status, u.name, i.reported_at, i.resolved_at
	FROM training_issues i
	JOIN users u ON u.id = i.reported_by
	LEFT JOIN events e ON e.id = i.event_id
	WHERE i.org_id = $1
	  AND ($3 OR i.reported_by = $2 OR i.event_id IN (SELECT event_id FROM event_assignments WHERE user_id = $2))`

func scanIssue(row pgx.Row) (issue, error) {
	var i issue
	err := row.Scan(&i.ID, &i.EventID, &i.EventName, &i.EventCounty, &i.Category, &i.ChiefName, &i.NationalID, &i.Phone,
		&i.Location, &i.Description, &i.ActionTaken, &i.Status, &i.ReportedBy, &i.ReportedAt, &i.ResolvedAt)
	return i, err
}

type issueInput struct {
	EventID     *string `json:"event_id"`
	Category    string  `json:"category"`
	ChiefName   string  `json:"chief_name"`
	NationalID  string  `json:"national_id"`
	Phone       string  `json:"phone"`
	Location    string  `json:"location"`
	Description string  `json:"description"`
	ActionTaken string  `json:"action_taken"`
	Status      string  `json:"status"`
}

// clean trims the input and returns what's wrong with it, if anything.
func (in *issueInput) clean() string {
	for _, f := range []*string{&in.Category, &in.ChiefName, &in.NationalID, &in.Phone, &in.Location, &in.Description, &in.ActionTaken, &in.Status} {
		*f = strings.TrimSpace(*f)
	}
	in.NationalID = strings.ToUpper(strings.ReplaceAll(in.NationalID, " ", ""))
	if in.EventID != nil && strings.TrimSpace(*in.EventID) == "" {
		in.EventID = nil
	}
	if in.Status == "" {
		in.Status = "open"
	}
	switch {
	case !issueCategories[in.Category]:
		return "Pick the kind of problem"
	case in.Description == "":
		return "Describe the problem"
	case utf8.RuneCountInString(in.Description) > 4000 || utf8.RuneCountInString(in.ActionTaken) > 4000:
		return "Keep the description and action under 4000 characters"
	case utf8.RuneCountInString(in.ChiefName) > 200 || len(in.NationalID) > 20 || len(in.Phone) > 30 || utf8.RuneCountInString(in.Location) > 300:
		return "A chief detail is too long"
	case in.Status != "open" && in.Status != "resolved":
		return "Status must be open or resolved"
	}
	return ""
}

func (s *Server) listIssues(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	q := issueSelect
	args := []any{p.OrgID, p.UserID, p.SeesAll()}
	add := func(cond string, v any) {
		args = append(args, v)
		q += strings.Replace(cond, "?", "$"+strconv.Itoa(len(args)), 1)
	}
	if v := r.URL.Query().Get("event_id"); v != "" {
		add(` AND i.event_id::text = ?`, v)
	}
	if v := r.URL.Query().Get("category"); issueCategories[v] {
		add(` AND i.category = ?`, v)
	}
	if v := r.URL.Query().Get("status"); v == "open" || v == "resolved" {
		add(` AND i.status = ?`, v)
	}
	if pattern := likePattern(r.URL.Query().Get("q")); pattern != nil {
		add(` AND concat_ws(' ', i.chief_name, i.national_id, i.phone, i.location, i.description, i.action_taken, e.name) ILIKE ?`, pattern)
	}
	rows, err := s.db.Query(r.Context(), q+` ORDER BY i.reported_at DESC LIMIT 2000`, args...)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	items, err := collect(rows, scanIssue)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (s *Server) createIssue(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	if !p.CanOperate() {
		writeErr(w, http.StatusForbidden, "you can't log issues with a view-only account")
		return
	}
	var in issueInput
	if !readJSON(w, r, &in) {
		return
	}
	if msg := in.clean(); msg != "" {
		writeErr(w, http.StatusBadRequest, msg)
		return
	}
	if in.EventID != nil {
		if _, err := s.loadEvent(r.Context(), p, *in.EventID); errors.Is(err, errNotFound) {
			writeErr(w, http.StatusBadRequest, "That training isn't one of yours")
			return
		} else if err != nil {
			s.internal(w, r, err)
			return
		}
	}
	var id string
	err := s.db.QueryRow(r.Context(), `
		INSERT INTO training_issues (org_id, event_id, category, chief_name, national_id, phone, location, description,
		                             action_taken, status, reported_by, resolved_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, CASE WHEN $10 = 'resolved' THEN now() END)
		RETURNING id`,
		p.OrgID, in.EventID, in.Category, in.ChiefName, in.NationalID, in.Phone, in.Location, in.Description,
		in.ActionTaken, in.Status, p.UserID).Scan(&id)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	s.writeIssue(w, r, p, id, http.StatusCreated)
}

// PATCH /api/issues/{id}: the whole issue again (the form), by an administrator or whoever logged it.
func (s *Server) updateIssue(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	var in issueInput
	if !readJSON(w, r, &in) {
		return
	}
	if msg := in.clean(); msg != "" {
		writeErr(w, http.StatusBadRequest, msg)
		return
	}
	var mine bool
	err := s.db.QueryRow(r.Context(), `SELECT $3 OR reported_by = $4 FROM training_issues WHERE id::text = $1 AND org_id = $2`,
		r.PathValue("id"), p.OrgID, p.IsManager(), p.UserID).Scan(&mine)
	if errors.Is(err, pgx.ErrNoRows) || isInvalidUUID(err) || (err == nil && (!mine || !p.CanOperate())) {
		writeErr(w, http.StatusNotFound, "Issue not found, or not yours to change")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if in.EventID != nil {
		if _, err := s.loadEvent(r.Context(), p, *in.EventID); errors.Is(err, errNotFound) {
			writeErr(w, http.StatusBadRequest, "That training isn't one of yours")
			return
		} else if err != nil {
			s.internal(w, r, err)
			return
		}
	}
	tag, err := s.db.Exec(r.Context(), `
		UPDATE training_issues SET event_id = $3, category = $4, chief_name = $5, national_id = $6, phone = $7, location = $8,
		       description = $9, action_taken = $10,
		       resolved_at = CASE WHEN $11 = 'resolved' THEN coalesce(resolved_at, now()) END, status = $11, updated_at = now()
		WHERE id::text = $1 AND org_id = $2 AND ($12 OR reported_by = $13) AND $14`,
		r.PathValue("id"), p.OrgID, in.EventID, in.Category, in.ChiefName, in.NationalID, in.Phone, in.Location,
		in.Description, in.ActionTaken, in.Status, p.IsManager(), p.UserID, p.CanOperate())
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if tag.RowsAffected() == 0 {
		writeErr(w, http.StatusNotFound, "Issue not found, or not yours to change")
		return
	}
	s.writeIssue(w, r, p, r.PathValue("id"), http.StatusOK)
}

func (s *Server) writeIssue(w http.ResponseWriter, r *http.Request, p *Principal, id string, status int) {
	i, err := scanIssue(s.db.QueryRow(r.Context(), issueSelect+` AND i.id::text = $4`, p.OrgID, p.UserID, p.SeesAll(), id))
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, status, i)
}

// GET /api/issues/chief?event_id=…&national_id=… — the chief's details from their check-in at that
// training (latest), to fill the form; 404 when they weren't checked in there.
func (s *Server) issueChief(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	eventID, nid := r.URL.Query().Get("event_id"), strings.ToUpper(strings.ReplaceAll(r.URL.Query().Get("national_id"), " ", ""))
	if eventID == "" || nid == "" {
		writeErr(w, http.StatusBadRequest, "event_id and national_id are required")
		return
	}
	if _, err := s.loadEvent(r.Context(), p, eventID); errors.Is(err, errNotFound) {
		writeErr(w, http.StatusNotFound, "Training not found")
		return
	} else if err != nil {
		s.internal(w, r, err)
		return
	}
	var out struct {
		Name     string `json:"name"`
		Phone    string `json:"phone"`
		Location string `json:"location"`
	}
	err := s.db.QueryRow(r.Context(), `
		SELECT name, coalesce(phone, ''), concat_ws(', ', nullif(ward, ''), nullif(constituency, ''), nullif(county, ''))
		FROM checkins WHERE event_id = $1 AND org_id = $2 AND national_id = $3
		ORDER BY checked_in_at DESC LIMIT 1`, eventID, p.OrgID, nid).Scan(&out.Name, &out.Phone, &out.Location)
	if errors.Is(err, pgx.ErrNoRows) {
		writeErr(w, http.StatusNotFound, "Not checked in at this training")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

// The issues report: every training with its attendance and issues, and every issue.
type issueTraining struct {
	EventID    string         `json:"event_id"`
	Name       string         `json:"name"`
	Venue      string         `json:"venue"`
	County     string         `json:"county"`
	StartsAt   time.Time      `json:"starts_at"`
	Active     bool           `json:"active"`
	HeldOn     *string        `json:"held_on"`
	FirstAt    *time.Time     `json:"first_at"`
	LastAt     *time.Time     `json:"last_at"`
	Present    int            `json:"present"`
	Phones     int            `json:"phones"`
	OutRegion  int            `json:"out_region"`
	Issues     int            `json:"issues"`
	Open       int            `json:"open"`
	ByCategory map[string]int `json:"by_category"`
}

func (s *Server) issuesReport(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	if !p.SeesAll() {
		writeErr(w, http.StatusForbidden, "the issues report is for administrators")
		return
	}
	ctx := r.Context()
	rows, err := s.db.Query(ctx, `
		SELECT e.id, e.name, e.venue, coalesce(e.county, ''), e.starts_at, e.active,
		       to_char(min(c.checked_in_at) AT TIME ZONE `+tzNairobi+`, 'YYYY-MM-DD'), min(c.checked_in_at), max(c.checked_in_at),
		       count(DISTINCT c.national_id),
		       count(DISTINCT c.national_id) FILTER (WHERE coalesce(c.phone, '') <> ''),
		       count(DISTINCT c.national_id) FILTER (WHERE NOT c.in_region)
		FROM events e LEFT JOIN checkins c ON c.event_id = e.id
		WHERE e.org_id = $1
		GROUP BY e.id ORDER BY min(c.checked_in_at) NULLS LAST, e.starts_at`, p.OrgID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	trainings, err := collect(rows, func(row pgx.Row) (issueTraining, error) {
		t := issueTraining{ByCategory: map[string]int{}}
		err := row.Scan(&t.EventID, &t.Name, &t.Venue, &t.County, &t.StartsAt, &t.Active, &t.HeldOn, &t.FirstAt, &t.LastAt,
			&t.Present, &t.Phones, &t.OutRegion)
		return t, err
	})
	if err != nil {
		s.internal(w, r, err)
		return
	}
	rows, err = s.db.Query(ctx, issueSelect+` ORDER BY i.reported_at`, p.OrgID, p.UserID, true)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	issues, err := collect(rows, scanIssue)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	idx := map[string]int{}
	for i, t := range trainings {
		idx[t.EventID] = i
	}
	byCategory := map[string]int{}
	open := 0
	for _, i := range issues {
		byCategory[i.Category]++
		if i.Status == "open" {
			open++
		}
		if i.EventID == nil {
			continue
		}
		if k, ok := idx[*i.EventID]; ok {
			t := &trainings[k]
			t.Issues++
			t.ByCategory[i.Category]++
			if i.Status == "open" {
				t.Open++
			}
		}
	}
	var org string
	_ = s.db.QueryRow(ctx, `SELECT name FROM organizations WHERE id = $1`, p.OrgID).Scan(&org)
	writeJSON(w, http.StatusOK, map[string]any{
		"organization": org, "generated_at": time.Now(), "trainings": trainings, "issues": issues,
		"by_category": byCategory, "open": open,
	})
}
