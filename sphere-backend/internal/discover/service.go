// Package discover powers the "Find something new" swipe deck on iOS.
//
// The service produces a randomized but personalized stream of catalog tracks
// that the user has not yet liked or listened to. It reuses the existing
// recommend pipeline as the source of truth and layers a few cheap variations
// on top so the deck never feels empty.
package discover

import (
	"context"
	"math/rand"
	"sort"
	"strings"
	"sync"
	"time"

	"sphere-backend/internal/favorites"
	"sphere-backend/internal/history"
	"sphere-backend/internal/model"
	"sphere-backend/internal/recommend"
)

// FeedResponse mirrors the JSON returned to clients.
type FeedResponse struct {
	Tracks []model.Track `json:"tracks"`
	Cursor string        `json:"cursor,omitempty"`
}

// Service builds the discover feed and records swipe feedback.
type Service struct {
	recs    *recommend.Service
	history *history.Service
	favs    *favorites.Service

	cacheMu sync.Mutex
	// Per-user shuffled deck cache (lightweight in-memory pool).
	cache map[string]cacheEntry
}

type cacheEntry struct {
	tracks    []model.Track
	expiresAt time.Time
}

const cacheTTL = 4 * time.Minute

// NewService wires the discover service to its dependencies.
func NewService(recs *recommend.Service, hist *history.Service, favs *favorites.Service) *Service {
	return &Service{
		recs:    recs,
		history: hist,
		favs:    favs,
		cache:   make(map[string]cacheEntry),
	}
}

// Feed returns up to limit tracks for the swipe deck. `excluded` lets the
// client skip tracks it already has on screen.
func (s *Service) Feed(ctx context.Context, userID, lang string, limit int, excluded map[string]bool) FeedResponse {
	if limit <= 0 {
		limit = 20
	}
	if limit > 60 {
		limit = 60
	}

	pool := s.fetchPool(ctx, userID, lang)
	if len(pool) == 0 {
		return FeedResponse{Tracks: []model.Track{}}
	}

	// Drop tracks already liked.
	if userID != "" && s.favs != nil {
		if liked, err := s.favs.List(ctx, userID, "track"); err == nil {
			likedKeys := make(map[string]bool, len(liked))
			for _, fav := range liked {
				likedKeys[strings.ToLower(fav.Provider+":"+fav.ProviderItemID)] = true
			}
			pool = filterTracks(pool, likedKeys)
		}
	}

	// Drop tracks the client already has on screen.
	if len(excluded) > 0 {
		pool = filterTracks(pool, excluded)
	}

	if len(pool) > limit {
		pool = pool[:limit]
	}
	return FeedResponse{Tracks: pool}
}

func (s *Service) fetchPool(ctx context.Context, userID, lang string) []model.Track {
	cacheKey := userID + "|" + strings.ToLower(strings.TrimSpace(lang))
	s.cacheMu.Lock()
	if entry, ok := s.cache[cacheKey]; ok && time.Now().Before(entry.expiresAt) {
		s.cacheMu.Unlock()
		return shuffleCopy(entry.tracks)
	}
	s.cacheMu.Unlock()

	pool := []model.Track{}
	if s.recs != nil {
		recs := s.recs.GetRecommendations(ctx, userID, lang)
		if recs != nil {
			pool = append(pool, recs.Tracks...)
		}
	}

	pool = dedupeTracks(pool)
	rand.New(rand.NewSource(time.Now().UnixNano())).Shuffle(len(pool), func(i, j int) {
		pool[i], pool[j] = pool[j], pool[i]
	})

	s.cacheMu.Lock()
	s.cache[cacheKey] = cacheEntry{tracks: pool, expiresAt: time.Now().Add(cacheTTL)}
	s.cacheMu.Unlock()

	return shuffleCopy(pool)
}

// Feedback records a swipe action so we can train the recommend engine.
// Currently we just log it as listen_history with `skipped` flag for skips and
// rely on /favorites for likes (the iOS client already calls /favorites).
func (s *Service) Feedback(ctx context.Context, userID, provider, trackID, action, title, artist string) error {
	if s.history == nil {
		return nil
	}
	if action == "skip" {
		return s.history.Record(ctx, userID, history.Entry{
			Provider: provider,
			TrackID:  trackID,
			Title:    title,
			Artist:   artist,
			Skipped:  true,
		})
	}
	return nil
}

func filterTracks(pool []model.Track, blocked map[string]bool) []model.Track {
	out := make([]model.Track, 0, len(pool))
	for _, t := range pool {
		key := strings.ToLower(t.Provider + ":" + t.ID)
		if blocked[key] {
			continue
		}
		out = append(out, t)
	}
	return out
}

func dedupeTracks(in []model.Track) []model.Track {
	seen := make(map[string]bool, len(in))
	out := make([]model.Track, 0, len(in))
	for _, t := range in {
		k := strings.ToLower(t.Provider + ":" + t.ID)
		if k == ":" || seen[k] {
			continue
		}
		seen[k] = true
		out = append(out, t)
	}
	// Stable order primarily by length so the response feels predictable
	// before being shuffled by the caller.
	sort.SliceStable(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out
}

func shuffleCopy(in []model.Track) []model.Track {
	out := make([]model.Track, len(in))
	copy(out, in)
	rand.New(rand.NewSource(time.Now().UnixNano())).Shuffle(len(out), func(i, j int) {
		out[i], out[j] = out[j], out[i]
	})
	return out
}
