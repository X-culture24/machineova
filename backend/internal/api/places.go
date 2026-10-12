package api

import "strings"

// placeKey reduces a place name to lower-case letters and digits, so spelling variants
// compare equal: "Taita Taveta", "Taita-Taveta" and "TAITA/TAVETA" all become "taitataveta".
func placeKey(s string) string {
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
		m[placeKey(n)] = n
	}
	return m
}()

// countyName returns the official county name for a register spelling ("HOMABAY" -> "Homa Bay"),
// or the input in title case when it is not one of the 47 (e.g. old province labels).
func countyName(s string) string {
	if n, ok := counties[placeKey(s)]; ok {
		return n
	}
	return titleCase(s)
}
