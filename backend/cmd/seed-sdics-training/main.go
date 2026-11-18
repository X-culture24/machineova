// Command seed-sdics-training sets up the "SDICS Chiefs Training" campaign: one organization
// with the SDICS chiefs wording, its owner account, and one training event per SDICS county.
// At the training, trainers look each chief up in the IEBC voter register, record their phone
// number and mark them present.
//
// The county list comes from the SDICS database (SDICS_DATABASE_URL, read-only).
// Safe to run again: existing events are kept; the owner's password is only set
// when the account is created (or with -reset-password).
//
//	set -a; . /opt/machinenova/.env; set +a
//	/opt/machinenova/bin/seed-sdics-training -owner-email admin@sdics-training.machinenova.com -owner-password '...'
package main

import (
	"context"
	"crypto/rand"
	"errors"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/machinenova/checkin/backend/internal/auth"
	"github.com/machinenova/checkin/backend/internal/config"
	"github.com/machinenova/checkin/backend/internal/db"
	"github.com/machinenova/checkin/backend/internal/places"
)

func main() {
	orgName := flag.String("org", "SDICS Chiefs Training", "organization (campaign) name")
	ownerName := flag.String("owner-name", "SDICS Training Admin", "owner display name")
	ownerEmail := flag.String("owner-email", "", "owner sign-in email (required)")
	ownerPassword := flag.String("owner-password", "", "owner password, 8+ characters (required for a new owner)")
	resetPassword := flag.Bool("reset-password", false, "set -owner-password even if the owner already exists")
	trainerDomain := flag.String("trainer-domain", "", `also create one field-app trainer per county, "<county>@<domain>", assigned to that county's training`)
	startsAt := flag.String("starts", "2026-12-01T09:00:00+03:00", "placeholder training start (RFC 3339); edit each event's date in the dashboard")
	flag.Parse()
	email := strings.ToLower(strings.TrimSpace(*ownerEmail))
	if !strings.Contains(email, "@") {
		log.Fatal("-owner-email is required")
	}
	start, err := time.Parse(time.RFC3339, *startsAt)
	if err != nil {
		log.Fatalf("-starts: %v", err)
	}
	ctx := context.Background()

	counties, err := sdicsCounties(ctx)
	if err != nil {
		log.Fatal(err)
	}

	pool, err := db.Connect(ctx, config.Load().DatabaseURL)
	if err != nil {
		log.Fatal(err)
	}
	defer pool.Close()
	if err := db.Migrate(ctx, pool); err != nil {
		log.Fatal(err)
	}
	tx, err := pool.Begin(ctx)
	if err != nil {
		log.Fatal(err)
	}
	defer tx.Rollback(ctx)

	slug := strings.Trim(strings.Map(func(r rune) rune {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
			return r
		}
		return '-'
	}, strings.ToLower(*orgName)), "-")
	var orgID string
	err = tx.QueryRow(ctx, `
		INSERT INTO organizations (name, slug, vocabulary, accent_color, contact_email)
		VALUES ($1, $2, 'sdics_chiefs', '#0F8A7A', $3)
		ON CONFLICT (slug) DO UPDATE SET vocabulary = 'sdics_chiefs', active = true
		RETURNING id`, *orgName, slug, email).Scan(&orgID)
	if err != nil {
		log.Fatalf("organization: %v", err)
	}

	var ownerOrg *string
	err = tx.QueryRow(ctx, `SELECT org_id FROM users WHERE email = $1`, email).Scan(&ownerOrg)
	switch {
	case err == pgx.ErrNoRows:
		if len(*ownerPassword) < 8 {
			log.Fatal("-owner-password (8+ characters) is required to create the owner")
		}
		hash, err := auth.HashPassword(*ownerPassword)
		if err != nil {
			log.Fatal(err)
		}
		if _, err := tx.Exec(ctx, `INSERT INTO users (org_id, name, email, password_hash, role) VALUES ($1,$2,$3,$4,'owner')`,
			orgID, *ownerName, email, hash); err != nil {
			log.Fatalf("owner: %v", err)
		}
		log.Printf("owner %s created", email)
	case err != nil:
		log.Fatal(err)
	case ownerOrg == nil || *ownerOrg != orgID:
		log.Fatalf("%s already belongs to another organization; pick another -owner-email", email)
	default:
		if *resetPassword {
			if len(*ownerPassword) < 8 {
				log.Fatal("-owner-password (8+ characters) is required with -reset-password")
			}
			hash, err := auth.HashPassword(*ownerPassword)
			if err != nil {
				log.Fatal(err)
			}
			if _, err := tx.Exec(ctx, `UPDATE users SET password_hash=$2, active=true WHERE email=$1`, email, hash); err != nil {
				log.Fatal(err)
			}
			log.Printf("owner %s password reset", email)
		} else {
			log.Printf("owner %s already exists (password unchanged)", email)
		}
	}

	var created [][3]string // county, login, password (new trainers only)
	for _, c := range counties {
		event := fmt.Sprintf("SDICS App Training – Chiefs – %s", c)
		var n int
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM events WHERE org_id=$1 AND name=$2`, orgID, event).Scan(&n); err != nil {
			log.Fatal(err)
		}
		if n == 0 {
			if _, err := tx.Exec(ctx, `
				INSERT INTO events (org_id, name, venue, county, starts_at) VALUES ($1,$2,$3,$4,$5)`,
				orgID, event, c+" County (venue to be confirmed)", c, start); err != nil {
				log.Fatalf("event %s: %v", c, err)
			}
		}
		log.Printf("  %-16s training event", c)
		if *trainerDomain != "" {
			login, pw, err := trainer(ctx, tx, orgID, event, c, *trainerDomain)
			if err != nil {
				log.Fatalf("trainer %s: %v", c, err)
			}
			if pw != "" {
				created = append(created, [3]string{c, login, pw})
			}
		}
	}
	if err := tx.Commit(ctx); err != nil {
		log.Fatal(err)
	}
	log.Printf("%s ready: %d counties", *orgName, len(counties))
	if len(created) > 0 {
		// Printed once: only bcrypt hashes are stored. Hand these to the trainers.
		fmt.Println("\nNew trainer accounts (field app):")
		for _, t := range created {
			fmt.Printf("  %-16s %-40s %s\n", t[0], t[1], t[2])
		}
	}
}

// trainer makes sure the county has its field-app trainer: a member scoped to the county,
// assigned to the county's training only, without the outreach module. Returns the password
// only when the account is new (existing trainers keep theirs).
func trainer(ctx context.Context, tx pgx.Tx, orgID, event, county, domain string) (login, password string, err error) {
	// "Elgeyo-Marakwet" → elgeyo-marakwet, "Trans Nzoia" → trans-nzoia
	login = strings.Trim(strings.Map(func(r rune) rune {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '-' {
			return r
		}
		if r == ' ' {
			return '-'
		}
		return -1
	}, strings.ToLower(county)), "-")
	login += "@" + strings.ToLower(strings.TrimSpace(domain))
	var userID string
	var userOrg *string
	err = tx.QueryRow(ctx, `SELECT id, org_id FROM users WHERE email=$1`, login).Scan(&userID, &userOrg)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		password = newPassword(county)
		hash, herr := auth.HashPassword(password)
		if herr != nil {
			return "", "", herr
		}
		err = tx.QueryRow(ctx, `
			INSERT INTO users (org_id, name, email, password_hash, role, module_events, module_mobilization, scope_county)
			VALUES ($1,$2,$3,$4,'member',true,false,$5) RETURNING id`,
			orgID, county+" Trainer", login, hash, county).Scan(&userID)
		if err != nil {
			return "", "", err
		}
	case err != nil:
		return "", "", err
	case userOrg == nil || *userOrg != orgID:
		return "", "", fmt.Errorf("%s already belongs to another organization", login)
	}
	_, err = tx.Exec(ctx, `
		INSERT INTO event_assignments (event_id, user_id)
		SELECT e.id, $3 FROM events e WHERE e.org_id=$1 AND e.name=$2
		ON CONFLICT DO NOTHING`, orgID, event, userID)
	return login, password, err
}

// newPassword: the county name plus 6 random letters/digits (no look-alikes), e.g. Nandi-7KQ4MX.
func newPassword(county string) string {
	const alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
	b := make([]byte, 6)
	if _, err := rand.Read(b); err != nil {
		log.Fatal(err)
	}
	for i := range b {
		b[i] = alphabet[int(b[i])%len(alphabet)]
	}
	name := strings.ReplaceAll(strings.ReplaceAll(county, " ", ""), "-", "")
	return name + "-" + string(b)
}

// sdicsCounties: the counties SDICS covers (usajili_location_ref), in official spelling.
func sdicsCounties(ctx context.Context) ([]string, error) {
	url := os.Getenv("SDICS_DATABASE_URL")
	if url == "" {
		return nil, fmt.Errorf("SDICS_DATABASE_URL is not set (load /opt/machinenova/.env first)")
	}
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		return nil, err
	}
	defer pool.Close()
	rows, err := pool.Query(ctx, `SELECT DISTINCT county FROM usajili_location_ref ORDER BY 1`)
	if err != nil {
		return nil, fmt.Errorf("sdics counties: %w", err)
	}
	names, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		return nil, err
	}
	if len(names) == 0 {
		return nil, fmt.Errorf("SDICS lists no counties")
	}
	for i, n := range names {
		names[i] = places.CountyName(n)
	}
	return names, nil
}
