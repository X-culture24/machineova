package api

import (
	"encoding/csv"
	"errors"
	"fmt"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// ---- reports ----

// opsReport streams one of the four exports as CSV, scoped to the principal's area.
func (s *Server) opsReport(w http.ResponseWriter, r *http.Request, p *Principal) {
	e, sc, ok := s.opsContext(w, r, p)
	if !ok {
		return
	}
	kind := r.PathValue("kind")
	ctx := r.Context()
	stations, err := s.loadStations(ctx, e.ID, sc)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	var header []string
	var rows [][]string
	pct := func(f float64) string { return strconv.Itoa(int(f*100+0.5)) + "%" }

	switch kind {
	case "coverage":
		header = []string{"code", "station", "county", "constituency", "ward", "registered", "status", "agents", "agent_names", "agent_phones", "managers"}
		agents := map[string][2][]string{}
		rs, err := s.db.Query(ctx, `SELECT a.station_code, u.name, COALESCE(u.phone, '') FROM station_agents a JOIN users u ON u.id = a.user_id
			WHERE a.election_id=$1 ORDER BY u.name`, e.ID)
		if err != nil {
			s.internal(w, r, err)
			return
		}
		for rs.Next() {
			var code, name, phone string
			if err := rs.Scan(&code, &name, &phone); err != nil {
				s.internal(w, r, err)
				return
			}
			a := agents[code]
			a[0], a[1] = append(a[0], name), append(a[1], phone)
			agents[code] = a
		}
		managers := map[string][]string{}
		rs, err = s.db.Query(ctx, `SELECT scope_constituency || '/' || scope_ward, name || ' ' || COALESCE(phone, '') FROM users
			WHERE org_id=$1 AND role='manager' AND active AND scope_ward IS NOT NULL`, p.OrgID)
		if err != nil {
			s.internal(w, r, err)
			return
		}
		for rs.Next() {
			var key, m string
			if err := rs.Scan(&key, &m); err != nil {
				s.internal(w, r, err)
				return
			}
			managers[key] = append(managers[key], m)
		}
		for _, st := range stations {
			a := agents[st.Code]
			rows = append(rows, []string{st.Code, st.Name, st.County, st.Constituency, st.Ward, strconv.Itoa(st.Registered),
				statusLabels[st.Status], strconv.Itoa(st.Agents), strings.Join(a[0], "; "), strings.Join(a[1], "; "),
				strings.Join(managers[st.Constituency+"/"+st.Ward], "; ")})
		}
	case "turnout":
		t, err := s.loadTurnout(ctx, e.ID)
		if err != nil {
			s.internal(w, r, err)
			return
		}
		header = []string{"level", "region", "registered"}
		for _, h := range turnoutSlots {
			header = append(header, slotLabel(h))
		}
		emit := func(level string, groups []group) {
			for _, g := range groups {
				_, reg := turnoutOf(g.Stations, t, 23)
				row := []string{level, g.Name, strconv.Itoa(reg)}
				for _, h := range turnoutSlots {
					c, rg := turnoutOf(g.Stations, t, h)
					row = append(row, pct(share(c, rg)))
				}
				rows = append(rows, row)
			}
		}
		emit("constituency", groupBy(stations, "constituency"))
		emit("ward", groupBy(stations, "ward"))
		emit("station", groupBy(stations, "station"))
	case "results":
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
		cmap := candidateMap(cands)
		header = []string{"position", "code", "station", "ward", "constituency", "verified", "candidate", "party", "votes"}
		for _, pos := range positions {
			tl, err := s.loadTally(ctx, e.ID, pos.ID, nil)
			if err != nil {
				s.internal(w, r, err)
				return
			}
			for _, st := range stations {
				if !tl.submitted[st.Code] {
					rows = append(rows, []string{pos.Name, st.Code, st.Name, st.Ward, st.Constituency, "no", "", "", ""})
					continue
				}
				for cid, v := range tl.votes[st.Code] {
					c := cmap[cid]
					party := ""
					if c.PartyCode != nil {
						party = *c.PartyCode
					}
					rows = append(rows, []string{pos.Name, st.Code, st.Name, st.Ward, st.Constituency, "yes", c.Name, party, strconv.Itoa(v)})
				}
			}
		}
	case "incidents":
		header = []string{"reported_at", "code", "station", "ward", "type", "description", "reported_by", "resolved_at", "resolution"}
		inScope := map[string]stationRow{}
		for _, st := range stations {
			inScope[st.Code] = st
		}
		rs, err := s.db.Query(ctx, `
			SELECT i.station_code, i.created_at, i.type, i.description, u.name, i.resolved_at, COALESCE(i.resolution, '')
			FROM incidents i JOIN users u ON u.id = i.reported_by WHERE i.election_id=$1 ORDER BY i.created_at`, e.ID)
		if err != nil {
			s.internal(w, r, err)
			return
		}
		for rs.Next() {
			var code, typ, desc, by, res string
			var at time.Time
			var resolved *time.Time
			if err := rs.Scan(&code, &at, &typ, &desc, &by, &resolved, &res); err != nil {
				s.internal(w, r, err)
				return
			}
			st, ok := inScope[code]
			if !ok {
				continue
			}
			resAt := ""
			if resolved != nil {
				resAt = resolved.In(nairobi).Format(time.DateTime)
			}
			rows = append(rows, []string{at.In(nairobi).Format(time.DateTime), code, st.Name, st.Ward, typ, desc, by, resAt, res})
		}
	default:
		writeErr(w, http.StatusNotFound, "unknown report")
		return
	}
	w.Header().Set("Content-Type", "text/csv; charset=utf-8")
	w.Header().Set("Content-Disposition", fmt.Sprintf(`attachment; filename="%s-%s.csv"`, strings.ToLower(e.Code), kind))
	cw := csv.NewWriter(w)
	cw.Write(header)
	cw.WriteAll(rows)
}

// ---- settings (white-label branding, owner only) ----

var hexColor = regexp.MustCompile(`^#[0-9A-Fa-f]{6}$`)

func (s *Server) getSettings(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	var out struct {
		Name         string  `json:"name"`
		AccentColor  string  `json:"accent_color"`
		ContactEmail *string `json:"contact_email"`
		Boundary     scope   `json:"boundary"`
	}
	if err := s.db.QueryRow(r.Context(), `SELECT name, accent_color, contact_email, boundary_county, boundary_constituency
		FROM organizations WHERE id=$1`, p.OrgID).Scan(&out.Name, &out.AccentColor, &out.ContactEmail, &out.Boundary.County, &out.Boundary.Constituency); err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) updateSettings(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	if p.Role != "owner" {
		writeErr(w, http.StatusForbidden, "only the owner can change branding")
		return
	}
	var in struct {
		Name         *string `json:"name"`
		AccentColor  *string `json:"accent_color"`
		ContactEmail *string `json:"contact_email"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	if in.AccentColor != nil && !hexColor.MatchString(*in.AccentColor) {
		writeErr(w, http.StatusBadRequest, "accent color must be a hex value like #0D9488")
		return
	}
	if _, err := s.db.Exec(r.Context(), `UPDATE organizations SET name=COALESCE($2,name), accent_color=COALESCE($3,accent_color),
		contact_email=COALESCE($4,contact_email) WHERE id=$1`, p.OrgID, emptyNil(in.Name), in.AccentColor, emptyNil(in.ContactEmail)); err != nil {
		s.internal(w, r, err)
		return
	}
	s.getSettings(w, r, p)
}

// ---- platform console additions ----

func (s *Server) platformOverview(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requirePlatform(w, p) {
		return
	}
	var out struct {
		Organizations int `json:"organizations"`
		Active        int `json:"active"`
		Trial         int `json:"trial"`
		Members       int `json:"members"`
		Stations      int `json:"stations"`
		Agents        int `json:"agents"`
	}
	if err := s.db.QueryRow(r.Context(), `
		SELECT (SELECT count(*) FROM organizations),
		       (SELECT count(*) FROM organizations WHERE active AND NOT trial),
		       (SELECT count(*) FROM organizations WHERE active AND trial),
		       (SELECT count(*) FROM users WHERE org_id IS NOT NULL),
		       (SELECT count(DISTINCT es.station_code) FROM election_stations es JOIN elections e ON e.id = es.election_id AND e.status = 'active'),
		       (SELECT count(*) FROM users WHERE role = 'agent')`).
		Scan(&out.Organizations, &out.Active, &out.Trial, &out.Members, &out.Stations, &out.Agents); err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) platformGetOrg(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requirePlatform(w, p) {
		return
	}
	o, err := scanOrgSummary(s.db.QueryRow(r.Context(), orgSummarySQL+` WHERE o.id::text=$1`, r.PathValue("id")))
	if errors.Is(err, pgx.ErrNoRows) {
		writeErr(w, http.StatusNotFound, "organization not found")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	var extra struct {
		AccentColor  string  `json:"accent_color"`
		ContactEmail *string `json:"contact_email"`
		Trial        bool    `json:"trial"`
		Stations     int     `json:"stations"`
		Agents       int     `json:"agents"`
	}
	if err := s.db.QueryRow(r.Context(), `
		SELECT o.accent_color, o.contact_email, o.trial,
		       (SELECT count(*) FROM election_stations es JOIN elections e ON e.id = es.election_id WHERE e.org_id = o.id AND e.status='active'),
		       (SELECT count(*) FROM users u WHERE u.org_id = o.id AND u.role = 'agent')
		FROM organizations o WHERE o.id = $1`, o.ID).Scan(&extra.AccentColor, &extra.ContactEmail, &extra.Trial, &extra.Stations, &extra.Agents); err != nil {
		s.internal(w, r, err)
		return
	}
	rows, err := s.db.Query(r.Context(), `SELECT `+memberCols+` FROM users WHERE org_id=$1 AND role IN ('owner','admin') ORDER BY role, name`, o.ID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	admins, err := collect(rows, scanMember)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"organization": o, "details": extra, "admins": admins})
}

func (s *Server) platformDeleteOrg(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requirePlatform(w, p) {
		return
	}
	var in struct {
		ConfirmName string `json:"confirm_name"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	tag, err := s.db.Exec(r.Context(), `DELETE FROM organizations WHERE id::text=$1 AND name=$2`, r.PathValue("id"), in.ConfirmName)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if tag.RowsAffected() == 0 {
		writeErr(w, http.StatusBadRequest, "type the organization's exact name to confirm deletion")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type emailTemplate struct {
	Key       string    `json:"key"`
	Name      string    `json:"name"`
	Purpose   string    `json:"purpose"`
	Subject   string    `json:"subject"`
	Body      string    `json:"body"`
	UpdatedAt time.Time `json:"updated_at"`
}

var mergeFields = []string{"{{org_name}}", "{{election_name}}", "{{recipient_name}}", "{{turnout_pct}}", "{{sign_in_link}}"}

func (s *Server) platformTemplates(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requirePlatform(w, p) {
		return
	}
	rows, err := s.db.Query(r.Context(), `SELECT key, name, purpose, subject, body, updated_at FROM email_templates ORDER BY name`)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	out, err := collect(rows, func(row pgx.Row) (emailTemplate, error) {
		var t emailTemplate
		return t, row.Scan(&t.Key, &t.Name, &t.Purpose, &t.Subject, &t.Body, &t.UpdatedAt)
	})
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"templates": out, "merge_fields": mergeFields})
}

var mergeFieldRe = regexp.MustCompile(`\{\{\s*([a-z_]+)\s*\}\}`)

func (s *Server) platformSaveTemplate(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requirePlatform(w, p) {
		return
	}
	var in struct {
		Subject string `json:"subject"`
		Body    string `json:"body"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	if strings.TrimSpace(in.Subject) == "" || strings.TrimSpace(in.Body) == "" {
		writeErr(w, http.StatusBadRequest, "subject and body are required")
		return
	}
	known := map[string]bool{}
	for _, f := range mergeFields {
		known[strings.Trim(f, "{}")] = true
	}
	for _, m := range mergeFieldRe.FindAllStringSubmatch(in.Subject+in.Body, -1) {
		if !known[m[1]] {
			writeErr(w, http.StatusBadRequest, "unknown merge field {{"+m[1]+"}}")
			return
		}
	}
	tag, err := s.db.Exec(r.Context(), `UPDATE email_templates SET subject=$2, body=$3, updated_at=now() WHERE key=$1`,
		r.PathValue("key"), in.Subject, in.Body)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if tag.RowsAffected() == 0 {
		writeErr(w, http.StatusNotFound, "template not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
