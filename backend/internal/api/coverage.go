package api

import (
	"errors"
	"net/http"
	"sort"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// Coverage status bands (share of an area's registered voters reached).
func coverageStatus(reached, registered int) string {
	if reached == 0 || registered == 0 {
		return "not_started"
	}
	switch c := float64(reached) / float64(registered); {
	case c >= .6:
		return "strong"
	case c >= .4:
		return "moderate"
	case c >= .2:
		return "low"
	default:
		return "critical"
	}
}

type coverageRow struct {
	Area       string  `json:"area"`
	Registered int     `json:"registered"`
	Reached    int     `json:"reached"`
	Coverage   float64 `json:"coverage"`
	Remaining  int     `json:"remaining"`
	Status     string  `json:"status"`
}

// coverage compares the people an event (check-ins) or drive (mobilizations) reached with the
// registered voters in its area, drilling down county → constituency → ward → polling centre.
// Only voters on the register count towards coverage; others are reported as not registered.
func (s *Server) coverage(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	q := r.URL.Query()
	var county, constituency, ward *string
	var table, group string
	if id := q.Get("event_id"); id != "" {
		e, err := s.loadEvent(r.Context(), p, id)
		if errors.Is(err, errNotFound) {
			writeErr(w, http.StatusNotFound, "event not found")
			return
		} else if err != nil {
			s.internal(w, r, err)
			return
		}
		county, constituency, ward, table, group = e.County, e.Constituency, e.Ward, "checkins", "event_id"
	} else if id := q.Get("drive_id"); id != "" {
		d, err := s.loadDrive(r.Context(), p, id)
		if errors.Is(err, errNotFound) {
			writeErr(w, http.StatusNotFound, "drive not found")
			return
		} else if err != nil {
			s.internal(w, r, err)
			return
		}
		county, constituency, ward, table, group = d.County, d.Constituency, d.Ward, "mobilizations", "drive_id"
	} else {
		writeErr(w, http.StatusBadRequest, "event_id or drive_id is required")
		return
	}
	groupID := q.Get("event_id") + q.Get("drive_id")
	// Drill-down inside the group's area.
	if v := strings.TrimSpace(q.Get("constituency")); v != "" && constituency == nil {
		constituency = &v
	}
	if v := strings.TrimSpace(q.Get("ward")); v != "" && ward == nil {
		ward = &v
	}
	level, label := "county", "Kenya"
	switch {
	case ward != nil:
		level, label = "polling_center", *ward
	case constituency != nil:
		level, label = "ward", *constituency
	case county != nil:
		level, label = "constituency", *county
	}
	stationCol := map[string]string{"county": "county", "constituency": "constituency", "ward": "ward", "polling_center": "name"}[level]
	scopeSQL := func(prefix string) string {
		return ` place_key(` + prefix + `county) = coalesce(place_key($1), place_key(` + prefix + `county))
		 AND place_key(` + prefix + `constituency) = coalesce(place_key($2), place_key(` + prefix + `constituency))
		 AND place_key(` + prefix + `ward) = coalesce(place_key($3), place_key(` + prefix + `ward))`
	}

	// Registered voters per area (from the polling-station register built from the voter register).
	regRows, err := s.db.Query(r.Context(), `
		SELECT `+stationCol+`, sum(registered_voters)::int FROM polling_stations WHERE`+scopeSQL("")+`
		GROUP BY 1`, county, constituency, ward)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	rows := map[string]*coverageRow{}
	for regRows.Next() {
		var c coverageRow
		if err := regRows.Scan(&c.Area, &c.Registered); err != nil {
			regRows.Close()
			s.internal(w, r, err)
			return
		}
		rows[c.Area] = &c
	}
	regRows.Close()

	// People reached who are registered voters in the area, by their registration area.
	regCol := map[string]string{"county": "county", "constituency": "constituency", "ward": "ward", "polling_center": "polling_center"}[level]
	reachRows, err := s.db.Query(r.Context(), `
		SELECT v.`+regCol+`, count(DISTINCT x.national_id)::int
		FROM `+table+` x JOIN register_voters v ON v.national_id = x.national_id
		WHERE x.`+group+`::text = $4 AND x.org_id = $5 AND`+scopeSQL("v.")+`
		GROUP BY 1`, county, constituency, ward, groupID, p.OrgID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	for reachRows.Next() {
		var area string
		var n int
		if err := reachRows.Scan(&area, &n); err != nil {
			reachRows.Close()
			s.internal(w, r, err)
			return
		}
		c := rows[area]
		if c == nil {
			c = &coverageRow{Area: area}
			rows[area] = c
		}
		c.Reached = n
	}
	reachRows.Close()

	var out struct {
		Level         string        `json:"level"`
		Label         string        `json:"label"`
		CheckedIn     int           `json:"reached"`
		Registered    int           `json:"registered"`
		Coverage      float64       `json:"coverage"`
		Remaining     int           `json:"remaining"`
		NotRegistered int           `json:"not_registered"`
		Female        int           `json:"female"`
		Male          int           `json:"male"`
		TopAgeGroup   *string       `json:"top_age_group"`
		Rows          []coverageRow `json:"rows"`
		PushHereNext  []coverageRow `json:"push_here_next"`
	}
	out.Level, out.Label = level, label
	for _, c := range rows {
		if c.Reached > c.Registered {
			c.Registered = c.Reached // a voter re-registered after the register snapshot
		}
		c.Remaining = c.Registered - c.Reached
		if c.Registered > 0 {
			c.Coverage = round2(float64(c.Reached) / float64(c.Registered))
		}
		c.Status = coverageStatus(c.Reached, c.Registered)
		out.Rows = append(out.Rows, *c)
		out.Registered += c.Registered
		out.CheckedIn += c.Reached
	}
	sort.Slice(out.Rows, func(i, j int) bool {
		if out.Rows[i].Coverage != out.Rows[j].Coverage {
			return out.Rows[i].Coverage > out.Rows[j].Coverage
		}
		return out.Rows[i].Area < out.Rows[j].Area
	})
	out.Remaining = out.Registered - out.CheckedIn
	if out.Registered > 0 {
		out.Coverage = round2(float64(out.CheckedIn) / float64(out.Registered))
	}
	// Push here next: the weakest areas with the most people still to reach.
	weak := []coverageRow{}
	for _, c := range out.Rows {
		if c.Status != "strong" && c.Status != "moderate" {
			weak = append(weak, c)
		}
	}
	sort.Slice(weak, func(i, j int) bool { return weak[i].Remaining > weak[j].Remaining })
	if len(weak) > 3 {
		weak = weak[:3]
	}
	out.PushHereNext = weak

	// Who was reached: not-registered count, gender mix and the most common age band.
	var topAge *string
	err = s.db.QueryRow(r.Context(), `
		WITH people AS (
			SELECT DISTINCT ON (national_id) national_id, sex, dob FROM `+table+`
			WHERE `+group+`::text = $1 AND org_id = $2)
		SELECT count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM register_voters v WHERE v.national_id = people.national_id)),
		       count(*) FILTER (WHERE sex = 'F'), count(*) FILTER (WHERE sex = 'M'),
		       (SELECT band FROM (
		          SELECT CASE WHEN a < 25 THEN '18–24' WHEN a < 35 THEN '25–34' WHEN a < 45 THEN '35–44'
		                      WHEN a < 55 THEN '45–54' WHEN a < 65 THEN '55–64' ELSE '65+' END AS band, count(*) n
		          FROM (SELECT extract(year FROM age(dob))::int AS a FROM people WHERE dob IS NOT NULL) ages
		          GROUP BY 1 ORDER BY n DESC, band LIMIT 1) t)
		FROM people`, groupID, p.OrgID).Scan(&out.NotRegistered, &out.Female, &out.Male, &topAge)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		s.internal(w, r, err)
		return
	}
	out.TopAgeGroup = topAge
	writeJSON(w, http.StatusOK, out)
}

// registrationStats: adults in the national ID records vs those registered to vote, per home
// area, scoped to the organization's boundary county (precomputed by cmd/build-analytics).
func (s *Server) registrationStats(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	b, err := s.orgBoundary(r.Context(), p.OrgID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	county := b.County
	if v := strings.TrimSpace(r.URL.Query().Get("county")); v != "" && county == nil {
		county = &v
	}
	sql := `SELECT county, sum(adults)::int, sum(registered)::int, max(built_at) FROM registration_stats GROUP BY county ORDER BY county`
	args := []any{}
	if county != nil {
		sql = `SELECT sub_county, adults, registered, built_at FROM registration_stats
		       WHERE place_key(county) = place_key($1) ORDER BY sub_county`
		args = append(args, *county)
	}
	rows, err := s.db.Query(r.Context(), sql, args...)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	type row struct {
		Area         string  `json:"area"`
		Adults       int     `json:"adults"`
		Registered   int     `json:"registered"`
		Unregistered int     `json:"unregistered"`
		Rate         float64 `json:"rate"`
	}
	var out struct {
		Level      string  `json:"level"`
		Label      string  `json:"label"`
		BuiltAt    *string `json:"built_at"`
		Rows       []row   `json:"rows"`
		Adults     int     `json:"adults"`
		Registered int     `json:"registered"`
	}
	out.Level, out.Label, out.Rows = "county", "Kenya", []row{}
	if county != nil {
		out.Level, out.Label = "sub_county", *county
	}
	for rows.Next() {
		var x row
		var at *time.Time
		if err := rows.Scan(&x.Area, &x.Adults, &x.Registered, &at); err != nil {
			rows.Close()
			s.internal(w, r, err)
			return
		}
		if at != nil {
			t := at.In(nairobi).Format("2006-01-02 15:04")
			out.BuiltAt = &t
		}
		x.Unregistered = x.Adults - x.Registered
		if x.Adults > 0 {
			x.Rate = round2(float64(x.Registered) / float64(x.Adults))
		}
		out.Adults += x.Adults
		out.Registered += x.Registered
		out.Rows = append(out.Rows, x)
	}
	rows.Close()
	writeJSON(w, http.StatusOK, out)
}
