package wave

import (
	"bytes"
	"context"
	"encoding/json"
	"log"
	"math"
	"os"
	"os/exec"
	"time"
)

// nodexModelPath is the path to the exported NodeX Wave ONNX model.
const nodexModelPath = "/models/nodex_wave.onnx"

// NodeXAvailable reports whether the NodeX Wave ONNX model is present.
func NodeXAvailable() bool {
	_, err := os.Stat(nodexModelPath)
	return err == nil
}

// UserContext holds contextual features for NodeX Wave scoring.
type UserContext struct {
	Hour                 int     `json:"hour"`
	DayOfWeek            int     `json:"day_of_week"`
	RecentEnergyAvg      float64 `json:"recent_energy_avg"`
	RecentValenceAvg     float64 `json:"recent_valence_avg"`
	RecentTempoAvg       float64 `json:"recent_tempo_avg"`
	SessionSkipRate      float64 `json:"session_skip_rate"`
	SessionLength        int     `json:"session_length"`
	HoursSinceLastListen float64 `json:"hours_since_last_listen"`
	TracksToday          int     `json:"tracks_today"`
}

// buildUserContext constructs contextual features from the database.
func (s *Service) buildUserContext(ctx context.Context, userID string) UserContext {
	now := time.Now()
	uc := UserContext{
		Hour:      now.Hour(),
		DayOfWeek: int(now.Weekday()),
	}

	// Recent mood: average energy/valence of last 5 tracks.
	rows, err := s.db.Query(ctx,
		`SELECT genres FROM listen_history
		 WHERE user_id = $1 ORDER BY listened_at DESC LIMIT 5`,
		userID,
	)
	if err == nil {
		defer rows.Close()
		var count int
		for rows.Next() {
			var genres []string
			if rows.Scan(&genres) == nil && len(genres) > 0 {
				e, v := estimateAudioFeatures(genres)
				uc.RecentEnergyAvg += e
				uc.RecentValenceAvg += v
				count++
			}
		}
		if count > 0 {
			uc.RecentEnergyAvg /= float64(count)
			uc.RecentValenceAvg /= float64(count)
		} else {
			uc.RecentEnergyAvg = 0.5
			uc.RecentValenceAvg = 0.5
		}
	}
	uc.RecentTempoAvg = 120.0

	// Session skip rate from wave_events today.
	var plays, skips int
	_ = s.db.QueryRow(ctx,
		`SELECT
			COUNT(*) FILTER (WHERE event_type = 'play'),
			COUNT(*) FILTER (WHERE event_type = 'skip')
		 FROM wave_events
		 WHERE user_id = $1 AND created_at > now() - interval '2 hours'`,
		userID,
	).Scan(&plays, &skips)
	uc.SessionLength = plays + skips
	if plays+skips > 0 {
		uc.SessionSkipRate = float64(skips) / float64(plays+skips)
	}

	// Hours since last listen.
	var lastListened time.Time
	err = s.db.QueryRow(ctx,
		`SELECT listened_at FROM listen_history WHERE user_id = $1 ORDER BY listened_at DESC LIMIT 1`,
		userID,
	).Scan(&lastListened)
	if err == nil {
		uc.HoursSinceLastListen = time.Since(lastListened).Hours()
	} else {
		uc.HoursSinceLastListen = 24.0
	}

	// Tracks today.
	_ = s.db.QueryRow(ctx,
		`SELECT COUNT(*) FROM listen_history WHERE user_id = $1 AND listened_at > CURRENT_DATE`,
		userID,
	).Scan(&uc.TracksToday)

	return uc
}

// 8 canonical genre indices matching Python GENRE_VOCAB.
var genreVocab = []string{"pop", "rock", "hiphop", "electronic", "rnb", "jazz", "classical", "other"}

// buildFeatureVector constructs the 50-dim feature vector for a single track.
func buildFeatureVector(
	energy, valence, tempo, danceability float64,
	genres []string,
	uc UserContext,
	profile *TasteProfile,
	genreMatch, artistMatch, novelty, peerScore float64,
) []float64 {
	vec := make([]float64, 0, 50)

	// Track features (12)
	vec = append(vec, energy, valence, tempo/200.0, danceability)
	genreVec := make([]float64, 8)
	for _, g := range genres {
		matched := false
		for i, vg := range genreVocab {
			if containsLower(g, vg) {
				genreVec[i] = 1.0
				matched = true
				break
			}
		}
		if !matched {
			genreVec[7] = 1.0 // other
		}
	}
	// Normalize genre vector
	sum := 0.0
	for _, v := range genreVec {
		sum += v
	}
	if sum > 0 {
		for i := range genreVec {
			genreVec[i] /= sum
		}
	}
	vec = append(vec, genreVec...)

	// Context features (16)
	hSin := math.Sin(2 * math.Pi * float64(uc.Hour) / 24)
	hCos := math.Cos(2 * math.Pi * float64(uc.Hour) / 24)
	dSin := math.Sin(2 * math.Pi * float64(uc.DayOfWeek) / 7)
	dCos := math.Cos(2 * math.Pi * float64(uc.DayOfWeek) / 7)
	vec = append(vec, hSin, hCos, dSin, dCos)
	vec = append(vec, uc.RecentEnergyAvg, uc.RecentValenceAvg, uc.RecentTempoAvg/200.0)
	vec = append(vec, math.Min(uc.SessionSkipRate, 1.0))
	vec = append(vec, math.Min(float64(uc.SessionLength)/50.0, 1.0))
	vec = append(vec, math.Min(uc.HoursSinceLastListen/24.0, 1.0))
	vec = append(vec, math.Min(float64(uc.TracksToday)/100.0, 1.0))
	isWeekend := 0.0
	if uc.DayOfWeek == 0 || uc.DayOfWeek == 6 {
		isWeekend = 1.0
	}
	vec = append(vec, isWeekend)
	morning, afternoon, evening, night := 0.0, 0.0, 0.0, 0.0
	switch {
	case uc.Hour >= 6 && uc.Hour < 12:
		morning = 1.0
	case uc.Hour >= 12 && uc.Hour < 18:
		afternoon = 1.0
	case uc.Hour >= 18 && uc.Hour < 23:
		evening = 1.0
	default:
		night = 1.0
	}
	vec = append(vec, morning, afternoon, evening, night)

	// User preferences (22)
	for _, g := range genreVocab {
		vec = append(vec, profile.GenreWeights[g])
	}
	vec = append(vec, profile.EnergyPref, profile.ValencePref, profile.TempoPref/200.0)
	vec = append(vec, genreMatch, artistMatch)
	providerVocab := []string{"spotify", "youtube", "deezer", "soundcloud"}
	for _, p := range providerVocab {
		vec = append(vec, profile.ProviderWeights[p])
	}
	vec = append(vec, novelty, peerScore)
	vec = append(vec, 0.5) // days_since_last_play_artist (approximate)
	vec = append(vec, 0.0) // repeat_count_7d
	vec = append(vec, 0.0) // favorite_flag

	return vec
}

// scoreTracksNodeX scores a batch of tracks using the NodeX Wave ONNX model.
// Returns nil (falling back to manual scoring) on any error.
func scoreTracksNodeX(features [][]float64) ([]float64, error) {
	input := struct {
		Features [][]float64 `json:"features"`
	}{Features: features}

	inputJSON, err := json.Marshal(input)
	if err != nil {
		return nil, err
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx,
		"python3", "/app/scripts/nodex/wave/inference.py",
		"--model", nodexModelPath,
	)
	cmd.Stdin = bytes.NewReader(inputJSON)

	out, err := cmd.Output()
	if err != nil {
		return nil, err
	}

	var result struct {
		Scores []float64 `json:"scores"`
	}
	if err := json.Unmarshal(out, &result); err != nil {
		return nil, err
	}

	return result.Scores, nil
}

// containsLower checks if target appears in source (case-insensitive substring).
func containsLower(source, target string) bool {
	s := toLower(source)
	return len(s) >= len(target) && (s == target || contains(s, target))
}

func toLower(s string) string {
	b := make([]byte, len(s))
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c >= 'A' && c <= 'Z' {
			c += 32
		}
		b[i] = c
	}
	return string(b)
}

func contains(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}

func init() {
	if NodeXAvailable() {
		log.Printf("[nodex-wave] ONNX model found at %s — AI scoring enabled", nodexModelPath)
	} else {
		log.Printf("[nodex-wave] No ONNX model at %s — using manual scoring fallback", nodexModelPath)
	}
}
