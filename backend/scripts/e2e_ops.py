"""End-to-end Election Ops check against a running API with an EMPTY database.

Setup (see Makefile target e2e):
  import testdata/sample_*.csv, bootstrap ops@test.local / testpass123, then run this.
Sample data only — never point this at production.
"""
import json, os, urllib.request, urllib.error, datetime, sys
B = os.environ.get("API", "http://localhost:8080") + "/api"
def call(method, path, body=None, tok=None, raw=False):
    req = urllib.request.Request(B + path, method=method, data=None if body is None else json.dumps(body).encode())
    req.add_header("Content-Type", "application/json")
    if tok: req.add_header("Authorization", "Bearer " + tok)
    try:
        with urllib.request.urlopen(req) as r:
            data = r.read()
            return r.status, (data.decode() if raw else (json.loads(data) if data else None))
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")
def callh(method, path, body, tok, headers):
    req = urllib.request.Request(B + path, method=method, data=json.dumps(body).encode())
    req.add_header("Content-Type", "application/json"); req.add_header("Authorization", "Bearer " + tok)
    for k, v in headers.items(): req.add_header(k, v)
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.loads(r.read() or b"null"), dict(r.headers)
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}"), dict(e.headers)
def login(u, p): return call("POST", "/auth/login", {"login": u, "password": p})[1]["token"]
def ok(label, cond, extra=""):
    print(("PASS " if cond else "FAIL ") + label + ("" if cond else f"  -> {extra}")); 
    if not cond: ok.fail = True
ok.fail = False

plat = login("ops@test.local", "testpass123")
st, org = call("POST", "/platform/organizations", {"name": "Migori County Campaign", "boundary_county": "Migori", "owner_name": "Amara Mwangi",
    "owner_email": "amara@test.local", "owner_password": "ownerpass1", "accent_color": "#0D9488", "contact_email": "ops@mc.test"}, plat)
ok("create org", st == 201, org)
own = login("amara@test.local", "ownerpass1")

st, r = call("GET", "/ops/overview", tok=own); ok("overview without active election -> 404 no_active_election", st == 404 and r.get("code") == "no_active_election", r)
pos = [{"name": n, "level": l} for n, l in [("Governor","county"),("Senator","county"),("Woman Representative","county"),("Member of Parliament","constituency"),("MCA","ward")]]
st, r = call("POST", "/ops/elections", {"name":"Bad","code":"X","election_date":"2027-08-09","positions":[{"name":"President","level":"national"}]}, own)
ok("President above county scope rejected", st == 400, r)
st, r = call("POST", "/ops/elections", {"name":"Kisumu","code":"K","election_date":"2027-08-09","scope_county":"Kisumu","positions":pos}, own)
ok("scope outside org boundary rejected", st == 400, r)
today = datetime.date.today().isoformat()
st, el = call("POST", "/ops/elections", {"name":"Migori County General Election 2027","code":"MGR-GE27","election_date":today,"positions":pos}, own)
ok("create election (14 stations, 4 constituencies, 6 wards)", st == 201 and el["stations"] == 14 and el["constituencies"] == 4 and el["wards"] == 6, el)
st, r = call("POST", f"/ops/elections/{el['id']}/status", {"status":"active"}, own); ok("activate", st == 200 and r["status"] == "active", r)
st, r = call("GET", f"/ops/elections/{el['id']}?constituency=Suna%20East", tok=own)
ok("drill-down Suna East -> 3 wards", st == 200 and len(r["drill"]["rows"]) == 3, r.get("drill"))
ok("derived regions: MP in 4 constituencies", any(l["level"]=="constituency" and len(l["regions"])==4 for l in r["levels"]), r["levels"])

st, races = call("GET", "/ops/races", tok=own)
gov = next(p for p in races["positions"] if p["name"]=="Governor")
mp = next(p for p in races["positions"] if p["name"]=="Member of Parliament")
ok("races: 3 county + 4 MP + 6 MCA = 13", len(races["races"]) == 13, len(races["races"]))
cands = {}
for name, party, ours in [("Dr. Susan Ayieko","UA",True),("James Ochieng","PF",False),("Hellen Moraa","GC",False)]:
    st, c = call("POST", "/ops/candidates", {"position_id": gov["id"], "region": "Migori", "name": name, "party_code": party, "is_ours": ours}, own)
    ok(f"add governor candidate {name}", st == 201, c); cands[name] = c["id"]
st, r = call("POST", "/ops/candidates", {"position_id": mp["id"], "region": "Nowhere", "name": "X"}, own); ok("candidate in unknown region rejected", st == 400, r)
st, r = call("POST", "/ops/candidates", {"position_id": gov["id"], "region": "Migori", "name": "X", "party_code": "ZZZ"}, own); ok("unknown party rejected", st == 400, r)

# people
st, adm = call("POST", "/ops/people", {"role":"admin","name":"Daniel Otieno","phone":"+254 722 118 445","national_id":"24810335","constituency":"Suna East",
    "email":"daniel@test.local","password":"adminpass1"}, own); ok("owner adds admin (Suna East)", st == 201 and adm["area"] == "Suna East Constituency", adm)
adm_t = login("daniel@test.local", "adminpass1")
st, mgr = call("POST", "/ops/people", {"role":"manager","name":"Beatrice Adhiambo","phone":"+254 707 442 190","national_id":"27384451","constituency":"Suna East","ward":"Kakrao",
    "email":"bea@test.local","password":"managerpass1"}, adm_t); ok("admin adds manager (Kakrao)", st == 201, mgr)
st, r = call("POST", "/ops/people", {"role":"manager","name":"Out","phone":"+254 700 000 000","national_id":"11111111","constituency":"Awendo","ward":"North Sakwa"}, adm_t)
ok("admin can't add outside own constituency", st == 403, r)
st, r = call("POST", "/ops/people", {"role":"admin","name":"X","phone":"+254 700 000 001","national_id":"11111112","constituency":"Suna East"}, adm_t)
ok("admin can't add admin", st == 403, r)
mgr_t = login("bea@test.local", "managerpass1")
st, ag1 = call("POST", "/ops/people", {"role":"agent","name":"Kevin Odhiambo","phone":"+254 712 334 551","national_id":"28714566","station_code":"MGR-001",
    "email":"kevin@test.local","password":"agentpass1"}, mgr_t); ok("manager adds agent at MGR-001 (ward inherited)", st == 201 and ag1["station_code"] == "MGR-001", ag1)
st, ag2 = call("POST", "/ops/people", {"role":"agent","name":"Brian Okoth","phone":"+254 701 456 208","national_id":"27553390"}, mgr_t); ok("manager adds unassigned agent", st == 201, ag2)
st, r = call("POST", "/ops/people", {"role":"agent","name":"Dup","phone":"+254 701 456 209","national_id":"27553390"}, mgr_t); ok("duplicate national ID rejected", st == 409, r)
st, ppl = call("GET", "/ops/people", tok=mgr_t); ok("manager directory shows self + 2 agents", st == 200 and ppl["total"] == 3, ppl.get("total"))

# manager scope
st, ov = call("GET", "/ops/overview", tok=mgr_t)
ok("manager overview scoped to 4 Kakrao stations, 3 uncovered", ov["stations"] == 4 and ov["uncovered"] == 3 and ov["scope_label"] == "Kakrao Ward", (ov["stations"], ov["uncovered"], ov["scope_label"]))
st, r = call("GET", "/ops/stations/MGR-011", tok=mgr_t); ok("manager can't see Awendo station", st == 404, r)
st, pool = call("GET", "/ops/stations/MGR-003/agent-pool", tok=mgr_t); ok("agent pool lists 2 Kakrao agents", len(pool["agents"]) == 2, pool)
st, r = call("PUT", f"/ops/stations/MGR-003/agents/{ag2['id']}", tok=mgr_t); ok("assign Brian to MGR-003", st == 204, r)

ag_t = login("kevin@test.local", "agentpass1")
st, r = call("POST", "/ops/stations/MGR-003/status", {"status":"open"}, ag_t); ok("agent blocked on other station", st == 403, r)
st, r = call("POST", "/ops/stations/MGR-001/status", {"status":"open"}, ag_t); ok("agent opens own station", st == 204, r)
st, r = call("POST", "/ops/stations/MGR-001/turnout", {"slot_hour":11,"cumulative":214}, ag_t); ok("turnout 11AM", st == 204, r)
st, r = call("POST", "/ops/stations/MGR-001/turnout", {"slot_hour":13,"cumulative":200}, ag_t); ok("non-cumulative turnout rejected", st == 400, r)
st, r = call("POST", "/ops/stations/MGR-001/turnout", {"slot_hour":13,"cumulative":900}, ag_t); ok("turnout > registered rejected", st == 400, r)
st, r = call("POST", "/ops/stations/MGR-001/turnout", {"slot_hour":15,"cumulative":388}, ag_t); ok("turnout 3PM", st == 204, r)
st, inc = call("POST", "/ops/stations/MGR-003/incidents", {"type":"KIEMS kit failure","description":"Manual register in use."}, mgr_t); ok("manager reports incident", st == 201, inc)
st, d = call("GET", "/ops/stations/MGR-003", tok=mgr_t); ok("station flagged Issue", d["station"]["status"] == "issue" and d["station"]["open_incidents"] == 1, d["station"])
st, r = call("POST", f"/ops/stations/MGR-003/incidents/{inc['id']}/resolve", {"resolution":"Kit replaced"}, ag_t); ok("agent can't resolve", st == 403, r)
st, r = call("POST", f"/ops/stations/MGR-003/incidents/{inc['id']}/resolve", {"resolution":"Kit replaced"}, mgr_t); ok("manager resolves", st == 204, r)
st, d = call("GET", "/ops/stations/MGR-003", tok=mgr_t); ok("status back to Open after resolve", d["station"]["status"] == "open", d["station"]["status"])
# results at MGR-001 for Governor
st, rs = call("GET", f"/ops/stations/MGR-001/results?position_id={gov['id']}", tok=ag_t); ok("results form lists 3 candidates", len(rs["candidates"]) == 3, rs)
votes = {cands["Dr. Susan Ayieko"]: 150, cands["James Ochieng"]: 120, cands["Hellen Moraa"]: 100}
st, r = call("POST", "/ops/stations/MGR-001/results", {"position_id":gov["id"],"votes":votes,"rejected":5,"confirm":False}, ag_t); ok("results need confirm", st == 400, r)
st, r = call("POST", "/ops/stations/MGR-001/results", {"position_id":gov["id"],"votes":{**votes, cands["James Ochieng"]: 999},"rejected":5,"confirm":True}, ag_t); ok("results > registered rejected", st == 400, r)
st, r = call("POST", "/ops/stations/MGR-001/results", {"position_id":gov["id"],"votes":votes,"rejected":5,"confirm":True}, ag_t); ok("submit Form 37A", st == 204, r)
# second station results so leader differs by area
call("POST", "/ops/stations/MGR-011/status", {"status":"open"}, own)
call("POST", "/ops/stations/MGR-011/turnout", {"slot_hour":9,"cumulative":100}, own)
call("POST", "/ops/stations/MGR-011/results", {"position_id":gov["id"],"votes":{cands["Dr. Susan Ayieko"]: 40, cands["James Ochieng"]: 90, cands["Hellen Moraa"]: 30},"rejected":0,"confirm":True}, own)
call("POST", "/ops/stations/MGR-011/status", {"status":"closed"}, own)

st, ov = call("GET", "/ops/overview", tok=own)
ok("owner overview: 14 stations, reported 2, cast 488", ov["stations"] == 14 and ov["reported"] == 2 and ov["cast"] == 488, {k: ov[k] for k in ("stations","reported","cast","to_verify")})
ok("closed MGR-011 still needs MP/MCA/... verification", ov["to_verify"] == 1, ov["to_verify"])
st, tu = call("GET", "/ops/turnout", tok=own)
ok("turnout monitor: 4 constituencies, focus Governor", len(tu["areas"]) == 4 and tu["focus_position"]["name"] == "Governor", [a["name"] for a in tu["areas"]])
aw = next(a for a in tu["areas"] if a["name"] == "Awendo"); se = next(a for a in tu["areas"] if a["name"] == "Suna East")
ok("Awendo: opponent leads", aw["we_lead"] is False and aw["leading"]["candidate"]["name"] == "James Ochieng", aw)
ok("Suna East: we lead", se["we_lead"] is True, se)
st, res = call("GET", f"/ops/results?position_id={gov['id']}", tok=own)
ok("results: single county race, Ochieng 210 leads county-wide", res["single_race"] and res["totals"][0]["votes"] == 210 and res["stations_reporting"] == 2, res["totals"])
st, res = call("GET", f"/ops/results?position_id={mp['id']}", tok=own); ok("MP at county view: multiple races, no totals", st == 200 and not res["single_race"], res.get("single_race"))
st, rp = call("GET", "/ops/replay?hour=23", tok=own); ok("replay end of day has events", st == 200 and len(rp["events"]) > 5, len(rp.get("events", [])))
st, rp = call("GET", "/ops/replay?hour=0", tok=own); ok("replay at midnight: nothing reported", rp["stations_reporting"] == 0, rp["stations_reporting"])
for k in ("coverage","turnout","results","incidents"):
    st, csv = call("GET", f"/ops/reports/{k}", tok=mgr_t, raw=True)
    ok(f"report {k}.csv (manager-scoped)", st == 200 and "MGR-011" not in csv, csv[:200])
st, r = call("PATCH", "/settings", {"accent_color":"#7C3AED"}, mgr_t); ok("non-owner can't brand", st == 403, r)
st, r = call("PATCH", "/settings", {"accent_color":"#7C3AED"}, own); ok("owner sets accent", st == 200 and r["accent_color"] == "#7C3AED", r)
st, r = call("GET", "/platform/overview", tok=plat); ok("platform overview", st == 200 and r["stations"] == 14 and r["agents"] == 2, r)
st, r = call("PUT", "/platform/email-templates/agent_invite", {"subject":"Hi {{bogus}}","body":"x"}, plat); ok("unknown merge field rejected", st == 400, r)
st, r = call("DELETE", f"/platform/organizations/{org['id']}", {"confirm_name":"wrong"}, plat); ok("delete needs exact name", st == 400, r)

# ---- offline sync: idempotent replays + device time ----
st, r = call("POST", "/auth/login", {"login": "kevin@test.local", "password": "agentpass1", "remember": True})
exp = datetime.datetime.fromisoformat(r["expires_at"]); ok("remember-me token lasts ~14 days", (exp - datetime.datetime.now(exp.tzinfo)).days >= 13, r["expires_at"])
st, ev = call("POST", "/events", {"name": "Offline Rally", "county": "Migori", "starts_at": datetime.datetime.now(datetime.timezone.utc).isoformat()}, own)
two_h_ago = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=2)).replace(microsecond=0)
body = {"event_id": ev["id"], "national_id": "55554444", "name": "Offline Voter", "sex": "F", "county": "Migori", "constituency": "Rongo", "ward": "North Kamagambo"}
h = {"Idempotency-Key": "chk-1", "X-Recorded-At": two_h_ago.isoformat().replace("+00:00", "Z")}
s1, r1, h1 = callh("POST", "/checkins", body, own, h)
s2, r2, h2 = callh("POST", "/checkins", body, own, h)
ok("queued check-in synced once", s1 == 201 and s2 == 201 and r1["id"] == r2["id"] and h2.get("Idempotent-Replay") == "true", (s1, s2, h2.get("Idempotent-Replay")))
at = datetime.datetime.fromisoformat(r1["checked_in_at"])
ok("check-in keeps the device's recorded time", abs((at - two_h_ago).total_seconds()) < 1, (r1["checked_in_at"], two_h_ago))
s3, r3, _ = callh("POST", "/checkins", body, own, {"Idempotency-Key": "chk-2"})
ok("a genuinely new attempt still hits same-day dedup", s3 == 409 and r3.get("code") == "already_checked_in", (s3, r3))
s4, r4, _ = callh("POST", "/mobilizations", {}, own, {"Idempotency-Key": "chk-1"})
ok("reusing a key for another request is rejected", s4 == 422, (s4, r4))
fut = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=2)).isoformat()
s5, r5, _ = callh("POST", "/checkins", {**body, "national_id": "55554445"}, own, {"X-Recorded-At": fut})
ok("future device clock falls back to server time", s5 == 201 and abs((datetime.datetime.fromisoformat(r5["checked_in_at"]) - datetime.datetime.now(datetime.timezone.utc)).total_seconds()) < 60, r5)
before = len(call("GET", "/ops/stations/MGR-001", tok=ag_t)[1]["incidents"])
ih = {"Idempotency-Key": "inc-1", "X-Recorded-At": two_h_ago.isoformat()}
callh("POST", "/ops/stations/MGR-001/incidents", {"type": "Security concern", "description": "offline"}, ag_t, ih)
callh("POST", "/ops/stations/MGR-001/incidents", {"type": "Security concern", "description": "offline"}, ag_t, ih)
d = call("GET", "/ops/stations/MGR-001", tok=ag_t)[1]
ok("queued incident retried twice is recorded once", len(d["incidents"]) == before + 1, len(d["incidents"]) - before)
inc_at = datetime.datetime.fromisoformat(d["incidents"][0]["created_at"])
ok("incident keeps device time", abs((inc_at - two_h_ago).total_seconds()) < 1, d["incidents"][0]["created_at"])
s6, r6, _ = callh("POST", "/ops/stations/MGR-003/status", {"status": "open"}, ag_t, {"Idempotency-Key": "st-x"})
s7, r7, _ = callh("POST", "/ops/stations/MGR-003/status", {"status": "open"}, ag_t, {"Idempotency-Key": "st-x"})
ok("stored 4xx replays identically (agent not assigned)", s6 == 403 and s7 == 403 and r6 == r7, (s6, s7))

# ---- revocation signal for field-app auto-wipe ----
st, r = call("GET", "/me", tok="not-a-token"); ok("bad token -> token_invalid", st == 401 and r.get("code") == "token_invalid", r)
kt = login("kevin@test.local", "agentpass1")
call("PATCH", f"/ops/people/{ag1['id']}", {"active": False}, mgr_t)
st, r = call("GET", "/me", tok=kt); ok("deactivated account -> account_inactive", st == 401 and r.get("code") == "account_inactive", r)
call("PATCH", f"/ops/people/{ag1['id']}", {"active": True}, mgr_t)

print("FAILURES" if ok.fail else "ALL PASSED")
sys.exit(1 if ok.fail else 0)
