package api

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/machinenova/checkin/backend/internal/places"
)

// SDICS fallback: the SDICS database on the same server holds the national ID records
// (core_citizen, ~35M) and the voter register with polling centres (core_analytics_person
// → core_analytics_pc → core_analytics_ward, ~24M registered). MachineNova reads them over a
// separate read-only connection (SDICS_DATABASE_URL) instead of keeping its own copy. It is
// only asked when MachineNova's own register and ID records don't know the ID.

const sdicsLookupSQL = `
	SELECT c.full_name, c.sex, c.date_of_birth, c.county, c.district, c.division, c.location, c.sub_location, c.village,
	       p.full_name, p.reg_date, p.pc_id IS NOT NULL OR p.reg_date IS NOT NULL,
	       w.county, w.constituency, w.ward, pc.polling_centre
	FROM (SELECT 1) one
	LEFT JOIN LATERAL (SELECT * FROM core_citizen WHERE national_id = ANY($1) LIMIT 1) c ON true
	LEFT JOIN LATERAL (SELECT * FROM core_analytics_person WHERE national_id = ANY($1) LIMIT 1) p ON true
	LEFT JOIN core_analytics_pc pc ON pc.pc_id = p.pc_id
	LEFT JOIN core_analytics_ward w ON w.ward_id = pc.ward_id`

// sdicsKeys are the spellings an ID may be stored under: as typed (digits), without leading
// zeros, and zero-padded to 8 digits.
func sdicsKeys(nationalID string) []string {
	key := registryKey(nationalID)
	if key == "" {
		return nil
	}
	keys := []string{key}
	if padded := fmt.Sprintf("%08s", key); padded != key {
		keys = append(keys, padded)
	}
	if raw := digitsOnly(nationalID); raw != key && raw != fmt.Sprintf("%08s", key) {
		keys = append(keys, raw)
	}
	return keys
}

func digitsOnly(s string) string {
	b := make([]rune, 0, len(s))
	for _, r := range s {
		if r >= '0' && r <= '9' {
			b = append(b, r)
		}
	}
	return string(b)
}

// sdicsLookup returns the person from SDICS, or nil when SDICS isn't connected or doesn't
// know the ID. Registered voters come back as voter_register records with their polling
// area; everyone else in the ID records as id_registry records.
func (s *Server) sdicsLookup(ctx context.Context, nationalID string) (*voter, error) {
	keys := sdicsKeys(nationalID)
	if s.sdics == nil || len(keys) == 0 {
		return nil, nil
	}
	ctx, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()
	var cName, cSex *string
	var cDOB, regOn *time.Time
	var pName *string
	var registered *bool
	var wCounty, wConst, wWard, pcName *string
	h := homeArea{}
	err := s.sdics.QueryRow(ctx, sdicsLookupSQL, keys).Scan(
		&cName, &cSex, &cDOB, &h.County, &h.SubCounty, &h.Division, &h.Location, &h.SubLocation, &h.Village,
		&pName, &regOn, &registered, &wCounty, &wConst, &wWard, &pcName)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("sdics lookup: %w", err)
	}
	inID := cName != nil
	onRegister := registered != nil && *registered && wCounty != nil
	if !inID && !onRegister {
		return nil, nil
	}
	v := voter{NationalID: nationalID}
	switch {
	case cName != nil:
		v.Name = places.TitleCase(*cName)
	case pName != nil:
		v.Name = places.TitleCase(*pName)
	}
	if cSex != nil {
		v.Sex = sexLetter(*cSex)
	}
	if cDOB != nil {
		v.DOB = cDOB.Format(time.DateOnly)
		v.Age = ageOn(*cDOB, time.Now())
	}
	if inID {
		h.tidy()
		v.Home = &h
	}
	if onRegister {
		v.Source = sourceVoterRegister
		v.County = places.CountyName(*wCounty)
		v.Constituency = places.TitleCase(str(wConst))
		v.Ward = places.TitleCase(str(wWard))
		if pcName != nil {
			pc := places.TitleCase(*pcName)
			v.PollingCenter = &pc
		}
		if regOn != nil {
			d := regOn.Format(time.DateOnly)
			v.RegisteredOn = &d
		}
		return &v, nil
	}
	// In the ID records only: NRB county, sub-county and location stand in for the electoral
	// area, as for MachineNova's own ID records (region checks compare county only).
	v.Source = sourceIDRegistry
	v.County = str(h.County)
	v.Constituency = str(h.SubCounty)
	v.Ward = str(h.Location)
	return &v, nil
}

// sexLetter maps NRB/IEBC spellings (M, F, MALE, FEMALE) to M or F.
func sexLetter(s string) string {
	switch places.Key(s) {
	case "m", "male":
		return "M"
	case "f", "female":
		return "F"
	}
	return s
}
