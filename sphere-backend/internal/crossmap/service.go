package crossmap

import (
	"context"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"sphere-backend/internal/model"
	"sphere-backend/internal/music"
)

// Service provides cross-provider track mapping and quality switching.
type Service struct {
	db    *pgxpool.Pool
	music *music.Service
}

func NewService(db *pgxpool.Pool, musicSvc *music.Service) *Service {
	return &Service{db: db, music: musicSvc}
}

// TrackMapping represents a provider-specific version of a canonical track.
type TrackMapping struct {
	Provider       string  `json:"provider"`
	TrackID        string  `json:"track_id"`
	Title          string  `json:"title"`
	Artist         string  `json:"artist"`
	BitrateKbps    int     `json:"bitrate_kbps"`
	Codec          string  `json:"codec"`
	DurationSeconds int    `json:"duration_seconds"`
	Confidence     float64 `json:"confidence"`
	HasFullTrack   bool    `json:"has_full_track"`
}

// FindAlternatives searches all providers for the same track.
func (s *Service) FindAlternatives(ctx context.Context, provider, trackID string) ([]TrackMapping, error) {
	// Get the source track.
	source, err := s.music.GetTrack(ctx, provider, trackID)
	if err != nil {
		return nil, fmt.Errorf("source track: %w", err)
	}

	canonHash := CanonicalHash(source.Artist, source.Title)

	// Check DB cache first.
	cached, err := s.loadMappings(ctx, canonHash)
	if err == nil && len(cached) > 1 {
		return cached, nil
	}

	// Search other providers in parallel.
	query := source.Artist + " " + source.Title
	providers := []string{"spotify", "youtube", "deezer", "soundcloud"}

	var mu sync.Mutex
	var mappings []TrackMapping

	// Add source track.
	mappings = append(mappings, TrackMapping{
		Provider:        provider,
		TrackID:         trackID,
		Title:           source.Title,
		Artist:          source.Artist,
		Codec:           DefaultCodecForProvider(provider),
		BitrateKbps:     bitrateForCodec(DefaultCodecForProvider(provider)),
		DurationSeconds: source.Duration,
		Confidence:      1.0,
		HasFullTrack:    true,
	})

	var wg sync.WaitGroup
	for _, p := range providers {
		if p == provider {
			continue
		}
		p := p
		wg.Add(1)
		go func() {
			defer wg.Done()
			searchCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
			defer cancel()

			result := s.music.Search(searchCtx, query, 5, p)
			if result == nil {
				return
			}

			for _, t := range result.Tracks {
				conf := MatchConfidence(
					source.Title, source.Artist, source.Duration,
					t.Title, t.Artist, t.Duration,
				)
				if conf >= MatchThreshold {
					mu.Lock()
					mappings = append(mappings, TrackMapping{
						Provider:        t.Provider,
						TrackID:         t.ID,
						Title:           t.Title,
						Artist:          t.Artist,
						Codec:           DefaultCodecForProvider(t.Provider),
						BitrateKbps:     bitrateForCodec(DefaultCodecForProvider(t.Provider)),
						DurationSeconds: t.Duration,
						Confidence:      conf,
						HasFullTrack:    true,
					})
					mu.Unlock()
					break // take best match per provider
				}
			}
		}()
	}
	wg.Wait()

	// Save to DB.
	s.saveMappings(ctx, canonHash, source.Artist, source.Title, mappings)

	return mappings, nil
}

// BestSource returns the highest-quality available source for a track.
func (s *Service) BestSource(ctx context.Context, provider, trackID string) (*TrackMapping, error) {
	alts, err := s.FindAlternatives(ctx, provider, trackID)
	if err != nil {
		return nil, err
	}
	if len(alts) == 0 {
		return nil, fmt.Errorf("no sources found")
	}

	best := alts[0]
	for _, a := range alts[1:] {
		if QualityScore(a.Codec) > QualityScore(best.Codec) {
			best = a
		}
	}
	return &best, nil
}

// BatchMatch maps multiple tracks to their cross-provider alternatives.
func (s *Service) BatchMatch(ctx context.Context, tracks []model.Track) map[string][]TrackMapping {
	result := make(map[string][]TrackMapping)
	var mu sync.Mutex
	var wg sync.WaitGroup

	// Limit concurrency.
	sem := make(chan struct{}, 3)

	for _, t := range tracks {
		t := t
		wg.Add(1)
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			alts, err := s.FindAlternatives(ctx, t.Provider, t.ID)
			if err != nil {
				return
			}
			key := t.Provider + ":" + t.ID
			mu.Lock()
			result[key] = alts
			mu.Unlock()
		}()
	}
	wg.Wait()
	return result
}

// SetPreferredSource saves a user's preferred source for a track.
func (s *Service) SetPreferredSource(ctx context.Context, userID, canonicalHash, provider, trackID, reason string) error {
	_, err := s.db.Exec(ctx,
		`INSERT INTO user_track_source (user_id, canonical_hash, preferred_provider, preferred_track_id, reason, updated_at)
		 VALUES ($1, $2, $3, $4, $5, now())
		 ON CONFLICT (user_id, canonical_hash) DO UPDATE SET
			preferred_provider = $3, preferred_track_id = $4, reason = $5, updated_at = now()`,
		userID, canonicalHash, provider, trackID, reason,
	)
	return err
}

// loadMappings loads cached mappings from the database.
func (s *Service) loadMappings(ctx context.Context, canonHash string) ([]TrackMapping, error) {
	rows, err := s.db.Query(ctx,
		`SELECT provider, track_id, canonical_artist, canonical_title,
		        bitrate_kbps, codec, has_full_track, duration_seconds, confidence
		 FROM track_mappings WHERE canonical_hash = $1`,
		canonHash,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var mappings []TrackMapping
	for rows.Next() {
		var m TrackMapping
		var artist, title string
		if err := rows.Scan(&m.Provider, &m.TrackID, &artist, &title,
			&m.BitrateKbps, &m.Codec, &m.HasFullTrack, &m.DurationSeconds, &m.Confidence); err != nil {
			continue
		}
		m.Artist = artist
		m.Title = title
		mappings = append(mappings, m)
	}
	return mappings, nil
}

// saveMappings persists track mappings to the database.
func (s *Service) saveMappings(ctx context.Context, canonHash, artist, title string, mappings []TrackMapping) {
	for _, m := range mappings {
		_, err := s.db.Exec(ctx,
			`INSERT INTO track_mappings (canonical_hash, canonical_artist, canonical_title,
			  provider, track_id, bitrate_kbps, codec, has_full_track, duration_seconds, confidence)
			 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
			 ON CONFLICT (provider, track_id) DO UPDATE SET
				canonical_hash = $1, bitrate_kbps = $6, codec = $7,
				has_full_track = $8, confidence = $10, updated_at = now()`,
			canonHash, artist, title,
			m.Provider, m.TrackID, m.BitrateKbps, m.Codec,
			m.HasFullTrack, m.DurationSeconds, m.Confidence,
		)
		if err != nil {
			log.Printf("[crossmap] save mapping error %s/%s: %v", m.Provider, m.TrackID, err)
		}
	}
}

func bitrateForCodec(codec string) int {
	switch codec {
	case "flac":
		return 1411
	case "mp3_320", "ogg_320":
		return 320
	case "mp3_192":
		return 192
	case "ogg_160":
		return 160
	case "aac_128", "mp3_128":
		return 128
	case "ogg_96":
		return 96
	default:
		return 0
	}
}
