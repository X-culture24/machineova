// Command seed-demo builds a simulated election for a demo organization: contestants for every
// race, turnout through the day, station statuses, incidents and verified Form 37A results, all
// timestamped on election day so Monitor and Replay work as they would after a real election.
//
//	go run ./cmd/seed-demo -org "MachineNova Demo Campaign" -name "General Election 2025 (simulated)" \
//	    -code GE25-SIM -date 2025-08-12 -county Nairobi
//	go run ./cmd/seed-demo -org "Demo Candidate" -county Nairobi -constituency Westlands \
//	    -positions "Member of Parliament,MCA" -ours "Member of Parliament=Amina Wairimu Odhiambo"
//	go run ./cmd/seed-demo -org "Demo Candidate" -name "General Election 2027" -code GE27 -date 2027-08-10 \
//	    -county Nairobi -constituency Westlands -positions "Member of Parliament" -status active -results=false \
//	    -ours "Member of Parliament=Amina Wairimu Odhiambo"
//
// Everything is simulated: candidate names are invented, and results are generated from a fixed
// seed (-seed), so the same race comes out the same in every organization seeded with that seed.
// Party codes come from the parties registry. Elections are labelled by -name; keep "(simulated)"
// in the name of anything that could be mistaken for real results.
package main

import (
	"context"
	"flag"
	"fmt"
	"hash/fnv"
	"log"
	"math"
	"math/rand/v2"
	"sort"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/machinenova/checkin/backend/internal/config"
	"github.com/machinenova/checkin/backend/internal/db"
)

var standard = []struct{ name, level string }{
	{"President", "national"}, {"Governor", "county"}, {"Senator", "county"},
	{"Woman Representative", "county"}, {"Member of Parliament", "constituency"}, {"MCA", "ward"},
}
var levelRank = map[string]int{"national": 0, "county": 1, "constituency": 2, "ward": 3}

var slots = []int{7, 9, 11, 13, 15, 17}
var slotShare = []float64{0.13, 0.31, 0.49, 0.67, 0.86, 1}
var incidentTypes = []string{"KIEMS kit failure", "Ballot paper shortage", "Security concern", "Agent absent", "Voter intimidation", "Other"}

// Invented names, combined per race; any match with a real person is coincidence.
var firstNames = []string{"Amina", "Brian", "Caroline", "Daniel", "Esther", "Felix", "Grace", "Hassan", "Irene", "James",
	"Joyce", "Kevin", "Lilian", "Moses", "Naomi", "Otieno", "Purity", "Rashid", "Sarah", "Timothy", "Valentine", "Wanjiru",
	"Yusuf", "Zipporah", "Collins", "Faith", "Geoffrey", "Halima", "Ian", "Mercy", "Peter", "Rose", "Samuel", "Teresia"}
var middleNames = []string{"Achieng", "Chebet", "Jeptoo", "Kerubo", "Muthoni", "Nafula", "Wairimu", "Akinyi", "Mwende",
	"Kiprono", "Mutua", "Onyango", "Kamau", "Barasa", "Omondi", "Ndegwa", "Wekesa", "Kipchumba", "Ochieng", "Mwangi"}
var lastNames = []string{"Odhiambo", "Wanyama", "Kariuki", "Rotich", "Njoroge", "Abdi", "Musyoka", "Otieno", "Kimani", "Langat",
	"Mohamed", "Waweru", "Nyamweya", "Koech", "Ouma", "Gitau", "Simiyu", "Mbugua", "Kiplagat", "Owino", "Kilonzo", "Maina"}

type station struct {
	code, county, constituency, ward string
	registered                       int
}

type position struct {
	id, name, level string
}

type contestant struct {
	id, name, party string
	weight          float64
}

func main() {
	org := flag.String("org", "", "organization name or id (required)")
	name := flag.String("name", "General Election 2025 (simulated)", "election name")
	code := flag.String("code", "GE25-SIM", "election code")
	date := flag.String("date", "2025-08-12", "election day (YYYY-MM-DD)")
	county := flag.String("county", "", "scope county (blank: the organization's boundary)")
	constituency := flag.String("constituency", "", "scope constituency (optional)")
	positionsFlag := flag.String("positions", "", "comma-separated positions (default: every standard position in scope)")
	status := flag.String("status", "completed", "election status: completed, active or draft")
	results := flag.Bool("results", true, "generate election-day activity and results (false: candidates only)")
	ours := flag.String("ours", "", `mark our candidate: "Position=Full Name" (the seat must be a single race in scope)`)
	seed := flag.String("seed", "GE2025", "simulation seed: the same seed gives the same results")
	replace := flag.Bool("replace", false, "delete an existing election with this code in the organization first")
	flag.Parse()
	if *org == "" {
		log.Fatal("-org is required")
	}
	if *status != "completed" && *status != "active" && *status != "draft" {
		log.Fatal("-status must be completed, active or draft")
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

	var orgID, ownerID string
	var bCounty, bConstituency *string
	if err := pool.QueryRow(ctx, `
		SELECT o.id, o.boundary_county, o.boundary_constituency,
		       (SELECT u.id FROM users u WHERE u.org_id = o.id AND u.role = 'owner' ORDER BY u.created_at LIMIT 1)
		FROM organizations o WHERE o.id::text = $1 OR lower(o.name) = lower($1)`, *org).
		Scan(&orgID, &bCounty, &bConstituency, &ownerID); err != nil {
		log.Fatalf("organization %q: %v", *org, err)
	}
	sc, sk := pick(*county, bCounty), pick(*constituency, bConstituency)
	if bCounty != nil && !strings.EqualFold(sc, *bCounty) || bConstituency != nil && !strings.EqualFold(sk, *bConstituency) {
		log.Fatal("the scope must lie inside the organization's boundary")
	}
	scopeRank := 0
	if sc != "" {
		scopeRank = 1
	}
	if sk != "" {
		scopeRank = 2
	}

	var positions []position
	want := map[string]bool{}
	for _, p := range strings.Split(*positionsFlag, ",") {
		if p = strings.TrimSpace(p); p != "" {
			want[strings.ToLower(p)] = true
		}
	}
	for _, p := range standard {
		if levelRank[p.level] >= scopeRank && (len(want) == 0 || want[strings.ToLower(p.name)]) {
			positions = append(positions, position{name: p.name, level: p.level})
		}
	}
	if len(positions) == 0 {
		log.Fatal("no positions in scope")
	}
	oursPos, oursName, _ := strings.Cut(*ours, "=")

	stations, err := loadStations(ctx, pool, sc, sk)
	if err != nil {
		log.Fatal(err)
	}
	if len(stations) == 0 {
		log.Fatal("no polling stations in scope — check the county/constituency spelling against the register")
	}
	var parties []string
	rows, _ := pool.Query(ctx, `SELECT code FROM parties WHERE code <> 'IND' ORDER BY code`)
	if parties, err = pgx.CollectRows(rows, pgx.RowTo[string]); err != nil || len(parties) == 0 {
		log.Fatal("load the parties registry first (import-registry -parties)")
	}
	day, err := time.ParseInLocation(time.DateOnly, *date, nairobi)
	if err != nil {
		log.Fatal("-date: ", err)
	}

	tx, err := pool.Begin(ctx)
	if err != nil {
		log.Fatal(err)
	}
	defer tx.Rollback(ctx)
	if *replace {
		if _, err := tx.Exec(ctx, `DELETE FROM elections WHERE org_id=$1 AND code=$2`, orgID, strings.ToUpper(*code)); err != nil {
			log.Fatal(err)
		}
	}
	if *status == "active" {
		if _, err := tx.Exec(ctx, `UPDATE elections SET status='draft' WHERE org_id=$1 AND status='active'`, orgID); err != nil {
			log.Fatal(err)
		}
	}
	var electionID string
	if err := tx.QueryRow(ctx, `
		INSERT INTO elections (org_id, name, code, election_date, scope_county, scope_constituency, status, created_at)
		VALUES ($1,$2,$3,$4,NULLIF($5,''),NULLIF($6,''),$7,$8) RETURNING id`,
		orgID, *name, strings.ToUpper(*code), *date, sc, sk, *status, day.AddDate(0, -3, 0)).Scan(&electionID); err != nil {
		log.Fatal("create election: ", err)
	}
	stationRows := make([][]any, len(stations))
	for i, st := range stations {
		stationRows[i] = []any{electionID, st.code}
	}
	if _, err := tx.CopyFrom(ctx, pgx.Identifier{"election_stations"}, []string{"election_id", "station_code"}, pgx.CopyFromRows(stationRows)); err != nil {
		log.Fatal(err)
	}
	for i := range positions {
		if err := tx.QueryRow(ctx, `INSERT INTO positions (election_id, name, level, sort) VALUES ($1,$2,$3,$4) RETURNING id`,
			electionID, positions[i].name, positions[i].level, i).Scan(&positions[i].id); err != nil {
			log.Fatal(err)
		}
	}

	// Contestants per race. A race is a position plus its region key (as the API keys them).
	races := map[string][]contestant{} // positionID|regionKey → contestants
	oursPlaced := false
	for _, pos := range positions {
		regions := map[string]bool{}
		for _, st := range stations {
			regions[regionKey(st, pos.level)] = true
		}
		keys := sortedKeys(regions)
		for _, reg := range keys {
			cs := makeContestants(*seed, pos.name+"|"+reg, parties)
			isOurs := strings.EqualFold(pos.name, oursPos) && oursName != ""
			if isOurs {
				if len(keys) != 1 {
					log.Fatalf("-ours: %s has %d races in this scope; narrow the scope to the seat", pos.name, len(keys))
				}
				cs[1].name = strings.TrimSpace(oursName) // our candidate takes a contender's place
				// Same party as when this organization last ran them; a rival holding it swaps.
				var party string
				if err := tx.QueryRow(ctx, `
					SELECT c.party_code FROM candidates c JOIN positions p ON p.id = c.position_id JOIN elections e ON e.id = p.election_id
					WHERE e.org_id = $1 AND lower(c.name) = lower($2) AND c.party_code IS NOT NULL
					ORDER BY e.election_date DESC LIMIT 1`, orgID, cs[1].name).Scan(&party); err == nil && party != cs[1].party {
					for i := range cs {
						if cs[i].party == party {
							cs[i].party = cs[1].party
						}
					}
					cs[1].party = party
				}
				oursPlaced = true
			}
			var region any
			if pos.level != "national" {
				region = reg
			}
			for i := range cs {
				if err := tx.QueryRow(ctx, `
					INSERT INTO candidates (position_id, region, name, party_code, is_ours, sort) VALUES ($1,$2,$3,$4,$5,$6) RETURNING id`,
					pos.id, region, cs[i].name, cs[i].party, isOurs && i == 1, i).Scan(&cs[i].id); err != nil {
					log.Fatal(err)
				}
			}
			races[pos.id+"|"+reg] = cs
		}
	}
	if oursName != "" && !oursPlaced {
		log.Fatalf("-ours: no %q position in this election", oursPos)
	}

	if *results {
		if err := simulateDay(ctx, tx, electionID, ownerID, *seed, day, stations, positions, races, *status == "completed"); err != nil {
			log.Fatal(err)
		}
	}
	if err := tx.Commit(ctx); err != nil {
		log.Fatal(err)
	}
	log.Printf("%s: %s · %d stations · %d positions · %d races · status %s", *name, scopeLabel(sc, sk), len(stations), len(positions), len(races), *status)
}

// simulateDay writes the election day: opening, hourly turnout, incidents, closing and verified results.
func simulateDay(ctx context.Context, tx pgx.Tx, electionID, userID, seed string, day time.Time, stations []station,
	positions []position, races map[string][]contestant, completed bool) error {
	var turnout, events, subs, votes, incidents [][]any
	at := func(r *rand.Rand, hour, fromMin, toMin int) time.Time {
		return day.Add(time.Duration(hour)*time.Hour + time.Duration(fromMin+r.IntN(toMin-fromMin+1))*time.Minute)
	}
	statusRows := make([][]any, 0, len(stations))
	for _, st := range stations {
		r := rng(seed, "station", st.code)
		// Turnout varies by county, constituency and station.
		rate := 0.5 + 0.22*rng(seed, "county", st.county).Float64() + 0.08*(rng(seed, "const", st.constituency).Float64()-0.5) +
			0.06*r.NormFloat64()
		rate = math.Max(0.32, math.Min(0.91, rate))
		cast := int(math.Round(float64(st.registered) * rate))

		opened := at(r, 6, 0, 45)
		events = append(events, []any{electionID, st.code, "status", "Polls opened — status set to Open", userID, opened})
		var last time.Time
		for i, h := range slots {
			share := slotShare[i]
			if i < len(slots)-1 {
				share *= 1 + 0.08*r.NormFloat64()
			}
			cum := int(math.Round(float64(cast) * math.Min(1, share)))
			if i > 0 {
				prev := turnout[len(turnout)-1][3].(int)
				cum = max(cum, prev)
			}
			if i == len(slots)-1 {
				cum = cast
			}
			last = at(r, h, 5, 40)
			turnout = append(turnout, []any{electionID, st.code, h, cum, userID, last})
			pct := ""
			if st.registered > 0 {
				pct = fmt.Sprintf(" (%d%%)", int(math.Round(100*float64(cum)/float64(st.registered))))
			}
			events = append(events, []any{electionID, st.code, "turnout", fmt.Sprintf("Turnout recorded for %s — %d%s", slotLabel(h), cum, pct), userID, last})
		}
		if r.Float64() < 0.03 {
			typ := incidentTypes[r.IntN(len(incidentTypes))]
			reported := at(r, 8+r.IntN(8), 0, 50)
			resolved := reported.Add(time.Duration(20+r.IntN(100)) * time.Minute)
			note := "Handled by the presiding officer; voting continued."
			incidents = append(incidents, []any{electionID, st.code, typ, "Reported by the station agent.", userID, reported, resolved, userID, note})
			events = append(events,
				[]any{electionID, st.code, "incident", "Incident reported — " + typ + ". Reported by the station agent.", userID, reported},
				[]any{electionID, st.code, "resolved", "Resolved — " + typ + ". " + note, userID, resolved})
		}
		if !completed {
			statusRows = append(statusRows, []any{st.code, "reporting", last})
			continue
		}
		closed := at(r, 17, 0, 40)
		events = append(events, []any{electionID, st.code, "status", "Polls closed — awaiting verification", userID, closed})
		statusRows = append(statusRows, []any{st.code, "closed", closed})

		for _, pos := range positions {
			cs := races[pos.id+"|"+regionKey(st, pos.level)]
			// Its own stream per race, so a race's figures don't depend on which other seats are seeded.
			rr := rng(seed, "form", pos.name, regionKey(st, pos.level), st.code)
			rejected := int(math.Round(float64(cast) * (0.004 + 0.012*rr.Float64())))
			split := splitVotes(seed, pos.name+"|"+regionKey(st, pos.level), st, cs, cast-rejected)
			submitted := closed.Add(time.Duration(30+rr.IntN(200)) * time.Minute)
			if submitted.Hour() >= 22 {
				submitted = day.Add(21*time.Hour + time.Duration(rr.IntN(50))*time.Minute)
			}
			verified := submitted.Add(time.Duration(3+rr.IntN(25)) * time.Minute)
			subs = append(subs, []any{electionID, st.code, pos.id, rejected, userID, submitted, userID, verified})
			for i, c := range cs {
				votes = append(votes, []any{electionID, st.code, pos.id, c.id, split[i]})
			}
			events = append(events, []any{electionID, st.code, "results",
				fmt.Sprintf("Form 37A verified — %s · %d ballots", pos.name, cast), userID, verified})
		}
	}
	copyRows := func(table string, cols []string, rows [][]any) error {
		_, err := tx.CopyFrom(ctx, pgx.Identifier{table}, cols, pgx.CopyFromRows(rows))
		if err != nil {
			return fmt.Errorf("%s: %w", table, err)
		}
		return nil
	}
	if err := copyRows("turnout_reports", []string{"election_id", "station_code", "slot_hour", "cumulative", "recorded_by", "recorded_at"}, turnout); err != nil {
		return err
	}
	if err := copyRows("incidents", []string{"election_id", "station_code", "type", "description", "reported_by", "created_at", "resolved_at", "resolved_by", "resolution"}, incidents); err != nil {
		return err
	}
	if err := copyRows("result_submissions", []string{"election_id", "station_code", "position_id", "rejected", "submitted_by", "submitted_at", "verified_by", "verified_at"}, subs); err != nil {
		return err
	}
	if err := copyRows("result_votes", []string{"election_id", "station_code", "position_id", "candidate_id", "votes"}, votes); err != nil {
		return err
	}
	if err := copyRows("station_events", []string{"election_id", "station_code", "kind", "message", "user_id", "at"}, events); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `CREATE TEMP TABLE seed_status (code text, status station_status, at timestamptz) ON COMMIT DROP`); err != nil {
		return err
	}
	if err := copyRows("seed_status", []string{"code", "status", "at"}, statusRows); err != nil {
		return err
	}
	_, err := tx.Exec(ctx, `UPDATE election_stations es SET status = s.status, updated_at = s.at FROM seed_status s
		WHERE es.election_id = $1 AND es.station_code = s.code`, electionID)
	return err
}

// makeContestants invents 3–6 contestants for a race with distinct parties and an overall strength each.
func makeContestants(seed, race string, parties []string) []contestant {
	r := rng(seed, "race", race)
	n := 3 + r.IntN(4)
	order := r.Perm(len(parties))
	used := map[string]bool{}
	out := make([]contestant, n)
	for i := range out {
		var nm string
		for nm == "" || used[nm] {
			nm = firstNames[r.IntN(len(firstNames))] + " " + middleNames[r.IntN(len(middleNames))] + " " + lastNames[r.IntN(len(lastNames))]
		}
		used[nm] = true
		party := parties[order[i%len(order)]]
		if i == n-1 && r.Float64() < 0.3 {
			party = "IND"
		}
		// Two strong contenders, then a tail: most races are a two-horse contest.
		w := 0.15 + 0.5*r.Float64()
		if i < 2 {
			w = 1 + 0.6*r.Float64()
		}
		out[i] = contestant{name: nm, party: party, weight: w}
	}
	return out
}

// splitVotes shares valid votes among contestants, with local strongholds by constituency and ward.
func splitVotes(seed, race string, st station, cs []contestant, valid int) []int {
	w := make([]float64, len(cs))
	sum := 0.0
	for i, c := range cs {
		// Keyed by ballot position, not name: renaming a contestant (-ours) keeps the race's results.
		slot := fmt.Sprint(i)
		local := math.Exp(0.45*rng(seed, race, slot, st.constituency).NormFloat64() +
			0.25*rng(seed, race, slot, st.ward).NormFloat64() + 0.12*rng(seed, race, slot, st.code).NormFloat64())
		w[i] = c.weight * local
		sum += w[i]
	}
	out := make([]int, len(cs))
	type rem struct {
		i int
		f float64
	}
	var rems []rem
	given := 0
	for i := range w {
		exact := float64(valid) * w[i] / sum
		out[i] = int(exact)
		given += out[i]
		rems = append(rems, rem{i, exact - float64(out[i])})
	}
	sort.Slice(rems, func(a, b int) bool { return rems[a].f > rems[b].f })
	for k := 0; given < valid; k++ {
		out[rems[k%len(rems)].i]++
		given++
	}
	return out
}

func loadStations(ctx context.Context, pool *pgxpool.Pool, county, constituency string) ([]station, error) {
	rows, err := pool.Query(ctx, `
		SELECT code, county, constituency, ward, registered_voters FROM polling_stations
		WHERE ($1 = '' OR county = $1) AND ($2 = '' OR constituency = $2) ORDER BY code`, county, constituency)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(row pgx.CollectableRow) (station, error) {
		var s station
		return s, row.Scan(&s.code, &s.county, &s.constituency, &s.ward, &s.registered)
	})
}

// regionKey matches the API's race keys ("County / Constituency / Ward").
func regionKey(st station, level string) string {
	switch level {
	case "national":
		return "national"
	case "county":
		return st.county
	case "constituency":
		return st.county + " / " + st.constituency
	}
	return st.county + " / " + st.constituency + " / " + st.ward
}

func rng(parts ...string) *rand.Rand {
	h := fnv.New64a()
	h.Write([]byte(strings.Join(parts, "\x00")))
	s := h.Sum64()
	return rand.New(rand.NewPCG(s, s^0x9e3779b97f4a7c15))
}

func pick(flagVal string, boundary *string) string {
	if v := strings.TrimSpace(flagVal); v != "" {
		return v
	}
	if boundary != nil {
		return *boundary
	}
	return ""
}

func scopeLabel(county, constituency string) string {
	switch {
	case constituency != "":
		return constituency + " Constituency"
	case county != "":
		return county + " County"
	}
	return "All regions"
}

func slotLabel(h int) string {
	suffix := "AM"
	if h >= 12 {
		suffix = "PM"
	}
	if h%12 == 0 {
		return "12 " + suffix
	}
	return fmt.Sprintf("%d %s", h%12, suffix)
}

func sortedKeys(m map[string]bool) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

var nairobi = func() *time.Location {
	if loc, err := time.LoadLocation("Africa/Nairobi"); err == nil {
		return loc
	}
	return time.FixedZone("EAT", 3*60*60)
}()
