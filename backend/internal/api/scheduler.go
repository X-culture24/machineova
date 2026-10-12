package api

import (
	"context"
	"fmt"
	"log/slog"
	"time"
)

// digestHour is when the daily turnout digest goes out (Africa/Nairobi).
const digestHour = 19

// RunScheduler sends the daily turnout digest to owners and admins of every organization
// with an active election, once a day after digestHour. It runs until ctx is cancelled.
func (s *Server) RunScheduler(ctx context.Context) {
	t := time.NewTicker(time.Minute)
	defer t.Stop()
	for {
		if now := time.Now().In(nairobi); now.Hour() >= digestHour {
			if n, err := s.SendDigests(ctx, now); err != nil {
				slog.Error("turnout digest", "err", err)
			} else if n > 0 {
				slog.Info("turnout digest sent", "emails", n)
			}
		}
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}

// SendDigests emails today's digest for organizations that haven't had one yet.
func (s *Server) SendDigests(ctx context.Context, now time.Time) (int, error) {
	day := now.In(nairobi).Format(time.DateOnly)
	rows, err := s.db.Query(ctx, `
		SELECT e.org_id, e.id, e.name FROM elections e
		JOIN organizations o ON o.id = e.org_id AND o.active
		WHERE e.status = 'active'
		  AND NOT EXISTS (SELECT 1 FROM digest_runs d WHERE d.org_id = e.org_id AND d.day = $1::date)`, day)
	if err != nil {
		return 0, err
	}
	type job struct{ org, election, name string }
	var jobs []job
	for rows.Next() {
		var j job
		if err := rows.Scan(&j.org, &j.election, &j.name); err != nil {
			rows.Close()
			return 0, err
		}
		jobs = append(jobs, j)
	}
	rows.Close()
	sent := 0
	for _, j := range jobs {
		// Claim the day first so a crash can't double-send.
		tag, err := s.db.Exec(ctx, `INSERT INTO digest_runs (org_id, day) VALUES ($1, $2::date) ON CONFLICT DO NOTHING`, j.org, day)
		if err != nil {
			return sent, err
		}
		if tag.RowsAffected() == 0 {
			continue
		}
		pct, err := s.electionTurnout(ctx, j.election)
		if err != nil {
			return sent, err
		}
		n, err := s.emailManagers(ctx, j.org, "turnout_digest", map[string]string{
			"election_name": j.name, "turnout_pct": pct, "sign_in_link": s.appURL + "/ops/turnout"})
		sent += n
		if err != nil {
			return sent, err
		}
	}
	return sent, nil
}

// electionTurnout is the latest cumulative turnout over registered voters, e.g. "57%".
func (s *Server) electionTurnout(ctx context.Context, electionID string) (string, error) {
	var cast, registered int64
	err := s.db.QueryRow(ctx, `
		SELECT coalesce((SELECT sum(t.cumulative) FROM (
		         SELECT DISTINCT ON (station_code) cumulative FROM turnout_reports
		         WHERE election_id = $1 ORDER BY station_code, slot_hour DESC) t), 0),
		       coalesce((SELECT sum(ps.registered_voters) FROM election_stations es
		         JOIN polling_stations ps ON ps.code = es.station_code WHERE es.election_id = $1), 0)`,
		electionID).Scan(&cast, &registered)
	if err != nil || registered == 0 {
		return "0%", err
	}
	return fmt.Sprintf("%d%%", cast*100/registered), nil
}

// emailManagers sends a template to every active owner and admin of an organization.
func (s *Server) emailManagers(ctx context.Context, orgID, template string, fields map[string]string) (int, error) {
	rows, err := s.db.Query(ctx, `SELECT id FROM users WHERE org_id = $1 AND active AND role IN ('owner','admin')`, orgID)
	if err != nil {
		return 0, err
	}
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return 0, err
		}
		ids = append(ids, id)
	}
	rows.Close()
	n := 0
	for _, id := range ids {
		rc, err := s.loadRecipient(ctx, id)
		if err != nil {
			return n, err
		}
		if err := s.sendTemplate(ctx, template, rc, fields); err != nil {
			slog.Error("email", "template", template, "err", err)
			continue
		}
		n++
	}
	return n, nil
}

// announceResults emails the provisional results link when an election is completed.
func (s *Server) announceResults(orgID, electionID string) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	var name string
	if err := s.db.QueryRow(ctx, `SELECT name FROM elections WHERE id = $1`, electionID).Scan(&name); err != nil {
		slog.Error("results announcement", "err", err)
		return
	}
	if _, err := s.emailManagers(ctx, orgID, "results_announcement", map[string]string{
		"election_name": name, "sign_in_link": s.appURL + "/ops/results"}); err != nil {
		slog.Error("results announcement", "err", err)
	}
}
