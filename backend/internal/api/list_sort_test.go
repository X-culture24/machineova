package api

import (
	"net/http/httptest"
	"net/url"
	"testing"
)

func TestOrderParam(t *testing.T) {
	cols := map[string]string{"name": "lower(u.name)"}
	for _, c := range []struct {
		q, want string
		ok      bool
	}{
		{"", "u.id", true},
		{"sort=name", "lower(u.name) ASC NULLS LAST, u.id", true},
		{"sort=name&dir=desc", "lower(u.name) DESC NULLS LAST, u.id", true},
		{"sort=password_hash", "", false},
		{"sort=name&dir=sideways", "", false},
	} {
		q, _ := url.ParseQuery(c.q)
		w := httptest.NewRecorder()
		got, ok := orderParam(w, q, cols, "u.id")
		if got != c.want || ok != c.ok || (!ok && w.Code != 400) {
			t.Errorf("%q: %q %v %d", c.q, got, ok, w.Code)
		}
	}
}

func TestSortStations(t *testing.T) {
	half := 0.5
	rows := []stationRow{{Name: "b", Agents: 2}, {Name: "A", Turnout: &half}, {Name: "c", Agents: 1}}
	q, _ := url.ParseQuery("sort=name")
	sortStations(httptest.NewRecorder(), q, rows)
	if rows[0].Name != "A" || rows[2].Name != "c" {
		t.Fatalf("name: %+v", rows)
	}
	q, _ = url.ParseQuery("sort=turnout&dir=desc")
	sortStations(httptest.NewRecorder(), q, rows)
	if rows[0].Name != "A" {
		t.Fatalf("turnout: %+v", rows)
	}
	q, _ = url.ParseQuery("sort=agents&dir=desc")
	sortStations(httptest.NewRecorder(), q, rows)
	if rows[0].Name != "b" {
		t.Fatalf("agents: %+v", rows)
	}
	w := httptest.NewRecorder()
	if q, _ = url.ParseQuery("sort=code"); sortStations(w, q, rows) || w.Code != 400 {
		t.Fatal("unknown sort accepted")
	}
}
