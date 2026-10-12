// Command import-register loads the statutory voter register from CSV, upserting by national_id.
//
// Expected header (any column order):
//
//	national_id,name,sex,dob,county,constituency,ward,polling_center
//
// sex is F/M; dob is YYYY-MM-DD.
package main

import (
	"context"
	"encoding/csv"
	"flag"
	"io"
	"log"
	"os"
	"strings"

	"github.com/jackc/pgx/v5"

	"github.com/machinenova/checkin/backend/internal/config"
	"github.com/machinenova/checkin/backend/internal/db"
)

var columns = []string{"national_id", "name", "sex", "dob", "county", "constituency", "ward", "polling_center"}

func main() {
	file := flag.String("file", "", "path to register CSV")
	flag.Parse()
	f, err := os.Open(*file)
	if err != nil {
		log.Fatal(err)
	}
	defer f.Close()

	r := csv.NewReader(f)
	r.TrimLeadingSpace = true
	header, err := r.Read()
	if err != nil {
		log.Fatal("read header: ", err)
	}
	idx := map[string]int{}
	for i, h := range header {
		idx[strings.ToLower(strings.TrimSpace(h))] = i
	}
	for _, c := range columns {
		if _, ok := idx[c]; !ok {
			log.Fatalf("missing column %q", c)
		}
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
	tx, err := pool.Begin(ctx)
	if err != nil {
		log.Fatal(err)
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `CREATE TEMP TABLE register_import (LIKE register_voters) ON COMMIT DROP`); err != nil {
		log.Fatal(err)
	}

	var rows [][]any
	line := 1
	for {
		rec, err := r.Read()
		if err == io.EOF {
			break
		}
		line++
		if err != nil {
			log.Fatalf("line %d: %v", line, err)
		}
		row := make([]any, len(columns))
		for i, c := range columns {
			v := strings.TrimSpace(rec[idx[c]])
			switch c {
			case "national_id":
				v = strings.Join(strings.Fields(v), "")
			case "sex":
				v = strings.ToUpper(v[:min(1, len(v))])
			}
			row[i] = v
		}
		rows = append(rows, row)
	}
	n, err := tx.CopyFrom(ctx, pgx.Identifier{"register_import"}, columns, pgx.CopyFromRows(rows))
	if err != nil {
		log.Fatal("copy: ", err)
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO register_voters SELECT DISTINCT ON (national_id) * FROM register_import
		ON CONFLICT (national_id) DO UPDATE SET name=EXCLUDED.name, sex=EXCLUDED.sex, dob=EXCLUDED.dob,
			county=EXCLUDED.county, constituency=EXCLUDED.constituency, ward=EXCLUDED.ward,
			polling_center=EXCLUDED.polling_center`); err != nil {
		log.Fatal("upsert: ", err)
	}
	if err := tx.Commit(ctx); err != nil {
		log.Fatal(err)
	}
	log.Printf("imported %d register rows", n)
}
