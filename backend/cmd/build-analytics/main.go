// Command build-analytics rebuilds the registration analysis: for every home county and
// sub-county in the national ID records, how many adults there are and how many of them are
// on the voter register. Run it after loading either register.
//
//	go run ./cmd/build-analytics
package main

import (
	"context"
	"log"
	"time"

	"github.com/machinenova/checkin/backend/internal/config"
	"github.com/machinenova/checkin/backend/internal/db"
	"github.com/machinenova/checkin/backend/internal/places"
)

func main() {
	ctx := context.Background()
	pool, err := db.Connect(ctx, config.Load().DatabaseURL)
	if err != nil {
		log.Fatal(err)
	}
	defer pool.Close()
	if err := db.Migrate(ctx, pool); err != nil {
		log.Fatal(err)
	}
	start := time.Now()
	if _, err := pool.Exec(ctx, `SET work_mem = '512MB'`); err != nil {
		log.Fatal(err)
	}
	log.Print("counting adults and registered voters per home area…")
	rows, err := pool.Query(ctx, `
		SELECT coalesce(i.county, ''), coalesce(i.sub_county, ''), count(*), count(v.national_id)
		FROM id_registry i LEFT JOIN register_voters v ON v.national_id = i.national_id
		WHERE i.dob <= current_date - interval '18 years'
		GROUP BY 1, 2`)
	if err != nil {
		log.Fatal(err)
	}
	type key struct{ county, sub string }
	agg := map[key][2]int64{}
	for rows.Next() {
		var county, sub string
		var adults, registered int64
		if err := rows.Scan(&county, &sub, &adults, &registered); err != nil {
			log.Fatal(err)
		}
		k := key{places.CountyName(county), places.TitleCase(sub)}
		if k.sub == "" {
			k.sub = "Unknown"
		}
		v := agg[k]
		agg[k] = [2]int64{v[0] + adults, v[1] + registered}
	}
	if err := rows.Err(); err != nil {
		log.Fatal(err)
	}
	tx, err := pool.Begin(ctx)
	if err != nil {
		log.Fatal(err)
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `DELETE FROM registration_stats`); err != nil {
		log.Fatal(err)
	}
	var adults, registered int64
	for k, v := range agg {
		if _, err := tx.Exec(ctx, `INSERT INTO registration_stats (county, sub_county, adults, registered) VALUES ($1,$2,$3,$4)`,
			k.county, k.sub, v[0], v[1]); err != nil {
			log.Fatal(err)
		}
		adults += v[0]
		registered += v[1]
	}
	if err := tx.Commit(ctx); err != nil {
		log.Fatal(err)
	}
	log.Printf("done: %d areas, %d adults, %d registered (%.1f%%) in %s", len(agg), adults, registered,
		100*float64(registered)/float64(max(adults, 1)), time.Since(start).Round(time.Second))
}
