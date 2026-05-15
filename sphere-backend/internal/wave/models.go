package wave

import (
	"time"

	"sphere-backend/internal/model"
)

// TasteProfile captures a user's musical preferences as weighted dimensions.
type TasteProfile struct {
	UserID          string             `json:"user_id"`
	GenreWeights    map[string]float64 `json:"genre_weights"`
	ArtistWeights   map[string]float64 `json:"artist_weights"`
	ProviderWeights map[string]float64 `json:"provider_weights"`
	EnergyPref      float64            `json:"energy_pref"`
	ValencePref     float64            `json:"valence_pref"`
	TempoPref       float64            `json:"tempo_pref"`
	UpdatedAt       time.Time          `json:"updated_at"`
}

// WaveSession represents an active personalized radio session.
type WaveSession struct {
	SessionID string       `json:"session_id"`
	Profile   TasteProfile `json:"profile"`
	CreatedAt time.Time    `json:"created_at"`
}

// WaveEvent is a real-time feedback signal from the client.
type WaveEvent struct {
	Provider        string  `json:"provider"`
	TrackID         string  `json:"track_id"`
	EventType       string  `json:"event_type"`
	PositionSeconds float64 `json:"position_seconds"`
}

// ScoredTrack pairs a track with its relevance score.
type ScoredTrack struct {
	Track model.Track `json:"track"`
	Score float64     `json:"score"`
}

// OfflinePackage is a self-contained bundle the client can use for offline
// scoring and playback without network access.
type OfflinePackage struct {
	Profile       TasteProfile          `json:"profile"`
	TrackPool     []ScoredTrack         `json:"track_pool"`
	Weights       ScoreWeights          `json:"weights"`
	GenreDefaults map[string][2]float64 `json:"genre_audio_defaults"`
	GeneratedAt   time.Time             `json:"generated_at"`
}

// ScoreWeights holds the relative importance of each scoring dimension.
type ScoreWeights struct {
	Genre        float64 `json:"genre"`
	Artist       float64 `json:"artist"`
	AudioFeature float64 `json:"audio_feature"`
	Provider     float64 `json:"provider"`
	Novelty      float64 `json:"novelty"`
	PeerSignal   float64 `json:"peer_signal"`
}

// TimeProfile defines target energy/valence ranges for a time-of-day slot.
type TimeProfile struct {
	EnergyMin  float64
	EnergyMax  float64
	ValenceMin float64
	ValenceMax float64
}
