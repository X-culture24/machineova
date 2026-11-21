package api

import (
	"github.com/machinenova/checkin/backend/internal/auth"
	"reflect"
	"testing"
)

func TestSDICSKeys(t *testing.T) {
	cases := map[string][]string{
		"39822117":    {"39822117"},
		" 3982 2117 ": {"39822117"},
		"0123456":     {"123456", "00123456", "0123456"},
		"1234567":     {"1234567", "01234567"},
		"":            nil,
		"000":         nil,
	}
	for in, want := range cases {
		if got := sdicsKeys(in); !reflect.DeepEqual(got, want) {
			t.Errorf("sdicsKeys(%q) = %v, want %v", in, got, want)
		}
	}
}

func TestSexLetter(t *testing.T) {
	for in, want := range map[string]string{"M": "M", "male": "M", "FEMALE": "F", "f": "F", "X": "X"} {
		if got := sexLetter(in); got != want {
			t.Errorf("sexLetter(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestSDICSLookupOffWithoutConnection(t *testing.T) {
	s := &Server{}
	v, err := s.sdicsLookup(t.Context(), "39822117")
	if v != nil || err != nil {
		t.Fatalf("got %v, %v; want nil, nil when SDICS isn't connected", v, err)
	}
}

func TestPhoneMissing(t *testing.T) {
	empty, blank, ph := "", "  ", "0712000000"
	if !phoneMissing(vocabSDICSChiefs, nil) || !phoneMissing(vocabSDICSChiefs, &empty) || !phoneMissing(vocabSDICSChiefs, &blank) {
		t.Fatal("chief onboarding needs a phone number")
	}
	if phoneMissing(vocabSDICSChiefs, &ph) || phoneMissing(vocabStandard, nil) {
		t.Fatal("a phone satisfies onboarding; campaigns don't need one")
	}
}

func TestPasswordMatchesForgivesOuterWhitespaceOnly(t *testing.T) {
	hash, err := auth.HashPassword("baringo-482731")
	if err != nil {
		t.Fatal(err)
	}
	for _, ok := range []string{"baringo-482731", "baringo-482731 ", " baringo-482731\n", "\tbaringo-482731"} {
		if !passwordMatches(hash, ok) {
			t.Errorf("%q should sign in", ok)
		}
	}
	for _, bad := range []string{"Baringo-482731", "baringo-48273", "baringo 482731", "", "   "} {
		if passwordMatches(hash, bad) {
			t.Errorf("%q must not sign in", bad)
		}
	}
}
