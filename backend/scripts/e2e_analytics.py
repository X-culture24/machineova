"""End-to-end: coverage analytics (event + drive) and registration analysis.

Needs voter register, polling stations and registration_stats (cmd/build-analytics) loaded.
Creates a throwaway org; picks registered voters from the database (never printed).

  API=http://localhost:8080 DATABASE_URL=postgres://... python3 scripts/e2e_analytics.py
"""
import json, os, subprocess, sys, urllib.error, urllib.parse, urllib.request, uuid

B = os.environ.get("API", "http://localhost:8080") + "/api"
DB = os.environ["DATABASE_URL"]
fails = 0


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
    return subprocess.run(["psql", DB, "-Atc", q], capture_output=True, text=True, check=True).stdout.split()


def ok(label, cond, extra=""):
    global fails
    print(("PASS " if cond else "FAIL ") + label + ("" if cond else f"  -> {extra}"))
    fails += 0 if cond else 1


def login(u, p):
    return call("POST", "/auth/login", {"login": u, "password": p})[1]["token"]


run = uuid.uuid4().hex[:6]
plat = login(os.environ.get("PLATFORM_EMAIL", "ops@test.local"), os.environ.get("PLATFORM_PASSWORD", "testpass123"))
st, org = call("POST", "/platform/organizations", {"name": f"Analytics Test {run}", "boundary_county": "Nairobi",
    "owner_name": "Test Owner", "owner_email": f"owner-{run}@test.local", "owner_password": "ownerpass1",
    "accent_color": "#8B2CF5", "contact_email": f"ops-{run}@test.local"}, plat)
ok("create org", st == 201, org)
own = login(f"owner-{run}@test.local", "ownerpass1")

st, ev = call("POST", "/events", {"name": f"Kibra Rally {run}", "venue": "Kamukunji", "county": "Nairobi",
    "constituency": "Kibra", "starts_at": "2026-01-01T06:00:00Z", "region_restricted": True}, own)
ok("create Kibra event", st == 201, ev)
ward = sql("SELECT ward FROM polling_stations WHERE county='Nairobi' AND constituency='Kibra' ORDER BY registered_voters DESC LIMIT 1")
ward = " ".join(ward)
ids = sql(f"SELECT national_id FROM register_voters WHERE county='Nairobi' AND constituency='Kibra' AND ward='{ward}' "
          "AND name IS NOT NULL AND sex IS NOT NULL LIMIT 5 OFFSET 100")
outsider = sql("SELECT national_id FROM register_voters WHERE county='Mombasa' AND name IS NOT NULL AND sex IS NOT NULL LIMIT 1 OFFSET 50")
ok("picked 5 registered Kibra voters and 1 outsider", len(ids) == 5 and len(outsider) == 1, (len(ids), len(outsider)))
for nid in ids + outsider:
    st, r = call("POST", "/checkins", {"event_id": ev["id"], "national_id": nid}, own)
    if st != 201:
        ok("check-in", False, r)

st, cov = call("GET", f"/insights/coverage?event_id={ev['id']}", tok=own)
ok("coverage for a constituency event drills down by ward", st == 200 and cov["level"] == "ward" and cov["label"] == "Kibra", cov.get("level"))
ok("coverage counts the 5 registered voters reached (outsider excluded)", cov.get("reached") == 5, cov.get("reached"))
ok("registered voters in scope come from the register", cov.get("registered", 0) > 10000, cov.get("registered"))
row = next((x for x in cov.get("rows", []) if x["area"] == ward), None)
ok("the ward reached shows 5 reached with a status", row and row["reached"] == 5 and row["status"] in
   ("critical", "low", "moderate", "strong"), row)
ok("other wards are 'not started'", any(x["status"] == "not_started" for x in cov["rows"]), [x["status"] for x in cov["rows"]][:5])
ok("push here next lists up to 3 weak areas", 1 <= len(cov.get("push_here_next", [])) <= 3, cov.get("push_here_next"))
ok("gender mix and top age group are reported", cov["female"] + cov["male"] == 6 and cov.get("top_age_group"), (cov["female"], cov["male"], cov.get("top_age_group")))

st, cov2 = call("GET", f"/insights/coverage?event_id={ev['id']}&ward={urllib.parse.quote(ward)}", tok=own)
ok("drill into a ward lists polling centres", st == 200 and cov2["level"] == "polling_center" and len(cov2["rows"]) >= 1, cov2.get("level"))

st, dr = call("POST", "/drives", {"name": f"Kibra Drive {run}", "county": "Nairobi", "constituency": "Kibra", "target": 1000}, own)
for nid in ids[:3]:
    call("POST", "/mobilizations", {"drive_id": dr["id"], "national_id": nid}, own)
st, cd = call("GET", f"/insights/coverage?drive_id={dr['id']}", tok=own)
ok("drive coverage works the same way", st == 200 and cd.get("reached") == 3, cd.get("reached"))

st, reg = call("GET", "/insights/registration", tok=own)
ok("registration analysis scoped to the org's county, by sub-county", st == 200 and reg["level"] == "sub_county"
   and reg["label"] == "Nairobi" and len(reg["rows"]) > 0, reg.get("level"))
ok("registered never exceeds adults; unregistered = adults - registered",
   all(r["registered"] <= r["adults"] and r["unregistered"] == r["adults"] - r["registered"] for r in reg["rows"]), "")

print(f"\n{'ALL PASSED' if not fails else str(fails) + ' FAILED'}")
sys.exit(1 if fails else 0)
