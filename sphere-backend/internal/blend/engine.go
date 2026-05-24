package blend

import (
	"context"
	"fmt"
	"log"
	"math"
	"sort"
	"strings"
	"sync"

	"sphere-backend/internal/model"
	"sphere-backend/internal/taste"
)

// tasteProfile holds a user's taste data for blend scoring.
type tasteProfile struct {
	UserID          string
	Username        string
	GenreWeights    map[string]float64
	ArtistWeights   map[string]float64
	ProviderWeights map[string]float64
	EnergyPref      float64
	ValencePref     float64
}

// Generate builds the blend playlist for all accepted members.
func (s *Service) Generate(ctx context.Context, blendID string) error {
	// Load accepted members
	rows, err := s.db.Query(ctx,
		`SELECT bm.user_id, COALESCE(u.username,'')
		 FROM blend_members bm JOIN users u ON u.id = bm.user_id
		 WHERE bm.blend_id = $1 AND bm.status = 'accepted'`, blendID)
	if err != nil {
		return err
	}
	defer rows.Close()

	var members []struct{ ID, Username string }
	for rows.Next() {
		var m struct{ ID, Username string }
		if rows.Scan(&m.ID, &m.Username) == nil {
			members = append(members, m)
		}
	}
	if len(members) == 0 {
		return fmt.Errorf("no accepted members")
	}

	// Build taste profiles for each member
	profiles := make([]tasteProfile, 0, len(members))
	for _, m := range members {
		p, err := s.buildMemberProfile(ctx, m.ID)
		if err != nil {
			log.Printf("[blend] profile for %s: %v", m.ID, err)
			continue
		}
		p.UserID = m.ID
		p.Username = m.Username
		profiles = append(profiles, *p)
	}
	if len(profiles) == 0 {
		return fmt.Errorf("no profiles available")
	}

	// Merge profiles
	merged := mergeTasteProfiles(profiles)

	// Build search queries from merged profile
	topGenres := taste.TopKeys(merged.GenreWeights, 6)
	topArtists := taste.TopKeys(merged.ArtistWeights, 6)

	queries := make([]string, 0, len(topGenres)+len(topArtists))
	for _, g := range topGenres {
		queries = append(queries, g+" music")
	}
	for _, a := range topArtists {
		queries = append(queries, a)
	}

	// Search all providers in parallel
	var mu sync.Mutex
	var candidates []model.Track
	var wg sync.WaitGroup

	for _, q := range queries {
		q := q
		wg.Add(1)
		go func() {
			defer wg.Done()
			res := s.music.Search(ctx, q, 15, "")
			if res != nil {
				mu.Lock()
				candidates = append(candidates, res.Tracks...)
				mu.Unlock()
			}
		}()
	}
	wg.Wait()

	// Score each candidate against each member
	type scoredBlendTrack struct {
		Track       model.Track
		MatchScore  float64
		MatchLabel  string
		MemberScores []float64
	}

	var scored []scoredBlendTrack
	for _, t := range candidates {
		memberScores := make([]float64, len(profiles))
		for i, p := range profiles {
			memberScores[i] = taste.ScoreTrackTasteOnly(
				t, p.GenreWeights, p.ArtistWeights,
				p.EnergyPref, p.ValencePref, p.ProviderWeights,
			)
		}

		// Match score = min of member scores (ensures all members like it)
		minScore := memberScores[0]
		maxScore := memberScores[0]
		sum := 0.0
		for _, ms := range memberScores {
			if ms < minScore {
				minScore = ms
			}
			if ms > maxScore {
				maxScore = ms
			}
			sum += ms
		}
		avg := sum / float64(len(memberScores))

		// Generate label
		label := generateMatchLabel(memberScores, profiles, avg)

		scored = append(scored, scoredBlendTrack{
			Track:        t,
			MatchScore:   minScore,
			MatchLabel:   label,
			MemberScores: memberScores,
		})
	}

	// Dedup by artist+title
	best := make(map[string]scoredBlendTrack)
	for _, st := range scored {
		key := strings.ToLower(st.Track.Artist + "|" + st.Track.Title)
		if existing, ok := best[key]; !ok || st.MatchScore > existing.MatchScore {
			best[key] = st
		}
	}

	deduped := make([]scoredBlendTrack, 0, len(best))
	for _, st := range best {
		deduped = append(deduped, st)
	}

	// Sort by match score descending
	sort.Slice(deduped, func(i, j int) bool { return deduped[i].MatchScore > deduped[j].MatchScore })

	// Balance providers and take top 30
	if len(deduped) > 30 {
		deduped = deduped[:30]
	}

	// Save to DB
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	_, _ = tx.Exec(ctx, `DELETE FROM blend_tracks WHERE blend_id = $1`, blendID)

	for i, st := range deduped {
		_, err := tx.Exec(ctx,
			`INSERT INTO blend_tracks (blend_id, provider, track_id, title, artist, cover_url, duration, match_score, match_label, position)
			 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
			blendID, st.Track.Provider, st.Track.ID, st.Track.Title, st.Track.Artist,
			st.Track.CoverURL, st.Track.Duration,
			math.Round(st.MatchScore*100)/100, st.MatchLabel, i+1,
		)
		if err != nil {
			log.Printf("[blend] insert track: %v", err)
		}
	}

	_, _ = tx.Exec(ctx, `UPDATE blends SET last_generated_at = now() WHERE id = $1`, blendID)

	log.Printf("[blend] generated %d tracks for blend %s", len(deduped), blendID)
	return tx.Commit(ctx)
}

func (s *Service) buildMemberProfile(ctx context.Context, userID string) (*tasteProfile, error) {
	genreWeights, err := s.history.TopGenresWeighted(ctx, userID, 20)
	if err != nil {
		genreWeights = map[string]float64{}
	}

	artistWeights, err := s.history.TopArtistsWeighted(ctx, userID, 20)
	if err != nil {
		artistWeights = map[string]float64{}
	}

	// Merge favorite artists
	favArtists, _ := s.favorites.TopArtistsWeighted(ctx, userID, 10)
	for a, w := range favArtists {
		if cur, ok := artistWeights[a]; !ok || w > cur {
			artistWeights[a] = w
		}
	}

	providerWeights, _ := s.history.ProviderWeights(ctx, userID)

	// Estimate audio prefs from top genres
	topGenres := taste.TopKeys(genreWeights, 5)
	e, v := taste.EstimateAudioFeatures(topGenres)

	return &tasteProfile{
		GenreWeights:    genreWeights,
		ArtistWeights:   artistWeights,
		ProviderWeights: providerWeights,
		EnergyPref:      e,
		ValencePref:     v,
	}, nil
}

func mergeTasteProfiles(profiles []tasteProfile) tasteProfile {
	n := float64(len(profiles))
	merged := tasteProfile{
		GenreWeights:    make(map[string]float64),
		ArtistWeights:   make(map[string]float64),
		ProviderWeights: make(map[string]float64),
	}

	// Count how many profiles have each genre/artist
	genreCounts := make(map[string]int)
	artistCounts := make(map[string]int)

	for _, p := range profiles {
		for g, w := range p.GenreWeights {
			merged.GenreWeights[g] += w / n
			genreCounts[g]++
		}
		for a, w := range p.ArtistWeights {
			merged.ArtistWeights[a] += w / n
			artistCounts[a]++
		}
		for pr, w := range p.ProviderWeights {
			merged.ProviderWeights[pr] += w / n
		}
		merged.EnergyPref += p.EnergyPref / n
		merged.ValencePref += p.ValencePref / n
	}

	// Intersection boost: shared genres/artists get 1.5x
	total := len(profiles)
	for g, count := range genreCounts {
		if count == total {
			merged.GenreWeights[g] *= 1.5
		}
	}
	for a, count := range artistCounts {
		if count == total {
			merged.ArtistWeights[a] *= 1.5
		}
	}

	return merged
}

func generateMatchLabel(memberScores []float64, profiles []tasteProfile, avg float64) string {
	allHigh := true
	for _, s := range memberScores {
		if s < 0.6 {
			allHigh = false
			break
		}
	}
	if allHigh {
		return fmt.Sprintf("Нравится всем %d%%", int(avg*100))
	}

	// Check if one member dominates
	if len(memberScores) >= 2 {
		maxIdx := 0
		for i, s := range memberScores {
			if s > memberScores[maxIdx] {
				maxIdx = i
			}
		}
		secondMax := 0.0
		for i, s := range memberScores {
			if i != maxIdx && s > secondMax {
				secondMax = s
			}
		}
		if memberScores[maxIdx]-secondMax > 0.3 && maxIdx < len(profiles) {
			return fmt.Sprintf("Из вкусов %s", profiles[maxIdx].Username)
		}
	}

	return fmt.Sprintf("Общий вкус %d%%", int(avg*100))
}
