package api

import (
	"errors"
	"math"
	"net/http"
	"sort"
	"strings"

	"github.com/jackc/pgx/v5"
)

// seatArea is one area of the seat in the previous election, from our candidate's point of view.
type seatArea struct {
	Name     string   `json:"name"`
	Leader   *leader  `json:"leader"`
	OurShare *float64 `json:"our_share"` // nil when our candidate did not stand last time
	Margin   *float64 `json:"margin"`    // our share minus the best rival's, percentage points
	Turnout  float64  `json:"turnout"`
}

type seatHistory struct {
	Election   election         `json:"election"`
	Position   position         `json:"position"`
	Region     *string          `json:"region"`
	Ours       candidate        `json:"ours"`      // our candidate in the live election
	OursThen   *candidateTotal  `json:"ours_then"` // the same person last time, if they stood
	Rank       int              `json:"rank"`      // 1 = won; 0 = did not stand
	Totals     []candidateTotal `json:"totals"`
	Turnout    float64          `json:"turnout"`
	ChildLevel string           `json:"child_level"`
	Areas      []seatArea       `json:"areas"`
}

// opsSeatHistory answers a candidate's first question: how did this seat go last time?
// For each of our candidates in the live election it finds the latest completed election of the
// organization with the same position and region, and returns that race's result by area.
func (s *Server) opsSeatHistory(w http.ResponseWriter, r *http.Request, p *Principal) {
	e, _, ok := s.opsContext(w, r, p)
	if !ok {
		return
	}
	ctx := r.Context()
	positions, err := s.loadPositions(ctx, e.ID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	cands, err := s.loadCandidates(ctx, e.ID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	posByID := map[string]position{}
	for _, ps := range positions {
		posByID[ps.ID] = ps
	}
	out := []seatHistory{}
	for _, ours := range cands {
		if !ours.IsOurs {
			continue
		}
		pos := posByID[ours.PositionID]
		var prevID, prevPos string
		err := s.db.QueryRow(ctx, `
			SELECT pe.id, pp.id FROM elections pe JOIN positions pp ON pp.election_id = pe.id
			WHERE pe.org_id = $1 AND pe.status = 'completed' AND pe.id <> $2 AND lower(pp.name) = lower($3)
			ORDER BY pe.election_date DESC LIMIT 1`, p.OrgID, e.ID, pos.Name).Scan(&prevID, &prevPos)
		if errors.Is(err, pgx.ErrNoRows) {
			continue
		}
		if err != nil {
			s.internal(w, r, err)
			return
		}
		prev, err := s.loadElection(ctx, p, prevID)
		if err != nil {
			s.internal(w, r, err)
			return
		}
		all, err := s.loadStations(ctx, prev.ID, prev.Scope)
		if err != nil {
			s.internal(w, r, err)
			return
		}
		// The seat's stations: every station for a national race, else those in our region.
		var seat []stationRow
		for i := range all {
			if pos.Level == "national" || ours.Region != nil && strings.EqualFold(regionKey(&all[i], pos.Level), *ours.Region) {
				seat = append(seat, all[i])
			}
		}
		if len(seat) == 0 {
			continue
		}
		tl, err := s.loadTally(ctx, prev.ID, prevPos, nil)
		if err != nil {
			s.internal(w, r, err)
			return
		}
		prevCands, err := s.loadCandidates(ctx, prev.ID)
		if err != nil {
			s.internal(w, r, err)
			return
		}
		cmap := candidateMap(prevCands)
		turnout, err := s.loadTurnout(ctx, prev.ID)
		if err != nil {
			s.internal(w, r, err)
			return
		}
		h := seatHistory{Election: prev, Position: pos, Region: ours.Region, Ours: ours, Totals: sumCandidates(tl, ptrs(seat), cmap)}
		cast, reg := turnoutOf(ptrs(seat), turnout, 23)
		h.Turnout = share(cast, reg)
		ourID := ""
		for i, t := range h.Totals {
			if strings.EqualFold(t.Candidate.Name, ours.Name) {
				tt := t
				h.OursThen, h.Rank, ourID = &tt, i+1, t.Candidate.ID
			}
		}
		h.ChildLevel = childOf(pos.Level)
		for _, g := range groupBy(seat, h.ChildLevel) {
			a := seatArea{Name: g.Name}
			c, rg := turnoutOf(g.Stations, turnout, 23)
			a.Turnout = share(c, rg)
			ranked := sumCandidates(tl, g.Stations, cmap)
			if len(ranked) > 0 {
				a.Leader = &leader{Candidate: ranked[0].Candidate, Share: ranked[0].Share}
			}
			if ourID != "" {
				var mine, rival float64
				for _, t := range ranked {
					if t.Candidate.ID == ourID {
						mine = t.Share
					} else if t.Share > rival {
						rival = t.Share
					}
				}
				m := math.Round((mine - rival) * 100)
				a.OurShare, a.Margin = &mine, &m
			}
			h.Areas = append(h.Areas, a)
		}
		// Strongest first when our candidate stood; otherwise by name (groupBy's order).
		if ourID != "" {
			sort.SliceStable(h.Areas, func(i, j int) bool { return *h.Areas[i].Margin > *h.Areas[j].Margin })
		}
		out = append(out, h)
	}
	writeJSON(w, http.StatusOK, out)
}

// childOf is the level a seat's results break down into.
func childOf(level string) string {
	switch level {
	case "national":
		return "county"
	case "county":
		return "constituency"
	case "constituency":
		return "ward"
	}
	return "station"
}
