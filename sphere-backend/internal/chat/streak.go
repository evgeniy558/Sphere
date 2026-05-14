package chat

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// StreakInfo is returned to the client as part of the Thread or via a dedicated endpoint.
type StreakInfo struct {
	CurrentStreak    int     `json:"current_streak"`
	LongestStreak    int     `json:"longest_streak"`
	LastActivityDate *string `json:"last_activity_date,omitempty"`
}

// canonicalPair returns the two IDs in sorted order so they always match the DB key.
func canonicalPair(a, b string) (string, string) {
	if b < a {
		return b, a
	}
	return a, b
}

// RecordActivity is called after every message send. It updates the daily activity
// table and recalculates the streak when both track_share and discussion happened today.
func RecordActivity(ctx context.Context, db *pgxpool.Pool, senderID, chatID, kind string) {
	// Resolve the chat to get both user IDs.
	var dm1, dm2 string
	err := db.QueryRow(ctx,
		`SELECT dm_user1, dm_user2 FROM chats WHERE id = $1 AND kind = 'dm'`, chatID,
	).Scan(&dm1, &dm2)
	if err != nil {
		return
	}

	u1, u2 := canonicalPair(dm1, dm2)
	today := time.Now().UTC().Format("2006-01-02")

	// Determine which flag to set.
	shareCol := "has_track_share"
	if kind == "text" {
		shareCol = "has_discussion"
	}

	// UPSERT the daily activity row.
	_, _ = db.Exec(ctx, `
		INSERT INTO chat_daily_activity (user1_id, user2_id, activity_date, `+shareCol+`)
		VALUES ($1, $2, $3, true)
		ON CONFLICT (user1_id, user2_id, activity_date) DO UPDATE SET `+shareCol+` = true
	`, u1, u2, today)

	// Check if today has BOTH flags.
	var bothActive bool
	_ = db.QueryRow(ctx, `
		SELECT has_track_share AND has_discussion
		FROM chat_daily_activity
		WHERE user1_id = $1 AND user2_id = $2 AND activity_date = $3
	`, u1, u2, today).Scan(&bothActive)

	if !bothActive {
		return
	}

	// Recalculate streak: count consecutive days backwards from today.
	streak := calculateStreak(ctx, db, u1, u2)

	// Upsert the streak record.
	_, _ = db.Exec(ctx, `
		INSERT INTO chat_streaks (user1_id, user2_id, current_streak, last_activity_date, longest_streak)
		VALUES ($1, $2, $3, $4, $3)
		ON CONFLICT (user1_id, user2_id) DO UPDATE SET
			current_streak = $3,
			last_activity_date = $4,
			longest_streak = GREATEST(chat_streaks.longest_streak, $3)
	`, u1, u2, streak, today)
}

// calculateStreak counts consecutive days (including today) where both
// has_track_share AND has_discussion are true.
func calculateStreak(ctx context.Context, db *pgxpool.Pool, u1, u2 string) int {
	rows, err := db.Query(ctx, `
		SELECT activity_date
		FROM chat_daily_activity
		WHERE user1_id = $1 AND user2_id = $2
		  AND has_track_share = true AND has_discussion = true
		ORDER BY activity_date DESC
		LIMIT 365
	`, u1, u2)
	if err != nil {
		return 0
	}
	defer rows.Close()

	streak := 0
	expected := time.Now().UTC().Truncate(24 * time.Hour)
	for rows.Next() {
		var d time.Time
		if err := rows.Scan(&d); err != nil {
			break
		}
		day := d.Truncate(24 * time.Hour)
		if day.Equal(expected) {
			streak++
			expected = expected.AddDate(0, 0, -1)
		} else if day.Before(expected) {
			break
		}
	}
	return streak
}

// GetStreakForChat returns the streak between two users in a chat.
func GetStreakForChat(ctx context.Context, db *pgxpool.Pool, chatID string) (*StreakInfo, error) {
	var dm1, dm2 string
	err := db.QueryRow(ctx,
		`SELECT dm_user1, dm_user2 FROM chats WHERE id = $1 AND kind = 'dm'`, chatID,
	).Scan(&dm1, &dm2)
	if err != nil {
		return nil, err
	}
	return GetStreak(ctx, db, dm1, dm2)
}

// GetStreak returns the streak between two users.
func GetStreak(ctx context.Context, db *pgxpool.Pool, userA, userB string) (*StreakInfo, error) {
	u1, u2 := canonicalPair(userA, userB)

	var info StreakInfo
	var lastDate *time.Time
	err := db.QueryRow(ctx, `
		SELECT current_streak, longest_streak, last_activity_date
		FROM chat_streaks
		WHERE user1_id = $1 AND user2_id = $2
	`, u1, u2).Scan(&info.CurrentStreak, &info.LongestStreak, &lastDate)
	if err != nil {
		// No streak yet.
		return &StreakInfo{}, nil
	}

	if lastDate != nil {
		s := lastDate.Format("2006-01-02")
		info.LastActivityDate = &s

		// If last activity was more than 1 day ago, streak is broken.
		today := time.Now().UTC().Truncate(24 * time.Hour)
		lastDay := lastDate.Truncate(24 * time.Hour)
		diff := today.Sub(lastDay).Hours() / 24
		if diff > 1 {
			info.CurrentStreak = 0
		}
	}

	return &info, nil
}
