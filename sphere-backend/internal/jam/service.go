package jam

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type sessionState struct {
	HostID          string
	CurrentProvider string
	CurrentTrackID  string
	Position        float64
	IsPlaying       bool
	LastSync        time.Time
}

type Service struct {
	db     *pgxpool.Pool
	mu     sync.Mutex
	active map[string]*sessionState
}

func NewService(db *pgxpool.Pool) *Service {
	return &Service{db: db, active: make(map[string]*sessionState)}
}

// --- Models ---

type JamSession struct {
	ID              string           `json:"id"`
	HostID          string           `json:"host_id"`
	Title           string           `json:"title"`
	Status          string           `json:"status"`
	CurrentProvider string           `json:"current_provider"`
	CurrentTrackID  string           `json:"current_track_id"`
	CurrentPosition float64          `json:"current_position"`
	IsPlaying       bool             `json:"is_playing"`
	CreatedAt       time.Time        `json:"created_at"`
	EndedAt         *time.Time       `json:"ended_at,omitempty"`
	Participants    []JamParticipant `json:"participants,omitempty"`
	Queue           []QueueItem      `json:"queue,omitempty"`
}

type JamParticipant struct {
	UserID   string `json:"user_id"`
	Username string `json:"username"`
	Name     string `json:"name"`
	Avatar   string `json:"avatar_url"`
}

type QueueItem struct {
	ID        string    `json:"id"`
	Provider  string    `json:"provider"`
	TrackID   string    `json:"track_id"`
	Title     string    `json:"title"`
	Artist    string    `json:"artist"`
	CoverURL  string    `json:"cover_url"`
	Duration  int       `json:"duration"`
	AddedBy   string    `json:"added_by"`
	Position  int       `json:"position"`
	Status    string    `json:"status"`
	Upvotes   int       `json:"upvotes"`
	Downvotes int       `json:"downvotes"`
	AddedAt   time.Time `json:"added_at"`
}

// --- Session lifecycle ---

func (s *Service) CreateSession(ctx context.Context, hostID, title string) (*JamSession, error) {
	// End prior active sessions
	_, _ = s.db.Exec(ctx,
		`UPDATE jam_sessions SET status = 'ended', ended_at = now() WHERE host_id = $1 AND status = 'active'`,
		hostID)

	var sess JamSession
	err := s.db.QueryRow(ctx,
		`INSERT INTO jam_sessions (host_id, title) VALUES ($1, $2)
		 RETURNING id, host_id, title, status, current_provider, current_track_id, current_position, is_playing, created_at`,
		hostID, title,
	).Scan(&sess.ID, &sess.HostID, &sess.Title, &sess.Status,
		&sess.CurrentProvider, &sess.CurrentTrackID, &sess.CurrentPosition,
		&sess.IsPlaying, &sess.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("create jam: %w", err)
	}

	// Auto-join host
	_, _ = s.db.Exec(ctx,
		`INSERT INTO jam_participants (session_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
		sess.ID, hostID)

	s.mu.Lock()
	s.active[sess.ID] = &sessionState{HostID: hostID, LastSync: time.Now()}
	s.mu.Unlock()

	return &sess, nil
}

func (s *Service) JoinSession(ctx context.Context, sessionID, userID string) error {
	var status string
	err := s.db.QueryRow(ctx, `SELECT status FROM jam_sessions WHERE id = $1`, sessionID).Scan(&status)
	if err != nil {
		return fmt.Errorf("session not found")
	}
	if status != "active" {
		return fmt.Errorf("session ended")
	}
	_, err = s.db.Exec(ctx,
		`INSERT INTO jam_participants (session_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
		sessionID, userID)
	return err
}

func (s *Service) LeaveSession(ctx context.Context, sessionID, userID string) error {
	_, err := s.db.Exec(ctx,
		`DELETE FROM jam_participants WHERE session_id = $1 AND user_id = $2`,
		sessionID, userID)
	if err != nil {
		return err
	}
	// If host leaves, end session
	var hostID string
	_ = s.db.QueryRow(ctx, `SELECT host_id FROM jam_sessions WHERE id = $1`, sessionID).Scan(&hostID)
	if hostID == userID {
		return s.EndSession(ctx, sessionID, userID)
	}
	return nil
}

func (s *Service) EndSession(ctx context.Context, sessionID, hostID string) error {
	_, err := s.db.Exec(ctx,
		`UPDATE jam_sessions SET status = 'ended', ended_at = now() WHERE id = $1 AND host_id = $2`,
		sessionID, hostID)
	s.mu.Lock()
	delete(s.active, sessionID)
	s.mu.Unlock()
	return err
}

func (s *Service) GetSession(ctx context.Context, sessionID string) (*JamSession, error) {
	var sess JamSession
	err := s.db.QueryRow(ctx,
		`SELECT id, host_id, title, status, current_provider, current_track_id,
		        current_position, is_playing, created_at, ended_at
		 FROM jam_sessions WHERE id = $1`, sessionID,
	).Scan(&sess.ID, &sess.HostID, &sess.Title, &sess.Status,
		&sess.CurrentProvider, &sess.CurrentTrackID, &sess.CurrentPosition,
		&sess.IsPlaying, &sess.CreatedAt, &sess.EndedAt)
	if err != nil {
		return nil, fmt.Errorf("session not found")
	}

	// Load participants
	rows, err := s.db.Query(ctx,
		`SELECT jp.user_id, COALESCE(u.username,''), COALESCE(u.name,''), COALESCE(u.avatar_url,'')
		 FROM jam_participants jp JOIN users u ON u.id = jp.user_id
		 WHERE jp.session_id = $1 ORDER BY jp.joined_at`, sessionID)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var p JamParticipant
			if rows.Scan(&p.UserID, &p.Username, &p.Name, &p.Avatar) == nil {
				sess.Participants = append(sess.Participants, p)
			}
		}
	}

	// Load queue
	sess.Queue, _ = s.GetQueue(ctx, sessionID)
	return &sess, nil
}

func (s *Service) GetParticipantIDs(ctx context.Context, sessionID string) ([]string, error) {
	rows, err := s.db.Query(ctx,
		`SELECT user_id FROM jam_participants WHERE session_id = $1`, sessionID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		if rows.Scan(&id) == nil {
			ids = append(ids, id)
		}
	}
	return ids, nil
}

// --- Queue ---

func (s *Service) AddToQueue(ctx context.Context, sessionID, userID string, item QueueItem) (*QueueItem, error) {
	var maxPos int
	_ = s.db.QueryRow(ctx,
		`SELECT COALESCE(MAX(position), 0) FROM jam_queue WHERE session_id = $1`, sessionID,
	).Scan(&maxPos)

	var out QueueItem
	err := s.db.QueryRow(ctx,
		`INSERT INTO jam_queue (session_id, provider, track_id, title, artist, cover_url, duration, added_by, position)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		 RETURNING id, provider, track_id, title, artist, cover_url, duration, added_by, position, status, upvotes, downvotes, added_at`,
		sessionID, item.Provider, item.TrackID, item.Title, item.Artist,
		item.CoverURL, item.Duration, userID, maxPos+1,
	).Scan(&out.ID, &out.Provider, &out.TrackID, &out.Title, &out.Artist,
		&out.CoverURL, &out.Duration, &out.AddedBy, &out.Position,
		&out.Status, &out.Upvotes, &out.Downvotes, &out.AddedAt)
	if err != nil {
		return nil, fmt.Errorf("add to queue: %w", err)
	}
	return &out, nil
}

func (s *Service) RemoveFromQueue(ctx context.Context, sessionID, userID, itemID string) error {
	// Only adder or host can remove
	var addedBy, hostID string
	_ = s.db.QueryRow(ctx, `SELECT added_by FROM jam_queue WHERE id = $1 AND session_id = $2`, itemID, sessionID).Scan(&addedBy)
	_ = s.db.QueryRow(ctx, `SELECT host_id FROM jam_sessions WHERE id = $1`, sessionID).Scan(&hostID)
	if addedBy != userID && hostID != userID {
		return fmt.Errorf("forbidden")
	}
	_, err := s.db.Exec(ctx, `DELETE FROM jam_queue WHERE id = $1 AND session_id = $2`, itemID, sessionID)
	return err
}

func (s *Service) VoteQueue(ctx context.Context, sessionID, userID, itemID string, vote int) (*QueueItem, error) {
	if vote != 1 && vote != -1 {
		return nil, fmt.Errorf("vote must be 1 or -1")
	}

	// Upsert vote
	_, err := s.db.Exec(ctx,
		`INSERT INTO jam_queue_votes (queue_item_id, user_id, vote) VALUES ($1, $2, $3)
		 ON CONFLICT (queue_item_id, user_id) DO UPDATE SET vote = $3`,
		itemID, userID, vote)
	if err != nil {
		return nil, err
	}

	// Recalculate counts
	_, err = s.db.Exec(ctx,
		`UPDATE jam_queue SET
		   upvotes = (SELECT COUNT(*) FROM jam_queue_votes WHERE queue_item_id = $1 AND vote = 1),
		   downvotes = (SELECT COUNT(*) FROM jam_queue_votes WHERE queue_item_id = $1 AND vote = -1)
		 WHERE id = $1`, itemID)
	if err != nil {
		return nil, err
	}

	// Return updated item
	var out QueueItem
	err = s.db.QueryRow(ctx,
		`SELECT id, provider, track_id, title, artist, cover_url, duration, added_by, position, status, upvotes, downvotes, added_at
		 FROM jam_queue WHERE id = $1`, itemID,
	).Scan(&out.ID, &out.Provider, &out.TrackID, &out.Title, &out.Artist,
		&out.CoverURL, &out.Duration, &out.AddedBy, &out.Position,
		&out.Status, &out.Upvotes, &out.Downvotes, &out.AddedAt)
	return &out, err
}

func (s *Service) GetQueue(ctx context.Context, sessionID string) ([]QueueItem, error) {
	rows, err := s.db.Query(ctx,
		`SELECT id, provider, track_id, title, artist, cover_url, duration, added_by, position, status, upvotes, downvotes, added_at
		 FROM jam_queue WHERE session_id = $1 AND status = 'queued'
		 ORDER BY (upvotes - downvotes) DESC, position ASC`, sessionID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []QueueItem
	for rows.Next() {
		var q QueueItem
		if rows.Scan(&q.ID, &q.Provider, &q.TrackID, &q.Title, &q.Artist,
			&q.CoverURL, &q.Duration, &q.AddedBy, &q.Position,
			&q.Status, &q.Upvotes, &q.Downvotes, &q.AddedAt) == nil {
			items = append(items, q)
		}
	}
	return items, nil
}

// --- Playback control (host only) ---

func (s *Service) PlayNext(ctx context.Context, sessionID, hostID string) (*QueueItem, error) {
	if err := s.checkHost(ctx, sessionID, hostID); err != nil {
		return nil, err
	}

	// Mark current as played
	_, _ = s.db.Exec(ctx,
		`UPDATE jam_queue SET status = 'played' WHERE session_id = $1 AND status = 'playing'`, sessionID)

	// Pick next by votes
	var next QueueItem
	err := s.db.QueryRow(ctx,
		`UPDATE jam_queue SET status = 'playing'
		 WHERE id = (
			SELECT id FROM jam_queue WHERE session_id = $1 AND status = 'queued'
			ORDER BY (upvotes - downvotes) DESC, position ASC LIMIT 1
		 )
		 RETURNING id, provider, track_id, title, artist, cover_url, duration, added_by, position, status, upvotes, downvotes, added_at`,
		sessionID,
	).Scan(&next.ID, &next.Provider, &next.TrackID, &next.Title, &next.Artist,
		&next.CoverURL, &next.Duration, &next.AddedBy, &next.Position,
		&next.Status, &next.Upvotes, &next.Downvotes, &next.AddedAt)
	if err != nil {
		return nil, fmt.Errorf("no more tracks in queue")
	}

	// Update session current track
	_, _ = s.db.Exec(ctx,
		`UPDATE jam_sessions SET current_provider = $2, current_track_id = $3, current_position = 0, is_playing = true
		 WHERE id = $1`, sessionID, next.Provider, next.TrackID)

	s.mu.Lock()
	if st, ok := s.active[sessionID]; ok {
		st.CurrentProvider = next.Provider
		st.CurrentTrackID = next.TrackID
		st.Position = 0
		st.IsPlaying = true
		st.LastSync = time.Now()
	}
	s.mu.Unlock()

	return &next, nil
}

func (s *Service) SkipTrack(ctx context.Context, sessionID, hostID string) (*QueueItem, error) {
	if err := s.checkHost(ctx, sessionID, hostID); err != nil {
		return nil, err
	}
	_, _ = s.db.Exec(ctx,
		`UPDATE jam_queue SET status = 'skipped' WHERE session_id = $1 AND status = 'playing'`, sessionID)
	return s.PlayNext(ctx, sessionID, hostID)
}

func (s *Service) SyncPlayback(ctx context.Context, sessionID, hostID, provider, trackID string, position float64, isPlaying bool) error {
	if err := s.checkHost(ctx, sessionID, hostID); err != nil {
		return err
	}

	_, err := s.db.Exec(ctx,
		`UPDATE jam_sessions SET current_provider = $2, current_track_id = $3, current_position = $4, is_playing = $5
		 WHERE id = $1`, sessionID, provider, trackID, position, isPlaying)

	s.mu.Lock()
	if st, ok := s.active[sessionID]; ok {
		st.CurrentProvider = provider
		st.CurrentTrackID = trackID
		st.Position = position
		st.IsPlaying = isPlaying
		st.LastSync = time.Now()
	}
	s.mu.Unlock()

	return err
}

func (s *Service) checkHost(ctx context.Context, sessionID, userID string) error {
	var hostID string
	err := s.db.QueryRow(ctx, `SELECT host_id FROM jam_sessions WHERE id = $1 AND status = 'active'`, sessionID).Scan(&hostID)
	if err != nil {
		return fmt.Errorf("session not found")
	}
	if hostID != userID {
		return fmt.Errorf("host only")
	}
	return nil
}
