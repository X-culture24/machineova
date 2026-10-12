// Command import-idregistry loads National Registration Bureau (NRB) ID extracts into id_registry.
//
//	go run ./cmd/import-idregistry -files a.csv,b.csv,c.csv
//
// Expected header (any column order, extra columns ignored):
//
//	IDNO,FULLNAME,DATE_BIRTH,SEX,COUNTY,SUBCOUNTY,DIVISION,LOCATION,SUBLOCATION,VILLAGE
//
// DATE_BIRTH is YYYYMMDD. Files are streamed (tens of millions of rows are fine): rows are
// COPYed into an unlogged staging table, de-duplicated by ID (earlier files win), indexed,
// and swapped in atomically, so lookups keep working during a reload. Sensitive columns
// in the extracts (parents' names, tribe, clan, family) are never read into the database.
package main

import (
	"context"
	"encoding/csv"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/machinenova/checkin/backend/internal/config"
	"github.com/machinenova/checkin/backend/internal/db"
)

var stagingCols = []string{"national_id", "name", "sex", "dob", "county", "sub_county", "division",
	"location", "sub_location", "village", "source", "file_rank", "row_no"}

// source CSV column for each stored field
var fieldCols = map[string]string{
	"national_id": "IDNO", "name": "FULLNAME", "dob": "DATE_BIRTH", "sex": "SEX", "county": "COUNTY",
	"sub_county": "SUBCOUNTY", "division": "DIVISION", "location": "LOCATION",
	"sub_location": "SUBLOCATION", "village": "VILLAGE",
}

func main() {
	files := flag.String("files", "", "comma-separated NRB CSV files (earlier files win on duplicate IDs)")
	flag.Parse()
	paths := strings.Split(*files, ",")
	if *files == "" {
		log.Fatal("-files is required")
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
	conn, err := pool.Acquire(ctx)
	if err != nil {
		log.Fatal(err)
	}
	defer conn.Release()
	c := conn.Conn()

	exec := func(sql string) {
		if _, err := c.Exec(ctx, sql); err != nil {
			log.Fatalf("%v\n%s", err, sql)
		}
	}
	exec(`SET maintenance_work_mem = '2GB'`)
	exec(`DROP TABLE IF EXISTS id_registry_staging`)
	exec(`CREATE UNLOGGED TABLE id_registry_staging (
		national_id TEXT, name TEXT, sex CHAR(1), dob DATE, county TEXT, sub_county TEXT, division TEXT,
		location TEXT, sub_location TEXT, village TEXT, source TEXT, file_rank INT, row_no BIGINT)`)

	start := time.Now()
	var total, skipped int64
	for rank, path := range paths {
		path = strings.TrimSpace(path)
		n, bad, err := loadFile(ctx, c, path, rank)
		if err != nil {
			log.Fatalf("%s: %v", path, err)
		}
		total += n
		skipped += bad
		log.Printf("%s: staged %d rows (%d skipped) — %s elapsed", filepath.Base(path), n, bad, time.Since(start).Round(time.Second))
	}

	log.Printf("de-duplicating %d staged rows by ID…", total)
	exec(`DROP TABLE IF EXISTS id_registry_new`)
	exec(`CREATE TABLE id_registry_new (LIKE id_registry INCLUDING DEFAULTS INCLUDING CONSTRAINTS)`)
	exec(`INSERT INTO id_registry_new (national_id, name, sex, dob, county, sub_county, division, location, sub_location, village, source)
		SELECT DISTINCT ON (national_id) national_id, name, sex, dob, county, sub_county, division, location, sub_location, village, source
		FROM id_registry_staging
		ORDER BY national_id, file_rank, row_no`)
	log.Printf("indexing… (%s elapsed)", time.Since(start).Round(time.Second))
	exec(`ALTER TABLE id_registry_new ADD PRIMARY KEY (national_id)`)

	var unique int64
	if err := c.QueryRow(ctx, `SELECT count(*) FROM id_registry_new`).Scan(&unique); err != nil {
		log.Fatal(err)
	}

	// Atomic swap: lookups see the old table until this commits.
	tx, err := c.Begin(ctx)
	if err != nil {
		log.Fatal(err)
	}
	for _, sql := range []string{
		`DROP TABLE id_registry`,
		`ALTER TABLE id_registry_new RENAME TO id_registry`,
		`ALTER INDEX id_registry_new_pkey RENAME TO id_registry_pkey`,
	} {
		if _, err := tx.Exec(ctx, sql); err != nil {
			log.Fatalf("swap: %v", err)
		}
	}
	if err := tx.Commit(ctx); err != nil {
		log.Fatal(err)
	}
	exec(`DROP TABLE id_registry_staging`)
	exec(`ANALYZE id_registry`)
	log.Printf("done: %d rows read, %d skipped, %d unique IDs loaded (%d duplicates dropped) in %s",
		total+skipped, skipped, unique, total-unique, time.Since(start).Round(time.Second))
}

// loadFile streams one CSV into the staging table.
func loadFile(ctx context.Context, c *pgx.Conn, path string, rank int) (int64, int64, error) {
	f, err := os.Open(path)
	if err != nil {
		return 0, 0, err
	}
	defer f.Close()
	r := csv.NewReader(f)
	r.ReuseRecord = true
	r.LazyQuotes = true
	r.FieldsPerRecord = -1
	header, err := r.Read()
	if err != nil {
		return 0, 0, fmt.Errorf("read header: %w", err)
	}
	idx := map[string]int{}
	for i, h := range header {
		idx[strings.ToUpper(strings.Trim(strings.TrimSpace(h), "\ufeff"))] = i
	}
	for _, col := range fieldCols {
		if _, ok := idx[col]; !ok {
			return 0, 0, fmt.Errorf("missing column %q", col)
		}
	}
	src := &rowSource{r: r, idx: idx, source: filepath.Base(path), rank: rank, started: time.Now()}
	n, err := c.CopyFrom(ctx, pgx.Identifier{"id_registry_staging"}, stagingCols, src)
	return n, src.skipped, err
}

// rowSource adapts the CSV reader to pgx.CopyFromSource, cleaning each row on the way.
type rowSource struct {
	r       *csv.Reader
	idx     map[string]int
	source  string
	rank    int
	row     []any
	err     error
	line    int64
	skipped int64
	started time.Time
}

func (s *rowSource) Next() bool {
	for {
		rec, err := s.r.Read()
		if errors.Is(err, io.EOF) {
			return false
		}
		s.line++
		if s.line%2_000_000 == 0 {
			log.Printf("  %s: %d rows read (%s)", s.source, s.line, time.Since(s.started).Round(time.Second))
		}
		if err != nil {
			s.skipped++ // malformed line; content is not logged
			continue
		}
		get := func(field string) string {
			i := s.idx[fieldCols[field]]
			if i >= len(rec) {
				return ""
			}
			return strings.Join(strings.Fields(rec[i]), " ")
		}
		id := registryKey(get("national_id"))
		name := get("name")
		if id == "" || name == "" {
			s.skipped++
			continue
		}
		s.row = []any{id, name, sexOrNil(get("sex")), dobOrNil(get("dob")),
			emptyNil(get("county")), emptyNil(get("sub_county")), emptyNil(get("division")),
			emptyNil(get("location")), emptyNil(get("sub_location")), emptyNil(get("village")),
			s.source, s.rank, s.line}
		return true
	}
}

func (s *rowSource) Values() ([]any, error) { return s.row, nil }
func (s *rowSource) Err() error             { return s.err }

// registryKey keeps digits only and drops leading zeros, matching api.registryKey.
func registryKey(s string) string {
	var b strings.Builder
	for _, r := range s {
		if r >= '0' && r <= '9' {
			b.WriteRune(r)
		}
	}
	return strings.TrimLeft(b.String(), "0")
}

func sexOrNil(s string) any {
	switch strings.ToUpper(s) {
	case "M", "MALE":
		return "M"
	case "F", "FEMALE":
		return "F"
	}
	return nil
}

func dobOrNil(s string) any {
	t, err := time.Parse("20060102", s)
	if err != nil || t.Year() < 1890 || t.After(time.Now()) {
		return nil
	}
	return t
}

func emptyNil(s string) any {
	if s == "" {
		return nil
	}
	return s
}
