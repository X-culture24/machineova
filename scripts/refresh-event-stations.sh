#!/usr/bin/env bash
# Run on the Checkin host after loading a new SDICS voter roll.
# Only station geography and aggregate counts are copied to Checkin.
set -euo pipefail

snapshot=$(mktemp)
trap 'rm -f "$snapshot"' EXIT

runuser -u postgres -- psql -X -d sdics_db -v ON_ERROR_STOP=1 >"$snapshot" <<'SQL'
COPY (
    WITH totals AS (
        SELECT pc_id, count(*) AS voters
        FROM core_analytics_person WHERE pc_id IS NOT NULL GROUP BY pc_id
    )
    SELECT 'sdics-' || p.pc_id, p.polling_centre, w.county, w.constituency, w.ward, coalesce(t.voters, 0)
    FROM core_analytics_pc p
    JOIN core_analytics_ward w ON w.ward_id = p.ward_id
    LEFT JOIN totals t ON t.pc_id = p.pc_id
) TO STDOUT WITH CSV;
SQL

. /opt/machinenova/.env
psql -X "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL
BEGIN;
CREATE TEMP TABLE station_import (LIKE sdics_station_roll INCLUDING ALL);
\copy station_import FROM '$snapshot' WITH CSV
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM station_import WHERE registered_voters > 0) THEN
        RAISE EXCEPTION 'SDICS station snapshot is empty';
    END IF;
END \$\$;
DELETE FROM sdics_station_roll WHERE code NOT IN (SELECT code FROM station_import);
INSERT INTO sdics_station_roll SELECT * FROM station_import
ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, county = EXCLUDED.county,
    constituency = EXCLUDED.constituency, ward = EXCLUDED.ward, registered_voters = EXCLUDED.registered_voters;
COMMIT;
SELECT count(*) AS stations, sum(registered_voters) AS voters FROM sdics_station_roll;
SQL
