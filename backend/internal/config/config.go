package config

import (
	"log"
	"os"
	"time"
)

type Config struct {
	Addr        string
	DatabaseURL string
	JWTSecret   []byte
	TokenTTL    time.Duration
	CORSOrigins string
}

func Load() Config {
	c := Config{
		Addr:        env("ADDR", ":8080"),
		DatabaseURL: env("DATABASE_URL", "postgres://postgres@localhost:5432/checkin?sslmode=disable"),
		JWTSecret:   []byte(env("JWT_SECRET", "")),
		TokenTTL:    12 * time.Hour,
		CORSOrigins: env("CORS_ORIGINS", "http://localhost:5173"),
	}
	if len(c.JWTSecret) == 0 {
		if env("APP_ENV", "dev") != "dev" {
			log.Fatal("JWT_SECRET must be set outside dev")
		}
		c.JWTSecret = []byte("dev-only-insecure-secret")
	}
	return c
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
