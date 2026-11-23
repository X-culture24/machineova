"""Training issues end-to-end: log, scope, edit, resolve, chief look-up and the issues report.
   API=http://localhost:8099 python3 backend/scripts/e2e_issues.py  (platform admin ops@test.local / testpass123)"""
import json, os, sys, urllib.request
API = os.environ.get("API", "http://localhost:8099") + "/api"
def call(method, path, body=None, tok=None):
    req = urllib.request.Request(API + path, method=method, data=json.dumps(body).encode() if body is not None else None,
        headers={"Content-Type": "application/json", **({"Authorization": "Bearer " + tok} if tok else {})})
    try:
        with urllib.request.urlopen(req, timeout=30) as r: raw = r.read(); return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e: raw = e.read(); return e.code, (json.loads(raw) if raw else {})
fails = 0
def ok(name, cond, detail=""):
    global fails
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else f"  -> {detail}"))
    fails += 0 if cond else 1
def login(u, p): return call("POST", "/auth/login", {"login": u, "password": p})[1]["token"]

plat = login("ops@test.local", "testpass123")
st, org = call("POST", "/platform/organizations", {"name": "Issues Test Campaign", "owner_name": "Olive Owner",
    "owner_email": "owner@issues.test", "owner_password": "ownerpass1", "accent_color": "#0D9488", "contact_email": "ops@issues.test"}, plat)
ok("create org", st in (200, 201), org)
own = login("owner@issues.test", "ownerpass1")
st, e1 = call("POST", "/events", {"name": "Baringo chiefs training", "venue": "Kabarnet hall", "county": "Baringo", "starts_at": "2026-11-20T06:00:00Z"}, own)
ok("event 1", st in (200, 201), e1)
st, e2 = call("POST", "/events", {"name": "Bomet chiefs training", "venue": "Bomet hall", "county": "Bomet", "starts_at": "2026-11-21T06:00:00Z"}, own)
ok("event 2", st in (200, 201), e2)
st, m = call("POST", "/team", {"name": "Tom Trainer", "email": "trainer@issues.test", "role": "member", "password": "trainpass1"}, own)
ok("member", st in (200, 201), m)
st, r = call("PUT", f"/events/{e1['id']}/assignments", {"user_ids": [m["id"]]}, own); ok("assign member to event 1", st in (200, 204), r)
mem = login("trainer@issues.test", "trainpass1")

base = {"chief_name": "Grace Chepkoech", "national_id": "2345 6789", "phone": "0712345678", "location": "Kapropita, Kabarnet"}
st, i1 = call("POST", "/issues", {**base, "event_id": e1["id"], "category": "internet", "description": "No data bundles on the phone; could not download the roll."}, mem)
ok("member logs an issue at their training", st == 201 and i1.get("national_id") == "23456789" and i1.get("reported_by") == "Tom Trainer" and i1.get("event_name") == "Baringo chiefs training", (st, i1))
st, r = call("POST", "/issues", {**base, "event_id": e2["id"], "category": "device", "description": "x"}, mem)
ok("member refused at a training not theirs", st == 400, (st, r))
st, r = call("POST", "/issues", {**base, "category": "weather", "description": "x"}, mem); ok("unknown category refused", st == 400, (st, r))
st, r = call("POST", "/issues", {**base, "category": "device", "description": "  "}, mem); ok("empty description refused", st == 400, (st, r))
st, i2 = call("POST", "/issues", {"event_id": e2["id"], "category": "location", "chief_name": "Daniel Kiprono", "national_id": "11112222",
    "description": "SDICS has him in the wrong location.", "action_taken": "Sent to HQ to correct.", "status": "resolved"}, own)
ok("owner logs a resolved issue", st == 201 and i2.get("status") == "resolved" and i2.get("resolved_at"), (st, i2))
st, i3 = call("POST", "/issues", {"category": "other", "description": "Venue changed at short notice."}, own)
ok("issue with no training", st == 201 and i3.get("event_id") is None, (st, i3))

st, r = call("GET", "/issues", tok=mem); ok("member sees only theirs / their training", st == 200 and [x["id"] for x in r["items"]] == [i1["id"]], r)
st, r = call("GET", "/issues", tok=own); ok("owner sees all 3", st == 200 and len(r["items"]) == 3, r)
st, r = call("GET", f"/issues?status=open&category=internet", tok=own); ok("filters", st == 200 and len(r["items"]) == 1, r)
st, r = call("GET", f"/issues?event_id={e2['id']}", tok=own); ok("filter by training", st == 200 and len(r["items"]) == 1, r)

st, r = call("PATCH", f"/issues/{i2['id']}", {"event_id": e2["id"], "category": "location", "description": "changed", "status": "open"}, mem)
ok("member can't change someone else's issue", st == 404, (st, r))
upd = {"event_id": e1["id"], "category": "internet", **base, "description": i1["description"], "action_taken": "Shared a hotspot.", "status": "resolved"}
st, r = call("PATCH", f"/issues/{i1['id']}", upd, mem)
ok("reporter resolves with the action taken", st == 200 and r["status"] == "resolved" and r["action_taken"] == "Shared a hotspot." and r["resolved_at"], (st, r))

st, r = call("GET", f"/issues/chief?event_id={e1['id']}&national_id=99999999", tok=mem); ok("chief look-up: not checked in -> 404", st == 404, (st, r))

st, r = call("GET", "/issues/report", tok=mem); ok("report is for administrators", st == 403, (st, r))
st, rep = call("GET", "/issues/report", tok=own)
t = {x["name"]: x for x in rep.get("trainings", [])}
ok("report", st == 200 and len(rep["issues"]) == 3 and rep["open"] == 1 and rep["by_category"] == {"internet": 1, "location": 1, "other": 1}
   and t["Baringo chiefs training"]["issues"] == 1 and t["Bomet chiefs training"]["by_category"] == {"location": 1}, (st, rep))
print("\n" + ("ALL PASS" if fails == 0 else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
