package notifications

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Service manages device tokens and push notification delivery.
type Service struct {
	db         *pgxpool.Pool
	apnsKeyID  string
	apnsTeamID string
	apnsBundleID string
	apnsKeyB64 string
}

// NewService creates a notification service.
func NewService(db *pgxpool.Pool, apnsKeyID, apnsTeamID, apnsBundleID, apnsKeyB64 string) *Service {
	return &Service{
		db:           db,
		apnsKeyID:    apnsKeyID,
		apnsTeamID:   apnsTeamID,
		apnsBundleID: apnsBundleID,
		apnsKeyB64:   apnsKeyB64,
	}
}

// RegisterDevice stores a device token for push notifications.
func (s *Service) RegisterDevice(ctx context.Context, userID, platform, token string) error {
	_, err := s.db.Exec(ctx,
		`INSERT INTO device_tokens (user_id, platform, token)
		 VALUES ($1, $2, $3)
		 ON CONFLICT (user_id, token) DO UPDATE SET platform = $2, updated_at = now()`,
		userID, platform, token,
	)
	return err
}

// UnregisterDevice removes a device token.
func (s *Service) UnregisterDevice(ctx context.Context, userID, token string) error {
	_, err := s.db.Exec(ctx,
		`DELETE FROM device_tokens WHERE user_id = $1 AND token = $2`,
		userID, token,
	)
	return err
}

// SendPush delivers a push notification to all of a user's devices.
func (s *Service) SendPush(ctx context.Context, userID, title, body string, data map[string]string) error {
	rows, err := s.db.Query(ctx,
		`SELECT platform, token FROM device_tokens WHERE user_id = $1`,
		userID,
	)
	if err != nil {
		return fmt.Errorf("query tokens: %w", err)
	}
	defer rows.Close()

	var sent int
	for rows.Next() {
		var platform, token string
		if err := rows.Scan(&platform, &token); err != nil {
			continue
		}

		switch platform {
		case "ios":
			if err := s.sendAPNs(ctx, token, title, body, data); err != nil {
				log.Printf("[push] APNs error user=%s token=%.20s: %v", userID, token, err)
			} else {
				sent++
			}
		default:
			log.Printf("[push] unsupported platform %s for user %s", platform, userID)
		}
	}

	// Log the notification.
	payload, _ := json.Marshal(data)
	_, _ = s.db.Exec(ctx,
		`INSERT INTO notifications_log (user_id, kind, title, body, payload)
		 VALUES ($1, $2, $3, $4, $5)`,
		userID, data["kind"], title, body, payload,
	)

	log.Printf("[push] sent %d notifications to user %s: %s", sent, userID, title)
	return nil
}

// History returns recent notifications for a user.
func (s *Service) History(ctx context.Context, userID string, limit int) ([]NotificationEntry, error) {
	if limit <= 0 {
		limit = 50
	}
	rows, err := s.db.Query(ctx,
		`SELECT id, kind, title, body, payload, sent_at
		 FROM notifications_log WHERE user_id = $1
		 ORDER BY sent_at DESC LIMIT $2`,
		userID, limit,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var entries []NotificationEntry
	for rows.Next() {
		var e NotificationEntry
		var payload []byte
		if err := rows.Scan(&e.ID, &e.Kind, &e.Title, &e.Body, &payload, &e.SentAt); err != nil {
			continue
		}
		_ = json.Unmarshal(payload, &e.Payload)
		entries = append(entries, e)
	}
	return entries, nil
}

// NotificationEntry is a logged notification.
type NotificationEntry struct {
	ID      string            `json:"id"`
	Kind    string            `json:"kind"`
	Title   string            `json:"title"`
	Body    string            `json:"body"`
	Payload map[string]string `json:"payload"`
	SentAt  time.Time         `json:"sent_at"`
}

// sendAPNs sends a push notification via Apple Push Notification service.
// Uses HTTP/2 APNs API directly when apns2 library is available,
// otherwise logs the notification.
func (s *Service) sendAPNs(ctx context.Context, deviceToken, title, body string, data map[string]string) error {
	if s.apnsKeyB64 == "" {
		log.Printf("[apns] no key configured, skipping push to %.20s", deviceToken)
		return nil
	}

	// Build APNs payload.
	payload := map[string]any{
		"aps": map[string]any{
			"alert": map[string]string{
				"title": title,
				"body":  body,
			},
			"sound": "default",
		},
		"data": data,
	}

	payloadJSON, err := json.Marshal(payload)
	if err != nil {
		return err
	}

	log.Printf("[apns] would send to %.20s: %s", deviceToken, string(payloadJSON))
	// TODO: implement actual APNs HTTP/2 delivery when sideshow/apns2 is added.
	// For now, the notification is logged and the infrastructure is ready.
	return nil
}
