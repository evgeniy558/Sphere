package listen

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Service struct {
	db *pgxpool.Pool
}

func NewService(db *pgxpool.Pool) *Service {
	return &Service{db: db}
}

func (s *Service) CreateSession(ctx context.Context, hostID, trackProvider, trackID string) (*Session, error) {
	// End any currently-active session by this host first.
	_, _ = s.db.Exec(ctx, `
		UPDATE listen_sessions SET status = 'ended', ended_at = now()
		WHERE host_id = $1 AND status = 'active'
	`, hostID)

	var sess Session
	err := s.db.QueryRow(ctx, `
		INSERT INTO listen_sessions (host_id, track_provider, track_id)
		VALUES ($1, $2, $3)
		RETURNING id, host_id, track_provider, track_id, status, created_at
	`, hostID, trackProvider, trackID).Scan(
		&sess.ID, &sess.HostID, &sess.TrackProvider, &sess.TrackID,
		&sess.Status, &sess.CreatedAt,
	)
	if err != nil {
		return nil, err
	}

	// Host joins automatically.
	_, _ = s.db.Exec(ctx, `
		INSERT INTO listen_session_participants (session_id, user_id)
		VALUES ($1, $2) ON CONFLICT DO NOTHING
	`, sess.ID, hostID)

	sess.Participants = []Participant{}
	return &sess, nil
}

func (s *Service) JoinSession(ctx context.Context, sessionID, userID string) error {
	var status string
	err := s.db.QueryRow(ctx,
		`SELECT status FROM listen_sessions WHERE id = $1`, sessionID,
	).Scan(&status)
	if err != nil {
		return fmt.Errorf("session not found")
	}
	if status != "active" {
		return fmt.Errorf("session ended")
	}

	_, err = s.db.Exec(ctx, `
		INSERT INTO listen_session_participants (session_id, user_id)
		VALUES ($1, $2) ON CONFLICT DO NOTHING
	`, sessionID, userID)
	return err
}

func (s *Service) LeaveSession(ctx context.Context, sessionID, userID string) error {
	_, err := s.db.Exec(ctx, `
		DELETE FROM listen_session_participants
		WHERE session_id = $1 AND user_id = $2
	`, sessionID, userID)
	return err
}

func (s *Service) EndSession(ctx context.Context, sessionID, hostID string) error {
	tag, err := s.db.Exec(ctx, `
		UPDATE listen_sessions SET status = 'ended', ended_at = now()
		WHERE id = $1 AND host_id = $2 AND status = 'active'
	`, sessionID, hostID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("not found or not host")
	}
	return nil
}

func (s *Service) GetSession(ctx context.Context, sessionID string) (*Session, error) {
	var sess Session
	var endedAt *time.Time
	err := s.db.QueryRow(ctx, `
		SELECT id, host_id, track_provider, track_id, status, created_at, ended_at
		FROM listen_sessions WHERE id = $1
	`, sessionID).Scan(
		&sess.ID, &sess.HostID, &sess.TrackProvider, &sess.TrackID,
		&sess.Status, &sess.CreatedAt, &endedAt,
	)
	if err == pgx.ErrNoRows {
		return nil, fmt.Errorf("not found")
	}
	if err != nil {
		return nil, err
	}
	sess.EndedAt = endedAt

	// Load participants.
	rows, err := s.db.Query(ctx, `
		SELECT p.user_id, u.username, u.name, u.avatar_url, p.joined_at
		FROM listen_session_participants p
		JOIN users u ON u.id = p.user_id
		WHERE p.session_id = $1
		ORDER BY p.joined_at ASC
	`, sessionID)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var pt Participant
			if err := rows.Scan(&pt.UserID, &pt.Username, &pt.Name, &pt.AvatarURL, &pt.JoinedAt); err != nil {
				continue
			}
			sess.Participants = append(sess.Participants, pt)
		}
	}
	if sess.Participants == nil {
		sess.Participants = []Participant{}
	}

	return &sess, nil
}

// GetParticipantIDs returns all user IDs in a session for broadcasting.
func (s *Service) GetParticipantIDs(ctx context.Context, sessionID string) ([]string, error) {
	rows, err := s.db.Query(ctx, `
		SELECT user_id FROM listen_session_participants WHERE session_id = $1
	`, sessionID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			continue
		}
		ids = append(ids, id)
	}
	return ids, nil
}
