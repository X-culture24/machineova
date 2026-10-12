package places

import (
	"testing"
	"unicode/utf8"
)

func TestTitleCaseKeepsMultibyteCharactersValid(t *testing.T) {
	for in, want := range map[string]string{
		"KWALE / MATUGA": "Kwale / Matuga",
		"’NYAMBU ÉLISE":  "’nyambu Élise",
		"OL’ KALOU":      "Ol’ Kalou",
	} {
		got := TitleCase(in)
		if got != want || !utf8.ValidString(got) {
			t.Errorf("TitleCase(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestCountyName(t *testing.T) {
	for in, want := range map[string]string{"NAIROBI CITY": "Nairobi", "HOMABAY": "Homa Bay", "MURANG'A": "Murang'a"} {
		if got := CountyName(in); got != want {
			t.Errorf("CountyName(%q) = %q, want %q", in, got, want)
		}
	}
}
