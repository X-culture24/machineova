#!/usr/bin/env bash
# Let MachineNova look up IDs in the SDICS database on the same server, read-only.
#
#   ssh sdics 'bash -s' < scripts/enable-sdics-lookup.sh
#
# Creates the login machinenova_sdics_ro on sdics_db with SELECT on four tables only
# (core_citizen, core_analytics_person, core_analytics_pc, core_analytics_ward), every
# transaction read-only and an 8 s statement limit; adds SDICS_DATABASE_URL to
# /opt/machinenova/.env (backed up first) and restarts the API. Safe to run again.
#
# Chief training also reads:
#   - the SDICS county list, usajili_location_ref (bin/seed-sdics-training);
#   - for the training report: which chiefs SDICS has per county and when each first signed in to
#     the SDICS app (onboarding). Only these columns: core_officer (id, national_id, role, status,
#     created_at), core_officerassignedlocation (officer_id, county, created_at), field_officer_title
#     (officer_id, title), core_auditlog (user_id, action, created_at). No names, phones, PINs, IPs.
set -euo pipefail
ENV=/opt/machinenova/.env

grant_county_list() {
  sudo -u postgres psql -d sdics_db -v ON_ERROR_STOP=1 -q <<'SQL'
GRANT SELECT ON usajili_location_ref TO machinenova_sdics_ro;
REVOKE ALL ON core_officer, core_officerassignedlocation, field_officer_title, field_officer_sublocation, core_auditlog FROM machinenova_sdics_ro;
GRANT SELECT (id, national_id, role, status, created_at) ON core_officer TO machinenova_sdics_ro;
GRANT SELECT (officer_id, county, created_at) ON core_officerassignedlocation TO machinenova_sdics_ro;
GRANT SELECT (officer_id, title) ON field_officer_title TO machinenova_sdics_ro;
GRANT SELECT (user_id, action, created_at) ON core_auditlog TO machinenova_sdics_ro;
SQL
  echo "county list and training-report columns readable"
}

if grep -q '^SDICS_DATABASE_URL=' "$ENV"; then
  echo "SDICS_DATABASE_URL is already set in $ENV."
  grant_county_list
  exit 0
fi

PW=$(openssl rand -hex 24)
sudo -u postgres psql -d sdics_db -v ON_ERROR_STOP=1 -q -v pw="$PW" <<'SQL'
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'machinenova_sdics_ro') THEN
    CREATE ROLE machinenova_sdics_ro LOGIN CONNECTION LIMIT 10;
  END IF;
END $$;
ALTER ROLE machinenova_sdics_ro PASSWORD :'pw';
ALTER ROLE machinenova_sdics_ro SET default_transaction_read_only = on;
ALTER ROLE machinenova_sdics_ro SET statement_timeout = '8s';
GRANT CONNECT ON DATABASE sdics_db TO machinenova_sdics_ro;
GRANT USAGE ON SCHEMA public TO machinenova_sdics_ro;
GRANT SELECT ON core_citizen, core_analytics_person, core_analytics_pc, core_analytics_ward TO machinenova_sdics_ro;
SQL
grant_county_list

cp -p "$ENV" "$ENV.bak-$(date +%Y%m%d%H%M%S)"
echo "SDICS_DATABASE_URL=postgres://machinenova_sdics_ro:$PW@127.0.0.1:5432/sdics_db?sslmode=disable&pool_max_conns=4" >> "$ENV"

PGPASSWORD=$PW psql -h 127.0.0.1 -U machinenova_sdics_ro -d sdics_db -Atc 'SELECT count(*) FROM core_analytics_ward' >/dev/null
echo "read-only login works"

systemctl restart machinenova-api
for i in $(seq 1 20); do curl -fsS http://127.0.0.1:8081/healthz >/dev/null 2>&1 && break; sleep 1; done
journalctl -u machinenova-api --since '-1 min' --no-pager | grep -i -E 'sdics' | tail -2
echo "done"
