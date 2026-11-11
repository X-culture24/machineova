package api

import (
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
