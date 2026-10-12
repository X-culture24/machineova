# Checkin monorepo — Go API, React dashboard, Flutter field app.
DATABASE_URL ?= postgres://postgres@localhost:5432/checkin?sslmode=disable
export DATABASE_URL

.PHONY: api dashboard mobile db bootstrap import-register import-registry build test e2e

db:                 ## Create the local database (Postgres.app / local server)
	createdb checkin 2>/dev/null || true

api:                ## Run the Go API on :8080 (migrations run on start)
	cd backend && go run ./cmd/api

bootstrap:          ## Create the first platform admin: make bootstrap EMAIL=... PASSWORD=...
	cd backend && go run ./cmd/bootstrap -email "$(EMAIL)" -password "$(PASSWORD)"

import-register:    ## Load the voter register: make import-register FILE=path/to/register.csv
	cd backend && go run ./cmd/import-register -file "$(abspath $(FILE))"

import-registry:    ## Load polling stations / parties: make import-registry STATIONS=stations.csv PARTIES=parties.csv
	cd backend && go run ./cmd/import-registry $(if $(STATIONS),-stations "$(abspath $(STATIONS))") $(if $(PARTIES),-parties "$(abspath $(PARTIES))")

e2e:                ## Election Ops end-to-end run on a throwaway DB: make e2e DATABASE_URL=postgres://.../checkin_e2e
	cd backend && go build -o bin/e2e-api ./cmd/api \
		&& go run ./cmd/import-registry -stations testdata/sample_stations.csv -parties testdata/sample_parties.csv \
		&& go run ./cmd/bootstrap -email ops@test.local -password testpass123
	ADDR=:8098 backend/bin/e2e-api & pid=$$!; sleep 2; \
		API=http://localhost:8098 python3 backend/scripts/e2e_ops.py; status=$$?; kill $$pid; exit $$status

dashboard:          ## Run the dashboard on :5173 (proxies /api to :8080)
	cd dashboard && npm install && npm run dev

mobile:             ## Run the Flutter app against the local API (Android emulator)
	cd mobile && flutter run --dart-define=API_URL=http://10.0.2.2:8080

build:
	cd backend && go build ./...
	cd dashboard && npm run build

test:
	cd backend && go vet ./... && go test ./...
	cd dashboard && npm run typecheck
