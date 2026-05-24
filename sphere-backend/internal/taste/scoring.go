// Package taste provides shared scoring utilities for track recommendation,
// used by wave (My Wave radio) and blend (taste-merged playlists).
package taste

import (
	"math"
	"sort"
	"strings"

	"sphere-backend/internal/model"
)

// ScoredTrack pairs a track with its relevance score.
type ScoredTrack struct {
	Track model.Track `json:"track"`
	Score float64     `json:"score"`
}

// ScoreTrack computes a relevance score [0, 1] for a track given user preferences.
func ScoreTrack(
	track model.Track,
	genreWeights map[string]float64,
	artistWeights map[string]float64,
	energyPref, valencePref float64,
	providerWeights map[string]float64,
	recentlyPlayed map[string]bool,
	peerTracks map[string]bool,
) float64 {
	// Genre match (0.30)
	var genreScore float64
	if len(track.Genres) > 0 {
		for _, g := range track.Genres {
			genreScore += genreWeights[strings.ToLower(g)]
		}
		genreScore /= float64(len(track.Genres))
	}

	// Artist match (0.25)
	artistScore := artistWeights[track.Artist]

	// Audio feature match (0.15)
	e, v := EstimateAudioFeatures(track.Genres)
	eDiff := math.Abs(e - energyPref)
	vDiff := math.Abs(v - valencePref)
	audioScore := math.Max(0, 1.0-eDiff*0.5-vDiff*0.5)

	// Provider match (0.10)
	providerScore := providerWeights[track.Provider]
	if providerScore == 0 {
		providerScore = 0.1
	}

	// Novelty (0.10)
	noveltyScore := 1.0
	key := track.Provider + ":" + track.ID
	if recentlyPlayed[key] {
		noveltyScore = 0.0
	}

	// Peer signal (0.10)
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

// ScoreTrackTasteOnly computes a taste-based score without novelty/peer signals.
// Used by Blend where we care about taste overlap, not personal listening history.
func ScoreTrackTasteOnly(
	track model.Track,
	genreWeights map[string]float64,
	artistWeights map[string]float64,
	energyPref, valencePref float64,
	providerWeights map[string]float64,
) float64 {
	var genreScore float64
	if len(track.Genres) > 0 {
		for _, g := range track.Genres {
			genreScore += genreWeights[strings.ToLower(g)]
		}
		genreScore /= float64(len(track.Genres))
	}

	artistScore := artistWeights[track.Artist]

	e, v := EstimateAudioFeatures(track.Genres)
	eDiff := math.Abs(e - energyPref)
	vDiff := math.Abs(v - valencePref)
	audioScore := math.Max(0, 1.0-eDiff*0.5-vDiff*0.5)

	providerScore := providerWeights[track.Provider]
	if providerScore == 0 {
		providerScore = 0.1
	}

	return genreScore*0.35 + artistScore*0.30 + audioScore*0.20 + providerScore*0.15
}

// TopKeys returns the n keys with the highest values from a weight map.
func TopKeys(m map[string]float64, n int) []string {
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

// Dedup removes duplicate tracks (same artist+title) keeping the highest score.
func Dedup(scored []ScoredTrack) []ScoredTrack {
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

// BalanceProviders limits each provider's share roughly to its weight proportion.
func BalanceProviders(scored []ScoredTrack, weights map[string]float64, maxTotal int) []ScoredTrack {
	sort.Slice(scored, func(i, j int) bool { return scored[i].Score > scored[j].Score })

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
			cap = 3
		}
		if counts[st.Track.Provider] >= cap {
			continue
		}
		counts[st.Track.Provider]++
		out = append(out, st)
	}
	return out
}

// EstimateAudioFeatures estimates energy and valence from genre names.
func EstimateAudioFeatures(genres []string) (energy, valence float64) {
	if len(genres) == 0 {
		return 0.5, 0.5
	}
	defaults := GenreAudioDefaults()
	var eSum, vSum float64
	var count int
	for _, g := range genres {
		g = strings.ToLower(g)
		if ev, ok := defaults[g]; ok {
			eSum += ev[0]
			vSum += ev[1]
			count++
		}
	}
	if count == 0 {
		return 0.5, 0.5
	}
	return eSum / float64(count), vSum / float64(count)
}

// GenreAudioDefaults returns default energy/valence for common genres.
func GenreAudioDefaults() map[string][2]float64 {
	return map[string][2]float64{
		"pop":          {0.65, 0.70},
		"rock":         {0.75, 0.55},
		"hip-hop":      {0.70, 0.50},
		"rap":          {0.72, 0.48},
		"electronic":   {0.80, 0.55},
		"dance":        {0.82, 0.65},
		"r&b":          {0.55, 0.60},
		"rnb":          {0.55, 0.60},
		"jazz":         {0.40, 0.55},
		"classical":    {0.25, 0.40},
		"metal":        {0.90, 0.35},
		"punk":         {0.85, 0.45},
		"indie":        {0.55, 0.50},
		"folk":         {0.35, 0.55},
		"country":      {0.55, 0.65},
		"latin":        {0.75, 0.75},
		"reggaeton":    {0.78, 0.70},
		"soul":         {0.50, 0.60},
		"funk":         {0.70, 0.70},
		"blues":        {0.45, 0.40},
		"ambient":      {0.20, 0.45},
		"house":        {0.78, 0.60},
		"techno":       {0.85, 0.40},
		"drill":        {0.75, 0.35},
		"trap":         {0.72, 0.40},
		"phonk":        {0.80, 0.35},
		"k-pop":        {0.70, 0.75},
		"anime":        {0.65, 0.65},
	}
}
