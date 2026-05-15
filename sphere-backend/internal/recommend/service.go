package recommend

import (
	"context"
	"log"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"sphere-backend/internal/favorites"
	"sphere-backend/internal/history"
	"sphere-backend/internal/model"
	"sphere-backend/internal/music"
	"sphere-backend/internal/preferences"
	"sphere-backend/internal/provider"
	"sphere-backend/internal/recommend/engine"
)

// Response is the JSON for GET /recommendations.
type Response = model.RecommendationFeed

const recommendationsCacheTTL = 5 * time.Minute

type cachedFeed struct {
	value     *Response
	expiresAt time.Time
}

const similarUsersCacheTTL = 30 * time.Minute

type cachedSimilar struct {
	value     []model.SimilarUserInfo
	expiresAt time.Time
}

type Service struct {
	db        *pgxpool.Pool
	history   *history.Service
	music     *music.Service
	prefs     *preferences.Service
	favorites *favorites.Service
	spotify   *provider.Spotify

	cacheMu      sync.Mutex
	cache        map[string]cachedFeed
	similarCache map[string]cachedSimilar
}

func NewService(db *pgxpool.Pool, h *history.Service, m *music.Service, p *preferences.Service, f *favorites.Service, sp *provider.Spotify) *Service {
	return &Service{
		db:           db,
		history:      h,
		music:        m,
		prefs:        p,
		favorites:    f,
		spotify:      sp,
		cache:        make(map[string]cachedFeed),
		similarCache: make(map[string]cachedSimilar),
	}
}

func (s *Service) cacheKey(userID, lang string) string {
	l := strings.ToLower(strings.TrimSpace(lang))
	if strings.Contains(l, "ru") {
		l = "ru"
	} else {
		l = "en"
	}
	return strings.TrimSpace(userID) + "|" + l
}

func (s *Service) cachedRecommendations(key string) *Response {
	s.cacheMu.Lock()
	defer s.cacheMu.Unlock()
	if entry, ok := s.cache[key]; ok && time.Now().Before(entry.expiresAt) {
		return entry.value
	}
	return nil
}

func (s *Service) storeRecommendations(key string, resp *Response) {
	if resp == nil {
		return
	}
	s.cacheMu.Lock()
	defer s.cacheMu.Unlock()
	s.cache[key] = cachedFeed{value: resp, expiresAt: time.Now().Add(recommendationsCacheTTL)}
}

// GetRecommendations always runs the new multi-provider engine (no legacy “charts” cold-start).
func (s *Service) GetRecommendations(ctx context.Context, userID, lang string) *Response {
	key := s.cacheKey(userID, lang)
	if cached := s.cachedRecommendations(key); cached != nil {
		log.Printf("[recommend-cache] hit user=%s lang=%s tracks=%d", userID, lang, len(cached.Tracks))
		return cached
	}

	deps := engine.Deps{
		Spotify:   s.spotify,
		Music:     s.music,
		History:   s.history,
		Prefs:     s.prefs,
		Favorites: s.favorites,
	}
	eng, err := engine.Run(ctx, &deps, userID, lang)
	if err != nil || eng == nil {
		log.Printf("[recommend] engine error or nil user=%s: %v", userID, err)
		empty := &Response{Tracks: []model.Track{}, Albums: []model.Album{}, Artists: []model.Artist{}}
		s.storeRecommendations(key, empty)
		return empty
	}
	if len(eng.Tracks) == 0 {
		empty := &Response{Tracks: []model.Track{}, Albums: eng.Albums, Artists: eng.Artists}
		s.storeRecommendations(key, empty)
		return empty
	}

	// Enrich with similar users (separate cache, non-fatal).
	eng.SimilarUsers = s.getSimilarUsers(ctx, userID)

	s.storeRecommendations(key, eng)
	log.Printf("[recommend-cache] miss-stored user=%s lang=%s tracks=%d albums=%d artists=%d similar=%d ttl=%s",
		userID, lang, len(eng.Tracks), len(eng.Albums), len(eng.Artists), len(eng.SimilarUsers), recommendationsCacheTTL)
	return eng
}

func (s *Service) getSimilarUsers(ctx context.Context, userID string) []model.SimilarUserInfo {
	// Check 30-min cache.
	s.cacheMu.Lock()
	if entry, ok := s.similarCache[userID]; ok && time.Now().Before(entry.expiresAt) {
		s.cacheMu.Unlock()
		return entry.value
	}
	s.cacheMu.Unlock()

	// Build user's taste profile for comparison.
	genres, err := s.history.TopGenresWeighted(ctx, userID, 20)
	if err != nil {
		genres = map[string]float64{}
	}
	artists, err := s.history.TopArtistsWeighted(ctx, userID, 15)
	if err != nil {
		artists = map[string]float64{}
	}
	favArtists, err := s.favorites.TopArtistsWeighted(ctx, userID, 10)
	if err == nil {
		for k, v := range favArtists {
			if existing, ok := artists[k]; !ok || v > existing {
				artists[k] = v
			}
		}
	}

	similar := FindSimilarUsers(ctx, s.db, userID, genres, artists, 10)
	if similar == nil {
		similar = []model.SimilarUserInfo{}
	}

	// Cache.
	s.cacheMu.Lock()
	s.similarCache[userID] = cachedSimilar{value: similar, expiresAt: time.Now().Add(similarUsersCacheTTL)}
	s.cacheMu.Unlock()

	return similar
}

// GetDailyMixes returns four personalized track bundles.
func (s *Service) GetDailyMixes(ctx context.Context, userID, lang string) ([]model.DailyMix, error) {
	return engine.DailyMixes(ctx, &engine.Deps{
		Spotify:   s.spotify,
		Music:     s.music,
		History:   s.history,
		Prefs:     s.prefs,
		Favorites: s.favorites,
	}, userID, lang)
}
