package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/machinenova/checkin/backend/internal/api"
	"github.com/machinenova/checkin/backend/internal/auth"
	"github.com/machinenova/checkin/backend/internal/config"
	"github.com/machinenova/checkin/backend/internal/db"
	"github.com/machinenova/checkin/backend/internal/mail"
)

func main() {
	cfg := config.Load()
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	pool, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		slog.Error("database", "err", err)
		os.Exit(1)
	}
	defer pool.Close()
	if err := db.Migrate(ctx, pool); err != nil {
		slog.Error("migrate", "err", err)
		os.Exit(1)
	}

	// Optional: the SDICS register and ID records, read-only. The API still starts without it.
	var sdics *pgxpool.Pool
	if url := os.Getenv("SDICS_DATABASE_URL"); url != "" {
		if sdics, err = db.Connect(ctx, url); err != nil {
			slog.Error("sdics database unavailable; lookups use MachineNova's own records only", "err", err)
			sdics = nil
		} else {
			defer sdics.Close()
			slog.Info("sdics lookups enabled")
		}
	}

	server := api.New(pool, auth.Tokens{Secret: cfg.JWTSecret, TTL: cfg.TokenTTL}, cfg.CORSOrigins).
		WithOptions(api.Options{Mail: mail.FromEnv(), AppURL: cfg.AppURL, ApkPath: cfg.ApkPath, SDICS: sdics})
	go server.RunScheduler(ctx) // daily turnout digest
	srv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           server.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
	}
	go func() {
		slog.Info("checkin api listening", "addr", cfg.Addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("server", "err", err)
			stop()
		}
	}()
	<-ctx.Done()
	shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	srv.Shutdown(shutdown)
}
