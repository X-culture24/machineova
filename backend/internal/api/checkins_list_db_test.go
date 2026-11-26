package api

import (
	"context"
	"encoding/json"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/machinenova/checkin/backend/internal/db"
)

// The check-in list's filters, sorts and facets. Runs only against a
// throwaway database: CHECKIN_TEST_DSN=postgres://…/checkin_list_test
func TestCheckinListFiltersDB(t *testing.T) {
	dsn := os.Getenv("CHECKIN_TEST_DSN")
	if dsn == "" {
		t.Skip("CHECKIN_TEST_DSN not set")
	}
	ctx := context.Background()
	pool, err := db.Connect(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	if err := db.Migrate(ctx, pool); err != nil {
		t.Fatal(err)
	}
	exec := func(q string, args ...any) {
		t.Helper()
		if _, err := pool.Exec(ctx, q, args...); err != nil {
			t.Fatalf("%s: %v", q, err)
		}
	}
	var org, admin, member, event string
	exec(`DELETE FROM organizations WHERE slug = 'list-test'`)
	if err := pool.QueryRow(ctx, `INSERT INTO organizations (name, slug) VALUES ('List test', 'list-test') RETURNING id`).Scan(&org); err != nil {
		t.Fatal(err)
	}
	pool.QueryRow(ctx, `INSERT INTO users (org_id, email, name, password_hash, role) VALUES ($1, 'a@list.test', 'Alice Admin', 'x', 'admin') RETURNING id`, org).Scan(&admin)
	pool.QueryRow(ctx, `INSERT INTO users (org_id, email, name, password_hash, role) VALUES ($1, 'm@list.test', 'Moses Member', 'x', 'member') RETURNING id`, org).Scan(&member)
	pool.QueryRow(ctx, `INSERT INTO events (org_id, name, starts_at) VALUES ($1, 'Rally', now()) RETURNING id`, org).Scan(&event)
	for _, c := range []struct{ nid, name, sex, dob, county, cons, ward, by string; in bool }{
		{"1001", "Zawadi Chebet", "F", "2004-01-01", "Nandi", "Nandi Hills", "Chepkunyuk", admin, true},
		{"1002", "Brian Kiprop", "M", "1980-06-01", "Nandi", "Emgwen", "Kapsabet", admin, true},
		{"1003", "Amina Wanjiru", "F", "1960-03-01", "Nairobi", "Westlands", "Parklands", member, false},
	} {
		exec(`INSERT INTO checkins (org_id, event_id, national_id, name, sex, dob, phone, county, constituency, ward, in_region, checked_in_by)
			VALUES ($1, $2, $3, $4, $5, $6, '0712345678', $7, $8, $9, $10, $11)`, org, event, c.nid, c.name, c.sex, c.dob, c.county, c.cons, c.ward, c.in, c.by)
	}
	exec(`INSERT INTO sdics_station_roll (code, name, county, constituency, ward, registered_voters)
		VALUES ('LT-PS-1', 'Kapsabet Primary', 'Nandi', 'Emgwen', 'Kapsabet', 500) ON CONFLICT (code) DO NOTHING`)
	exec(`UPDATE events SET polling_station_code = 'LT-PS-1' WHERE id = $1`, event)
	s := &Server{db: pool}
	list := func(p *Principal, query string, want int) []personRecord {
		t.Helper()
		w := httptest.NewRecorder()
		s.listCheckins(w, httptest.NewRequest("GET", "/api/checkins?"+query, nil), p)
		if w.Code != want {
			t.Fatalf("%s: %d %s", query, w.Code, w.Body)
		}
		var out []personRecord
		json.Unmarshal(w.Body.Bytes(), &out)
		return out
	}
	boss := &Principal{UserID: admin, OrgID: org, Role: "admin"}
	names := func(rs []personRecord) (out []string) {
		for _, r := range rs {
			out = append(out, r.Name)
		}
		return
	}
	if got := names(list(boss, "sort=name", 200)); len(got) != 3 || got[0] != "Amina Wanjiru" || got[2] != "Zawadi Chebet" {
		t.Fatalf("sort by name: %v", got)
	}
	if got := list(boss, "sort=age&dir=desc", 200); got[0].Name != "Amina Wanjiru" || got[0].AgeGroup != "65+" || got[0].Age == nil {
		t.Fatalf("sort by age: %+v", got[0])
	}
	for q, want := range map[string]int{
		"sex=F": 2, "age_group=18–24": 1, "county=Nandi": 2, "constituency=Emgwen": 1, "ward=Parklands": 1,
		"region=out": 1, "by=" + member: 1, "county=Nandi&sex=F": 1, "q=kiprop": 1, "q=0712345678": 3, "station=LT-PS-1": 3, "station=NONE": 0,
	} {
		if got := list(boss, q, 200); len(got) != want {
			t.Errorf("%s: %d rows, want %d", q, len(got), want)
		}
	}
	if got := list(boss, "sort=station", 200); got[0].Station != "Kapsabet Primary" || got[0].StationCode != "LT-PS-1" {
		t.Fatalf("station: %+v", got[0])
	}
	list(boss, "sort=phone", 400)
	list(boss, "region=north", 400)
	// A member sees only their own check-ins, whatever they filter on.
	if got := list(&Principal{UserID: member, OrgID: org, Role: "member"}, "county=Nandi", 200); len(got) != 0 {
		t.Fatalf("member sees others: %v", names(got))
	}

	w := httptest.NewRecorder()
	s.checkinFacets(w, httptest.NewRequest("GET", "/api/checkins/facets?event_id="+event, nil), boss)
	var facets map[string][]checkinFacet
	if err := json.Unmarshal(w.Body.Bytes(), &facets); err != nil || w.Code != 200 {
		t.Fatalf("facets: %d %s", w.Code, w.Body)
	}
	if len(facets["county"]) != 2 || len(facets["sex"]) != 2 || len(facets["by"]) != 2 || len(facets["region"]) != 2 ||
		len(facets["station"]) != 1 || facets["station"][0].Label != "Kapsabet Primary" {
		t.Fatalf("facets: %+v", facets)
	}
	exec(`DELETE FROM organizations WHERE id = $1`, org)
	exec(`DELETE FROM sdics_station_roll WHERE code = 'LT-PS-1'`)
}
