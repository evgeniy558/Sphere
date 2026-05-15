package playlist

import "time"

type Playlist struct {
	ID          string    `json:"id"`
	OwnerID     string    `json:"owner_id"`
	Title       string    `json:"title"`
	Description string    `json:"description"`
	CoverURL    string    `json:"cover_url"`
	IsPublic    bool      `json:"is_public"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
	TrackCount  int       `json:"track_count"`
	Role        string    `json:"role,omitempty"`
}

type PlaylistTrack struct {
	ID       string    `json:"id"`
	Provider string    `json:"provider"`
	TrackID  string    `json:"track_id"`
	Title    string    `json:"title"`
	Artist   string    `json:"artist"`
	CoverURL string    `json:"cover_url"`
	Duration int       `json:"duration"`
	AddedBy  string    `json:"added_by"`
	Position int       `json:"position"`
	AddedAt  time.Time `json:"added_at"`
}

type Member struct {
	UserID    string    `json:"user_id"`
	Username  string    `json:"username"`
	Name      string    `json:"name"`
	AvatarURL string    `json:"avatar_url"`
	Role      string    `json:"role"`
	AddedAt   time.Time `json:"added_at"`
}

type PlaylistDetail struct {
	Playlist
	Tracks  []PlaylistTrack `json:"tracks"`
	Members []Member        `json:"members,omitempty"`
}
