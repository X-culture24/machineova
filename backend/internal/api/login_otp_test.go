package api

import (
	"crypto/sha256"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func seedOTP(code string, expires time.Time) string {
	tok := randomToken()
	otpStore.mu.Lock()
	otpStore.m[tok] = &otpPending{userID: "u1", email: "viola@x", codeHash: sha256.Sum256([]byte(code)), expires: expires}
	otpStore.mu.Unlock()
	return tok
}

func postVerify(s *Server, tok, code string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodPost, "/api/auth/login/verify-otp",
		strings.NewReader(`{"otp_token":"`+tok+`","code":"`+code+`"}`))
	s.verifyOTP(w, r)
	return w
}

func TestVerifyOTPWrongExpiredAndLockout(t *testing.T) {
	s := &Server{}
	tok := seedOTP("123456", time.Now().Add(time.Minute))
	for i := 1; i < otpMaxAttempts; i++ {
		if w := postVerify(s, tok, "000000"); w.Code != 401 || !strings.Contains(w.Body.String(), "otp_invalid") {
			t.Fatalf("wrong code %d: %d %s", i, w.Code, w.Body.String())
		}
	}
	if w := postVerify(s, tok, "000000"); !strings.Contains(w.Body.String(), "otp_expired") {
		t.Fatalf("5th wrong code should end the code: %s", w.Body.String())
	}
	if w := postVerify(s, tok, "123456"); w.Code != 401 || !strings.Contains(w.Body.String(), "otp_expired") {
		t.Fatalf("the right code after lockout must fail: %d %s", w.Code, w.Body.String())
	}
	old := seedOTP("654321", time.Now().Add(-time.Second))
	if w := postVerify(s, old, "654321"); w.Code != 401 || !strings.Contains(w.Body.String(), "otp_expired") {
		t.Fatalf("expired code: %d %s", w.Code, w.Body.String())
	}
}

func TestOTPHelpers(t *testing.T) {
	if got := maskEmail("elijah.x.sawe@gmail.com"); got != "el***@gmail.com" {
		t.Errorf("mask: %s", got)
	}
	t.Setenv("LOGIN_OTP_SESSION", "")
	if otpSessionTTL() != 72*time.Hour {
		t.Error("default session should be 3 days")
	}
	t.Setenv("LOGIN_OTP_EMAIL", "")
	if need, _, _, err := (&Server{}).needsOTP(t.Context(), "u1"); need || err != nil {
		t.Error("without LOGIN_OTP_EMAIL nobody needs a code")
	}
	t.Setenv("LOGIN_OTP_EXEMPT_ROLES", "")
	if !exemptRole("agent") || !exemptRole("member") || exemptRole("owner") || exemptRole("admin") || exemptRole("viewer") {
		t.Error("field roles exempt by default, dashboard roles not")
	}
	if c := sixDigits(); len(c) != 6 {
		t.Errorf("code %q", c)
	}
}
