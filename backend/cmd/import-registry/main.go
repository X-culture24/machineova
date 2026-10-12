// Command import-registry loads the statutory polling-station register and party list from CSV,
// upserting by code.
//
//	go run ./cmd/import-registry -stations stations.csv -parties parties.csv
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

	"github.com/machinenova/checkin/backend/internal/config"
	"github.com/machinenova/checkin/backend/internal/db"
)

func main() {
	stations := flag.String("stations", "", "polling stations CSV")
	parties := flag.String("parties", "", "parties CSV")
	flag.Parse()
	if *stations == "" && *parties == "" {
		log.Fatal("pass -stations and/or -parties")
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
