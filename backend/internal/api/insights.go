package api

import (
	"errors"
	"math"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

const tz = "Africa/Nairobi"

type hourCount struct {
	Hour  int `json:"hour"`
	Count int `json:"count"`
}

// checkinInsights powers Insights › Check-ins for one event on one day.
func (s *Server) checkinInsights(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	e, err := s.loadEvent(r.Context(), p, r.URL.Query().Get("event_id"))
	if errors.Is(err, errNotFound) {
		writeErr(w, http.StatusNotFound, "event not found")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	// Default to the most recent day with activity (today during a live event).
	day := r.URL.Query().Get("day")
	if day == "" {
		var d *time.Time
		if err := s.db.QueryRow(r.Context(), `SELECT max(checkin_day) FROM checkins WHERE event_id=$1`, e.ID).Scan(&d); err != nil {
			s.internal(w, r, err)
			return
		}
		if d == nil {
			day = time.Now().In(nairobi).Format(time.DateOnly)
		} else {
			day = d.Format(time.DateOnly)
		}
	}

	var out struct {
		Event        event       `json:"event"`
		Day          string      `json:"day"`
		Total        int         `json:"total"`
		Unique       int         `json:"unique"`
		InRegionRate float64     `json:"in_region_rate"`
		PeakHour     *int        `json:"peak_hour"`
		ByHour       []hourCount `json:"by_hour"`
		Female       int         `json:"female"`
		Male         int         `json:"male"`
	}
	out.Event, out.Day = e, day
	var inRegion int
	err = s.db.QueryRow(r.Context(), `
		SELECT count(*), count(DISTINCT national_id), count(*) FILTER (WHERE in_region),
		       count(*) FILTER (WHERE sex='F'), count(*) FILTER (WHERE sex='M')
		FROM checkins WHERE event_id=$1 AND checkin_day=$2::date`, e.ID, day).
		Scan(&out.Total, &out.Unique, &inRegion, &out.Female, &out.Male)
	if isInvalidDate(err) {
		writeErr(w, http.StatusBadRequest, "day must be YYYY-MM-DD")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if out.Total > 0 {
		out.InRegionRate = round2(float64(inRegion) / float64(out.Total))
	}
	rows, err := s.db.Query(r.Context(), `
		SELECT extract(hour FROM checked_in_at AT TIME ZONE '`+tz+`')::int AS h, count(*)
		FROM checkins WHERE event_id=$1 AND checkin_day=$2::date GROUP BY h ORDER BY h`, e.ID, day)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	out.ByHour, err = collect(rows, func(row pgx.Row) (hourCount, error) {
		var h hourCount
		return h, row.Scan(&h.Hour, &h.Count)
	})
	if err != nil {
		s.internal(w, r, err)
		return
	}
	best := 0
	for _, h := range out.ByHour {
		if h.Count > best {
			best, out.PeakHour = h.Count, &h.Hour
		}
	}
	writeJSON(w, http.StatusOK, out)
}

type nameCount struct {
	Name  string `json:"name"`
	Count int    `json:"count"`
}

type dayCount struct {
	Day   string `json:"day"`
	Count int    `json:"count"`
}

// mobilizationInsights powers Insights › Mobilization for one drive, including pace to target.
func (s *Server) mobilizationInsights(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	d, err := s.loadDrive(r.Context(), p, r.URL.Query().Get("drive_id"))
	if errors.Is(err, errNotFound) {
		writeErr(w, http.StatusNotFound, "drive not found")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	var out struct {
		Drive         drive       `json:"drive"`
		Today         int         `json:"today"`
		TopMobilizers []nameCount `json:"top_mobilizers"`
		Daily         []dayCount  `json:"daily"`
		Pace          *pace       `json:"pace"`
	}
	out.Drive = d
	if err := s.db.QueryRow(r.Context(), `
		SELECT count(*) FROM mobilizations
		WHERE drive_id=$1 AND (created_at AT TIME ZONE '`+tz+`')::date = (now() AT TIME ZONE '`+tz+`')::date`, d.ID).
		Scan(&out.Today); err != nil {
		s.internal(w, r, err)
		return
	}
	rows, err := s.db.Query(r.Context(), `
		SELECT u.name, count(*) FROM mobilizations m JOIN users u ON u.id = m.mobilized_by
		WHERE m.drive_id=$1 GROUP BY u.name ORDER BY count(*) DESC, u.name LIMIT 10`, d.ID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if out.TopMobilizers, err = collect(rows, func(row pgx.Row) (nameCount, error) {
		var n nameCount
		return n, row.Scan(&n.Name, &n.Count)
	}); err != nil {
		s.internal(w, r, err)
		return
	}
	rows, err = s.db.Query(r.Context(), `
		SELECT to_char(g.day, 'YYYY-MM-DD'), count(m.id)
		FROM generate_series((now() AT TIME ZONE '`+tz+`')::date - 13, (now() AT TIME ZONE '`+tz+`')::date, '1 day') AS g(day)
		LEFT JOIN mobilizations m ON m.drive_id = $1 AND (m.created_at AT TIME ZONE '`+tz+`')::date = g.day
		GROUP BY g.day ORDER BY g.day`, d.ID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if out.Daily, err = collect(rows, func(row pgx.Row) (dayCount, error) {
		var c dayCount
		return c, row.Scan(&c.Day, &c.Count)
	}); err != nil {
		s.internal(w, r, err)
		return
	}
	out.Pace = computePace(d, out.Daily, time.Now().In(nairobi))
	writeJSON(w, http.StatusOK, out)
}

type pace struct {
	DaysLeft      int     `json:"days_left"`
	ToHitTarget   int     `json:"to_hit_target"`
	PaceNeeded    float64 `json:"pace_needed"`  // voters/day from now on
	CurrentPace   float64 `json:"current_pace"` // 7-day average
	Status        string  `json:"status"`       // ahead | on_track | behind | reached
	MomentumTrend string  `json:"momentum"`     // rising | steady | cooling
}

func computePace(d drive, daily []dayCount, now time.Time) *pace {
	if d.Target == 0 {
		return nil
	}
	p := &pace{ToHitTarget: d.Remaining}
	var last7, prev7 int
	for i, c := range daily {
		if i >= len(daily)-7 {
			last7 += c.Count
		} else {
			prev7 += c.Count
		}
	}
	p.CurrentPace = round2(float64(last7) / 7)
	switch {
	case last7 > prev7*11/10:
		p.MomentumTrend = "rising"
	case last7*11/10 < prev7:
		p.MomentumTrend = "cooling"
	default:
		p.MomentumTrend = "steady"
	}
	if d.Remaining == 0 {
		p.Status = "reached"
		return p
	}
	if d.TargetDate == nil {
		p.Status = "on_track"
		return p
	}
	td, err := time.ParseInLocation(time.DateOnly, *d.TargetDate, nairobi)
	if err != nil {
		return p
	}
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, nairobi)
	p.DaysLeft = max(int(td.Sub(today).Hours()/24)+1, 0)
	if p.DaysLeft == 0 {
		p.Status = "behind"
		return p
	}
	p.PaceNeeded = round2(float64(d.Remaining) / float64(p.DaysLeft))
	switch {
	case p.CurrentPace >= p.PaceNeeded*1.2:
		p.Status = "ahead"
	case p.CurrentPace >= p.PaceNeeded:
		p.Status = "on_track"
	default:
		p.Status = "behind"
	}
	return p
}

// dashboard powers the web org dashboard KPI cards.
func (s *Server) dashboard(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	var out struct {
		TotalEvents     int         `json:"total_events"`
		ActiveEvents    int         `json:"active_events"`
		VotersMobilized int         `json:"voters_mobilized"`
		ActiveRegions   int         `json:"active_regions"`
		TeamMembers     int         `json:"team_members"`
		Checkins7d      int         `json:"checkins_7d"`
		TopRegions      []nameCount `json:"top_regions"`
		RecentEvents    []event     `json:"recent_events"`
	}
	err := s.db.QueryRow(r.Context(), `
		SELECT (SELECT count(*) FROM events WHERE org_id=$1),
		       (SELECT count(*) FROM events WHERE org_id=$1 AND active),
		       (SELECT count(*) FROM mobilizations WHERE org_id=$1),
		       (SELECT count(*) FROM drives WHERE org_id=$1 AND active),
		       (SELECT count(*) FROM users WHERE org_id=$1 AND active),
		       (SELECT count(*) FROM checkins WHERE org_id=$1 AND checked_in_at > now() - interval '7 days')`, p.OrgID).
		Scan(&out.TotalEvents, &out.ActiveEvents, &out.VotersMobilized, &out.ActiveRegions, &out.TeamMembers, &out.Checkins7d)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	rows, err := s.db.Query(r.Context(), `
		SELECT d.name, count(m.id) FROM drives d LEFT JOIN mobilizations m ON m.drive_id = d.id
		WHERE d.org_id=$1 GROUP BY d.id, d.name ORDER BY count(m.id) DESC LIMIT 6`, p.OrgID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if out.TopRegions, err = collect(rows, func(row pgx.Row) (nameCount, error) {
		var n nameCount
		return n, row.Scan(&n.Name, &n.Count)
	}); err != nil {
		s.internal(w, r, err)
		return
	}
	rows, err = s.db.Query(r.Context(), eventSelect+visibleEvents+` ORDER BY e.starts_at DESC LIMIT 5`, p.OrgID, p.UserID, p.SeesAll())
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if out.RecentEvents, err = collect(rows, scanEvent); err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

type feedItem struct {
	Kind       string    `json:"kind"` // checkin | mobilization
	Name       string    `json:"name"`
	NationalID string    `json:"national_id"`
	Group      string    `json:"group"`
	By         string    `json:"by"`
	At         time.Time `json:"at"`
}

// home powers the mobile Home screen: today's counts and a live activity feed.
func (s *Server) home(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	var out struct {
		Name              string     `json:"name"`
		MyCheckinsToday   int        `json:"my_checkins_today"`
		MyMobilizedToday  int        `json:"my_mobilized_today"`
		OrgCheckinsToday  int        `json:"org_checkins_today"`
		OrgMobilizedToday int        `json:"org_mobilized_today"`
		Feed              []feedItem `json:"feed"`
	}
	out.Name = p.Name
	err := s.db.QueryRow(r.Context(), `
		WITH today AS (SELECT (now() AT TIME ZONE '`+tz+`')::date AS d)
		SELECT (SELECT count(*) FROM checkins, today WHERE org_id=$1 AND checked_in_by=$2 AND checkin_day = today.d),
		       (SELECT count(*) FROM mobilizations, today WHERE org_id=$1 AND mobilized_by=$2 AND (created_at AT TIME ZONE '`+tz+`')::date = today.d),
		       (SELECT count(*) FROM checkins, today WHERE org_id=$1 AND checkin_day = today.d),
		       (SELECT count(*) FROM mobilizations, today WHERE org_id=$1 AND (created_at AT TIME ZONE '`+tz+`')::date = today.d)`,
		p.OrgID, p.UserID).Scan(&out.MyCheckinsToday, &out.MyMobilizedToday, &out.OrgCheckinsToday, &out.OrgMobilizedToday)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	rows, err := s.db.Query(r.Context(), `
		(SELECT 'checkin', c.name, c.national_id, e.name, u.name, c.checked_in_at AS at
		 FROM checkins c JOIN events e ON e.id=c.event_id JOIN users u ON u.id=c.checked_in_by
		 WHERE c.org_id=$1 AND ($2 OR c.checked_in_by=$3) ORDER BY c.checked_in_at DESC LIMIT 20)
		UNION ALL
		(SELECT 'mobilization', m.name, m.national_id, d.name, u.name, m.created_at AS at
		 FROM mobilizations m JOIN drives d ON d.id=m.drive_id JOIN users u ON u.id=m.mobilized_by
		 WHERE m.org_id=$1 AND ($2 OR m.mobilized_by=$3) ORDER BY m.created_at DESC LIMIT 20)
		ORDER BY at DESC LIMIT 20`, p.OrgID, p.SeesAll(), p.UserID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if out.Feed, err = collect(rows, func(row pgx.Row) (feedItem, error) {
		var f feedItem
		return f, row.Scan(&f.Kind, &f.Name, &f.NationalID, &f.Group, &f.By, &f.At)
	}); err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

var nairobi = func() *time.Location {
	loc, err := time.LoadLocation(tz)
	if err != nil {
		return time.FixedZone("EAT", 3*60*60)
	}
	return loc
}()

func round2(f float64) float64 { return math.Round(f*100) / 100 }

func isInvalidDate(err error) bool {
	var pg *pgconn.PgError
	return errors.As(err, &pg) && (pg.Code == "22007" || pg.Code == "22008")
}
