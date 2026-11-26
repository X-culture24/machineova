package api

import "strings"

const phoneInvalidMessage = "Enter a 10-digit phone number, for example 0712 345 678"

// kenyanMobile returns a Kenyan mobile number in its 10-digit local form
// (07… or 01…), accepting spaces, dashes, dots and brackets and the +254 /
// 254 forms. ok is false for anything else: too short, too long, letters,
// or another prefix.
func kenyanMobile(s string) (string, bool) {
	var b strings.Builder
	for i, ch := range strings.TrimSpace(s) {
		switch {
		case ch >= '0' && ch <= '9':
			b.WriteRune(ch)
		case ch == '+' && i == 0, strings.ContainsRune(" -.()", ch):
		default:
			return "", false
		}
	}
	n := b.String()
	if len(n) == 12 && strings.HasPrefix(n, "254") {
		n = "0" + n[3:]
	}
	if len(n) != 10 || (!strings.HasPrefix(n, "07") && !strings.HasPrefix(n, "01")) {
		return "", false
	}
	return n, true
}

// normalizePhoneInput checks an optional phone: empty is fine (whether it is
// required is phoneMissing's question); otherwise it must be a Kenyan mobile
// number and is rewritten to the 10-digit form. false means refuse it.
func normalizePhoneInput(phone *string) bool {
	if phone == nil || strings.TrimSpace(*phone) == "" {
		return true
	}
	n, ok := kenyanMobile(*phone)
	if ok {
		*phone = n
	}
	return ok
}
