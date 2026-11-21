package api

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"sort"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/machinenova/checkin/backend/internal/places"
)

// The chiefs-training report: per county training, when it was actually held (from its check-ins),
// how many chiefs were present, arrivals by hour per day, and — when the SDICS database can be
// read — how many chiefs SDICS has in each county and how many signed in to the SDICS app for the
// first time (onboarding). Counts only; no names or ID numbers leave the server.

type trainingRow struct {
	EventID   string     `json:"event_id"`
	Name      string     `json:"name"`
	County    string     `json:"county"`
	HeldOn    *string    `json:"held_on"` // YYYY-MM-DD of the first check-in; nil = not held yet
	FirstAt   *time.Time `json:"first_at"`
	LastAt    *time.Time `json:"last_at"`
	Present   int        `json:"present"` // different chiefs
	Phones    int        `json:"phones"`
	OutRegion int        `json:"out_region"`
	Female    int        `json:"female"`
	Male      int        `json:"male"`
	// SDICS (nil when SDICS can't be read)
	SDICSChiefs    *int `json:"sdics_chiefs"`     // active chiefs SDICS has in the county
	WithAccount    *int `json:"with_account"`     // present chiefs who have an SDICS account
	SignedIn       *int `json:"signed_in"`        // present chiefs who have signed in to the SDICS app
	FirstSignInDay *int `json:"first_signin_day"` // … whose first sign-in was on the training day
}

type dayHours struct {
	Day   string      `json:"day"`
	Total int         `json:"total"`
	Hours []hourCount `json:"hours"`
}

type countyDayCount struct {
	Day    string `json:"day"`
	County string `json:"county"`
	Count  int    `json:"count"`
}

type trainingReport struct {
	Trainings  []trainingRow    `json:"trainings"`
	Days       []dayHours       `json:"days"`
	SDICS      bool             `json:"sdics"`      // SDICS figures included
	Onboarding []countyDayCount `json:"onboarding"` // first SDICS sign-ins per county per day
	Generated  time.Time        `json:"generated_at"`
}

const tzNairobi = `'Africa/Nairobi'`

func (s *Server) trainingReport(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	if !p.SeesAll() {
		writeErr(w, http.StatusForbidden, "the training report is for administrators")
		return
	}
	ctx := r.Context()
	out := trainingReport{Trainings: []trainingRow{}, Days: []dayHours{}, Onboarding: []countyDayCount{}, Generated: time.Now()}

	rows, err := s.db.Query(ctx, `
		SELECT e.id, e.name, coalesce(e.county, ''),
		       to_char(min(c.checked_in_at) AT TIME ZONE `+tzNairobi+`, 'YYYY-MM-DD'), min(c.checked_in_at), max(c.checked_in_at),
		       count(DISTINCT c.national_id),
		       count(DISTINCT c.national_id) FILTER (WHERE coalesce(c.phone, '') <> ''),
		       count(DISTINCT c.national_id) FILTER (WHERE NOT c.in_region),
		       count(DISTINCT c.national_id) FILTER (WHERE c.sex = 'F'),
		       count(DISTINCT c.national_id) FILTER (WHERE c.sex = 'M')
		FROM events e LEFT JOIN checkins c ON c.event_id = e.id
		WHERE e.org_id = $1
		GROUP BY e.id ORDER BY min(c.checked_in_at) NULLS LAST, e.county`, p.OrgID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	out.Trainings, err = collect(rows, func(row pgx.Row) (trainingRow, error) {
		var t trainingRow
		err := row.Scan(&t.EventID, &t.Name, &t.County, &t.HeldOn, &t.FirstAt, &t.LastAt, &t.Present, &t.Phones, &t.OutRegion, &t.Female, &t.Male)
		return t, err
	})
	if err != nil {
		s.internal(w, r, err)
		return
	}

	// Arrivals by hour, per day (each chief counted once per day, at their first mark).
	rows, err = s.db.Query(ctx, `
		SELECT to_char(t AT TIME ZONE `+tzNairobi+`, 'YYYY-MM-DD'), extract(hour FROM t AT TIME ZONE `+tzNairobi+`)::int, count(*)
		FROM (SELECT min(c.checked_in_at) t FROM checkins c WHERE c.org_id = $1 GROUP BY c.event_id, c.national_id, c.checkin_day) x
		GROUP BY 1, 2 ORDER BY 1, 2`, p.OrgID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	byDay := map[string]*dayHours{}
	var order []string
	for rows.Next() {
		var day string
		var h hourCount
		if err := rows.Scan(&day, &h.Hour, &h.Count); err != nil {
			rows.Close()
			s.internal(w, r, err)
			return
		}
		d := byDay[day]
		if d == nil {
			d = &dayHours{Day: day}
			byDay[day] = d
			order = append(order, day)
		}
		d.Hours = append(d.Hours, h)
		d.Total += h.Count
	}
	if err := rows.Err(); err != nil {
		s.internal(w, r, err)
		return
	}
	for _, d := range order {
		out.Days = append(out.Days, *byDay[d])
	}

	if s.sdics != nil {
		if err := s.addSDICSOnboarding(ctx, p.OrgID, &out); err != nil {
			// Not fatal: the attendance report stands on its own.
			slog.Warn("training report: SDICS figures unavailable", "err", err)
		} else {
			out.SDICS = true
		}
	}
	writeJSON(w, http.StatusOK, out)
}

// addSDICSOnboarding adds SDICS chiefs per county, and which of the chiefs present have an SDICS
// account and have signed in to the SDICS app (first sign-in from the audit log).
func (s *Server) addSDICSOnboarding(ctx context.Context, orgID string, out *trainingReport) error {
	ctx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()

	// Present chiefs per training (IDs stay on the server).
	ids := map[string][]string{} // event id -> national IDs
	day := map[string]string{}   // event id -> held on
	rows, err := s.db.Query(ctx, `SELECT DISTINCT event_id, national_id FROM checkins WHERE org_id = $1`, orgID)
	if err != nil {
		return err
	}
	for rows.Next() {
		var e, n string
		if err := rows.Scan(&e, &n); err != nil {
			rows.Close()
			return err
		}
		ids[e] = append(ids[e], n)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	for _, t := range out.Trainings {
		if t.HeldOn != nil {
			day[t.EventID] = *t.HeldOn
		}
	}

	// SDICS chiefs per county.
	perCounty := map[string]int{}
	rows, err = s.sdics.Query(ctx, `
		SELECT a.county, count(DISTINCT o.id) FROM core_officer o
		JOIN core_officerassignedlocation a ON a.officer_id = o.id
		WHERE o.role = 'CHIEF' AND o.status = 'ACTIVE' AND a.county IS NOT NULL GROUP BY 1`)
	if err != nil {
		return fmt.Errorf("sdics chiefs per county: %w", err)
	}
	for rows.Next() {
		var c string
		var n int
		if err := rows.Scan(&c, &n); err != nil {
			rows.Close()
			return err
		}
		perCounty[places.Key(c)] += n
	}
	if err := rows.Err(); err != nil {
		return err
	}

	// For each training: of the chiefs present, who has an SDICS account / has signed in, and
	// whether the first sign-in was on the training day.
	for i := range out.Trainings {
		t := &out.Trainings[i]
		n := perCounty[places.Key(t.County)]
		t.SDICSChiefs = &n
		var keys []string
		for _, id := range ids[t.EventID] {
			keys = append(keys, sdicsKeys(id)...)
		}
		var acct, signed, sameDay int
		if len(keys) > 0 {
			err := s.sdics.QueryRow(ctx, `
				WITH o AS (SELECT DISTINCT id FROM core_officer WHERE role = 'CHIEF' AND national_id = ANY($1)),
				     f AS (SELECT user_id, min(created_at) first FROM core_auditlog
				           WHERE action = 'LOGIN' AND user_id IN (SELECT id FROM o) GROUP BY 1)
				SELECT (SELECT count(*) FROM o), count(f.user_id),
				       count(f.user_id) FILTER (WHERE to_char(f.first AT TIME ZONE `+tzNairobi+`, 'YYYY-MM-DD') = $2)
				FROM f`, keys, day[t.EventID]).Scan(&acct, &signed, &sameDay)
			if err != nil {
				return fmt.Errorf("sdics present chiefs: %w", err)
			}
		}
		t.WithAccount, t.SignedIn, t.FirstSignInDay = &acct, &signed, &sameDay
	}

	// Onboarding: first SDICS sign-ins per county per day, from the first training day.
	from := time.Now().AddDate(0, 0, -14).Format(time.DateOnly)
	for _, t := range out.Trainings {
		if t.HeldOn != nil && *t.HeldOn < from {
			from = *t.HeldOn
		}
	}
	rows, err = s.sdics.Query(ctx, `
		SELECT to_char(f.first AT TIME ZONE `+tzNairobi+`, 'YYYY-MM-DD') d, a.county, count(*)
		FROM (SELECT user_id, min(created_at) first FROM core_auditlog WHERE action = 'LOGIN' GROUP BY 1) f
		JOIN core_officer o ON o.id = f.user_id AND o.role = 'CHIEF'
		JOIN LATERAL (SELECT county FROM core_officerassignedlocation WHERE officer_id = o.id ORDER BY created_at LIMIT 1) a ON true
		WHERE f.first >= $1::date
		GROUP BY 1, 2 ORDER BY 1, 2`, from)
	if err != nil {
		return fmt.Errorf("sdics onboarding: %w", err)
	}
	for rows.Next() {
		var c countyDayCount
		if err := rows.Scan(&c.Day, &c.County, &c.Count); err != nil {
			rows.Close()
			return err
		}
		c.County = places.CountyName(c.County)
		out.Onboarding = append(out.Onboarding, c)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	sort.SliceStable(out.Onboarding, func(i, j int) bool { return out.Onboarding[i].Day < out.Onboarding[j].Day })
	return nil
}
