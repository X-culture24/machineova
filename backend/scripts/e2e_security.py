"""End-to-end: lockout, invitations, password reset, audit log, app download.

Runs against an API without SMTP (emails are logged), reading invite/reset links from the
server log. Creates a throwaway org; prints PASS/FAIL only.

  API=http://localhost:8080 LOG=/path/to/api.log python3 scripts/e2e_security.py
"""
import json, os, re, sys, time, urllib.error, urllib.request, uuid

B = os.environ.get("API", "http://localhost:8080") + "/api"
LOG = os.environ["LOG"]
fails = 0


def call(method, path, body=None, tok=None, raw=False):
    req = urllib.request.Request(B + path, method=method, data=None if body is None else json.dumps(body).encode())
    req.add_header("Content-Type", "application/json")
    if tok:
        req.add_header("Authorization", "Bearer " + tok)
    try:
        with urllib.request.urlopen(req) as r:
            data = r.read()
            return r.status, (data if raw else (json.loads(data) if data else None)), dict(r.headers)
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}"), dict(e.headers)


def ok(label, cond, extra=""):
    global fails
    print(("PASS " if cond else "FAIL ") + label + ("" if cond else f"  -> {extra}"))
    fails += 0 if cond else 1


def login(u, p):
    st, r, _ = call("POST", "/auth/login", {"login": u, "password": p})
    return st, r


def link_for(email, page):
    """Latest invite/reset link emailed to `email` (from the server log)."""
    time.sleep(0.4)
    pat = re.compile(re.escape(email) + r'.*?(' + re.escape(page) + r'\?token=[0-9a-f]{64})')
    found = None
    with open(LOG, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = pat.search(line)
            if m:
                found = m.group(1)
    return found.split("token=")[1] if found else None


run = uuid.uuid4().hex[:6]
_, plat = login(os.environ.get("PLATFORM_EMAIL", "ops@test.local"), os.environ.get("PLATFORM_PASSWORD", "testpass123"))
plat = plat["token"]
owner = f"owner-{run}@test.local"
st, org, _ = call("POST", "/platform/organizations", {"name": f"Security Test {run}", "boundary_county": "Nairobi",
    "owner_name": "Test Owner", "owner_email": owner, "owner_password": "ownerpass1", "accent_color": "#8B2CF5",
    "contact_email": f"ops-{run}@test.local"}, plat)
ok("create org", st == 201, org)
_, o = login(owner, "ownerpass1")
own = o["token"]

# --- invitation: add a member without a password
member = f"member-{run}@test.local"
st, m, _ = call("POST", "/team", {"name": "Invited Member", "email": member, "role": "member"}, own)
ok("add member without a password -> invited", st == 201 and m.get("invited") is True, m)
st, r = login(member, "anything")
ok("invited member can't sign in before accepting", st == 401, r)
tok = link_for(member, "/accept")
ok("invitation email contains a single-use link", bool(tok), "no link in log")
st, r, _ = call("POST", "/auth/redeem", {"token": tok, "password": "short"})
ok("password under 8 characters rejected", st == 400, r)
st, r, _ = call("POST", "/auth/redeem", {"token": tok, "password": "memberpass1"})
ok("accepting the invitation sets the password", st == 200 and r.get("email") == member, r)
st, r = login(member, "memberpass1")
ok("member signs in with the new password", st == 200 and r.get("token"), r)
st, r, _ = call("POST", "/auth/redeem", {"token": tok, "password": "another-pass1"})
ok("invitation link can't be used twice", st == 400 and r.get("code") == "link_invalid", r)

# --- lockout after 5 wrong passwords
codes = [login(member, "wrong-password")[0] for _ in range(5)]
ok("5 wrong passwords: 401 x4 then locked (429)", codes == [401, 401, 401, 401, 429], codes)
st, r = login(member, "memberpass1")
ok("correct password refused while locked", st == 429 and r.get("code") == "account_locked", r)

# --- forgot password unlocks via reset link
st, r, _ = call("POST", "/auth/forgot", {"login": member})
ok("forgot password answers generically", st == 200 and "If that account exists" in r.get("message", ""), r)
st, r2, _ = call("POST", "/auth/forgot", {"login": f"nobody-{run}@test.local"})
ok("unknown email gets the same answer (no account discovery)", st == 200 and r2.get("message") == r.get("message"), r2)
rt = link_for(member, "/reset")
ok("reset email contains a link", bool(rt), "no reset link")
st, r, _ = call("POST", "/auth/redeem", {"token": rt, "password": "newmemberpass1"})
ok("reset link sets a new password", st == 200, r)
st, r = login(member, "newmemberpass1")
ok("reset also clears the lockout: sign-in works", st == 200, r)

# --- re-send invite endpoint
st, r, _ = call("POST", f"/team/{m['id']}/invite", {}, own)
ok("owner can re-send an invitation", st == 200 and r.get("sent_to") == member, r)

# --- audit log
st, log, _ = call("GET", "/audit?limit=200", tok=own)
actions = [e["action"] for e in log] if st == 200 else []
ok("audit log is readable by the owner", st == 200 and len(actions) > 0, st)
for needle in ["POST /api/team", "LOGIN failed", "LOGIN failed — account locked", "LOGIN blocked (locked)",
               "PASSWORD reset requested", "PASSWORD set via invite link", "PASSWORD set via reset link", "LOGIN"]:
    ok(f"audit log records: {needle}", needle in actions, actions[:8])
_, mt = login(member, "newmemberpass1")
st, r, _ = call("GET", "/audit", tok=mt["token"])
ok("members can't read the audit log", st == 403, r)

# --- field app download (signed-in only)
st, info, _ = call("GET", "/app", tok=own)
ok("app info available to signed-in users", st == 200 and info.get("available") is True, info)
st, body, headers = call("GET", "/app/download", tok=own, raw=True)
ok("APK downloads with the right content type", st == 200 and headers.get("Content-Type") == "application/vnd.android.package-archive"
   and len(body) > 1_000_000, (st, headers.get("Content-Type")))
st, r, _ = call("GET", "/app/download")
ok("APK is not public", st == 401, st)

print(f"\n{'ALL PASSED' if not fails else str(fails) + ' FAILED'}")
sys.exit(1 if fails else 0)
