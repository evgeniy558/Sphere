package playlist

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Service struct {
	db *pgxpool.Pool
}

func NewService(db *pgxpool.Pool) *Service {
	return &Service{db: db}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func (s *Service) checkEditAccess(ctx context.Context, playlistID, userID string) error {
	var exists bool
	err := s.db.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM user_playlists
			WHERE id = $1 AND owner_id = $2
		) OR EXISTS(
			SELECT 1 FROM user_playlist_members
			WHERE playlist_id = $1 AND user_id = $2 AND role = 'editor'
		)
	`, playlistID, userID).Scan(&exists)
	if err != nil {
		return fmt.Errorf("check edit access: %w", err)
	}
	if !exists {
		return fmt.Errorf("forbidden")
	}
	return nil
}

func (s *Service) checkAnyAccess(ctx context.Context, playlistID, userID string) (bool, error) {
	var allowed bool
	err := s.db.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM user_playlists
			WHERE id = $1 AND (owner_id = $2 OR is_public = true)
		) OR EXISTS(
			SELECT 1 FROM user_playlist_members
			WHERE playlist_id = $1 AND user_id = $2
		)
	`, playlistID, userID).Scan(&allowed)
	if err != nil {
		return false, fmt.Errorf("check any access: %w", err)
	}
	return allowed, nil
}

// ---------------------------------------------------------------------------
// CRUD
// ---------------------------------------------------------------------------

func (s *Service) Create(ctx context.Context, ownerID, title, description string, isPublic bool) (*Playlist, error) {
	var p Playlist
	err := s.db.QueryRow(ctx, `
		INSERT INTO user_playlists (owner_id, title, description, is_public)
		VALUES ($1, $2, $3, $4)
		RETURNING id, owner_id, title, description, cover_url, is_public, created_at, updated_at
	`, ownerID, title, description, isPublic).Scan(
		&p.ID, &p.OwnerID, &p.Title, &p.Description,
		&p.CoverURL, &p.IsPublic, &p.CreatedAt, &p.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("create playlist: %w", err)
	}
	p.TrackCount = 0
	p.Role = "owner"
	return &p, nil
}

func (s *Service) ListMine(ctx context.Context, userID string) ([]Playlist, error) {
	rows, err := s.db.Query(ctx, `
		SELECT p.id, p.owner_id, p.title, p.description, p.cover_url, p.is_public,
		       p.created_at, p.updated_at,
		       (SELECT count(*) FROM user_playlist_tracks WHERE playlist_id = p.id) AS track_count,
		       'owner' AS role
		FROM user_playlists p
		WHERE p.owner_id = $1

		UNION ALL

		SELECT p.id, p.owner_id, p.title, p.description, p.cover_url, p.is_public,
		       p.created_at, p.updated_at,
		       (SELECT count(*) FROM user_playlist_tracks WHERE playlist_id = p.id) AS track_count,
		       pm.role
		FROM user_playlist_members pm
		JOIN user_playlists p ON p.id = pm.playlist_id
		WHERE pm.user_id = $1

		ORDER BY updated_at DESC
	`, userID)
	if err != nil {
		return nil, fmt.Errorf("list playlists: %w", err)
	}
	defer rows.Close()

	out := make([]Playlist, 0)
	for rows.Next() {
		var p Playlist
		if err := rows.Scan(
			&p.ID, &p.OwnerID, &p.Title, &p.Description, &p.CoverURL, &p.IsPublic,
			&p.CreatedAt, &p.UpdatedAt, &p.TrackCount, &p.Role,
		); err != nil {
			return nil, fmt.Errorf("scan playlist: %w", err)
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

func (s *Service) GetByID(ctx context.Context, playlistID, viewerID string) (*PlaylistDetail, error) {
	allowed, err := s.checkAnyAccess(ctx, playlistID, viewerID)
	if err != nil {
		return nil, err
	}
	if !allowed {
		return nil, fmt.Errorf("forbidden")
	}

	// Load playlist
	var d PlaylistDetail
	err = s.db.QueryRow(ctx, `
		SELECT id, owner_id, title, description, cover_url, is_public, created_at, updated_at,
		       (SELECT count(*) FROM user_playlist_tracks WHERE playlist_id = $1)
		FROM user_playlists
		WHERE id = $1
	`, playlistID).Scan(
		&d.ID, &d.OwnerID, &d.Title, &d.Description, &d.CoverURL,
		&d.IsPublic, &d.CreatedAt, &d.UpdatedAt, &d.TrackCount,
	)
	if err != nil {
		return nil, fmt.Errorf("get playlist: %w", err)
	}

	// Determine viewer role
	if d.OwnerID == viewerID {
		d.Role = "owner"
	} else {
		_ = s.db.QueryRow(ctx, `
			SELECT role FROM user_playlist_members
			WHERE playlist_id = $1 AND user_id = $2
		`, playlistID, viewerID).Scan(&d.Role)
	}

	// Load tracks
	tRows, err := s.db.Query(ctx, `
		SELECT id, provider, track_id, title, artist, cover_url, duration, added_by, position, added_at
		FROM user_playlist_tracks
		WHERE playlist_id = $1
		ORDER BY position ASC
	`, playlistID)
	if err != nil {
		return nil, fmt.Errorf("get playlist tracks: %w", err)
	}
	defer tRows.Close()

	d.Tracks = make([]PlaylistTrack, 0)
	for tRows.Next() {
		var t PlaylistTrack
		if err := tRows.Scan(
			&t.ID, &t.Provider, &t.TrackID, &t.Title, &t.Artist,
			&t.CoverURL, &t.Duration, &t.AddedBy, &t.Position, &t.AddedAt,
		); err != nil {
			return nil, fmt.Errorf("scan track: %w", err)
		}
		d.Tracks = append(d.Tracks, t)
	}
	if err := tRows.Err(); err != nil {
		return nil, err
	}

	// Load members
	mRows, err := s.db.Query(ctx, `
		SELECT pm.user_id, u.username, u.name, u.avatar_url, pm.role, pm.added_at
		FROM user_playlist_members pm
		JOIN users u ON u.id = pm.user_id
		WHERE pm.playlist_id = $1
		ORDER BY pm.added_at ASC
	`, playlistID)
	if err != nil {
		return nil, fmt.Errorf("get playlist members: %w", err)
	}
	defer mRows.Close()

	d.Members = make([]Member, 0)
	for mRows.Next() {
		var m Member
		if err := mRows.Scan(
			&m.UserID, &m.Username, &m.Name, &m.AvatarURL, &m.Role, &m.AddedAt,
		); err != nil {
			return nil, fmt.Errorf("scan member: %w", err)
		}
		d.Members = append(d.Members, m)
	}
	return &d, mRows.Err()
}

func (s *Service) Update(ctx context.Context, playlistID, userID, title, description, coverURL string) error {
	tag, err := s.db.Exec(ctx, `
		UPDATE user_playlists
		SET title = $3, description = $4, cover_url = $5, updated_at = now()
		WHERE id = $1 AND owner_id = $2
	`, playlistID, userID, title, description, coverURL)
	if err != nil {
		return fmt.Errorf("update playlist: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("forbidden")
	}
	return nil
}

func (s *Service) Delete(ctx context.Context, playlistID, userID string) error {
	tag, err := s.db.Exec(ctx, `
		DELETE FROM user_playlists
		WHERE id = $1 AND owner_id = $2
	`, playlistID, userID)
	if err != nil {
		return fmt.Errorf("delete playlist: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("forbidden")
	}
	return nil
}

// ---------------------------------------------------------------------------
// Tracks
// ---------------------------------------------------------------------------

func (s *Service) AddTrack(ctx context.Context, playlistID, userID string, t PlaylistTrack) error {
	if err := s.checkEditAccess(ctx, playlistID, userID); err != nil {
		return err
	}

	var maxPos int
	err := s.db.QueryRow(ctx, `
		SELECT coalesce(max(position), -1) FROM user_playlist_tracks WHERE playlist_id = $1
	`, playlistID).Scan(&maxPos)
	if err != nil {
		return fmt.Errorf("get max position: %w", err)
	}

	_, err = s.db.Exec(ctx, `
		INSERT INTO user_playlist_tracks (playlist_id, provider, track_id, title, artist, cover_url, duration, added_by, position)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
	`, playlistID, t.Provider, t.TrackID, t.Title, t.Artist, t.CoverURL, t.Duration, userID, maxPos+1)
	if err != nil {
		return fmt.Errorf("add track: %w", err)
	}

	_, err = s.db.Exec(ctx, `
		UPDATE user_playlists SET updated_at = now() WHERE id = $1
	`, playlistID)
	return err
}

func (s *Service) RemoveTrack(ctx context.Context, playlistID, userID, trackDBID string) error {
	if err := s.checkEditAccess(ctx, playlistID, userID); err != nil {
		return err
	}

	var pos int
	err := s.db.QueryRow(ctx, `
		DELETE FROM user_playlist_tracks WHERE id = $1 AND playlist_id = $2 RETURNING position
	`, trackDBID, playlistID).Scan(&pos)
	if err != nil {
		return fmt.Errorf("remove track: %w", err)
	}

	// Reindex remaining positions
	_, err = s.db.Exec(ctx, `
		UPDATE user_playlist_tracks
		SET position = position - 1
		WHERE playlist_id = $1 AND position > $2
	`, playlistID, pos)
	if err != nil {
		return fmt.Errorf("reindex tracks: %w", err)
	}

	_, err = s.db.Exec(ctx, `
		UPDATE user_playlists SET updated_at = now() WHERE id = $1
	`, playlistID)
	return err
}

func (s *Service) ReorderTracks(ctx context.Context, playlistID, userID string, trackIDs []string) error {
	if err := s.checkEditAccess(ctx, playlistID, userID); err != nil {
		return err
	}

	tx, err := s.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	for i, tid := range trackIDs {
		_, err := tx.Exec(ctx, `
			UPDATE user_playlist_tracks SET position = $1 WHERE id = $2 AND playlist_id = $3
		`, i, tid, playlistID)
		if err != nil {
			return fmt.Errorf("reorder track %s: %w", tid, err)
		}
	}

	_, err = tx.Exec(ctx, `
		UPDATE user_playlists SET updated_at = now() WHERE id = $1
	`, playlistID)
	if err != nil {
		return fmt.Errorf("update timestamp: %w", err)
	}

	return tx.Commit(ctx)
}

// ---------------------------------------------------------------------------
// Members
// ---------------------------------------------------------------------------

func (s *Service) AddMember(ctx context.Context, playlistID, ownerID, targetUserID, role string) error {
	var realOwner string
	err := s.db.QueryRow(ctx, `
		SELECT owner_id FROM user_playlists WHERE id = $1
	`, playlistID).Scan(&realOwner)
	if err != nil {
		return fmt.Errorf("playlist not found: %w", err)
	}
	if realOwner != ownerID {
		return fmt.Errorf("forbidden")
	}

	_, err = s.db.Exec(ctx, `
		INSERT INTO user_playlist_members (playlist_id, user_id, role)
		VALUES ($1, $2, $3)
		ON CONFLICT (playlist_id, user_id)
		DO UPDATE SET role = EXCLUDED.role
	`, playlistID, targetUserID, role)
	if err != nil {
		return fmt.Errorf("add member: %w", err)
	}
	return nil
}

func (s *Service) RemoveMember(ctx context.Context, playlistID, callerID, targetUserID string) error {
	var realOwner string
	err := s.db.QueryRow(ctx, `
		SELECT owner_id FROM user_playlists WHERE id = $1
	`, playlistID).Scan(&realOwner)
	if err != nil {
		return fmt.Errorf("playlist not found: %w", err)
	}
	if realOwner != callerID {
		return fmt.Errorf("forbidden")
	}

	_, err = s.db.Exec(ctx, `
		DELETE FROM user_playlist_members WHERE playlist_id = $1 AND user_id = $2
	`, playlistID, targetUserID)
	if err != nil {
		return fmt.Errorf("remove member: %w", err)
	}
	return nil
}

func (s *Service) ListMembers(ctx context.Context, playlistID, viewerID string) ([]Member, error) {
	allowed, err := s.checkAnyAccess(ctx, playlistID, viewerID)
	if err != nil {
		return nil, err
	}
	if !allowed {
		return nil, fmt.Errorf("forbidden")
	}

	rows, err := s.db.Query(ctx, `
		SELECT pm.user_id, u.username, u.name, u.avatar_url, pm.role, pm.added_at
		FROM user_playlist_members pm
		JOIN users u ON u.id = pm.user_id
		WHERE pm.playlist_id = $1
		ORDER BY pm.added_at ASC
	`, playlistID)
	if err != nil {
		return nil, fmt.Errorf("list members: %w", err)
	}
	defer rows.Close()

	out := make([]Member, 0)
	for rows.Next() {
		var m Member
		if err := rows.Scan(
			&m.UserID, &m.Username, &m.Name, &m.AvatarURL, &m.Role, &m.AddedAt,
		); err != nil {
			return nil, fmt.Errorf("scan member: %w", err)
		}
		out = append(out, m)
	}
	return out, rows.Err()
}
