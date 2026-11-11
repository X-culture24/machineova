package api

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestLimiterBurstThenRefill(t *testing.T) {
	now := time.Date(2027, 8, 10, 7, 0, 0, 0, time.UTC)
	l := newLimiter()
	l.now = func() time.Time { return now }
	r := perMinute("t", 60, 3) // 1 per second, burst 3
	for i := 0; i < 3; i++ {
		if ok, _ := l.allow(r, "a"); !ok {
			t.Fatalf("request %d within the burst was refused", i+1)
		}
	}
	ok, wait := l.allow(r, "a")
	if ok || wait <= 0 || wait > time.Second {
		t.Fatalf("4th request: ok=%v wait=%v, want refused with wait ≤ 1s", ok, wait)
	}
	if ok, _ := l.allow(r, "b"); !ok {
		t.Fatal("another key has its own bucket")
	}
	now = now.Add(time.Second)
	if ok, _ := l.allow(r, "a"); !ok {
		t.Fatal("one token should have refilled after a second")
	}
	now = now.Add(time.Hour)
	l.allow(r, "c") // triggers the sweep
	if _, kept := l.buckets["t|a"]; kept {
		t.Fatal("idle buckets are swept")
	}
}

func TestLimitedAnswers429WithRetryAfter(t *testing.T) {
	s := &Server{limits: newLimiter()}
	r := perMinute("t", 6, 1)
	if s.limited(httptest.NewRecorder(), r, "k") {
		t.Fatal("first request refused")
	}
	w := httptest.NewRecorder()
	if !s.limited(w, r, "k") {
		t.Fatal("second request allowed")
	}
	if w.Code != http.StatusTooManyRequests || w.Header().Get("Retry-After") == "" || !strings.Contains(w.Body.String(), "rate_limited") {
		t.Fatalf("got %d %q %s", w.Code, w.Header().Get("Retry-After"), w.Body.String())
	}
}

func TestClientIPOnlyTrustsLocalProxy(t *testing.T) {
	req := func(remote string, h map[string]string) *http.Request {
		r := httptest.NewRequest("GET", "/", nil)
		r.RemoteAddr = remote
		for k, v := range h {
			r.Header.Set(k, v)
		}
		return r
	}
	cases := []struct {
		name   string
		remote string
		h      map[string]string
		want   string
	}{
		{"direct caller can't claim another IP", "41.90.1.2:5000", map[string]string{"X-Forwarded-For": "1.1.1.1", "X-Real-IP": "1.1.1.1"}, "41.90.1.2"},
		{"behind nginx: X-Real-IP", "127.0.0.1:40000", map[string]string{"X-Real-IP": "41.90.1.2", "X-Forwarded-For": "6.6.6.6, 41.90.1.2"}, "41.90.1.2"},
		{"behind nginx: spoofed first hop ignored", "127.0.0.1:40000", map[string]string{"X-Forwarded-For": "6.6.6.6, 41.90.1.2"}, "41.90.1.2"},
		{"no headers", "[::1]:40000", nil, "::1"},
	}
	for _, c := range cases {
		if got := clientIP(req(c.remote, c.h)); got != c.want {
			t.Errorf("%s: got %s, want %s", c.name, got, c.want)
		}
	}
}

func TestRuleForPersonalDataRoutes(t *testing.T) {
	r := httptest.NewRequest("GET", "/api/checkins/lookup?national_id=1", nil)
	r.Pattern = "GET /api/checkins/lookup"
	if ruleFor(r).name != "lookup" {
		t.Fatal("voter lookups use the lookup budget")
	}
	r = httptest.NewRequest("GET", "/api/ops/reports/results", nil)
	r.Pattern = "GET /api/ops/reports/{kind}"
	if ruleFor(r).name != "export" {
		t.Fatal("reports use the export budget")
	}
	r = httptest.NewRequest("GET", "/api/ops/overview", nil)
	r.Pattern = "GET /api/ops/overview"
	if ruleFor(r).name != "api" {
		t.Fatal("everything else uses the general budget")
	}
}

func TestRateLimitsOff(t *testing.T) {
	t.Setenv("RATE_LIMITS", "off")
	if !limitsDisabled() {
		t.Fatal("RATE_LIMITS=off should disable limits")
	}
	t.Setenv("RATE_LIMITS", "")
	if limitsDisabled() {
		t.Fatal("limits must stay on when RATE_LIMITS is unset")
	}
	s := &Server{limits: newLimiter(), limitsOff: true}
	for i := 0; i < 50; i++ {
		if s.limited(httptest.NewRecorder(), ruleLogin, "1.2.3.4") {
			t.Fatalf("request %d was limited with limits off", i+1)
		}
	}
}
