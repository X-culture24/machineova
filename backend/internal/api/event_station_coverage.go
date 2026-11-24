package api

import (
	"context"
	"errors"
	"net/http"

	"github.com/jackc/pgx/v5"
)

func (e event) coverageArea() (county, constituency, ward *string) {
	switch str(e.CoverageLevel) {
	case "national":
		return nil, nil, nil
	case "county":
		return e.County, nil, nil
	case "constituency":
		return e.County, e.Constituency, nil
	default:
		return e.County, e.Constituency, e.Ward
	}
}

type stationCoverage struct {
	Code         string `json:"code"`
	Name         string `json:"name"`
	County       string `json:"county"`
	Constituency string `json:"constituency"`
	Ward         string `json:"ward"`
	Registered   int    `json:"registered"`
	Reached      int    `json:"reached"`
}

func (s *Server) eventRollSource(ctx context.Context) (string, error) {
	var ready bool
	err := s.db.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM sdics_station_roll)`).Scan(&ready)
	if ready {
		return "sdics_station_roll", err
	}
	return "polling_stations", err
}

func (s *Server) eventStationCoverage(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	e, err := s.loadEvent(r.Context(), p, r.PathValue("id"))
	if errors.Is(err, errNotFound) {
		writeErr(w, http.StatusNotFound, "event not found")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	county, constituency, ward := e.coverageArea()
	items, _, err := s.eventCoverageStations(r.Context(), e.ID, p.OrgID, county, constituency, ward)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, items)
}

func (s *Server) eventCoverageStations(ctx context.Context, eventID, orgID string, county, constituency, ward *string) ([]stationCoverage, *int, error) {
	source, err := s.eventRollSource(ctx)
	if err != nil {
		return nil, nil, err
	}
	if source == "sdics_station_roll" {
		reached, notRegistered, err := s.sdicsEventReach(ctx, eventID, orgID)
		if err != nil {
			return nil, nil, err
		}
		rows, err := s.db.Query(ctx, `
			SELECT code, name, county, constituency, ward, registered_voters
			FROM sdics_station_roll
			WHERE ($1::text IS NULL OR place_key(county) = place_key($1))
			  AND ($2::text IS NULL OR place_key(constituency) = place_key($2))
			  AND ($3::text IS NULL OR place_key(ward) = place_key($3))
			ORDER BY county, constituency, ward, name, code`, county, constituency, ward)
		if err != nil {
			return nil, nil, err
		}
		items, err := collect(rows, func(row pgx.Row) (stationCoverage, error) {
			var st stationCoverage
			err := row.Scan(&st.Code, &st.Name, &st.County, &st.Constituency, &st.Ward, &st.Registered)
			st.Reached = reached[st.Code]
			return st, err
		})
		return items, &notRegistered, err
	}

	rows, err := s.db.Query(ctx, `
		WITH reached AS (
			SELECT v.county, v.constituency, v.ward, v.polling_center, count(DISTINCT c.national_id)::int total
			FROM checkins c JOIN register_voters v ON v.national_id = c.national_id
			WHERE c.event_id = $1 AND c.org_id = $2
			GROUP BY 1, 2, 3, 4
		)
		SELECT p.code, p.name, p.county, p.constituency, p.ward, p.registered_voters, COALESCE(r.total, 0)
		FROM polling_stations p LEFT JOIN reached r ON r.county = p.county
		  AND r.constituency = p.constituency AND r.ward = p.ward AND r.polling_center = p.name
		WHERE ($3::text IS NULL OR place_key(p.county) = place_key($3))
		  AND ($4::text IS NULL OR place_key(p.constituency) = place_key($4))
		  AND ($5::text IS NULL OR place_key(p.ward) = place_key($5))
		ORDER BY p.county, p.constituency, p.ward, p.name, p.code`, eventID, orgID, county, constituency, ward)
	if err != nil {
		return nil, nil, err
	}
	items, err := collect(rows, func(row pgx.Row) (stationCoverage, error) {
		var st stationCoverage
		err := row.Scan(&st.Code, &st.Name, &st.County, &st.Constituency, &st.Ward, &st.Registered, &st.Reached)
		return st, err
	})
	return items, nil, err
}

func (s *Server) sdicsEventReach(ctx context.Context, eventID, orgID string) (map[string]int, int, error) {
	rows, err := s.db.Query(ctx, `SELECT DISTINCT national_id FROM checkins WHERE event_id = $1 AND org_id = $2`, eventID, orgID)
	if err != nil {
		return nil, 0, err
	}
	ids, err := collect(rows, func(row pgx.Row) (string, error) {
		var id string
		err := row.Scan(&id)
		return id, err
	})
	if err != nil {
		return nil, 0, err
	}
	reached := map[string]int{}
	if len(ids) == 0 {
		return reached, 0, nil
	}
	if s.sdics == nil {
		return nil, 0, errors.New("SDICS voter register is unavailable")
	}
	unique := map[string]bool{}
	var groups, keys []string
	for _, id := range ids {
		group := registryKey(id)
		if unique[group] {
			continue
		}
		unique[group] = true
		for _, key := range sdicsKeys(id) {
			groups, keys = append(groups, group), append(keys, key)
		}
	}
	matched := map[string]bool{}
	// Batched indexed ID lookups avoid scanning the voter roll or copying it into Checkin.
	const batch = 1000
	for start := 0; start < len(keys); start += batch {
		end := min(start+batch, len(keys))
		matches, err := s.sdics.Query(ctx, `
			SELECT inputs.id, 'sdics-' || p.pc_id
			FROM unnest($1::text[], $2::text[]) AS inputs(id, lookup)
			JOIN core_analytics_person p ON p.national_id = inputs.lookup AND p.pc_id IS NOT NULL
			ORDER BY inputs.id, (p.national_id = inputs.id) DESC, p.national_id`, groups[start:end], keys[start:end])
		if err != nil {
			return nil, 0, err
		}
		for matches.Next() {
			var id, code string
			if err := matches.Scan(&id, &code); err != nil {
				matches.Close()
				return nil, 0, err
			}
			if !matched[id] {
				matched[id] = true
				reached[code]++
			}
		}
		if err := matches.Err(); err != nil {
			return nil, 0, err
		}
	}
	return reached, len(unique) - len(matched), nil
}
