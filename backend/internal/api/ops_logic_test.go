package api

import (
	"net/http"
	"testing"
	"time"
)

func TestScopeContainsAndLabel(t *testing.T) {
	county := scope{County: sp("Migori")}
	ward := scope{County: sp("Migori"), Constituency: sp("Suna East"), Ward: sp("Kakrao")}
	if !county.contains(ward) || ward.contains(county) {
		t.Fatal("county should contain its ward, not the reverse")
	}
	if (scope{}).label() != "All regions" || ward.label() != "Kakrao Ward" || county.childLevel() != "constituency" {
		t.Fatalf("labels: %q %q %q", (scope{}).label(), ward.label(), county.childLevel())
	}
	if county.contains(scope{County: sp("Kisumu")}) {
		t.Fatal("other county must not be contained")
	}
}

func TestScopeNarrowNeverWidens(t *testing.T) {
	ward := scope{County: sp("Migori"), Constituency: sp("Suna East"), Ward: sp("Kakrao")}
	got := ward.narrow("Awendo", "North Sakwa")
	if *got.Constituency != "Suna East" || *got.Ward != "Kakrao" {
		t.Fatalf("a manager's drill must stay in their ward, got %+v", got)
	}
	county := scope{County: sp("Migori")}.narrow("Rongo", "")
	if county.Constituency == nil || *county.Constituency != "Rongo" || county.Ward != nil {
		t.Fatalf("drill into constituency: %+v", county)
	}
}

func TestOrElse(t *testing.T) {
	user := scope{}
	el := scope{County: sp("Migori")}
	if got := user.orElse(el); got.County == nil || *got.County != "Migori" {
		t.Fatal("owner with no scope inherits the election's")
	}
}

func TestCanAddRole(t *testing.T) {
	cases := []struct {
		me, role string
		want     bool
	}{
		{"owner", "admin", true}, {"owner", "executive", true}, {"admin", "admin", false}, {"admin", "manager", true},
		{"manager", "agent", true}, {"manager", "manager", false}, {"agent", "agent", false}, {"executive", "agent", false},
		{"owner", "member", false},
	}
	for _, c := range cases {
		if got := (&Principal{Role: c.me}).CanAddRole(c.role); got != c.want {
			t.Errorf("%s adds %s: got %v", c.me, c.role, got)
		}
	}
}

func TestSignalFor(t *testing.T) {
	yes, no := true, false
	cases := []struct {
		below      bool
		weLead     *bool
		hasResults bool
		want       string
		attention  bool
	}{
		{true, &yes, true, "Push GOTV", true},
		{true, &no, true, "Behind + low turnout", true},
		{false, &no, true, "Opponent ahead", true},
		{false, &yes, true, "Strong", false},
		{true, nil, false, "Below average", true},
		{false, nil, false, "On pace", false},
	}
	for _, c := range cases {
		got, att := signalFor(c.below, c.weLead, c.hasResults)
		if got != c.want || att != c.attention {
			t.Errorf("signalFor(%v,%v,%v) = %q,%v want %q,%v", c.below, c.weLead, c.hasResults, got, att, c.want, c.attention)
		}
	}
}

func TestTurnoutCarriesForward(t *testing.T) {
	tb := turnoutBySlot{"A": {9: 100, 13: 250}}
	if v, ok := tb.at("A", 11); !ok || v != 100 {
		t.Fatalf("11AM should carry the 9AM figure, got %d %v", v, ok)
	}
	if _, ok := tb.at("A", 7); ok {
		t.Fatal("nothing reported before 9AM")
	}
	if v, _ := tb.at("A", 17); v != 250 {
		t.Fatalf("5PM should carry 1PM, got %d", v)
	}
}

func TestRecordedAt(t *testing.T) {
	at := func(v string) time.Time {
		r, _ := http.NewRequest(http.MethodPost, "/", nil)
		if v != "" {
			r.Header.Set("X-Recorded-At", v)
		}
		return recordedAt(r)
	}
	now := time.Now()
	twoHours := now.Add(-2 * time.Hour).Truncate(time.Second)
	if got := at(twoHours.Format(time.RFC3339)); !got.Equal(twoHours) {
		t.Errorf("offline record keeps its time: got %v want %v", got, twoHours)
	}
	for name, v := range map[string]string{
		"missing":        "",
		"garbage":        "yesterday",
		"far future":     now.Add(48 * time.Hour).Format(time.RFC3339),
		"older than 7 d": now.Add(-8 * 24 * time.Hour).Format(time.RFC3339),
	} {
		if got := at(v); got.Sub(now).Abs() > 2*time.Second {
			t.Errorf("%s should fall back to server time, got %v", name, got)
		}
	}
	if got := at(now.Add(2 * time.Minute).Format(time.RFC3339)); got.After(time.Now()) {
		t.Errorf("small clock skew ahead is clamped to now, got %v", got)
	}
}
