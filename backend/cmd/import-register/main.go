// Command import-register loads the voter register from CSV, replacing the current register.
//
//	go run ./cmd/import-register -file register.csv
//
// Name, sex and date of birth are optional (lookup fills them from id_registry).
// Accepts the original header or the SDICS "registered voters" export (any column order;
// extra columns are ignored and never read into the database):
//
//	national_id | ID | IDNO          name | FULLNAME           sex | SEX (F/M)
//	dob | DATE_BIRTH (YYYY-MM-DD or YYYYMMDD)                   county | County
//	constituency                    ward | Ward                polling_center | Polling Center
//	registered_on | date_of_registration (optional)
//
// Tens of millions of rows are streamed via COPY into an unlogged staging table,
// de-duplicated by ID (latest registration wins), indexed and swapped in atomically,
// so lookups keep working during a reload. Place names are normalised for display.
package main

import (
	"context"
	"encoding/csv"
	"errors"
	"flag"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
	"golang.org/x/text/encoding/charmap"

	"github.com/machinenova/checkin/backend/internal/config"
	"github.com/machinenova/checkin/backend/internal/db"
	"github.com/machinenova/checkin/backend/internal/places"
)

// field -> accepted header names (lower-cased)
var aliases = map[string][]string{
	"national_id":    {"national_id", "id", "idno", "id_number"},
	"name":           {"name", "fullname", "full_name"},
	"sex":            {"sex", "gender"},
	"dob":            {"dob", "date_birth", "date_of_birth"},
	"county":         {"county"},
	"constituency":   {"constituency"},
	"ward":           {"ward"},
	"polling_center": {"polling_center", "polling center", "polling_centre", "polling station"},
	"registered_on":  {"registered_on", "date_of_registration", "registration_date"},
}

// Registration status and area are what matter; identity columns may be blank for some voters.
var required = []string{"national_id", "county", "constituency", "ward", "polling_center"}

var stagingCols = []string{"national_id", "name", "sex", "dob", "county", "constituency", "ward", "polling_center",
	"registered_on", "row_no"}

func main() {
	file := flag.String("file", "", "path to register CSV")
	flag.Parse()
	if *file == "" {
		log.Fatal("-file is required")
	}
	f, err := os.Open(*file)
	if err != nil {
		log.Fatal(err)
	}
	defer f.Close()

	r := csv.NewReader(f)
	r.ReuseRecord = true
	r.LazyQuotes = true
	r.FieldsPerRecord = -1
	r.TrimLeadingSpace = true
	header, err := r.Read()
	if err != nil {
		log.Fatal("read header: ", err)
	}
	pos := map[string]int{}
	for i, h := range header {
		pos[strings.ToLower(strings.TrimSpace(strings.Trim(h, "\ufeff")))] = i
	}
	idx := map[string]int{}
	for field, names := range aliases {
		for _, n := range names {
			if i, ok := pos[n]; ok {
				idx[field] = i
				break
			}
		}
	}
	for _, c := range required {
		if _, ok := idx[c]; !ok {
			log.Fatalf("missing column for %q (accepted: %s)", c, strings.Join(aliases[c], ", "))
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

	start := time.Now()
	exec(`SET maintenance_work_mem = '2GB'`)
	exec(`DROP TABLE IF EXISTS register_staging`)
	exec(`CREATE UNLOGGED TABLE register_staging (national_id TEXT, name TEXT, sex CHAR(1), dob DATE, county TEXT,
		constituency TEXT, ward TEXT, polling_center TEXT, registered_on DATE, row_no BIGINT)`)

	src := &rowSource{r: r, idx: idx, started: start, source: filepath.Base(*file)}
	n, err := c.CopyFrom(ctx, pgx.Identifier{"register_staging"}, stagingCols, src)
	if err != nil {
		log.Fatal("copy: ", err)
	}
	log.Printf("staged %d rows (%d skipped) — %s", n, src.skipped, time.Since(start).Round(time.Second))

	log.Printf("de-duplicating by ID…")
	exec(`DROP TABLE IF EXISTS register_voters_new`)
	exec(`CREATE TABLE register_voters_new (LIKE register_voters INCLUDING DEFAULTS INCLUDING CONSTRAINTS)`)
	exec(`INSERT INTO register_voters_new (national_id, name, sex, dob, county, constituency, ward, polling_center, registered_on)
		SELECT DISTINCT ON (national_id) national_id, name, sex, dob, county, constituency, ward, polling_center, registered_on
		FROM register_staging
		ORDER BY national_id, registered_on DESC NULLS LAST, row_no DESC`)
	log.Printf("indexing… (%s)", time.Since(start).Round(time.Second))
	exec(`ALTER TABLE register_voters_new ADD PRIMARY KEY (national_id)`)

	var unique int64
	if err := c.QueryRow(ctx, `SELECT count(*) FROM register_voters_new`).Scan(&unique); err != nil {
		log.Fatal(err)
	}
	tx, err := c.Begin(ctx)
	if err != nil {
		log.Fatal(err)
	}
	for _, sql := range []string{
		`DROP TABLE register_voters`,
		`ALTER TABLE register_voters_new RENAME TO register_voters`,
		`ALTER INDEX register_voters_new_pkey RENAME TO register_voters_pkey`,
	} {
		if _, err := tx.Exec(ctx, sql); err != nil {
			log.Fatalf("swap: %v", err)
		}
	}
	if err := tx.Commit(ctx); err != nil {
		log.Fatal(err)
	}
	exec(`DROP TABLE register_staging`)
	exec(`ANALYZE register_voters`)
	log.Printf("done: %d registered voters loaded (%d duplicate rows dropped, %d skipped) in %s",
		unique, n-unique, src.skipped, time.Since(start).Round(time.Second))
}

type rowSource struct {
	r       *csv.Reader
	idx     map[string]int
	row     []any
	line    int64
	skipped int64
	started time.Time
	source  string
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
			i, ok := s.idx[field]
			if !ok || i >= len(rec) {
				return ""
			}
			return strings.Join(strings.Fields(toUTF8(rec[i])), " ")
		}
		id := strings.ReplaceAll(get("national_id"), " ", "")
		name := get("name")
		sex := normSex(get("sex"))
		dob := parseDate(get("dob"))
		county, constituency, ward, pc := get("county"), get("constituency"), get("ward"), get("polling_center")
		if id == "" || county == "" || constituency == "" || ward == "" || pc == "" {
			s.skipped++
			continue
		}
		s.row = []any{id, emptyNil(name), emptyNil(sex), dob, places.CountyName(county), places.TitleCase(constituency),
			places.TitleCase(ward), places.TitleCase(pc), parseDate(get("registered_on")), s.line}
		return true
	}
}

func (s *rowSource) Values() ([]any, error) { return s.row, nil }
func (s *rowSource) Err() error             { return nil }

// toUTF8 repairs fields exported in Windows-1252 (e.g. curly quotes in names), which
// Postgres would otherwise reject.
func toUTF8(s string) string {
	if utf8.ValidString(s) {
		return s
	}
	if out, err := charmap.Windows1252.NewDecoder().String(s); err == nil {
		return out
	}
	return strings.ToValidUTF8(s, "")
}

func emptyNil(s string) any {
	if s == "" {
		return nil
	}
	return s
}

func normSex(s string) string {
	switch strings.ToUpper(s) {
	case "M", "MALE":
		return "M"
	case "F", "FEMALE":
		return "F"
	}
	return ""
}

// parseDate accepts YYYY-MM-DD, YYYYMMDD and "YYYY-MM-DD hh:mm:ss"; returns nil when unusable.
func parseDate(s string) any {
	if len(s) >= 10 && s[4] == '-' {
		s = s[:10]
	}
	for _, layout := range []string{time.DateOnly, "20060102"} {
		if t, err := time.Parse(layout, s); err == nil && t.Year() >= 1890 && !t.After(time.Now()) {
			return t
		}
	}
	return nil
}
