package api

import "testing"

func TestKenyanMobile(t *testing.T) {
	for in, want := range map[string]string{
		"0712345678": "0712345678", "0712 345 678": "0712345678", "0112-345-678": "0112345678",
		"+254712345678": "0712345678", "254 712 345 678": "0712345678", "(0712) 345.678": "0712345678",
	} {
		if got, ok := kenyanMobile(in); !ok || got != want {
			t.Errorf("%q: got %q %v, want %q", in, got, ok, want)
		}
	}
	for _, in := range []string{"", "712345678", "07123456789", "071234567", "0212345678", "0812345678",
		"+255712345678", "07123x5678", "254712345678 ext 2", "0712345678+", "1234567890"} {
		if got, ok := kenyanMobile(in); ok {
			t.Errorf("%q accepted as %q", in, got)
		}
	}
	blank, bad, good := "  ", "0712", "+254 712 345 678"
	if !normalizePhoneInput(nil) || !normalizePhoneInput(&blank) || normalizePhoneInput(&bad) {
		t.Fatal("optional phone rules")
	}
	if !normalizePhoneInput(&good) || good != "0712345678" {
		t.Fatalf("normalised to %q", good)
	}
}
