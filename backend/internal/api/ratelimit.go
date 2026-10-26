package api

import (
	"fmt"
	"math"
	"net/http"
	"strconv"
	"sync"
	"time"
)

// Rate limiting: in-memory token buckets (one API process per deployment).
//
// Signed-out endpoints (sign-in, password reset, invitation links) are limited per client IP:
// they are where password guessing and email flooding happen. Signed-in traffic is limited per
// user, not per IP — Kenyan mobile networks put many phones behind one carrier IP, and a whole
// county's agents can share it on election day. Voter lookups and exports, the two ways to pull
// personal data in bulk, get their own tighter per-user budgets.
//
// Over the limit the API answers 429 with Retry-After; the field app keeps queued work and
// retries later (it treats 429 like a dropped connection).

type rule struct {
	name  string
	rate  float64 // tokens per second
	burst float64
}

func perMinute(name string, n, burst int) rule {
	return rule{name: name, rate: float64(n) / 60, burst: float64(burst)}
}

var (
	ruleLogin   = perMinute("login", 10, 10)  // per IP; accounts also lock after 5 failures
	ruleForgot  = perMinute("forgot", 5, 5)   // per IP; each request can send an email
	ruleRedeem  = perMinute("redeem", 10, 10) // per IP; invitation / reset links
	ruleAPI     = perMinute("api", 300, 120)  // per user; dashboards poll, bulk updates burst
	ruleLookup  = perMinute("lookup", 90, 30) // per user; a busy check-in desk scans ~1 ID every 2 s
	ruleExport  = perMinute("export", 10, 5)  // per user; CSV reports and voter-list exports
	ruleUnknown = perMinute("ip", 600, 200)   // per IP, signed-out requests that are not auth
)

type bucket struct {
	tokens float64
	last   time.Time
}

type limiter struct {
	mu      sync.Mutex
	buckets map[string]*bucket
	now     func() time.Time
	swept   time.Time
}

func newLimiter() *limiter {
	return &limiter{buckets: map[string]*bucket{}, now: time.Now}
}

// allow takes one token from key's bucket under rule r. When empty it reports how long until
// the next token.
func (l *limiter) allow(r rule, key string) (bool, time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	l.sweep(now)
	k := r.name + "|" + key
	b, ok := l.buckets[k]
	if !ok {
		b = &bucket{tokens: r.burst, last: now}
		l.buckets[k] = b
	}
	b.tokens = math.Min(r.burst, b.tokens+now.Sub(b.last).Seconds()*r.rate)
	b.last = now
	if b.tokens >= 1 {
		b.tokens--
		return true, 0
	}
	return false, time.Duration((1 - b.tokens) / r.rate * float64(time.Second))
}

// sweep drops idle buckets (full again, so forgetting them changes nothing) every few minutes.
func (l *limiter) sweep(now time.Time) {
	if now.Sub(l.swept) < 5*time.Minute {
		return
	}
	l.swept = now
	for k, b := range l.buckets {
		if now.Sub(b.last) > 30*time.Minute {
			delete(l.buckets, k)
		}
	}
}

// limited answers 429 when key is over rule r; it returns false when the caller may proceed.
func (s *Server) limited(w http.ResponseWriter, r rule, key string) bool {
	ok, wait := s.limits.allow(r, key)
	if ok {
		return false
	}
	secs := int(math.Ceil(wait.Seconds()))
	w.Header().Set("Retry-After", strconv.Itoa(secs))
	writeErrCode(w, http.StatusTooManyRequests, "rate_limited", fmt.Sprintf("Too many requests — try again in %d s.", secs))
	return true
}

// ruleFor picks the per-user budget for an authenticated request.
func ruleFor(r *http.Request) rule {
	switch {
	case r.Pattern == "GET /api/checkins/lookup" || r.Pattern == "GET /api/mobilizations/lookup":
		return ruleLookup
	case r.Pattern == "GET /api/ops/reports/{kind}" || r.Pattern == "GET /api/app/download":
		return ruleExport
	}
	return ruleAPI
}

// limitIP wraps a signed-out handler with a per-IP budget.
func (s *Server) limitIP(rl rule, h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if s.limited(w, rl, clientIP(r)) {
			return
		}
		h(w, r)
	}
}
