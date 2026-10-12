// Command import-registry loads the statutory polling-station register and party list from CSV,
// upserting by code.
//
//	go run ./cmd/import-registry -stations stations.csv -parties parties.csv
//	go run ./cmd/import-registry -from-register -parties data/kenya_parties.csv
//
// -from-register builds the polling-station register from the loaded voter register: one
// station per polling centre, with its ward, constituency, county and registered-voter count.
// Codes are stable across reloads: the IEBC county number plus a fingerprint of the centre
// (e.g. 047-3F9A21C0), so elections created earlier keep pointing at the same stations.
//
// stations.csv header (any order): code,name,county,constituency,ward,registered_voters
// parties.csv header (any order):  code,name[,colour]
package main

import (
	"context"
	"encoding/csv"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/machinenova/checkin/backend/internal/config"
	"github.com/machinenova/checkin/backend/internal/db"
	"github.com/machinenova/checkin/backend/internal/places"
)

func main() {
	stations := flag.String("stations", "", "polling stations CSV")
	parties := flag.String("parties", "", "parties CSV")
	fromRegister := flag.Bool("from-register", false, "build polling stations from the loaded voter register")
	flag.Parse()
	if *stations == "" && *parties == "" && !*fromRegister {
		log.Fatal("pass -stations, -from-register and/or -parties")
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
	if *parties != "" {
		n, err := load(ctx, pool, *parties, []string{"code", "name"}, []string{"colour"}, `
			INSERT INTO parties SELECT DISTINCT ON (code) code, name, NULLIF(colour, '') FROM import
			ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, colour = EXCLUDED.colour`,
			func(col, v string) (any, error) {
				if col == "code" {
					return strings.ToUpper(v), nil
				}
				return v, nil
			})
		if err != nil {
			log.Fatal("parties: ", err)
		}
		log.Printf("imported %d parties", n)
	}
	if *fromRegister {
		n, err := stationsFromRegister(ctx, pool)
		if err != nil {
			log.Fatal("stations from register: ", err)
		}
		log.Printf("built %d polling stations from the voter register", n)
	}
	if *stations != "" {
		n, err := load(ctx, pool, *stations, []string{"code", "name", "county", "constituency", "ward", "registered_voters"}, nil, `
			INSERT INTO polling_stations SELECT DISTINCT ON (code) code, name, county, constituency, ward, registered_voters::int FROM import
			ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, county = EXCLUDED.county, constituency = EXCLUDED.constituency,
				ward = EXCLUDED.ward, registered_voters = EXCLUDED.registered_voters`,
			func(col, v string) (any, error) {
				if col == "registered_voters" {
					v = strings.ReplaceAll(v, ",", "")
					if _, err := strconv.Atoi(v); err != nil {
						return nil, fmt.Errorf("registered_voters %q is not a number", v)
					}
				}
				return v, nil
			})
		if err != nil {
			log.Fatal("stations: ", err)
		}
		log.Printf("imported %d polling stations", n)
	}
}

// load copies a CSV into a temp table named "import" (all text columns) and runs the upsert.
func load(ctx context.Context, pool interface {
	Begin(context.Context) (pgx.Tx, error)
}, path string, required, optional []string, upsert string, clean func(col, v string) (any, error)) (int64, error) {
	f, err := os.Open(path)
	if err != nil {
		return 0, err
	}
	defer f.Close()
	r := csv.NewReader(f)
	r.TrimLeadingSpace = true
	header, err := r.Read()
	if err != nil {
		return 0, fmt.Errorf("read header: %w", err)
	}
	idx := map[string]int{}
	for i, h := range header {
		idx[strings.ToLower(strings.TrimSpace(h))] = i
	}
	for _, c := range required {
		if _, ok := idx[c]; !ok {
			return 0, fmt.Errorf("missing column %q", c)
		}
	}
	cols := append(append([]string{}, required...), optional...)
	var rows [][]any
	line := 1
	for {
		rec, err := r.Read()
		if err == io.EOF {
			break
		}
		line++
		if err != nil {
			return 0, fmt.Errorf("line %d: %w", line, err)
		}
		row := make([]any, len(cols))
		for i, c := range cols {
			v := ""
			if j, ok := idx[c]; ok && j < len(rec) {
				v = strings.TrimSpace(rec[j])
			}
			if v == "" && i < len(required) {
				return 0, fmt.Errorf("line %d: %s is empty", line, c)
			}
			if row[i], err = clean(c, v); err != nil {
				return 0, fmt.Errorf("line %d: %w", line, err)
			}
		}
		rows = append(rows, row)
	}
	tx, err := pool.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback(ctx)
	ddl := "CREATE TEMP TABLE import (" + strings.Join(cols, " text, ") + " text) ON COMMIT DROP"
	if _, err := tx.Exec(ctx, ddl); err != nil {
		return 0, err
	}
	n, err := tx.CopyFrom(ctx, pgx.Identifier{"import"}, cols, pgx.CopyFromRows(rows))
	if err != nil {
		return 0, err
	}
	if _, err := tx.Exec(ctx, upsert); err != nil {
		return 0, err
	}
	return n, tx.Commit(ctx)
}

// stationsFromRegister upserts one polling station per (county, constituency, ward, centre)
// in register_voters, with its registered-voter count.
func stationsFromRegister(ctx context.Context, pool *pgxpool.Pool) (int64, error) {
	// IEBC county numbers (001 Mombasa … 047 Nairobi); other areas (diaspora, prisons) get 9xx.
	var codes strings.Builder
	codes.WriteString("VALUES ")
	for i, name := range places.Counties() {
		if i > 0 {
			codes.WriteString(",")
		}
		fmt.Fprintf(&codes, "('%s', %d)", strings.ReplaceAll(name, "'", "''"), i+1)
	}
	tag, err := pool.Exec(ctx, `
		WITH county_codes(county, n) AS (`+codes.String()+`),
		centres AS (
			SELECT r.county, r.constituency, r.ward, r.polling_center, count(*) AS voters,
			       coalesce(c.n, 900 + dense_rank() OVER (ORDER BY r.county) % 100) AS n
			FROM register_voters r LEFT JOIN county_codes c ON c.county = r.county
			GROUP BY r.county, r.constituency, r.ward, r.polling_center, c.n
		)
		INSERT INTO polling_stations (code, name, county, constituency, ward, registered_voters)
		SELECT lpad(n::text, 3, '0') || '-' ||
		       upper(left(md5(constituency || '|' || ward || '|' || polling_center), 8)),
		       polling_center, county, constituency, ward, voters
		FROM centres
		ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, county = EXCLUDED.county,
			constituency = EXCLUDED.constituency, ward = EXCLUDED.ward, registered_voters = EXCLUDED.registered_voters`)
	if err != nil {
		return 0, err
	}
	return tag.RowsAffected(), nil
}
