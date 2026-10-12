package api

import (
	"testing"
	"time"
)

func sp(s string) *string { return &s }

func TestInArea(t *testing.T) {
	cases := []struct {
		name                 string
		county, const_, ward *string
		want                 bool
	}{
		{"no area matches anything", nil, nil, nil, true},
		{"county match, case-insensitive", sp("nairobi"), nil, nil, true},
		{"constituency mismatch", sp("Nairobi"), sp("Langata"), nil, false},
		{"full match", sp("Nairobi"), sp("Kibra"), sp("Lindi"), true},
		{"ward mismatch", nil, nil, sp("Makina"), false},
	}
	for _, c := range cases {
		if got := inArea("Nairobi", "Kibra", "Lindi", c.county, c.const_, c.ward); got != c.want {
			t.Errorf("%s: got %v want %v", c.name, got, c.want)
		}
	}
}

func TestNormalizeID(t *testing.T) {
	if got := normalizeID(" 28 651\t234 "); got != "28651234" {
		t.Fatalf("got %q", got)
	}
}

func TestAgeOn(t *testing.T) {
	dob := time.Date(1990, 6, 15, 0, 0, 0, 0, time.UTC)
	if a := ageOn(dob, time.Date(2026, 6, 14, 0, 0, 0, 0, time.UTC)); a != 35 {
		t.Errorf("day before birthday: %d", a)
	}
	if a := ageOn(dob, time.Date(2026, 6, 15, 0, 0, 0, 0, time.UTC)); a != 36 {
		t.Errorf("on birthday: %d", a)
	}
}

func days(counts ...int) []dayCount {
	out := make([]dayCount, len(counts))
	for i, c := range counts {
		out[i] = dayCount{Count: c}
	}
	return out
}

func TestComputePace(t *testing.T) {
	now := time.Date(2026, 10, 11, 9, 0, 0, 0, nairobi)
	flat := days(10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10)

	if p := computePace(drive{Target: 0}, flat, now); p != nil {
		t.Fatal("no target should give no pace")
	}
	if p := computePace(drive{Target: 100, Mobilized: 100, Remaining: 0}, flat, now); p.Status != "reached" {
		t.Errorf("reached: %s", p.Status)
	}
	// 10 days left including today, 100 remaining → need 10/day; doing 10/day → on track.
	p := computePace(drive{Target: 200, Mobilized: 100, Remaining: 100, TargetDate: sp("2026-10-20")}, flat, now)
	if p.DaysLeft != 10 || p.PaceNeeded != 10 || p.Status != "on_track" || p.MomentumTrend != "steady" {
		t.Errorf("on track: %+v", p)
	}
	// Need 50/day → behind.
	p = computePace(drive{Target: 600, Mobilized: 100, Remaining: 500, TargetDate: sp("2026-10-20")}, flat, now)
	if p.Status != "behind" {
		t.Errorf("behind: %+v", p)
	}
	rising := days(1, 1, 1, 1, 1, 1, 1, 9, 9, 9, 9, 9, 9, 9)
	if p := computePace(drive{Target: 10, Remaining: 5}, rising, now); p.MomentumTrend != "rising" {
		t.Errorf("momentum: %s", p.MomentumTrend)
	}
	if p := computePace(drive{Target: 100, Remaining: 50, TargetDate: sp("2026-10-01")}, flat, now); p.Status != "behind" || p.DaysLeft != 0 {
		t.Errorf("past target date: %+v", p)
	}
}
