// Package studio backs the Node Studio dashboard on iOS.
//
// The dashboard surfaces a few high-level numbers (listening minutes, liked
// tracks, recent artists, top genres) plus the user's most-listened artists.
// Numbers are aggregated from listen_history and the favorites table.
package studio

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"

	"sphere-backend/internal/favorites"
	"sphere-backend/internal/history"
)

// Summary is the JSON payload returned to clients.
type Summary struct {
	ListeningMinutes  int      `json:"listening_minutes"`
	LikedTracks       int      `json:"liked_tracks"`
	RecentArtists     int      `json:"recent_artists"`
	TopGenres         []string `json:"top_genres"`
	TopArtists        []string `json:"top_artists"`
	HistoryEntries    int      `json:"history_entries"`
}

// Service exposes the dashboard data.
type Service struct {
	db      *pgxpool.Pool
	history *history.Service
	favs    *favorites.Service
}

// NewService wires the studio service.
func NewService(db *pgxpool.Pool, hist *history.Service, favs *favorites.Service) *Service {
	return &Service{db: db, history: hist, favs: favs}
}

// Summary returns the dashboard snapshot for `userID`.
//
// We deliberately keep the queries cheap and short-circuit on errors so a
// single broken counter does not break the screen.
func (s *Service) Summary(ctx context.Context, userID string) Summary {
	out := Summary{
		TopGenres:  []string{},
		TopArtists: []string{},
	}

	if s.db != nil && userID != "" {
		// Total entries in last 30 days (used as a proxy for "how active is the user").
		var total int
		_ = s.db.QueryRow(ctx,
			`SELECT COUNT(*) FROM listen_history
			   WHERE user_id = $1 AND listened_at > now() - interval '30 days'`,
			userID,
		).Scan(&total)
		out.HistoryEntries = total

		// Approximate listening minutes — three minutes per non-skipped entry.
		var played int
		_ = s.db.QueryRow(ctx,
			`SELECT COUNT(*) FROM listen_history
			   WHERE user_id = $1
			     AND COALESCE(skipped, false) = false
			     AND listened_at > now() - interval '30 days'`,
			userID,
		).Scan(&played)
		out.ListeningMinutes = played * 3

		// Distinct artists in the last week.
		var recent int
		_ = s.db.QueryRow(ctx,
			`SELECT COUNT(DISTINCT artist) FROM listen_history
			   WHERE user_id = $1 AND artist <> ''
			     AND listened_at > now() - interval '7 days'`,
			userID,
		).Scan(&recent)
		out.RecentArtists = recent
	}

	if s.history != nil && userID != "" {
		if g, err := s.history.TopGenres(ctx, userID, 6); err == nil && g != nil {
			out.TopGenres = g
		}
		if a, err := s.history.TopArtists(ctx, userID, 6); err == nil && a != nil {
			out.TopArtists = a
		}
	}

	if s.favs != nil && userID != "" {
		if liked, err := s.favs.List(ctx, userID, "track"); err == nil {
			out.LikedTracks = len(liked)
		}
	}

	return out
}
