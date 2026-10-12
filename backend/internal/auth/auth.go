// Package auth handles password hashing and signed session tokens.
package auth

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

func HashPassword(pw string) (string, error) {
	b, err := bcrypt.GenerateFromPassword([]byte(pw), bcrypt.DefaultCost)
	return string(b), err
}

func CheckPassword(hash, pw string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(pw)) == nil
}

type Tokens struct {
	Secret []byte
	TTL    time.Duration
}

func (t Tokens) Issue(userID string) (string, time.Time, error) {
	exp := time.Now().Add(t.TTL)
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.RegisteredClaims{
		Subject:   userID,
		IssuedAt:  jwt.NewNumericDate(time.Now()),
		ExpiresAt: jwt.NewNumericDate(exp),
		Issuer:    "checkin",
	})
	s, err := tok.SignedString(t.Secret)
	return s, exp, err
}

// Verify returns the user ID carried by a valid, unexpired token.
func (t Tokens) Verify(raw string) (string, error) {
	var claims jwt.RegisteredClaims
	_, err := jwt.ParseWithClaims(raw, &claims, func(*jwt.Token) (any, error) { return t.Secret, nil },
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithIssuer("checkin"),
		jwt.WithExpirationRequired(),
	)
	if err != nil {
		return "", err
	}
	if claims.Subject == "" {
		return "", errors.New("token has no subject")
	}
	return claims.Subject, nil
}
