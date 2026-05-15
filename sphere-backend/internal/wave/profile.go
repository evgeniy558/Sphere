package wave

import (
	"context"
	"encoding/json"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// avgFeatures holds averaged Spotify audio features for a user's recent tracks.
type avgFeatures struct {
	Energy  float64
	Valence float64
	Tempo   float64
}

// buildTasteProfile assembles a TasteProfile from pre-fetched weighted maps.
func buildTasteProfile(
	_ context.Context,
	_ *pgxpool.Pool,
	historyGenres map[string]float64,
	historyArtists map[string]float64,
	providerWeights map[string]float64,
	spotifyFeatures *avgFeatures,
) *TasteProfile {
	p := &TasteProfile{
		GenreWeights:    make(map[string]float64),
		ArtistWeights:   make(map[string]float64),
		ProviderWeights: providerWeights,
		UpdatedAt:       time.Now(),
	}

	// Merge genre weights from history.
	for g, w := range historyGenres {
		p.GenreWeights[g] = w
	}

	// Merge artist weights from history (favorites are merged by the caller
	// before being passed in; here we just copy).
	for a, w := range historyArtists {
		p.ArtistWeights[a] = w
	}

	// Set audio feature preferences from Spotify data or defaults.
	if spotifyFeatures != nil {
		p.EnergyPref = spotifyFeatures.Energy
		p.ValencePref = spotifyFeatures.Valence
		p.TempoPref = spotifyFeatures.Tempo
	} else {
		// Estimate from genre weights when no Spotify data is available.
		if len(p.GenreWeights) > 0 {
			genres := make([]string, 0, len(p.GenreWeights))
			for g := range p.GenreWeights {
				genres = append(genres, g)
			}
			e, v := estimateAudioFeatures(genres)
			p.EnergyPref = e
			p.ValencePref = v
		} else {
			p.EnergyPref = 0.50
			p.ValencePref = 0.50
		}
		p.TempoPref = 120.0
	}

	// Apply time-of-day context.
	tp := getTimeProfile(time.Now().Hour())
	applyTimeContext(p, tp)

	return p
}

// loadTasteProfile reads a persisted TasteProfile from the database.
func loadTasteProfile(ctx context.Context, db *pgxpool.Pool, userID string) (*TasteProfile, error) {
	var genreJSON, artistJSON, providerJSON []byte
	var p TasteProfile
	p.UserID = userID
	err := db.QueryRow(ctx,
		`SELECT genre_weights, artist_weights, provider_weights, energy_pref, valence_pref, tempo_pref, updated_at
		 FROM user_taste_profiles WHERE user_id = $1`,
		userID,
	).Scan(&genreJSON, &artistJSON, &providerJSON, &p.EnergyPref, &p.ValencePref, &p.TempoPref, &p.UpdatedAt)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	p.GenreWeights = make(map[string]float64)
	p.ArtistWeights = make(map[string]float64)
	p.ProviderWeights = make(map[string]float64)
	_ = json.Unmarshal(genreJSON, &p.GenreWeights)
	_ = json.Unmarshal(artistJSON, &p.ArtistWeights)
	_ = json.Unmarshal(providerJSON, &p.ProviderWeights)
	return &p, nil
}

// saveTasteProfile upserts a TasteProfile into the database.
func saveTasteProfile(ctx context.Context, db *pgxpool.Pool, profile *TasteProfile) error {
	genreJSON, _ := json.Marshal(profile.GenreWeights)
	artistJSON, _ := json.Marshal(profile.ArtistWeights)
	providerJSON, _ := json.Marshal(profile.ProviderWeights)
	_, err := db.Exec(ctx,
		`INSERT INTO user_taste_profiles (user_id, genre_weights, artist_weights, provider_weights, energy_pref, valence_pref, tempo_pref, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, now())
		 ON CONFLICT (user_id)
		 DO UPDATE SET genre_weights = $2, artist_weights = $3, provider_weights = $4,
		               energy_pref = $5, valence_pref = $6, tempo_pref = $7, updated_at = now()`,
		profile.UserID, genreJSON, artistJSON, providerJSON,
		profile.EnergyPref, profile.ValencePref, profile.TempoPref,
	)
	return err
}

// getTimeProfile returns energy/valence target ranges for the given hour.
func getTimeProfile(hour int) TimeProfile {
	switch {
	case hour >= 6 && hour < 10: // morning
		return TimeProfile{EnergyMin: 0.3, EnergyMax: 0.5, ValenceMin: 0.4, ValenceMax: 0.6}
	case hour >= 10 && hour < 18: // day
		return TimeProfile{EnergyMin: 0.5, EnergyMax: 0.7, ValenceMin: 0.5, ValenceMax: 0.7}
	case hour >= 18 && hour < 22: // evening
		return TimeProfile{EnergyMin: 0.6, EnergyMax: 0.8, ValenceMin: 0.5, ValenceMax: 0.8}
	default: // night (22-6)
		return TimeProfile{EnergyMin: 0.2, EnergyMax: 0.4, ValenceMin: 0.3, ValenceMax: 0.5}
	}
}

// applyTimeContext soft-blends the profile's audio prefs toward the time-of-day
// target (30 % time influence, 70 % personal taste).
func applyTimeContext(profile *TasteProfile, tp TimeProfile) {
	energyMid := (tp.EnergyMin + tp.EnergyMax) / 2
	valenceMid := (tp.ValenceMin + tp.ValenceMax) / 2
	profile.EnergyPref = profile.EnergyPref*0.7 + energyMid*0.3
	profile.ValencePref = profile.ValencePref*0.7 + valenceMid*0.3
}

// genreAudioDefaults returns a map of genre → [energy, valence] defaults used
// when Spotify audio features are unavailable.
func genreAudioDefaults() map[string][2]float64 {
	return map[string][2]float64{
		"electronic": {0.75, 0.65},
		"edm":        {0.75, 0.65},
		"house":      {0.75, 0.65},
		"pop":        {0.65, 0.70},
		"dance pop":  {0.65, 0.70},
		"rock":       {0.70, 0.45},
		"alternative": {0.70, 0.45},
		"hip hop":    {0.72, 0.50},
		"rap":        {0.72, 0.50},
		"trap":       {0.72, 0.50},
		"r&b":        {0.45, 0.55},
		"soul":       {0.45, 0.55},
		"classical":  {0.20, 0.35},
		"ambient":    {0.20, 0.35},
		"jazz":       {0.35, 0.60},
		"metal":      {0.85, 0.30},
		"acoustic":   {0.30, 0.55},
		"folk":       {0.30, 0.55},
		"indie":      {0.50, 0.55},
	}
}

// estimateAudioFeatures averages the genre defaults for the supplied genre list.
func estimateAudioFeatures(genres []string) (energy, valence float64) {
	defaults := genreAudioDefaults()
	if len(genres) == 0 {
		return 0.50, 0.50
	}
	var eSum, vSum float64
	var n int
	for _, g := range genres {
		if d, ok := defaults[g]; ok {
			eSum += d[0]
			vSum += d[1]
			n++
		}
	}
	if n == 0 {
		return 0.50, 0.50
	}
	return eSum / float64(n), vSum / float64(n)
}
