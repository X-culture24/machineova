-- Manager verification layer: results submitted by agents are pending until a manager (or
-- above) verifies them; only verified results count in tallies, replay and reports.
ALTER TABLE result_submissions
    ADD COLUMN verified_by UUID REFERENCES users(id),
    ADD COLUMN verified_at TIMESTAMPTZ;
-- Results entered before this change were entered by managers: treat them as verified.
UPDATE result_submissions SET verified_by = submitted_by, verified_at = submitted_at;
