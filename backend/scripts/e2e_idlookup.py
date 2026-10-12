"""End-to-end ID lookup / check-in against a running API whose database has id_registry loaded.

Picks real IDs from id_registry itself (never printed) and exercises the field flow:
lookup by ID -> details resolved -> check in with the ID only -> duplicate guard.
Prints PASS/FAIL lines only, no personal data.

  API=http://localhost:8099 DATABASE_URL=postgres://... python3 scripts/e2e_idlookup.py
"""
import json, os, subprocess, sys, urllib.request, urllib.error, uuid

B = os.environ.get("API", "http://localhost:8080") + "/api"
DB = os.environ["DATABASE_URL"]


def call(method, path, body=None, tok=None):
    req = urllib.request.Request(B + path, method=method, data=None if body is None else json.dumps(body).encode())
    req.add_header("Content-Type", "application/json")
    if tok:
        req.add_header("Authorization", "Bearer " + tok)
    try:
        with urllib.request.urlopen(req) as r:
            data = r.read()
            return r.status, json.loads(data) if data else None
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def sql(q):
    return subprocess.run(["psql", DB, "-Atc", q], capture_output=True, text=True, check=True).stdout.strip()


fails = 0


def ok(label, cond, extra=""):
    global fails
    print(("PASS " if cond else "FAIL ") + label + ("" if cond else f"  -> {extra}"))
    fails += 0 if cond else 1


def login(u, p):
    return call("POST", "/auth/login", {"login": u, "password": p})[1]["token"]


run = uuid.uuid4().hex[:6]
kwale_id = sql("SELECT national_id FROM id_registry WHERE county='KWALE' AND sex IS NOT NULL AND dob IS NOT NULL "
               "AND sub_county IS NOT NULL AND location IS NOT NULL LIMIT 1 OFFSET 1000")
kilifi_id = sql("SELECT national_id FROM id_registry WHERE county='KILIFI' AND sex IS NOT NULL AND dob IS NOT NULL "
                "AND sub_county IS NOT NULL AND location IS NOT NULL LIMIT 1 OFFSET 2000")
ok("picked registry IDs for test", kwale_id and kilifi_id)
missing = "999" + run.translate(str.maketrans("abcdef", "123456"))  # not a real ID format in the extracts

plat = login(os.environ.get("PLATFORM_EMAIL", "ops@test.local"), os.environ.get("PLATFORM_PASSWORD", "testpass123"))
st, org = call("POST", "/platform/organizations", {"name": f"Coast Test {run}", "boundary_county": "Kwale",
    "owner_name": "Test Owner", "owner_email": f"owner-{run}@test.local", "owner_password": "ownerpass1",
    "accent_color": "#8B2CF5", "contact_email": f"ops-{run}@test.local"}, plat)
ok("create org bounded to Kwale", st == 201, org)
own = login(f"owner-{run}@test.local", "ownerpass1")

st, ev = call("POST", "/events", {"name": f"Kwale Rally {run}", "venue": "Kwale Stadium", "county": "Kwale",
    "starts_at": "2026-01-01T08:00:00Z", "region_restricted": True}, own)
ok("create Kwale event", st == 201, ev)
eid = ev["id"]

# 1. Lookup an ID that exists only in the national ID registry
st, lk = call("GET", f"/checkins/lookup?event_id={eid}&national_id={kwale_id}", tok=own)
v = lk.get("voter") or {}
ok("lookup resolves registry ID", st == 200 and lk.get("in_register") is True and v.get("name"), lk.get("status"))
ok("source is id_registry and flagged not a registered voter",
   v.get("source") == "id_registry" and lk.get("registered_voter") is False, (v.get("source"), lk.get("registered_voter")))
ok("details filled: sex, dob, age, county, admin area",
   v.get("sex") in ("F", "M") and len(v.get("dob", "")) == 10 and v.get("age", 0) > 0 and v.get("county") == "Kwale"
   and (v.get("admin_area") or {}).get("location"), {k: bool(v.get(k)) for k in ("sex", "dob", "age", "county")})
ok("same-county person is in region", lk.get("in_region") is True, lk.get("in_region"))

# 2. Leading zeros / spaces typed or scanned still match
st, lk0 = call("GET", f"/checkins/lookup?event_id={eid}&national_id=0{kwale_id}", tok=own)
ok("leading zero still matches", st == 200 and (lk0.get("voter") or {}).get("source") == "id_registry", lk0.get("status"))

# 3. Different county -> found but out of region
st, lk2 = call("GET", f"/checkins/lookup?event_id={eid}&national_id={kilifi_id}", tok=own)
ok("Kilifi ID found, out of region for a Kwale event", st == 200 and lk2.get("voter") and lk2.get("in_region") is False, lk2.get("in_region"))

# 4. Unknown ID -> not found, operator enters details
st, lk3 = call("GET", f"/checkins/lookup?event_id={eid}&national_id={missing}", tok=own)
ok("unknown ID -> voter null, in_register false", st == 200 and lk3.get("voter") is None and lk3.get("in_register") is False, lk3)

# 5. Check in with the ID only: the server fills identity and location from the registry
st, ci = call("POST", "/checkins", {"event_id": eid, "national_id": kwale_id, "phone": "0700000000"}, own)
ok("check-in with ID only succeeds", st == 201 and ci.get("in_region") is True, ci)
st, lk4 = call("GET", f"/checkins/lookup?event_id={eid}&national_id={kwale_id}", tok=own)
ok("second lookup says already checked in", lk4.get("status") == "already_checked_in", lk4.get("status"))
st, dup = call("POST", "/checkins", {"event_id": eid, "national_id": kwale_id}, own)
ok("duplicate check-in rejected", st == 409, dup)

# 6. Out-of-region check-in is allowed and flagged
st, ci2 = call("POST", "/checkins", {"event_id": eid, "national_id": kilifi_id}, own)
ok("out-of-region check-in allowed and flagged", st == 201 and ci2.get("in_region") is False, ci2)

# 7. Mobilization lookup uses the same registry
st, dr = call("POST", "/drives", {"name": f"Kwale Drive {run}", "county": "Kwale", "target": 100}, own)
ok("create drive", st == 201, dr)
st, ml = call("GET", f"/mobilizations/lookup?national_id={kwale_id}", tok=own)
ok("mobilize lookup resolves registry ID", st == 200 and (ml.get("voter") or {}).get("source") == "id_registry", ml.get("status"))
st, mb = call("POST", "/mobilizations", {"drive_id": dr["id"], "national_id": kwale_id}, own)
ok("mobilize with ID only succeeds", st == 201, mb)

print(f"\n{'ALL PASSED' if not fails else str(fails) + ' FAILED'}")
sys.exit(1 if fails else 0)
