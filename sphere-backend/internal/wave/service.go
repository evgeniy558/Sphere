package wave

import (
	"context"
	"fmt"
	"log"
	"math"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/sync/errgroup"

	"sphere-backend/internal/favorites"
	"sphere-backend/internal/history"
	"sphere-backend/internal/model"
	"sphere-backend/internal/music"
	"sphere-backend/internal/provider"
)

// Service orchestrates personalized "My Wave" radio sessions.
type Service struct {
	db        *pgxpool.Pool
	history   *history.Service
	favorites *favorites.Service
	music     *music.Service
	spotify   *provider.Spotify // may be nil

	sessionsMu sync.Mutex
	sessions   map[string]string // sessionID → userID
}

// NewService creates a new wave Service.
func NewService(db *pgxpool.Pool, historySvc *history.Service, favSvc *favorites.Service, musicSvc *music.Service, spotify *provider.Spotify) *Service {
	return &Service{
		db:        db,
		history:   historySvc,
		favorites: favSvc,
		music:     musicSvc,
		spotify:   spotify,
		sessions:  make(map[string]string),
	}
}

// ---------------------------------------------------------------------------
// StartSession
// ---------------------------------------------------------------------------

// StartSession builds a taste profile from the user's listening history and
// favourites, persists it, and returns a new wave session.
func (s *Service) StartSession(ctx context.Context, userID string) (*WaveSession, error) {
	sessionID := uuid.New().String()

	// Fetch weighted maps in parallel.
	var (
		genreWeights    map[string]float64
		artistWeights   map[string]float64
		favArtistWeights map[string]float64
		providerWeights map[string]float64
		spotFeatures    *avgFeatures
	)

	g, gCtx := errgroup.WithContext(ctx)

	g.Go(func() error {
		var err error
		genreWeights, err = s.history.TopGenresWeighted(gCtx, userID, 30)
		return err
	})
	g.Go(func() error {
		var err error
		artistWeights, err = s.history.TopArtistsWeighted(gCtx, userID, 30)
		return err
	})
	g.Go(func() error {
		var err error
		favArtistWeights, err = s.favorites.TopArtistsWeighted(gCtx, userID, 20)
		return err
	})
	g.Go(func() error {
		var err error
		providerWeights, err = s.history.ProviderWeights(gCtx, userID)
		return err
	})

	if s.spotify != nil {
		g.Go(func() error {
			ids, err := s.history.RecentSpotifyTrackIDs(gCtx, userID, 50)
			if err != nil || len(ids) == 0 {
				return nil // non-fatal
			}
			feats, err := s.spotify.AudioFeatures(gCtx, ids)
			if err != nil || len(feats) == 0 {
				return nil
			}
			var eSum, vSum, tSum float64
			for _, f := range feats {
				eSum += f.Energy
				vSum += f.Valence
				tSum += f.Tempo
			}
			n := float64(len(feats))
			spotFeatures = &avgFeatures{
				Energy:  eSum / n,
				Valence: vSum / n,
				Tempo:   tSum / n,
			}
			return nil
		})
	}

	if err := g.Wait(); err != nil {
		return nil, fmt.Errorf("wave start: %w", err)
	}

	// Merge favourite artists into history artists (take max weight).
	if artistWeights == nil {
		artistWeights = make(map[string]float64)
	}
	for a, w := range favArtistWeights {
		if cur, ok := artistWeights[a]; !ok || w > cur {
			artistWeights[a] = w
		}
	}

	profile := buildTasteProfile(ctx, s.db, genreWeights, artistWeights, providerWeights, spotFeatures)
	profile.UserID = userID

	if err := saveTasteProfile(ctx, s.db, profile); err != nil {
		return nil, fmt.Errorf("wave save profile: %w", err)
	}

	s.sessionsMu.Lock()
	s.sessions[sessionID] = userID
	s.sessionsMu.Unlock()

	return &WaveSession{
		SessionID: sessionID,
		Profile:   *profile,
		CreatedAt: time.Now(),
	}, nil
}

// ---------------------------------------------------------------------------
// NextTracks
// ---------------------------------------------------------------------------

// NextTracks returns the next batch of scored, deduplicated tracks for the session.
func (s *Service) NextTracks(ctx context.Context, userID, sessionID string, count int) ([]model.Track, error) {
	if !s.validateSession(sessionID, userID) {
		return nil, fmt.Errorf("invalid session")
	}

	profile, err := loadTasteProfile(ctx, s.db, userID)
	if err != nil {
		return nil, fmt.Errorf("wave load profile: %w", err)
	}
	if profile == nil {
		return nil, fmt.Errorf("no taste profile found")
	}

	// Build search queries from top genres + artists.
	queries := s.buildSearchQueries(profile, 4, 4)

	// Search all providers in parallel.
	var mu sync.Mutex
	var candidates []model.Track

	eg, egCtx := errgroup.WithContext(ctx)
	for _, q := range queries {
		q := q
		eg.Go(func() error {
			res := s.music.Search(egCtx, q, 15, "")
			if res != nil {
				mu.Lock()
				candidates = append(candidates, res.Tracks...)
				mu.Unlock()
			}
			return nil
		})
	}
	_ = eg.Wait()

	// Add peer-influenced tracks.
	peerKeys, _ := s.history.PeerInfluencedTracks(ctx, userID, 30)
	peerSet := make(map[string]bool, len(peerKeys))
	for _, k := range peerKeys {
		peerSet[k.Provider+":"+k.TrackID] = true
		candidates = append(candidates, model.Track{
			ID:       k.TrackID,
			Provider: k.Provider,
			Title:    k.Title,
			Artist:   k.Artist,
		})
	}

	// Get recently played tracks (last 7 days) for novelty scoring.
	recentlyPlayed := s.recentlyPlayedSet(ctx, userID)

	// Score every candidate — try NodeX AI first, fall back to manual.
	scored := make([]ScoredTrack, 0, len(candidates))
	if NodeXAvailable() && len(candidates) > 0 {
		uc := s.buildUserContext(ctx, userID)
		featureVecs := make([][]float64, len(candidates))
		for i, t := range candidates {
			key := t.Provider + ":" + t.ID
			novelty := 1.0
			if recentlyPlayed[key] {
				novelty = 0.0
			}
			peer := 0.0
			if peerSet[key] {
				peer = 1.0
			}
			e, v := estimateAudioFeatures(t.Genres)
			genreMatch := 0.0
			for _, g := range t.Genres {
				genreMatch += profile.GenreWeights[strings.ToLower(g)]
			}
			if len(t.Genres) > 0 {
				genreMatch /= float64(len(t.Genres))
			}
			artistMatch := profile.ArtistWeights[t.Artist]
			featureVecs[i] = buildFeatureVector(e, v, 120.0, 0.5,
				t.Genres, uc, profile, genreMatch, artistMatch, novelty, peer)
		}
		if scores, err := scoreTracksNodeX(featureVecs); err == nil && len(scores) == len(candidates) {
			log.Printf("[wave] NodeX AI scoring %d candidates", len(candidates))
			for i, t := range candidates {
				scored = append(scored, ScoredTrack{Track: t, Score: scores[i]})
			}
		} else {
			if err != nil {
				log.Printf("[wave] NodeX scoring failed, fallback to manual: %v", err)
			}
			for _, t := range candidates {
				sc := s.scoreTrack(t, profile, recentlyPlayed, peerSet)
				scored = append(scored, ScoredTrack{Track: t, Score: sc})
			}
		}
	} else {
		for _, t := range candidates {
			sc := s.scoreTrack(t, profile, recentlyPlayed, peerSet)
			scored = append(scored, ScoredTrack{Track: t, Score: sc})
		}
	}

	// Deduplicate by artist+title (keep highest score).
	scored = dedup(scored)

	// Apply provider balancing.
	scored = s.balanceProviders(scored, profile.ProviderWeights, count*3)

	// Sort by score descending, take top count.
	sort.Slice(scored, func(i, j int) bool { return scored[i].Score > scored[j].Score })
	if len(scored) > count {
		scored = scored[:count]
	}

	out := make([]model.Track, len(scored))
	for i, st := range scored {
		out[i] = st.Track
	}
	return out, nil
}

// ---------------------------------------------------------------------------
// scoreTrack
// ---------------------------------------------------------------------------

func (s *Service) scoreTrack(track model.Track, profile *TasteProfile, recentlyPlayed map[string]bool, peerTracks map[string]bool) float64 {
	// Genre match (weight 0.30).
	var genreScore float64
	if len(track.Genres) > 0 {
		for _, g := range track.Genres {
			genreScore += profile.GenreWeights[strings.ToLower(g)]
		}
		genreScore /= float64(len(track.Genres))
	}

	// Artist match (weight 0.25).
	artistScore := profile.ArtistWeights[track.Artist]

	// Audio feature match (weight 0.15).
	var audioScore float64
	if track.Provider == "spotify" {
		// For Spotify tracks, use profile prefs directly (features fetched at session start).
		audioScore = 0.5 // neutral when we can't look up per-track features inline
	} else {
		e, v := estimateAudioFeatures(track.Genres)
		eDiff := math.Abs(e - profile.EnergyPref)
		vDiff := math.Abs(v - profile.ValencePref)
		audioScore = math.Max(0, 1.0-eDiff*0.5-vDiff*0.5)
	}

	// Provider match (weight 0.10).
	providerScore := profile.ProviderWeights[track.Provider]
	if providerScore == 0 {
		providerScore = 0.1
	}

	// Novelty (weight 0.10).
	noveltyScore := 1.0
	key := track.Provider + ":" + track.ID
	if recentlyPlayed[key] {
		noveltyScore = 0.0
	}

	// Peer signal (weight 0.10).
	peerScore := 0.0
	if peerTracks[key] {
		peerScore = 1.0
	}

	return genreScore*0.30 +
		artistScore*0.25 +
		audioScore*0.15 +
		providerScore*0.10 +
		noveltyScore*0.10 +
		peerScore*0.10
}

// ---------------------------------------------------------------------------
// RecordEvent
// ---------------------------------------------------------------------------

// RecordEvent persists a feedback event and updates the taste profile in real time.
func (s *Service) RecordEvent(ctx context.Context, userID, sessionID string, event WaveEvent) error {
	if !s.validateSession(sessionID, userID) {
		return fmt.Errorf("invalid session")
	}
	validTypes := map[string]bool{
		"play": true, "like": true, "dislike": true,
		"skip": true, "finish": true, "add_to_library": true,
	}
	if !validTypes[event.EventType] {
		return fmt.Errorf("invalid event_type: %s", event.EventType)
	}

	// Persist the event.
	_, err := s.db.Exec(ctx,
		`INSERT INTO wave_events (user_id, session_id, provider, track_id, event_type, position_seconds)
		 VALUES ($1, $2, $3, $4, $5, $6)`,
		userID, sessionID, event.Provider, event.TrackID, event.EventType, event.PositionSeconds,
	)
	if err != nil {
		return fmt.Errorf("wave insert event: %w", err)
	}

	// Load current profile.
	profile, err := loadTasteProfile(ctx, s.db, userID)
	if err != nil || profile == nil {
		return err
	}

	// Determine track genres from listen_history.
	trackGenres := s.lookupTrackGenres(ctx, event.Provider, event.TrackID)

	// Apply weight adjustments.
	s.applyEventDeltas(profile, event.EventType, trackGenres, event.Provider, event.TrackID)

	return saveTasteProfile(ctx, s.db, profile)
}

// ---------------------------------------------------------------------------
// GetProfile / GetOfflinePackage / SyncOfflineEvents
// ---------------------------------------------------------------------------

// GetProfile returns the persisted taste profile for a user.
func (s *Service) GetProfile(ctx context.Context, userID string) (*TasteProfile, error) {
	return loadTasteProfile(ctx, s.db, userID)
}

// GetOfflinePackage builds a self-contained bundle for offline playback scoring.
func (s *Service) GetOfflinePackage(ctx context.Context, userID string) (*OfflinePackage, error) {
	profile, err := loadTasteProfile(ctx, s.db, userID)
	if err != nil {
		return nil, err
	}
	if profile == nil {
		// Build a fresh profile on the fly.
		sess, err := s.StartSession(ctx, userID)
		if err != nil {
			return nil, fmt.Errorf("wave offline build: %w", err)
		}
		profile = &sess.Profile
	}

	// Generate a larger candidate pool (more queries).
	queries := s.buildSearchQueries(profile, 8, 8)

	var mu sync.Mutex
	var candidates []model.Track

	eg, egCtx := errgroup.WithContext(ctx)
	for _, q := range queries {
		q := q
		eg.Go(func() error {
			res := s.music.Search(egCtx, q, 20, "")
			if res != nil {
				mu.Lock()
				candidates = append(candidates, res.Tracks...)
				mu.Unlock()
			}
			return nil
		})
	}
	_ = eg.Wait()

	recentlyPlayed := s.recentlyPlayedSet(ctx, userID)
	peerKeys, _ := s.history.PeerInfluencedTracks(ctx, userID, 30)
	peerSet := make(map[string]bool, len(peerKeys))
	for _, k := range peerKeys {
		peerSet[k.Provider+":"+k.TrackID] = true
	}

	scored := make([]ScoredTrack, 0, len(candidates))
	for _, t := range candidates {
		sc := s.scoreTrack(t, profile, recentlyPlayed, peerSet)
		scored = append(scored, ScoredTrack{Track: t, Score: sc})
	}
	scored = dedup(scored)
	sort.Slice(scored, func(i, j int) bool { return scored[i].Score > scored[j].Score })
	if len(scored) > 200 {
		scored = scored[:200]
	}

	return &OfflinePackage{
		Profile:   *profile,
		TrackPool: scored,
		Weights: ScoreWeights{
			Genre:        0.30,
			Artist:       0.25,
			AudioFeature: 0.15,
			Provider:     0.10,
			Novelty:      0.10,
			PeerSignal:   0.10,
		},
		GenreDefaults: genreAudioDefaults(),
		GeneratedAt:   time.Now(),
	}, nil
}

// SyncOfflineEvents replays offline events into the database and updates the
// taste profile with the accumulated deltas.
func (s *Service) SyncOfflineEvents(ctx context.Context, userID string, events []WaveEvent) error {
	profile, err := loadTasteProfile(ctx, s.db, userID)
	if err != nil {
		return err
	}
	if profile == nil {
		return fmt.Errorf("no taste profile to sync against")
	}

	for _, ev := range events {
		_, err := s.db.Exec(ctx,
			`INSERT INTO wave_events (user_id, session_id, provider, track_id, event_type, position_seconds)
			 VALUES ($1, 'offline', $2, $3, $4, $5)`,
			userID, ev.Provider, ev.TrackID, ev.EventType, ev.PositionSeconds,
		)
		if err != nil {
			log.Printf("[wave] sync event insert: %v", err)
			continue
		}

		trackGenres := s.lookupTrackGenres(ctx, ev.Provider, ev.TrackID)
		s.applyEventDeltas(profile, ev.EventType, trackGenres, ev.Provider, ev.TrackID)
	}

	return saveTasteProfile(ctx, s.db, profile)
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

func (s *Service) validateSession(sessionID, userID string) bool {
	s.sessionsMu.Lock()
	defer s.sessionsMu.Unlock()
	owner, ok := s.sessions[sessionID]
	return ok && owner == userID
}

// buildSearchQueries produces search strings from the top-weighted genres and artists.
// Falls back to popular genre seeds when the user has no listening history.
func (s *Service) buildSearchQueries(profile *TasteProfile, maxGenres, maxArtists int) []string {
	topGenres := topKeys(profile.GenreWeights, maxGenres)
	topArtists := topKeys(profile.ArtistWeights, maxArtists)

	queries := make([]string, 0, len(topGenres)+len(topArtists))
	for _, g := range topGenres {
		queries = append(queries, g+" music")
	}
	for _, a := range topArtists {
		queries = append(queries, a)
	}

	// Fallback: if no history at all, use popular genre seeds so the wave always works
	if len(queries) == 0 {
		queries = []string{
			"indie rock", "electronic music", "alternative rock",
			"hip hop", "synth pop", "jazz", "neo soul", "pop music",
		}
	}

	return queries
}

// topKeys returns the n keys with the highest values.
func topKeys(m map[string]float64, n int) []string {
	type kv struct {
		Key string
		Val float64
	}
	sorted := make([]kv, 0, len(m))
	for k, v := range m {
		sorted = append(sorted, kv{k, v})
	}
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].Val > sorted[j].Val })
	if len(sorted) > n {
		sorted = sorted[:n]
	}
	out := make([]string, len(sorted))
	for i, kv := range sorted {
		out[i] = kv.Key
	}
	return out
}

// recentlyPlayedSet returns a set of "provider:track_id" keys from the last 7 days.
func (s *Service) recentlyPlayedSet(ctx context.Context, userID string) map[string]bool {
	rows, err := s.db.Query(ctx,
		`SELECT provider, track_id FROM listen_history
		 WHERE user_id = $1 AND listened_at > now() - interval '7 days'`,
		userID,
	)
	if err != nil {
		return map[string]bool{}
	}
	defer rows.Close()

	out := make(map[string]bool)
	for rows.Next() {
		var p, t string
		if err := rows.Scan(&p, &t); err != nil {
			continue
		}
		out[p+":"+t] = true
	}
	return out
}

// dedup removes duplicate tracks (same artist+title, case-insensitive) keeping
// the entry with the highest score.
func dedup(scored []ScoredTrack) []ScoredTrack {
	best := make(map[string]ScoredTrack)
	for _, st := range scored {
		key := strings.ToLower(st.Track.Artist + "|" + st.Track.Title)
		if existing, ok := best[key]; !ok || st.Score > existing.Score {
			best[key] = st
		}
	}
	out := make([]ScoredTrack, 0, len(best))
	for _, st := range best {
		out = append(out, st)
	}
	return out
}

// balanceProviders limits each provider's share to roughly its weight proportion.
func (s *Service) balanceProviders(scored []ScoredTrack, weights map[string]float64, maxTotal int) []ScoredTrack {
	// Sort by score descending first.
	sort.Slice(scored, func(i, j int) bool { return scored[i].Score > scored[j].Score })

	// Compute proportional caps.
	totalWeight := 0.0
	for _, w := range weights {
		totalWeight += w
	}
	if totalWeight == 0 {
		totalWeight = 1
	}

	caps := make(map[string]int)
	for p, w := range weights {
		cap := int(math.Ceil(float64(maxTotal) * w / totalWeight))
		if cap < 2 {
			cap = 2
		}
		caps[p] = cap
	}

	counts := make(map[string]int)
	var out []ScoredTrack
	for _, st := range scored {
		cap, ok := caps[st.Track.Provider]
		if !ok {
			cap = 3 // unknown provider gets a small share
		}
		if counts[st.Track.Provider] >= cap {
			continue
		}
		counts[st.Track.Provider]++
		out = append(out, st)
	}
	return out
}

// lookupTrackGenres tries to find genres for a track from listen_history.
func (s *Service) lookupTrackGenres(ctx context.Context, prov, trackID string) []string {
	var genres []string
	_ = s.db.QueryRow(ctx,
		`SELECT genres FROM listen_history
		 WHERE provider = $1 AND track_id = $2 AND genres IS NOT NULL
		 ORDER BY listened_at DESC LIMIT 1`,
		prov, trackID,
	).Scan(&genres)
	return genres
}

// applyEventDeltas adjusts genre and artist weights based on event feedback.
func (s *Service) applyEventDeltas(profile *TasteProfile, eventType string, genres []string, prov, trackID string) {
	var genreDelta, artistDelta float64
	switch eventType {
	case "like":
		genreDelta, artistDelta = 0.10, 0.15
	case "dislike":
		genreDelta, artistDelta = -0.15, -0.20
	case "skip":
		genreDelta, artistDelta = -0.05, -0.10
	case "finish":
		genreDelta, artistDelta = 0.03, 0.05
	case "add_to_library":
		genreDelta, artistDelta = 0.12, 0.15
	default:
		return
	}

	// Adjust genre weights.
	if profile.GenreWeights == nil {
		profile.GenreWeights = make(map[string]float64)
	}
	for _, g := range genres {
		g = strings.ToLower(g)
		profile.GenreWeights[g] = clamp01(profile.GenreWeights[g] + genreDelta)
	}

	// Adjust artist weight — look up artist name from listen_history.
	artist := s.lookupTrackArtist(profile, prov, trackID)
	if artist != "" {
		if profile.ArtistWeights == nil {
			profile.ArtistWeights = make(map[string]float64)
		}
		profile.ArtistWeights[artist] = clamp01(profile.ArtistWeights[artist] + artistDelta)
	}

	profile.UpdatedAt = time.Now()
}

// lookupTrackArtist returns the artist name if it is already present in the
// profile weights; otherwise falls back to an empty string.
func (s *Service) lookupTrackArtist(profile *TasteProfile, prov, trackID string) string {
	// Check if any artist weight key matches tracks in history.
	// For simplicity, try to find artist from the DB.
	var artist string
	_ = s.db.QueryRow(context.Background(),
		`SELECT artist FROM listen_history
		 WHERE provider = $1 AND track_id = $2 AND artist <> ''
		 ORDER BY listened_at DESC LIMIT 1`,
		prov, trackID,
	).Scan(&artist)
	return artist
}

func clamp01(v float64) float64 {
	if v < 0 {
		return 0
	}
	if v > 1 {
		return 1
	}
	return v
}
