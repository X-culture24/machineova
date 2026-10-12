# Checkin & Election Ops — MachineNova

One platform, two workspaces:

- **Checkin**: voter mobilization and event check-in, from the field training manuals.
- **Election Ops**: election-day operations (stations, agents, turnout, incidents, Form 37A results), from *Election Ops Redesign — Screens*.

| Part | Stack | Folder |
|---|---|---|
| API | Go 1.24+ · `net/http` · PostgreSQL (pgx) · JWT | `backend/` |
| Web dashboard | TypeScript · React 18 · Vite | `dashboard/` |
| Field app | Flutter (Android first, iOS ready) | `mobile/` |

Mobile field roles (Manager, Agent, Chief Agent) get the Election Ops field app; Checkin roles get the check-in/mobilize app.

The backend is the single source of truth. The dashboard and the mobile app both talk to the same `/api`.

## Quick start

```bash
# 1. Database (Postgres.app or any local Postgres)
createdb checkin

# 2. API on :8080. Migrations run automatically on start.
make api

# 3. First login: a MachineNova platform admin
make bootstrap EMAIL=you@machinenova.co.ke PASSWORD='choose-a-strong-one'

# 4. Load the real reference data (CSV formats below)
make import-register FILE=/path/to/register.csv                       # voters (Checkin)
make import-registry STATIONS=/path/to/stations.csv PARTIES=/path/to/parties.csv   # stations + parties (Election Ops)

# 5. Dashboard on http://localhost:5173
make dashboard

# 6. Field app (first time only: ./mobile/setup.sh generates android/ & ios/)
cd mobile && ./setup.sh && flutter run --dart-define=API_URL=http://10.0.2.2:8080
```

Then sign in to the dashboard as the platform admin, go to **Organizations → New organization** and create the org with its owner. The owner signs in, adds the team, creates events and drives, and assigns people to them.

### Configuration (API)

| Env var | Default | Notes |
|---|---|---|
| `DATABASE_URL` | `postgres://postgres@localhost:5432/checkin?sslmode=disable` | |
| `ADDR` | `:8080` | |
| `JWT_SECRET` | dev-only fallback | **Required** when `APP_ENV` ≠ `dev` |
| `CORS_ORIGINS` | `http://localhost:5173` | Comma-separated |

### Voter register CSV — registration status and polling area

The voter register decides **Registered voter** vs **Not registered to vote**, and gives each
registered voter's county, constituency, ward, polling centre and registration date.

```sh
make import-register FILE="~/Documents/sdics.tech/registred voters2026-10-06.csv"   # SDICS export
make import-register FILE=register.csv                                              # original format
```

Accepted columns (any order, extra columns ignored and never stored):
`national_id|ID|IDNO, name|FULLNAME, sex|SEX, dob|DATE_BIRTH, county|County, constituency,
ward|Ward, polling_center|Polling Center, registered_on|date_of_registration`.
Dates may be `YYYY-MM-DD`, `YYYYMMDD` or a timestamp. Name, sex and DOB are optional — some
registered voters in the SDICS export carry only ID and area; lookup fills their identity from
the national ID records when it can, otherwise the app asks the operator. The file is streamed
(25M rows in ~10 min), de-duplicated by ID (latest registration wins) and swapped in atomically;
a reload replaces the whole register. Windows-1252 characters in names are converted to UTF-8.
Parents' names, tribe, clan, family and phone numbers in the export are not loaded.

### National ID records (NRB extracts) — ID lookup fallback

When an ID is not on the voter register, lookup falls back to `id_registry` (person shown as
**Not registered to vote**, identity from national ID records), loaded from the
NRB extracts in `datasets/` (git-ignored — personal data, never commit):

```sh
make import-idregistry                       # all datasets/*.csv
make import-idregistry FILES="a.csv b.csv"   # specific files; earlier files win on duplicate IDs
```

Expected columns: `IDNO, FULLNAME, DATE_BIRTH (YYYYMMDD), SEX, COUNTY, SUBCOUNTY, DIVISION,
LOCATION, SUBLOCATION, VILLAGE`. Tens of millions of rows stream through an unlogged staging
table and are swapped in atomically, so lookups keep working during a reload. Parents' names,
tribe, clan and family columns in the extracts are deliberately not loaded.

How lookup behaves for these records:

- `in_register: true` (identity found — clients skip manual entry), `registered_voter: false`,
  `voter.source: "id_registry"`; the apps show **ID verified · Not on voter register**.
- IDs match ignoring spaces and leading zeros.
- NRB has no electoral geography: check-ins store county, with sub-county and location in the
  constituency and ward fields; in/out-of-region for these records compares **county only**.

`make e2e-idlookup` runs an end-to-end lookup → check-in → duplicate → mobilize test against the
loaded database (it creates a throwaway org and prints no personal data).

### Polling stations & parties CSV (Election Ops registry)

```
code,name,county,constituency,ward,registered_voters
MGR-001,Kakrao Primary School,Migori,Suna East,Kakrao,612
```
```
code,name,colour
UA,Umoja Alliance,#0F8A7A
```

The registry is statutory and read-only in the app. Re-importing updates rows by `code`. County, constituency and ward names must match the organization boundaries exactly.

## Election Ops

**Roles and scope.** Every person has a role and a geographic area, and sees only that area:

| Role | Area | Can |
|---|---|---|
| Owner | whole org | everything, including branding |
| Executive | whole org | read-only monitoring |
| Admin | constituency | set up elections, positions and candidates; add chief agents, managers and agents; operate stations |
| Chief Agent | constituency | add managers and agents; operate stations |
| Manager | ward | add agents; operate stations; resolve incidents |
| Agent | ward (+ one station) | update **only their assigned station** |

People can only add roles below their own, inside their own area. Agents can be directory-only contacts, or given an email and password to sign in.

**Flow.**
1. *Set up › Election* runs a wizard: details, scope, positions, review. Positions define the regions: picking MP creates a race in every constituency, picking MCA one in every ward. Positions above the scope are out of play.
2. Activate the election. Only one is active at a time, and it scopes every screen.
3. Add candidates per race. This works even while the election is live. Mark yours with ★.
4. *Directory*: add people with role and cascading scope, and optionally a station.
5. *Polling stations*: status chips, filters, search, bulk status. The station drawer has the quick actions: **Update status**, **Assign agent** (from the ward pool), **Record turnout** (cumulative per slot, can't go down, can't exceed registered), **Report incident** (flags the station as Issue instantly; managers resolve), and **Submit & verify results** (Form 37A per candidate, confirm checkbox, checked against registered voters).
6. *Monitor*:
   - Overview: what needs you now.
   - Voter turnout: drill-down with "Push GOTV / Behind + low turnout / Opponent ahead" signals, based on the race where you field a candidate, plus an hourly rollup.
   - Results: provisional tallies per position with region drill-down.
   - Replay: scrub or play any election hour by hour.
7. *Reports*: CSV export, or print to PDF, for coverage, turnout, results and incidents, all scoped to the viewer.
8. *Settings*: owner-only white-label accent colour, applied live.

**Platform console** (MachineNova operators):
- Overview across tenants
- New-organization wizard: boundary, branding, first admin
- Organization detail with active/trial toggles and delete (type the name to confirm)
- Email template library with validated merge fields

**Field app.** Field roles get the Election Ops app: Home, Stations, Agents and Account, with station records and quick-edit bottom sheets, plus call or WhatsApp from any agent. Owners and admins switch workspace under Account.

**Testing.** `make e2e DATABASE_URL=postgres://…/throwaway_db` loads `backend/testdata/sample_*.csv` (sample data only) and runs ~60 checks across every role and rule.

## What's built (Checkin)

**Roles:** Owner (one per org) · Admin · Member · Viewer, plus per-person *Events* and *Mobilization* module access. Members only see the events and drives they're assigned to. Viewers are read-only. Platform admins manage organizations.

**Check-in (teal):** look up by ID against the register, then check in.
- Same-day duplicates are blocked ("Already checked in today", with when and by whom).
- **Region-restricted** events flag out-of-region voters but still allow them in.
- **List-only** events block IDs that aren't on the uploaded participant list.
- Voters not in the register can be entered by hand.
- An inactive organization blocks all check-ins.

**Mobilization (amber):** register voters into a drive that has a target and a target date. Dedup is **once per organization**, and a duplicate reports who mobilized the voter and in which drive. Each drive shows progress, pace needed, current pace and a momentum trend.

**Dashboard (web):**
- Org KPIs and top regions
- Events: list, detail, hourly chart, gender mix, operators, rules, participant list
- Web check-in desk
- Mobilization: drives, pace and momentum, top mobilizers
- People with search and CSV export
- Team management
- Account
- Platform console (organizations)

**Field app (Flutter):**
- Sign in
- Home with today's counts and a live feed
- Centre **+** for Check in / Mobilize, with camera **Scan ID**
- Insights: Check-ins and Mobilization tabs
- People: Check-ins and Mobilized tabs, with filter and search
- Account and change password
- Pull to refresh everywhere

## Offline field work (mobile app)

The field app keeps working with no signal, for both Checkin and Election Ops.

- **Reading offline.** Every screen's last data is kept on the phone. While there's signal, the app also downloads what each person needs: their events and drives, or their stations, station records, Form 37A forms and agent pools. A banner shows "Offline · saved data from 9:22 PM".
- **Recording offline.** Check-ins, mobilizations, status changes, turnout, incidents, resolutions, results and assignments are saved in an outbox on the phone.
  - They're replayed oldest-first when signal returns: automatically every 30 s, when the app reopens, or with *Sync now*.
  - Records still waiting are listed on the station page.
- **No double counting.** Each queued write carries an `Idempotency-Key`, so a retry after a lost response returns the original result instead of writing twice. Server-side dedup (same-day check-in, once-per-org mobilization) still applies on sync, and shows as "already recorded".
- **Real times.** `X-Recorded-At` keeps the time on the phone, so check-in hour charts, turnout and replay reflect when things happened, not when they synced. Clocks more than 5 min ahead or 7 days behind are ignored.
- **Register lookups offline.** The register needs the server, so offline the operator records the ID plus any details they have. The server completes the record from the register at sync. The phone warns about IDs it has already recorded itself. Records the server rejects (e.g. a voter who isn't on the register and has no name entered) appear under *Sync & offline data › Needs attention*, with **Add details & retry** or **Discard**.
- **Encrypted at rest.** Everything the app keeps (saved screens, the outbox, the dedup ledger and the profile) is sealed with AES-256-GCM (`mobile/lib/offline/vault.dart`).
  - The data key is generated on the device and held in the platform keystore: Android Keystore-backed storage, or the iOS Keychain set to this-device-only and available after first unlock so background sync works.
  - The session token lives in the keystore itself. Storage names are hashed.
  - Tampered or unreadable entries are dropped rather than trusted. A copied app folder or cloud backup can't be read without the key, and `setup.sh` also turns off Android app-data backup (Android 6.0+ required).
  - Data saved in plaintext by earlier builds is re-encrypted on first launch: queued records and the profile are kept, and caches are dropped and re-downloaded.
  - Unit tests: `cd mobile && flutter test`.
- **App PIN lock** (`mobile/lib/security/app_lock.dart`).
  - After sign-in everyone sets a 4–6 digit PIN. All-same digits and runs like 1234 are refused.
  - The app locks on every launch and after **2 min** in the background. Fingerprint or face unlock can be turned on under *Account › Security*.
  - The PIN is stored only as a salted PBKDF2-SHA256 hash (120k iterations). The hash, the failure counter and the last-unlock time live in the platform keystore, so killing the app or editing its files doesn't reset them.
  - From the 5th wrong PIN each try waits 30 s, doubling each time, with a warning at 3 tries left.
  - *Forgot PIN?* checks the account password online and keeps unsynced records.
- **Auto-wipe.** The phone's offline data, including records not yet synced, is erased and the vault key destroyed when:
  - **10 wrong PINs** are entered in a row;
  - the app hasn't been unlocked for **14 days**; or
  - **an admin deactivates the account**. The server answers `401 account_inactive` (distinct from `token_invalid` for an expired session), and the app wipes on its next contact.

  The sign-in screen then says why. The limits can be tuned per build: `--dart-define=LOCK_AFTER_SECONDS=… WIPE_AFTER_DAYS=… MAX_PIN_ATTEMPTS=…`.
- **No screenshots on Android.** The main activity sets `FLAG_SECURE` before the first frame, so the recent-apps preview is blank, and screenshots, screen recording and casting capture black. On Android 13+ the recents snapshot is also disabled explicitly. The activity is committed at `mobile/android_template/MainActivity.kt`, and `setup.sh` installs it into the generated `android/` folder.
- **Sessions.** Field logins last 14 days, and the app opens offline with the last signed-in profile. Signing out with unsynced records asks first. They stay on the phone and sync at the next sign-in by the same person.

## API summary

All routes except `/healthz` and `/api/auth/login` need `Authorization: Bearer <token>`.

```
POST /api/auth/login                 GET  /api/me              POST /api/auth/change-password
GET  /api/dashboard                  GET  /api/home
GET|POST /api/events                 GET|PATCH /api/events/{id}
PUT  /api/events/{id}/assignments    PUT  /api/events/{id}/participants
GET  /api/checkins/lookup?event_id&national_id    POST /api/checkins    GET /api/checkins?event_id&q
GET|POST /api/drives                 GET|PATCH /api/drives/{id}        PUT /api/drives/{id}/assignments
GET  /api/mobilizations/lookup?national_id        POST /api/mobilizations  GET /api/mobilizations?drive_id&q
GET  /api/insights/checkins?event_id[&day]        GET  /api/insights/mobilization?drive_id
GET|POST /api/team                   PATCH /api/team/{id}
GET|POST /api/platform/organizations GET|PATCH|DELETE /api/platform/organizations/{id}
GET  /api/platform/overview          GET /api/platform/email-templates   PUT /api/platform/email-templates/{key}

# Election Ops (all scoped to the caller's area; ?election_id defaults to the active election)
GET|POST /api/ops/elections          GET|DELETE /api/ops/elections/{id}   POST /api/ops/elections/{id}/status
GET  /api/ops/races                  POST /api/ops/positions               DELETE /api/ops/positions/{id}
POST /api/ops/candidates             PATCH|DELETE /api/ops/candidates/{id}
GET  /api/ops/registry/{stations,parties,regions}
GET|POST /api/ops/people             PATCH /api/ops/people/{id}
GET  /api/ops/overview               GET /api/ops/stations                GET /api/ops/stations/{code}
POST /api/ops/stations/{code}/{status,turnout,incidents,results}       POST /api/ops/stations/{code}/incidents/{id}/resolve
GET  /api/ops/stations/{code}/agent-pool   PUT|DELETE /api/ops/stations/{code}/agents/{user}
GET  /api/ops/stations/{code}/results?position_id
GET  /api/ops/turnout                GET /api/ops/results                 GET /api/ops/replay?election_id&hour
GET  /api/ops/reports/{coverage,turnout,results,incidents}              GET|PATCH /api/settings
```

Errors are `{"error": "...", "code": "..."}`. Writes accept `Idempotency-Key` (replay-safe retries; reusing a key for a different request → 422) and `X-Recorded-At` (RFC 3339 device time). `POST /api/auth/login` accepts `"remember": true` for a 14-day session. Codes the clients act on: `already_checked_in`, `not_on_list`, `already_mobilized`, `not_assigned`, `org_inactive`, `event_closed`, `drive_closed`.

## Not yet built

- Email/SMS invitations and password-reset links. Admins currently set an initial password.
- Coverage analytics (constituency → ward → polling-centre drill-down, "push here next").
- Election Ops: the agent invite emails and the "notifies your admin" on incidents. Templates are stored, but nothing sends email or SMS yet.
- Election Ops: importing historical elections, such as 2022, for replay. Replay works for any election recorded in the system.
- Election Ops: per-organization overrides of email templates, and sign-in-screen branding before login.
