package api

import (
	"crypto/md5"
	"encoding/hex"
	"errors"
	"fmt"
	"net/http"
	"strings"

	"github.com/jackc/pgx/v5"

	"github.com/machinenova/checkin/backend/internal/places"
)

// The polling-station register is shared by every organization, so only platform admins
// (MachineNova staff) maintain it. Changes are audited like every other write.

type registerStation struct {
	Code         string `json:"code"`
	Name         string `json:"name"`
	County       string `json:"county"`
	Constituency string `json:"constituency"`
	Ward         string `json:"ward"`
	Registered   int    `json:"registered_voters"`
	Elections    int    `json:"elections"` // elections that include this station
	InUse        bool   `json:"in_use"`    // has election-day records: can't be deleted
}

// platformStations lists the register for one area (any of county, constituency, ward), with
// totals for the area so staff can check counts against the official figures.
func (s *Server) platformStations(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requirePlatform(w, p) {
		return
	}
	q := r.URL.Query()
	pg := pageParams(q.Get("page"), q.Get("page_size"))
	area := []any{emptyNil(ptr(q.Get("county"))), emptyNil(ptr(q.Get("constituency"))), emptyNil(ptr(q.Get("ward"))), likePattern(q.Get("q"))}
	const where = `($1::text IS NULL OR s.county = $1) AND ($2::text IS NULL OR s.constituency = $2) AND ($3::text IS NULL OR s.ward = $3)
		AND ($4::text IS NULL OR s.name ILIKE $4 OR s.code ILIKE $4)`
	var total, voters int
	if err := s.db.QueryRow(r.Context(), `SELECT count(*), COALESCE(sum(registered_voters), 0) FROM polling_stations s WHERE `+where, area...).
		Scan(&total, &voters); err != nil {
		s.internal(w, r, err)
		return
	}
	rows, err := s.db.Query(r.Context(), `
		SELECT s.code, s.name, s.county, s.constituency, s.ward, s.registered_voters,
		       (SELECT count(*) FROM election_stations es WHERE es.station_code = s.code),
		       `+stationInUseSQL+`
		FROM polling_stations s WHERE `+where+`
		ORDER BY s.county, s.constituency, s.ward, s.name LIMIT $5 OFFSET $6`, append(area, pg.size, pg.offset())...)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	items, err := collect(rows, func(row pgx.Row) (registerStation, error) {
		var st registerStation
		return st, row.Scan(&st.Code, &st.Name, &st.County, &st.Constituency, &st.Ward, &st.Registered, &st.Elections, &st.InUse)
	})
	if err != nil {
		s.internal(w, r, err)
		return
	}
	resp := pg.response(items, total)
	resp["registered_voters"] = voters
	writeJSON(w, http.StatusOK, resp)
}

// stationInUseSQL is true when a station has records that deleting it would destroy:
// it is part of a completed election, or has turnout, results, incidents or agents in any.
const stationInUseSQL = `(
	EXISTS (SELECT 1 FROM election_stations es JOIN elections e ON e.id = es.election_id WHERE es.station_code = s.code AND e.status = 'completed')
	OR EXISTS (SELECT 1 FROM turnout_reports t WHERE t.station_code = s.code)
	OR EXISTS (SELECT 1 FROM result_submissions rs WHERE rs.station_code = s.code)
	OR EXISTS (SELECT 1 FROM incidents i WHERE i.station_code = s.code)
	OR EXISTS (SELECT 1 FROM station_agents a WHERE a.station_code = s.code))`

type stationInput struct {
	Name         *string `json:"name"`
	County       *string `json:"county"`
	Constituency *string `json:"constituency"`
	Ward         *string `json:"ward"`
	Registered   *int    `json:"registered_voters"`
}

// platformCreateStation adds a station to the register and to every election that is not yet
// completed and whose scope covers it, so a new station is covered on election day.
func (s *Server) platformCreateStation(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requirePlatform(w, p) {
		return
	}
	var in stationInput
	if !readJSON(w, r, &in) {
		return
	}
	name, ward := trimmed(in.Name), trimmed(in.Ward)
	if name == "" || ward == "" || in.Registered == nil || *in.Registered < 0 {
		writeErr(w, http.StatusBadRequest, "name, ward and registered_voters (0 or more) are required")
		return
	}
	county, constituency, msg, err := s.registerBoundary(r.Context(), in.County, in.Constituency)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if msg == "" && (county == nil || constituency == nil) {
		msg = "county and constituency are required"
	}
	if msg != "" {
		writeErr(w, http.StatusBadRequest, msg)
		return
	}
	// Use the register's spelling of an existing ward; a new ward name is allowed (boundaries change).
	_ = s.db.QueryRow(r.Context(), `SELECT ward FROM polling_stations WHERE county=$1 AND constituency=$2 AND lower(ward)=lower($3) LIMIT 1`,
		*county, *constituency, ward).Scan(&ward)
	code := stationCode(*county, *constituency, ward, name)

	var added int64
	err = s.inTx(r.Context(), func(tx pgx.Tx) error {
		if _, err := tx.Exec(r.Context(), `INSERT INTO polling_stations (code, name, county, constituency, ward, registered_voters) VALUES ($1,$2,$3,$4,$5,$6)`,
			code, name, *county, *constituency, ward, *in.Registered); err != nil {
			return err
		}
		tag, err := tx.Exec(r.Context(), `
			INSERT INTO election_stations (election_id, station_code)
			SELECT e.id, $1 FROM elections e
			WHERE e.status <> 'completed' AND (e.scope_county IS NULL OR e.scope_county = $2)
			  AND (e.scope_constituency IS NULL OR e.scope_constituency = $3)`, code, *county, *constituency)
		added = tag.RowsAffected()
		return err
	})
	if isUniqueViolation(err) {
		writeErr(w, http.StatusConflict, "a station with this name is already in "+ward+" ward")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{
		"station":            registerStation{Code: code, Name: name, County: *county, Constituency: *constituency, Ward: ward, Registered: *in.Registered, Elections: int(added)},
		"added_to_elections": added,
	})
}

// platformUpdateStation edits a station's name, registered voters or ward. The code never changes,
// so elections, agents and results keep pointing at it. Moving it to another county or
// constituency is not allowed: delete and re-add instead (elections are scoped by those).
func (s *Server) platformUpdateStation(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requirePlatform(w, p) {
		return
	}
	var in stationInput
	if !readJSON(w, r, &in) {
		return
	}
	if in.Registered != nil && *in.Registered < 0 {
		writeErr(w, http.StatusBadRequest, "registered_voters can't be negative")
		return
	}
	if in.County != nil || in.Constituency != nil {
		writeErr(w, http.StatusBadRequest, "a station can't move to another county or constituency — delete it and add it there")
		return
	}
	if in.Name != nil && trimmed(in.Name) == "" || in.Ward != nil && trimmed(in.Ward) == "" {
		writeErr(w, http.StatusBadRequest, "name and ward can't be blank")
		return
	}
	var st registerStation
	err := s.db.QueryRow(r.Context(), `
		UPDATE polling_stations s SET name = COALESCE($2, name), ward = COALESCE($3, ward), registered_voters = COALESCE($4, registered_voters)
		WHERE code = $1
		RETURNING code, name, county, constituency, ward, registered_voters, (SELECT count(*) FROM election_stations es WHERE es.station_code = s.code), `+stationInUseSQL,
		r.PathValue("code"), emptyNil(ptr(trimmed(in.Name))), emptyNil(ptr(trimmed(in.Ward))), in.Registered).
		Scan(&st.Code, &st.Name, &st.County, &st.Constituency, &st.Ward, &st.Registered, &st.Elections, &st.InUse)
	if errors.Is(err, pgx.ErrNoRows) {
		writeErr(w, http.StatusNotFound, "station not found")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, st)
}

// platformDeleteStation removes a station that has no election-day history. It also leaves any
// draft or active election it was part of.
func (s *Server) platformDeleteStation(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requirePlatform(w, p) {
		return
	}
	code := r.PathValue("code")
	err := s.inTx(r.Context(), func(tx pgx.Tx) error {
		var inUse bool
		if err := tx.QueryRow(r.Context(), `SELECT `+stationInUseSQL+` FROM polling_stations s WHERE s.code = $1 FOR UPDATE`, code).Scan(&inUse); err != nil {
			return err
		}
		if inUse {
			return errStationInUse
		}
		if _, err := tx.Exec(r.Context(), `DELETE FROM election_stations WHERE station_code = $1`, code); err != nil {
			return err
		}
		_, err := tx.Exec(r.Context(), `DELETE FROM polling_stations WHERE code = $1`, code)
		return err
	})
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		writeErr(w, http.StatusNotFound, "station not found")
	case errors.Is(err, errStationInUse):
		writeErr(w, http.StatusConflict, "this station has election records (turnout, results, incidents, agents or a completed election) — edit it instead of deleting")
	case err != nil:
		s.internal(w, r, err)
	default:
		w.WriteHeader(http.StatusNoContent)
	}
}

var errStationInUse = errors.New("station in use")

// stationCode follows import-registry -from-register: the IEBC county number plus a fingerprint
// of the station, e.g. 047-3F9A21C0. Stations outside the 47 counties get 900.
func stationCode(county, constituency, ward, name string) string {
	n := 900
	for i, c := range places.Counties() {
		if strings.EqualFold(c, county) {
			n = i + 1
		}
	}
	sum := md5.Sum([]byte(constituency + "|" + ward + "|" + name))
	return fmt.Sprintf("%03d-%s", n, strings.ToUpper(hex.EncodeToString(sum[:])[:8]))
}

func trimmed(s *string) string {
	if s == nil {
		return ""
	}
	return strings.TrimSpace(*s)
}

func ptr(s string) *string { return &s }
