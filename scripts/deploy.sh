#!/usr/bin/env bash
# Deploy MachineNova (Go API + tools + dashboard) to the production server over SSH as root.
#
#   make deploy                  # test, build, back up, upload, restart, health-check
#   SKIP_TESTS=1 make deploy     # skip go vet/test and the dashboard typecheck
#   DEPLOY_APK=1 make deploy     # also rebuild the field app APK and publish it
#
# On the server: binaries in /opt/machinenova/bin, dashboard in /var/www/machinenova/dashboard,
# service machinenova-api (migrations run on start). Each deploy first saves the current
# binaries, dashboard and a database dump to /opt/machinenova/backup-<time> (the last 5 are
# kept) and rolls the binaries back automatically if the API doesn't come up healthy.
set -euo pipefail

HOST="${DEPLOY_HOST:-root@206.81.28.246}"
PUBLIC_URL="${PUBLIC_URL:-http://206.81.28.246}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
step() { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }

if [[ "${SKIP_TESTS:-}" != 1 ]]; then
  step "Checks"
  (cd "$ROOT/backend" && go vet ./... && go test ./...)
  (cd "$ROOT/dashboard" && npm run typecheck --silent)
fi

step "Build API and tools (linux/amd64)"
mkdir -p "$STAGE/bin"
for cmd in "$ROOT"/backend/cmd/*/; do
  name="$(basename "$cmd")"
  (cd "$ROOT/backend" && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o "$STAGE/bin/$name" "./cmd/$name")
  echo "  $name"
done

step "Build dashboard"
(cd "$ROOT/dashboard" && npm run build --silent >/dev/null)
cp -R "$ROOT/dashboard/dist" "$STAGE/dashboard"

if [[ "${DEPLOY_APK:-}" == 1 ]]; then
  step "Build field app APK"
  export JAVA_HOME="${JAVA_HOME:-$HOME/development/jdk-17/Contents/Home}"
  export PATH="$JAVA_HOME/bin:$PATH"
  FLUTTER="${FLUTTER:-$(command -v flutter || echo "$HOME/development/flutter/bin/flutter")}"
  # One APK per CPU type (about 42 MB instead of 108 MB); the 64-bit ARM build fits nearly every phone.
  (cd "$ROOT/mobile" && "$FLUTTER" build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols \
    --dart-define=API_URL="$PUBLIC_URL" >/dev/null)
  cp "$ROOT/mobile/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk" "$STAGE/MachineNova.apk"
fi

step "Back up the server"
BACKUP="$(ssh "$HOST" 'set -e
  B=/opt/machinenova/backup-$(date +%Y%m%d%H%M%S)
  mkdir -p "$B"
  cp -r /opt/machinenova/bin "$B/"
  cp -r /var/www/machinenova/dashboard "$B/"
  set -a; . /opt/machinenova/.env; set +a
  pg_dump -Fc "$DATABASE_URL" > "$B/checkin.dump"
  ls -dt /opt/machinenova/backup-* | tail -n +6 | xargs -r rm -rf   # keep the last 5
  echo "$B"')"
echo "  $BACKUP"

step "Upload"
ssh "$HOST" 'rm -rf /opt/machinenova/staging && mkdir -p /opt/machinenova/staging'
scp -qr "$STAGE"/. "$HOST:/opt/machinenova/staging/"

step "Install and restart"
ssh "$HOST" "set -e; cd /opt/machinenova
  install -m 755 staging/bin/* bin/
  rsync -a --delete staging/dashboard/ /var/www/machinenova/dashboard/
  if [ -f staging/MachineNova.apk ]; then install -m 640 -o root -g machinenova staging/MachineNova.apk data/MachineNova.apk; fi
  rm -rf staging
  systemctl restart machinenova-api
  for i in \$(seq 1 20); do curl -fsS http://127.0.0.1:8081/healthz >/dev/null 2>&1 && exit 0; sleep 1; done
  echo 'API not healthy — rolling back binaries to $BACKUP' >&2
  journalctl -u machinenova-api -n 20 --no-pager >&2
  install -m 755 $BACKUP/bin/* bin/
  rsync -a --delete $BACKUP/dashboard/ /var/www/machinenova/dashboard/
  systemctl restart machinenova-api
  exit 1"

step "Smoke test $PUBLIC_URL"
curl -fsS -o /dev/null "$PUBLIC_URL/" && echo "  dashboard ok"
code="$(curl -s -o /dev/null -w '%{http_code}' "$PUBLIC_URL/api/me")"
[[ "$code" == 401 ]] && echo "  api ok (401 without a token)" || { echo "  api returned $code" >&2; exit 1; }
echo
echo "Deployed. Backup: $HOST:$BACKUP"
