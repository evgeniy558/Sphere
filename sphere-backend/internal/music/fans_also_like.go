package music

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"sphere-backend/internal/model"
)

// FansAlsoLike returns artists that listeners of the given artist also enjoy,
// based on listen_history co-occurrence.
// GET /artists/{provider}/{id}/fans-also-like
func (h *Handler) FansAlsoLike(w http.ResponseWriter, r *http.Request) {
	if h.pool == nil {
		http.Error(w, `{"error":"database unavailable"}`, http.StatusServiceUnavailable)
		return
	}

	prov := chi.URLParam(r, "provider")
	id := chi.URLParam(r, "id")
	limit := 12

	artistName, err := h.resolveArtistName(r.Context(), prov, id)
	if err != nil || strings.TrimSpace(artistName) == "" {
		http.Error(w, `{"error":"artist not found"}`, http.StatusNotFound)
		return
	}

	artists, err := h.fansAlsoLikeArtists(r.Context(), h.pool, artistName, limit)
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}
	if artists == nil {
		artists = []model.Artist{}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"artists": artists})
}

func (h *Handler) resolveArtistName(ctx context.Context, provider, id string) (string, error) {
	a, err := h.svc.GetArtist(ctx, provider, id)
	if err == nil && a != nil && strings.TrimSpace(a.Name) != "" {
		return a.Name, nil
	}
	if h.pool != nil {
		var name string
		q := `SELECT artist FROM listen_history WHERE provider = $1 AND track_id = $2 AND artist <> '' LIMIT 1`
		if scanErr := h.pool.QueryRow(ctx, q, provider, id).Scan(&name); scanErr == nil {
			if trimmed := strings.TrimSpace(name); trimmed != "" {
				return trimmed, nil
			}
		}
	}
	if err != nil {
		return "", err
	}
	return "", fmt.Errorf("artist not found")
}

func (h *Handler) fansAlsoLikeArtists(ctx context.Context, pool *pgxpool.Pool, artistName string, limit int) ([]model.Artist, error) {
	if limit <= 0 {
		limit = 12
	}
	norm := strings.ToLower(strings.TrimSpace(artistName))

	rows, err := pool.Query(ctx, `
WITH fans AS (
  SELECT DISTINCT user_id
  FROM listen_history
  WHERE lower(trim(artist)) = $1
),
other_artists AS (
  SELECT lh.artist AS name, COUNT(*) AS score
  FROM listen_history lh
  INNER JOIN fans f ON f.user_id = lh.user_id
  WHERE lower(trim(lh.artist)) <> $1
    AND trim(lh.artist) <> ''
  GROUP BY lh.artist
  ORDER BY score DESC
  LIMIT $2
)
SELECT name FROM other_artists`, norm, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []model.Artist
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			continue
		}
		name = strings.TrimSpace(name)
		if name == "" {
			continue
		}
		out = append(out, model.Artist{
			ID:       "unified:" + strings.ToLower(name),
			Provider: "all",
			Name:     name,
		})
	}
	return out, nil
}
