"""End-to-end: owners AND admins can create elections, candidates, events and drives.

Needs a database with polling stations (import-registry -from-register) and parties loaded.
Creates a throwaway org; prints PASS/FAIL only.

  API=http://localhost:8080 python3 scripts/e2e_elections.py
"""
import datetime, json, os, sys, urllib.error, urllib.request, uuid

B = os.environ.get("API", "http://localhost:8080") + "/api"
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


def ok(label, cond, extra=""):
    global fails
    print(("PASS " if cond else "FAIL ") + label + ("" if cond else f"  -> {extra}"))
    fails += 0 if cond else 1


def login(u, p):
    return call("POST", "/auth/login", {"login": u, "password": p})[1]["token"]


run = uuid.uuid4().hex[:6]
plat = login(os.environ.get("PLATFORM_EMAIL", "ops@test.local"), os.environ.get("PLATFORM_PASSWORD", "testpass123"))
st, org = call("POST", "/platform/organizations", {"name": f"Nairobi Test {run}", "boundary_county": "Nairobi",
    "owner_name": "Test Owner", "owner_email": f"owner-{run}@test.local", "owner_password": "ownerpass1",
    "accent_color": "#8B2CF5", "contact_email": f"ops-{run}@test.local"}, plat)
ok("platform admin creates org bounded to Nairobi", st == 201, org)
own = login(f"owner-{run}@test.local", "ownerpass1")

today = datetime.date.today().isoformat()
pos = [{"name": n, "level": l} for n, l in [("Governor", "county"), ("Senator", "county"),
       ("Woman Representative", "county"), ("Member of Parliament", "constituency"), ("MCA", "ward")]]

# --- owner creates and activates a county-wide election
st, el = call("POST", "/ops/elections", {"name": f"Nairobi General Election {run}", "code": f"NRB{run}".upper(),
    "election_date": today, "positions": pos}, own)
ok("owner creates a county-wide election", st == 201, el)
ok("election pulls in real polling stations, constituencies and wards",
   st == 201 and el["stations"] > 100 and el["constituencies"] == 17 and el["wards"] == 85,
   {k: el.get(k) for k in ("stations", "constituencies", "wards")} if st == 201 else el)
st, r = call("POST", f"/ops/elections/{el['id']}/status", {"status": "active"}, own)
ok("owner activates the election", st == 200 and r["status"] == "active", r)

st, races = call("GET", "/ops/races", tok=own)
gov = next(p for p in races["positions"] if p["name"] == "Governor")
for name, party in [("Test Candidate A", "UDA"), ("Test Candidate B", "ODM")]:
    st, c = call("POST", "/ops/candidates", {"position_id": gov["id"], "region": "Nairobi", "name": name,
        "party_code": party, "is_ours": party == "UDA"}, own)
    ok(f"owner adds governor candidate ({party})", st == 201, c)

# --- owner adds an admin for Kibra
st, adm = call("POST", "/ops/people", {"role": "admin", "name": "Test Admin", "phone": "+254 700 000 101",
    "national_id": f"9{run[:7].translate(str.maketrans('abcdef', '123456'))}", "constituency": "Kibra",
    "email": f"admin-{run}@test.local", "password": "adminpass1"}, own)
ok("owner adds an admin (Kibra)", st == 201, adm)
admt = login(f"admin-{run}@test.local", "adminpass1")

# --- admin creates an election of their own (draft by-election)
st, by = call("POST", "/ops/elections", {"name": f"Kibra MCA By-Election {run}", "code": f"KBR{run}".upper(),
    "election_date": today, "scope_county": "Nairobi", "scope_constituency": "Kibra",
    "positions": [{"name": "MCA", "level": "ward"}]}, admt)
ok("admin creates an election (Kibra by-election)", st == 201 and by.get("stations", 0) > 0, by)
st, lst = call("GET", "/ops/elections", tok=admt)
items = lst if isinstance(lst, list) else lst.get("items", lst.get("elections", []))
ok("admin sees both elections", st == 200 and len(items) >= 2, st)
st, c = call("POST", "/ops/candidates", {"position_id": gov["id"], "region": "Nairobi", "name": "Test Candidate C",
    "party_code": "JP"}, admt)
ok("admin adds a candidate to the active election", st == 201, c)

# --- events and drives
for who, tok in [("owner", own), ("admin", admt)]:
    st, ev = call("POST", "/events", {"name": f"{who.title()} Rally {run}", "venue": "Kamukunji Grounds",
        "county": "Nairobi", "constituency": "Kibra", "starts_at": today + "T08:00:00Z", "region_restricted": True}, tok)
    ok(f"{who} creates an event", st == 201, ev)
    st, dr = call("POST", "/drives", {"name": f"{who.title()} Drive {run}", "county": "Nairobi",
        "constituency": "Kibra", "target": 1000}, tok)
    ok(f"{who} creates a mobilization drive", st == 201, dr)

st, evs = call("GET", "/events", tok=own)
ok("owner lists events", st == 200 and len(evs["items"]) >= 2, st)

# --- guard rails still hold
st, r = call("POST", "/ops/elections", {"name": "Out of bounds", "code": f"X{run}".upper(), "election_date": today,
    "scope_county": "Mombasa", "positions": pos}, own)
ok("election outside the org boundary is rejected", st == 400, r)

print(f"\n{'ALL PASSED' if not fails else str(fails) + ' FAILED'}")
sys.exit(1 if fails else 0)
