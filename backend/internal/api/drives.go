package api

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

type drive struct {
	ID           string  `json:"id"`
	Name         string  `json:"name"`
	County       *string `json:"county"`
	Constituency *string `json:"constituency"`
	Ward         *string `json:"ward"`
	Target       int     `json:"target"`
	TargetDate   *string `json:"target_date"`
	Active       bool    `json:"active"`
	Mobilized    int     `json:"mobilized"`
	Remaining    int     `json:"remaining"`
	Progress     float64 `json:"progress"` // 0..1
	Assigned     int     `json:"assigned"`
}

const driveSelect = `
	SELECT d.id, d.name, d.county, d.constituency, d.ward, d.target, to_char(d.target_date, 'YYYY-MM-DD'), d.active,
	       (SELECT count(*) FROM mobilizations m WHERE m.drive_id = d.id),
	       (SELECT count(*) FROM drive_assignments a WHERE a.drive_id = d.id)
	FROM drives d`

const visibleDrives = ` WHERE d.org_id = $1 AND ($3 OR EXISTS (
	SELECT 1 FROM drive_assignments a WHERE a.drive_id = d.id AND a.user_id = $2))`

func scanDrive(row pgx.Row) (drive, error) {
	var d drive
	err := row.Scan(&d.ID, &d.Name, &d.County, &d.Constituency, &d.Ward, &d.Target, &d.TargetDate, &d.Active,
		&d.Mobilized, &d.Assigned)
	d.Remaining = max(d.Target-d.Mobilized, 0)
	if d.Target > 0 {
		d.Progress = min(float64(d.Mobilized)/float64(d.Target), 1)
	}
	return d, err
}

func (s *Server) loadDrive(ctx context.Context, p *Principal, id string) (drive, error) {
	d, err := scanDrive(s.db.QueryRow(ctx, driveSelect+visibleDrives+` AND d.id::text = $4`, p.OrgID, p.UserID, p.SeesAll(), id))
	if errors.Is(err, pgx.ErrNoRows) {
		return d, errNotFound
	}
	return d, err
}

func (s *Server) listDrives(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	q := driveSelect + visibleDrives
	if r.URL.Query().Get("active") == "true" {
		q += ` AND d.active`
	}
	rows, err := s.db.Query(r.Context(), q+` ORDER BY d.active DESC, d.name`, p.OrgID, p.UserID, p.SeesAll())
	if err != nil {
		s.internal(w, r, err)
		return
	}
	items, err := collect(rows, scanDrive)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	var summary struct {
		ActiveRegions        int     `json:"active_regions"`
		Mobilized            int     `json:"mobilized"`
		Target               int     `json:"target"`
		BoundaryCounty       *string `json:"boundary_county"`
		BoundaryConstituency *string `json:"boundary_constituency"`
		OrgActive            bool    `json:"org_active"`
	}
	for _, d := range items {
		if d.Active {
			summary.ActiveRegions++
		}
		summary.Mobilized += d.Mobilized
		summary.Target += d.Target
	}
	if err := s.db.QueryRow(r.Context(), `SELECT boundary_county, boundary_constituency, active FROM organizations WHERE id=$1`, p.OrgID).
		Scan(&summary.BoundaryCounty, &summary.BoundaryConstituency, &summary.OrgActive); err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"summary": summary, "items": items})
}

type driveInput struct {
	Name         *string `json:"name"`
	County       *string `json:"county"`
	Constituency *string `json:"constituency"`
	Ward         *string `json:"ward"`
	Target       *int    `json:"target"`
	TargetDate   *string `json:"target_date"`
	Active       *bool   `json:"active"`
}

func (s *Server) createDrive(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireManager(w, p) {
		return
	}
	var in driveInput
	if !readJSON(w, r, &in) {
		return
	}
	if in.Name == nil || strings.TrimSpace(*in.Name) == "" {
		writeErr(w, http.StatusBadRequest, "name is required")
		return
	}
	if in.Target != nil && *in.Target < 0 {
		writeErr(w, http.StatusBadRequest, "target must be zero or more")
		return
	}
	var id string
	err := s.db.QueryRow(r.Context(), `
		INSERT INTO drives (org_id, name, county, constituency, ward, target, target_date)
		VALUES ($1,$2,$3,$4,$5,COALESCE($6,0),$7::date) RETURNING id`,
		p.OrgID, strings.TrimSpace(*in.Name), emptyNil(in.County), emptyNil(in.Constituency), emptyNil(in.Ward),
		in.Target, emptyNil(in.TargetDate)).Scan(&id)
	if isInvalidUUID(err) || isInvalidDate(err) {
		writeErr(w, http.StatusBadRequest, "target_date must be YYYY-MM-DD")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	d, err := s.loadDrive(r.Context(), p, id)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, d)
}

func (s *Server) getDrive(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	d, err := s.loadDrive(r.Context(), p, r.PathValue("id"))
	if errors.Is(err, errNotFound) {
		writeErr(w, http.StatusNotFound, "drive not found")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	rows, err := s.db.Query(r.Context(), `
		SELECT `+memberColsAs("u")+`
		FROM drive_assignments a JOIN users u ON u.id = a.user_id WHERE a.drive_id = $1 ORDER BY u.name`, d.ID)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	assigned, err := collect(rows, scanMember)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"drive": d, "assigned_users": assigned})
}

func (s *Server) updateDrive(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireManager(w, p) {
		return
	}
	var in driveInput
	if !readJSON(w, r, &in) {
		return
	}
	tag, err := s.db.Exec(r.Context(), `
		UPDATE drives SET name = COALESCE($3, name), county = COALESCE($4, county),
			constituency = COALESCE($5, constituency), ward = COALESCE($6, ward),
			target = COALESCE($7, target), target_date = COALESCE($8::date, target_date), active = COALESCE($9, active)
		WHERE id::text = $1 AND org_id = $2`,
		r.PathValue("id"), p.OrgID, in.Name, in.County, in.Constituency, in.Ward, in.Target, emptyNil(in.TargetDate), in.Active)
	if isInvalidDate(err) {
		writeErr(w, http.StatusBadRequest, "target_date must be YYYY-MM-DD")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if tag.RowsAffected() == 0 {
		writeErr(w, http.StatusNotFound, "drive not found")
		return
	}
	d, err := s.loadDrive(r.Context(), p, r.PathValue("id"))
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, d)
}

func (s *Server) setDriveAssignments(w http.ResponseWriter, r *http.Request, p *Principal) {
	s.replaceAssignments(w, r, p, "drives", "drive_assignments", "drive_id")
}

// ---- mobilizations ----

const statusAlreadyMobilized = "already_mobilized"

func (s *Server) priorMobilization(ctx context.Context, orgID, nid string) (*priorRecord, error) {
	var pr priorRecord
	err := s.db.QueryRow(ctx, `
		SELECT m.created_at, u.name, d.name FROM mobilizations m
		JOIN users u ON u.id = m.mobilized_by JOIN drives d ON d.id = m.drive_id
		WHERE m.org_id = $1 AND m.national_id = $2`, orgID, nid).Scan(&pr.At, &pr.By, &pr.Where)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	return &pr, err
}

func (s *Server) mobilizeLookup(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	nid := normalizeID(r.URL.Query().Get("national_id"))
	if nid == "" {
		writeErr(w, http.StatusBadRequest, "national_id is required")
		return
	}
	v, err := s.registerLookup(r.Context(), nid)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	prior, err := s.priorMobilization(r.Context(), p.OrgID, nid)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	status := statusReady
	if prior != nil {
		status = statusAlreadyMobilized
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": status, "voter": v, "in_register": v != nil, "previous": prior})
}

func (s *Server) createMobilization(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	if !p.OrgActive {
		writeErrCode(w, http.StatusForbidden, "org_inactive", "This organization is inactive")
		return
	}
	if !p.CanOperate() || !p.ModMobilization {
		writeErr(w, http.StatusForbidden, "you do not have mobilization access")
		return
	}
	var in struct {
		DriveID string `json:"drive_id"`
		personInput
	}
	if !readJSON(w, r, &in) {
		return
	}
	d, err := s.loadDrive(r.Context(), p, in.DriveID)
	if errors.Is(err, errNotFound) {
		writeErrCode(w, http.StatusForbidden, "not_assigned", "You are not assigned to this drive")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	if !d.Active {
		writeErrCode(w, http.StatusConflict, "drive_closed", "This drive is closed")
		return
	}
	if msg, err := s.resolvePerson(r.Context(), &in.personInput); err != nil {
		s.internal(w, r, err)
		return
	} else if msg != "" {
		writeErr(w, http.StatusBadRequest, msg)
		return
	}
	var id string
	var at time.Time
	err = s.db.QueryRow(r.Context(), `
		INSERT INTO mobilizations (org_id, drive_id, national_id, name, sex, dob, phone, county, constituency, ward, mobilized_by, created_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING id, created_at`,
		p.OrgID, d.ID, in.NationalID, in.Name, in.Sex, in.DOB, emptyNil(in.Phone), in.County, in.Constituency, in.Ward,
		p.UserID, recordedAt(r)).Scan(&id, &at)
	if isUniqueViolation(err) {
		prior, perr := s.priorMobilization(r.Context(), p.OrgID, in.NationalID)
		if perr != nil {
			s.internal(w, r, perr)
			return
		}
		writeJSON(w, http.StatusConflict, map[string]any{"error": "Already mobilized", "code": statusAlreadyMobilized, "previous": prior})
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"id": id, "created_at": at, "name": in.Name})
}

func (s *Server) listMobilizations(w http.ResponseWriter, r *http.Request, p *Principal) {
	if !requireOrg(w, p) {
		return
	}
	q := r.URL.Query()
	rows, err := s.db.Query(r.Context(), `
		SELECT m.id, m.national_id, m.name, m.sex, m.phone, m.county, m.constituency, m.ward,
		       m.created_at, u.name, d.id, d.name
		FROM mobilizations m JOIN users u ON u.id = m.mobilized_by JOIN drives d ON d.id = m.drive_id
		WHERE m.org_id = $1 AND ($2 OR m.mobilized_by = $3)
		  AND ($4::uuid IS NULL OR m.drive_id = $4::uuid)
		  AND ($5::text IS NULL OR m.name ILIKE $5 OR m.national_id LIKE $5)
		ORDER BY m.created_at DESC LIMIT $6`,
		p.OrgID, p.SeesAll(), p.UserID, nilIfEmpty(q.Get("drive_id")), likePattern(q.Get("q")), limitParam(q.Get("limit")))
	if err != nil {
		if isInvalidUUID(err) {
			writeErr(w, http.StatusBadRequest, "invalid drive_id")
			return
		}
		s.internal(w, r, err)
		return
	}
	out, err := collect(rows, func(row pgx.Row) (personRecord, error) {
		var pr personRecord
		err := row.Scan(&pr.ID, &pr.NationalID, &pr.Name, &pr.Sex, &pr.Phone, &pr.County, &pr.Constituency, &pr.Ward,
			&pr.At, &pr.By, &pr.GroupID, &pr.GroupName)
		return pr, err
	})
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}
