// Package mail sends transactional email over SMTP.
//
// Configure with SMTP_HOST, SMTP_PORT (default 587), SMTP_USER, SMTP_PASSWORD and MAIL_FROM.
// Without SMTP_HOST, messages are written to the server log instead, so invite and reset links
// still work in development.
package mail

import (
	"fmt"
	"log/slog"
	"net/smtp"
	"os"
	"strings"
	"time"
)

type Mailer struct {
	host, port, user, pass, from string
}

func FromEnv() *Mailer {
	port := os.Getenv("SMTP_PORT")
	if port == "" {
		port = "587"
	}
	from := os.Getenv("MAIL_FROM")
	if from == "" {
		from = "Checkin <no-reply@machinenova.com>"
	}
	return &Mailer{host: os.Getenv("SMTP_HOST"), port: port, user: os.Getenv("SMTP_USER"),
		pass: os.Getenv("SMTP_PASSWORD"), from: from}
}

// Configured reports whether real email is sent (otherwise messages go to the log).
func (m *Mailer) Configured() bool { return m != nil && m.host != "" }

// Send delivers a plain-text message. Without SMTP it logs the message instead.
func (m *Mailer) Send(to, subject, body string) error {
	if !m.Configured() {
		slog.Info("email (SMTP not configured — logged instead of sent)", "to", to, "subject", subject, "body", body)
		return nil
	}
	msg := strings.Join([]string{
		"From: " + m.from,
		"To: " + to,
		"Subject: " + mimeHeader(subject),
		"Date: " + time.Now().Format(time.RFC1123Z),
		"MIME-Version: 1.0",
		"Content-Type: text/plain; charset=UTF-8",
		"Content-Transfer-Encoding: 8bit",
		"",
		body,
	}, "\r\n")
	var a smtp.Auth
	if m.user != "" {
		a = smtp.PlainAuth("", m.user, m.pass, m.host)
	}
	if err := smtp.SendMail(m.host+":"+m.port, a, envelope(m.from), []string{to}, []byte(msg)); err != nil {
		return fmt.Errorf("send mail to %s: %w", to, err)
	}
	return nil
}

// Render fills {{field}} merge fields.
func Render(tpl string, fields map[string]string) string {
	for k, v := range fields {
		tpl = strings.ReplaceAll(tpl, "{{"+k+"}}", v)
	}
	return tpl
}

func envelope(from string) string {
	if i, j := strings.Index(from, "<"), strings.Index(from, ">"); i >= 0 && j > i {
		return from[i+1 : j]
	}
	return from
}

func mimeHeader(s string) string {
	for _, r := range s {
		if r > 127 {
			return "=?UTF-8?B?" + b64(s) + "?="
		}
	}
	return s
}
