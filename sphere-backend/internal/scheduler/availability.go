package scheduler

import (
	"context"
	"fmt"
	"log"
	"time"
)

// runAvailabilityCheck scans user playlists and favorites for unavailable tracks,
// finds replacements via crossmap, and sends push notifications.
func (s *Scheduler) runAvailabilityCheck() {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
	defer cancel()

	log.Println("[availability] starting track availability check...")
	start := time.Now()

	// Collect unique (provider, track_id) pairs from user playlists and favorites.
	type trackKey struct {
		Provider string
		TrackID  string
	}

	trackUsers := make(map[trackKey][]string) // track → list of user IDs that have it

	// From user_playlist_tracks
	rows, err := s.db.Query(ctx,
		`SELECT DISTINCT upt.provider, upt.track_id, up.owner_id
		 FROM user_playlist_tracks upt
		 JOIN user_playlists up ON up.id = upt.playlist_id
		 LIMIT 10000`,
	)
	if err != nil {
		log.Printf("[availability] query playlist tracks: %v", err)
		return
	}
	for rows.Next() {
		var prov, trackID, userID string
		if rows.Scan(&prov, &trackID, &userID) == nil {
			key := trackKey{prov, trackID}
			trackUsers[key] = append(trackUsers[key], userID)
		}
	}
	rows.Close()

	// From favorites (tracks only)
	rows2, err := s.db.Query(ctx,
		`SELECT DISTINCT provider, provider_item_id, user_id
		 FROM favorites WHERE item_type = 'track'
		 LIMIT 10000`,
	)
	if err != nil {
		log.Printf("[availability] query favorites: %v", err)
		return
	}
	for rows2.Next() {
		var prov, trackID, userID string
		if rows2.Scan(&prov, &trackID, &userID) == nil {
			key := trackKey{prov, trackID}
			// Deduplicate users.
			found := false
			for _, u := range trackUsers[key] {
				if u == userID {
					found = true
					break
				}
			}
			if !found {
				trackUsers[key] = append(trackUsers[key], userID)
			}
		}
	}
	rows2.Close()

	log.Printf("[availability] checking %d unique tracks...", len(trackUsers))

	var checked, unavailable, replaced int

	for key, users := range trackUsers {
		// Rate limit: 100ms between checks.
		time.Sleep(100 * time.Millisecond)

		checkCtx, checkCancel := context.WithTimeout(ctx, 10*time.Second)

		// Check if track is still available.
		_, err := s.music.GetTrack(checkCtx, key.Provider, key.TrackID)
		checkCancel()
		checked++

		if err != nil {
			// Track is unavailable.
			unavailable++
			log.Printf("[availability] unavailable: %s/%s (%d users affected)", key.Provider, key.TrackID, len(users))

			// Try to find a replacement.
			alts, altErr := s.crossmap.FindAlternatives(ctx, key.Provider, key.TrackID)
			var replacementProvider, replacementTrackID string
			if altErr == nil {
				for _, alt := range alts {
					if alt.Provider != key.Provider && alt.Confidence >= 0.75 {
						replacementProvider = alt.Provider
						replacementTrackID = alt.TrackID
						replaced++
						break
					}
				}
			}

			// Update track_availability table.
			status := "unavailable"
			_, _ = s.db.Exec(ctx,
				`INSERT INTO track_availability (provider, track_id, status, last_checked_at, replacement_provider, replacement_track_id)
				 VALUES ($1, $2, $3, now(), $4, $5)
				 ON CONFLICT (provider, track_id) DO UPDATE SET
					status = $3, last_checked_at = now(),
					replacement_provider = $4, replacement_track_id = $5`,
				key.Provider, key.TrackID, status, replacementProvider, replacementTrackID,
			)

			// Send push notifications to affected users.
			for _, userID := range users {
				var title, body string
				if replacementProvider != "" {
					title = "Трек больше недоступен"
					body = fmt.Sprintf("Трек из %s больше недоступен, но найден на %s. Заменить источник?",
						key.Provider, replacementProvider)
				} else {
					title = "Трек недоступен"
					body = fmt.Sprintf("Трек из %s больше недоступен.", key.Provider)
				}

				_ = s.notif.SendPush(ctx, userID, title, body, map[string]string{
					"kind":                  "track_unavailable",
					"provider":              key.Provider,
					"track_id":              key.TrackID,
					"replacement_provider":  replacementProvider,
					"replacement_track_id":  replacementTrackID,
				})
			}
		} else {
			// Track is available — update status.
			_, _ = s.db.Exec(ctx,
				`INSERT INTO track_availability (provider, track_id, status, last_checked_at)
				 VALUES ($1, $2, 'available', now())
				 ON CONFLICT (provider, track_id) DO UPDATE SET
					status = 'available', last_checked_at = now()`,
				key.Provider, key.TrackID,
			)
		}
	}

	elapsed := time.Since(start)
	log.Printf("[availability] completed: checked=%d unavailable=%d replaced=%d elapsed=%s",
		checked, unavailable, replaced, elapsed.Round(time.Second))
}
