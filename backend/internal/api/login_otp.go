package api

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/machinenova/checkin/backend/internal/mail"
)

// Sign-in codes (2026-11-21), the same rule as the SDICS dashboards
// (sdics.tech, analytics, RRI): after the password, a dashboard account
// must enter a 6-digit code emailed to LOGIN_OTP_EMAIL (one inbox that
// approves every sign-in), and the session then lasts LOGIN_OTP_SESSION
// (default 72h) before the next code. Exempt:
//   - field accounts (roles in LOGIN_OTP_EXEMPT_ROLES, default agent and
//     member: the phone app's "Field Agent", e.g. the county training
//     accounts), which work offline for days, like SDICS chiefs;
//   - the addresses in LOGIN_OTP_EXEMPT (the system administrator).
// Without LOGIN_OTP_EMAIL nobody is asked for a code (as before).
//
// The codes go out through Brevo's HTTPS API (LOGIN_OTP_BREVO_API_KEY,
// sender LOGIN_OTP_MAIL_FROM), as the SDICS servers send: DigitalOcean blocks
// outgoing SMTP from the droplet. Without a Brevo key, LOGIN_OTP_SMTP_HOST/
// PORT/USER/PASSWORD. Only the codes. Other Checkin email (invites,
// resets, the daily digest) keeps the SMTP_* settings, which are unset on
// production, so it is still only logged.

const (
	otpTTL         = 10 * time.Minute
	otpMaxAttempts = 5
)

type otpPending struct {
	userID, orgID, email string
	codeHash             [32]byte
	expires              time.Time
	attempts             int
}

var otpStore = struct {
	mu sync.Mutex
	m  map[string]*otpPending
}{m: map[string]*otpPending{}}

func otpEmail() string { return strings.TrimSpace(os.Getenv("LOGIN_OTP_EMAIL")) }

func otpSessionTTL() time.Duration {
	if d, err := time.ParseDuration(os.Getenv("LOGIN_OTP_SESSION")); err == nil && d > 0 {
		return d
	}
	return 72 * time.Hour
}

// needsOTP: a dashboard account, codes switched on, not exempt.
func (s *Server) needsOTP(ctx context.Context, userID string) (bool, string, string, error) {
	if otpEmail() == "" {
		return false, "", "", nil
	}
	var email, role string
	var org *string
	if err := s.db.QueryRow(ctx, `SELECT email, role::text, org_id::text FROM users WHERE id = $1`, userID).
		Scan(&email, &role, &org); err != nil {
		return false, "", "", err
	}
	o := ""
	if org != nil {
		o = *org
	}
	if exemptRole(role) {
		return false, email, o, nil
	}
	for _, x := range strings.Split(os.Getenv("LOGIN_OTP_EXEMPT"), ",") {
		if x = strings.ToLower(strings.TrimSpace(x)); x != "" && x == strings.ToLower(email) {
			return false, email, o, nil
		}
	}
	return true, email, o, nil
}

func randomToken() string {
	b := make([]byte, 24)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func sixDigits() string {
	n, _ := rand.Int(rand.Reader, big.NewInt(1000000))
	return fmt.Sprintf("%06d", n.Int64())
}

// maskEmail: "elijah.x.sawe@gmail.com" -> "el***@gmail.com".
func maskEmail(e string) string {
	at := strings.LastIndex(e, "@")
	if at < 0 {
		return "your email"
	}
	name := e[:at]
	if len(name) > 2 {
		name = name[:2]
	}
	return name + "***" + e[at:]
}

// startOTP emails a code for the user and answers the challenge.
func (s *Server) startOTP(w http.ResponseWriter, r *http.Request, userID, orgID, email string) {
	to := otpEmail()
	code := sixDigits()
	tok := randomToken()
	now := time.Now()
	otpStore.mu.Lock()
	for k, p := range otpStore.m {
		if now.After(p.expires) {
			delete(otpStore.m, k)
		}
	}
	otpStore.m[tok] = &otpPending{userID: userID, orgID: orgID, email: email,
		codeHash: sha256.Sum256([]byte(code)), expires: now.Add(otpTTL)}
	otpStore.mu.Unlock()

	body := fmt.Sprintf("Sign-in code for %s on Checkin (checkin.sdics.tech):\n\n    %s\n\n"+
		"It works once, for 10 minutes. If nobody you know is signing in as %s, don't share it.\n",
		email, code, email)
	if err := otpSend(s, to, "Checkin sign-in code: "+email, body); err != nil {
		otpStore.mu.Lock()
		delete(otpStore.m, tok)
		otpStore.mu.Unlock()
		s.audit(r.Context(), orgID, userID, email, "OTP send failed", "/api/auth/login", http.StatusBadGateway, clientIP(r))
		writeErr(w, http.StatusBadGateway, "The sign-in code could not be emailed. Try again in a minute.")
		return
	}
	s.audit(r.Context(), orgID, userID, email, "OTP sent to "+maskEmail(to), "/api/auth/login", http.StatusOK, clientIP(r))
	writeJSON(w, http.StatusOK, map[string]any{
		"otp_required": true, "otp_token": tok, "sent_to": maskEmail(to), "expires_in": int(otpTTL.Seconds()),
	})
}

// POST /api/auth/login/verify-otp {otp_token, code} — the second step.
func (s *Server) verifyOTP(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Token string `json:"otp_token"`
		Code  string `json:"code"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	code := strings.TrimSpace(in.Code)
	otpStore.mu.Lock()
	p, ok := otpStore.m[in.Token]
	if ok && time.Now().After(p.expires) {
		delete(otpStore.m, in.Token)
		ok = false
	}
	if !ok {
		otpStore.mu.Unlock()
		writeErrCode(w, http.StatusUnauthorized, "otp_expired", "This code has expired. Sign in again for a new one.")
		return
	}
	h := sha256.Sum256([]byte(code))
	if subtle.ConstantTimeCompare(h[:], p.codeHash[:]) != 1 {
		p.attempts++
		left := otpMaxAttempts - p.attempts
		if left <= 0 {
			delete(otpStore.m, in.Token)
		}
		otpStore.mu.Unlock()
		s.audit(r.Context(), p.orgID, p.userID, p.email, "OTP failed (wrong code)", "/api/auth/login/verify-otp", http.StatusUnauthorized, clientIP(r))
		if left <= 0 {
			writeErrCode(w, http.StatusUnauthorized, "otp_expired", "Too many wrong codes. Sign in again for a new one.")
			return
		}
		writeErrCode(w, http.StatusUnauthorized, "otp_invalid", "Wrong code. Check the latest email and try again.")
		return
	}
	delete(otpStore.m, in.Token)
	otpStore.mu.Unlock()

	tokens := s.tokens
	tokens.TTL = otpSessionTTL()
	tok, exp, err := tokens.Issue(p.userID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	pr, err := s.loadPrincipal(r.Context(), p.userID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	me, err := s.meFor(r, pr)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	s.audit(r.Context(), p.orgID, p.userID, p.email, "LOGIN ok (code verified)", "/api/auth/login/verify-otp", http.StatusOK, clientIP(r))
	writeJSON(w, http.StatusOK, map[string]any{"token": tok, "expires_at": exp.Format(time.RFC3339), "user": me})
}

// exemptRole: the field roles that sign in on the phone app.
func exemptRole(role string) bool {
	roles := os.Getenv("LOGIN_OTP_EXEMPT_ROLES")
	if strings.TrimSpace(roles) == "" {
		roles = "agent,member"
	}
	for _, r := range strings.Split(roles, ",") {
		if strings.EqualFold(strings.TrimSpace(r), role) {
			return true
		}
	}
	return false
}

// otpMailer sends the codes: LOGIN_OTP_SMTP_* when set, else the server's.
func otpMailer(s *Server) *mail.Mailer {
	if h := os.Getenv("LOGIN_OTP_SMTP_HOST"); h != "" {
		return mail.New(h, os.Getenv("LOGIN_OTP_SMTP_PORT"), os.Getenv("LOGIN_OTP_SMTP_USER"),
			os.Getenv("LOGIN_OTP_SMTP_PASSWORD"), os.Getenv("LOGIN_OTP_MAIL_FROM"))
	}
	return s.mail
}

// otpSend emails one code: Brevo when LOGIN_OTP_BREVO_API_KEY is set (15 s
// limit), else SMTP (otpMailer).
func otpSend(s *Server, to, subject, body string) error {
	key := strings.TrimSpace(os.Getenv("LOGIN_OTP_BREVO_API_KEY"))
	if key == "" {
		return otpMailer(s).Send(to, subject, body)
	}
	from := strings.TrimSpace(os.Getenv("LOGIN_OTP_MAIL_FROM"))
	if i := strings.LastIndex(from, "<"); i >= 0 { // "Name <email>"
		from = strings.TrimSuffix(strings.TrimSpace(from[i+1:]), ">")
	}
	if from == "" {
		return fmt.Errorf("LOGIN_OTP_MAIL_FROM is not set")
	}
	payload, _ := json.Marshal(map[string]any{
		"sender":      map[string]string{"name": "SDICS Checkin", "email": from},
		"to":          []map[string]string{{"email": to}},
		"subject":     subject,
		"textContent": body,
	})
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://api.brevo.com/v3/smtp/email", bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("api-key", key)
	req.Header.Set("Content-Type", "application/json")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("brevo: %w", err)
	}
	defer res.Body.Close()
	if res.StatusCode/100 != 2 {
		msg, _ := io.ReadAll(io.LimitReader(res.Body, 300))
		return fmt.Errorf("brevo: %s %s", res.Status, strings.TrimSpace(string(msg)))
	}
	return nil
}
