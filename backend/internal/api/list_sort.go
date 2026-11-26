package api

import (
	"cmp"
	"net/http"
	"net/url"
	"slices"
	"strings"
)

// orderParam reads ?sort= and ?dir= against a whitelist of SQL expressions,
// so nothing from the request reaches the SQL text. An empty sort keeps the
// list's own order (def). ok is false once a 400 has been written.
func orderParam(w http.ResponseWriter, q url.Values, cols map[string]string, def string) (string, bool) {
	key, dir := q.Get("sort"), strings.ToLower(q.Get("dir"))
	if dir != "" && dir != "asc" && dir != "desc" {
		writeErr(w, http.StatusBadRequest, "invalid sort")
		return "", false
	}
	if key == "" {
		return def, true
	}
	expr, known := cols[key]
	if !known {
		writeErr(w, http.StatusBadRequest, "invalid sort")
		return "", false
	}
	if dir == "" {
		dir = "asc"
	}
	return expr + " " + strings.ToUpper(dir) + " NULLS LAST, " + def, true
}

// stationSorts orders an election's stations in memory (they are loaded
// whole for the status counts).
var stationSorts = map[string]func(a, b stationRow) int{
	"name":       func(a, b stationRow) int { return cmp.Compare(strings.ToLower(a.Name), strings.ToLower(b.Name)) },
	"ward":       func(a, b stationRow) int { return cmp.Compare(strings.ToLower(a.Ward), strings.ToLower(b.Ward)) },
	"registered": func(a, b stationRow) int { return cmp.Compare(a.Registered, b.Registered) },
	"turnout": func(a, b stationRow) int {
		return cmp.Compare(deref(a.Turnout, -1), deref(b.Turnout, -1))
	},
	"agents": func(a, b stationRow) int { return cmp.Compare(a.Agents, b.Agents) },
	"status": func(a, b stationRow) int { return cmp.Compare(a.Status, b.Status) },
}

func sortStations(w http.ResponseWriter, q url.Values, rows []stationRow) bool {
	key, dir := q.Get("sort"), strings.ToLower(q.Get("dir"))
	if dir != "" && dir != "asc" && dir != "desc" {
		writeErr(w, http.StatusBadRequest, "invalid sort")
		return false
	}
	if key == "" {
		return true
	}
	by, known := stationSorts[key]
	if !known {
		writeErr(w, http.StatusBadRequest, "invalid sort")
		return false
	}
	slices.SortStableFunc(rows, func(a, b stationRow) int {
		if dir == "desc" {
			return by(b, a)
		}
		return by(a, b)
	})
	return true
}

func deref[T any](p *T, def T) T {
	if p == nil {
		return def
	}
	return *p
}
