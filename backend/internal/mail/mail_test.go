package mail

import "testing"

func TestRender(t *testing.T) {
	got := Render("Hello {{recipient_name}}, welcome to {{org_name}}. {{unknown}}", map[string]string{
		"recipient_name": "Amina", "org_name": "Nairobi Grassroots"})
	if got != "Hello Amina, welcome to Nairobi Grassroots. {{unknown}}" {
		t.Fatal(got)
	}
}

func TestEnvelopeAndHeader(t *testing.T) {
	if envelope("Checkin <no-reply@x.com>") != "no-reply@x.com" || envelope("a@b.c") != "a@b.c" {
		t.Fatal("envelope")
	}
	if mimeHeader("Plain") != "Plain" || mimeHeader("Karibu — welcome")[:10] != "=?UTF-8?B?" {
		t.Fatal("mime header")
	}
}
