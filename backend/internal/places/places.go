// Package places normalises Kenyan place names so register spellings compare and display consistently.
package places

import (
	"strings"
	"unicode"
)

// Key reduces a place name to lower-case letters and digits, so spelling variants
// compare equal: "Taita Taveta", "Taita-Taveta" and "TAITA/TAVETA" all become "taitataveta".
func Key(s string) string {
	var b strings.Builder
	for _, r := range strings.ToLower(s) {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
			b.WriteRune(r)
		}
	}
	k := b.String()
	if alias, ok := placeAliases[k]; ok {
		return alias
	}
	return k
}

var placeAliases = map[string]string{"nairobicity": "nairobi"}

// counties maps placeKey -> official name for Kenya's 47 counties.
var counties = func() map[string]string {
	m := map[string]string{}
	for _, n := range []string{
		"Mombasa", "Kwale", "Kilifi", "Tana River", "Lamu", "Taita-Taveta", "Garissa", "Wajir", "Mandera",
		"Marsabit", "Isiolo", "Meru", "Tharaka-Nithi", "Embu", "Kitui", "Machakos", "Makueni", "Nyandarua",
		"Nyeri", "Kirinyaga", "Murang'a", "Kiambu", "Turkana", "West Pokot", "Samburu", "Trans Nzoia",
		"Uasin Gishu", "Elgeyo-Marakwet", "Nandi", "Baringo", "Laikipia", "Nakuru", "Narok", "Kajiado",
		"Kericho", "Bomet", "Kakamega", "Vihiga", "Bungoma", "Busia", "Siaya", "Kisumu", "Homa Bay",
		"Migori", "Kisii", "Nyamira", "Nairobi",
	} {
		m[Key(n)] = n
	}
	return m
}()

// CountyName returns the official county name for a register spelling ("HOMABAY" -> "Homa Bay"),
// or the input in title case when it is not one of the 47 (e.g. old province labels).
func CountyName(s string) string {
	if n, ok := counties[Key(s)]; ok {
		return n
	}
	return TitleCase(s)
}

// TitleCase turns upper-case register names ("KWALE / MATUGA") into display case.
func TitleCase(s string) string {
	words := strings.Fields(strings.ToLower(s))
	for i, w := range words {
		// Work on runes, not bytes: a word may start with a multi-byte character ("’", "é").
		r := []rune(w)
		r[0] = unicode.ToUpper(r[0])
		words[i] = string(r)
	}
	return strings.Join(words, " ")
}
