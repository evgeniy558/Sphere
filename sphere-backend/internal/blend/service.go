package blend

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"sphere-backend/internal/favorites"
	"sphere-backend/internal/history"
	"sphere-backend/internal/music"
	"sphere-backend/internal/provider"
)

type Service struct {
	db        *pgxpool.Pool
	history   *history.Service
	favorites *favorites.Service
	music     *music.Service
	spotify   *provider.Spotify
}

func NewService(db *pgxpool.Pool, historySvc *history.Service, favSvc *favorites.Service,
	musicSvc *music.Service, spotify *provider.Spotify) *Service {
	return &Service{db: db, history: historySvc, favorites: favSvc, music: musicSvc, spotify: spotify}
}

// --- Models ---

type Blend struct {
	ID              string        `json:"id"`
	CreatorID       string        `json:"creator_id"`
	Title           string        `json:"title"`
	Status          string        `json:"status"`
	LastGeneratedAt *time.Time    `json:"last_generated_at,omitempty"`
	CreatedAt       time.Time     `json:"created_at"`
	Members         []BlendMember `json:"members,omitempty"`
	Tracks          []BlendTrack  `json:"tracks,omitempty"`
}

type BlendMember struct {
	UserID   string `json:"user_id"`
	Username string `json:"username"`
	Name     string `json:"name"`
	Avatar   string `json:"avatar_url"`
	Status   string `json:"status"`
}

type BlendTrack struct {
	ID         string  `json:"id"`
	Provider   string  `json:"provider"`
	TrackID    string  `json:"track_id"`
	Title      string  `json:"title"`
	Artist     string  `json:"artist"`
	CoverURL   string  `json:"cover_url"`
	Duration   int     `json:"duration"`
	MatchScore float64 `json:"match_score"`
	MatchLabel string  `json:"match_label"`
	Position   int     `json:"position"`
}

// --- CRUD ---

func (s *Service) Create(ctx context.Context, creatorID, title string, memberIDs []string) (*Blend, error) {
	if title == "" {
		title = "Blend"
	}

	var blendID string
	err := s.db.QueryRow(ctx,
		`INSERT INTO blends (creator_id, title) VALUES ($1, $2) RETURNING id`,
		creatorID, title,
	).Scan(&blendID)
	if err != nil {
		return nil, fmt.Errorf("create blend: %w", err)
	}

	// Add creator as accepted member
	_, _ = s.db.Exec(ctx,
		`INSERT INTO blend_members (blend_id, user_id, status) VALUES ($1, $2, 'accepted')`,
		blendID, creatorID)

	// Invite others as pending
	for _, uid := range memberIDs {
		if uid == creatorID {
			continue
		}
		_, _ = s.db.Exec(ctx,
			`INSERT INTO blend_members (blend_id, user_id, status) VALUES ($1, $2, 'pending') ON CONFLICT DO NOTHING`,
			blendID, uid)
	}

	// Generate immediately (creator's taste alone for now)
	go func() {
		genCtx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
		defer cancel()
		if err := s.Generate(genCtx, blendID); err != nil {
			log.Printf("[blend] initial generate %s: %v", blendID, err)
		}
	}()

	return s.GetByID(ctx, blendID, creatorID)
}

func (s *Service) AcceptInvite(ctx context.Context, blendID, userID string) error {
	tag, err := s.db.Exec(ctx,
		`UPDATE blend_members SET status = 'accepted', joined_at = now()
		 WHERE blend_id = $1 AND user_id = $2 AND status = 'pending'`,
		blendID, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("no pending invite")
	}

	// Regenerate with new member's taste
	go func() {
		genCtx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
		defer cancel()
		_ = s.Generate(genCtx, blendID)
	}()

	return nil
}

func (s *Service) DeclineInvite(ctx context.Context, blendID, userID string) error {
	_, err := s.db.Exec(ctx,
		`UPDATE blend_members SET status = 'declined' WHERE blend_id = $1 AND user_id = $2`,
		blendID, userID)
	return err
}

func (s *Service) ListMine(ctx context.Context, userID string) ([]Blend, error) {
	rows, err := s.db.Query(ctx,
		`SELECT b.id, b.creator_id, b.title, b.status, b.last_generated_at, b.created_at
		 FROM blends b JOIN blend_members bm ON bm.blend_id = b.id
		 WHERE bm.user_id = $1 AND bm.status IN ('accepted','pending') AND b.status = 'active'
		 ORDER BY b.created_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var blends []Blend
	for rows.Next() {
		var b Blend
		if rows.Scan(&b.ID, &b.CreatorID, &b.Title, &b.Status, &b.LastGeneratedAt, &b.CreatedAt) == nil {
			blends = append(blends, b)
		}
	}
	return blends, nil
}

func (s *Service) GetByID(ctx context.Context, blendID, viewerID string) (*Blend, error) {
	var b Blend
	err := s.db.QueryRow(ctx,
		`SELECT id, creator_id, title, status, last_generated_at, created_at FROM blends WHERE id = $1`,
		blendID,
	).Scan(&b.ID, &b.CreatorID, &b.Title, &b.Status, &b.LastGeneratedAt, &b.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("blend not found")
	}

	// Members
	mRows, _ := s.db.Query(ctx,
		`SELECT bm.user_id, COALESCE(u.username,''), COALESCE(u.name,''), COALESCE(u.avatar_url,''), bm.status
		 FROM blend_members bm JOIN users u ON u.id = bm.user_id
		 WHERE bm.blend_id = $1 ORDER BY bm.joined_at`, blendID)
	if mRows != nil {
		defer mRows.Close()
		for mRows.Next() {
			var m BlendMember
			if mRows.Scan(&m.UserID, &m.Username, &m.Name, &m.Avatar, &m.Status) == nil {
				b.Members = append(b.Members, m)
			}
		}
	}

	// Tracks
	tRows, _ := s.db.Query(ctx,
		`SELECT id, provider, track_id, title, artist, cover_url, duration, match_score, match_label, position
		 FROM blend_tracks WHERE blend_id = $1 ORDER BY position`, blendID)
	if tRows != nil {
		defer tRows.Close()
		for tRows.Next() {
			var t BlendTrack
			if tRows.Scan(&t.ID, &t.Provider, &t.TrackID, &t.Title, &t.Artist,
				&t.CoverURL, &t.Duration, &t.MatchScore, &t.MatchLabel, &t.Position) == nil {
				b.Tracks = append(b.Tracks, t)
			}
		}
	}

	return &b, nil
}

func (s *Service) Delete(ctx context.Context, blendID, creatorID string) error {
	_, err := s.db.Exec(ctx,
		`UPDATE blends SET status = 'archived' WHERE id = $1 AND creator_id = $2`,
		blendID, creatorID)
	return err
}

// RegenerateAll is called by the daily cron job.
func (s *Service) RegenerateAll(ctx context.Context) error {
	rows, err := s.db.Query(ctx, `SELECT id FROM blends WHERE status = 'active'`)
	if err != nil {
		return err
	}
	defer rows.Close()

	var ids []string
	for rows.Next() {
		var id string
		if rows.Scan(&id) == nil {
			ids = append(ids, id)
		}
	}

	log.Printf("[blend] regenerating %d active blends...", len(ids))
	for _, id := range ids {
		if err := s.Generate(ctx, id); err != nil {
			log.Printf("[blend] regenerate %s failed: %v", id, err)
		}
		time.Sleep(500 * time.Millisecond) // rate limit
	}
	log.Printf("[blend] regeneration complete")
	return nil
}
