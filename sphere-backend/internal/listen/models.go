package listen

import "time"

type Session struct {
	ID            string     `json:"id"`
	HostID        string     `json:"host_id"`
	TrackProvider string     `json:"track_provider"`
	TrackID       string     `json:"track_id"`
	Status        string     `json:"status"`
	CreatedAt     time.Time  `json:"created_at"`
	EndedAt       *time.Time `json:"ended_at,omitempty"`
	Participants  []Participant `json:"participants,omitempty"`
}

type Participant struct {
	UserID   string    `json:"user_id"`
	Username string    `json:"username"`
	Name     string    `json:"name"`
	AvatarURL string   `json:"avatar_url"`
	JoinedAt time.Time `json:"joined_at"`
}

type SyncPayload struct {
	SessionID       string  `json:"session_id"`
	TrackProvider   string  `json:"track_provider"`
	TrackID         string  `json:"track_id"`
	PositionSeconds float64 `json:"position_seconds"`
	IsPlaying       bool    `json:"is_playing"`
}

type InvitePayload struct {
	SessionID     string `json:"session_id"`
	FromUserID    string `json:"from_user_id"`
	FromUsername  string  `json:"from_username"`
	TrackProvider string `json:"track_provider"`
	TrackID       string `json:"track_id"`
	TrackTitle    string `json:"track_title"`
	TrackArtist   string `json:"track_artist"`
	TrackCoverURL string `json:"track_cover_url"`
}
