// Command bootstrap creates (or resets) the first MachineNova platform-admin account.
//
//	go run ./cmd/bootstrap -email ops@machinenova.co.ke -name "Ops" -password '...'
package main

import (
	"context"
	"flag"
	"log"
	"strings"

	"github.com/machinenova/checkin/backend/internal/auth"
	"github.com/machinenova/checkin/backend/internal/config"
	"github.com/machinenova/checkin/backend/internal/db"
)

func main() {
	email := flag.String("email", "", "platform admin email")
	name := flag.String("name", "Platform Admin", "display name")
	password := flag.String("password", "", "password (8+ characters)")
	flag.Parse()
	if !strings.Contains(*email, "@") || len(*password) < 8 {
		log.Fatal("-email and an 8+ character -password are required")
	}
	ctx := context.Background()
	pool, err := db.Connect(ctx, config.Load().DatabaseURL)
	if err != nil {
		log.Fatal(err)
	}
	defer pool.Close()
	if err := db.Migrate(ctx, pool); err != nil {
		log.Fatal(err)
	}
	hash, err := auth.HashPassword(*password)
	if err != nil {
		log.Fatal(err)
	}
	_, err = pool.Exec(ctx, `
		INSERT INTO users (email, name, password_hash, role, is_platform_admin)
		VALUES (lower($1), $2, $3, 'viewer', true)
		ON CONFLICT (email) DO UPDATE SET password_hash = EXCLUDED.password_hash, is_platform_admin = true, active = true`,
		*email, *name, hash)
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("platform admin %s ready", *email)
}
