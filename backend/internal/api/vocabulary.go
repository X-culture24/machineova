package api

import (
	"context"
	"errors"
	"strings"

	"github.com/jackc/pgx/v5"
)

// Vocabularies: the words an organization's dashboard and field app use.
const (
	vocabStandard    = "standard"
	vocabSDICSChiefs = "sdics_chiefs"
)

func validVocabulary(v string) bool { return v == vocabStandard || v == vocabSDICSChiefs }

// orgVocabulary is the organization's wording (standard when unknown).
func (s *Server) orgVocabulary(ctx context.Context, orgID string) (string, error) {
	var v string
	err := s.db.QueryRow(ctx, `SELECT vocabulary FROM organizations WHERE id=$1`, orgID).Scan(&v)
	if errors.Is(err, pgx.ErrNoRows) {
		return vocabStandard, nil
	}
	return v, err
}

// phoneMissing: chief training marks each chief present and collects their phone number, so it's
// required there; campaigns keep it optional.
func phoneMissing(vocab string, phone *string) bool {
	return vocab == vocabSDICSChiefs && (phone == nil || strings.TrimSpace(*phone) == "")
}
