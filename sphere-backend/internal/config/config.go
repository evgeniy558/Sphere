package config

import (
	"encoding/hex"
	"fmt"
	"os"
	"strings"
)

type Config struct {
	Port           string
	DatabaseURL    string
	JWTSecret      string
	GoogleClientID string
	CommentEncryptionKey string
	ChatMessageKey       string
	// reCAPTCHA v3: https://developers.google.com/recaptcha/docs/v3
	RecaptchaSecret   string
	RecaptchaSiteKey  string
	RecaptchaMinScore float64
	// Resend: https://resend.com (signup verification email)
	ResendAPIKey     string
	MailFrom         string
	SignupLogCode    bool
	S3Endpoint       string
	S3AccessKey      string
	S3SecretKey      string
	S3Bucket         string
	SpotifyClientID  string
	SpotifySecret    string
	// Spotify streaming (optional): if set, backend can stream full Spotify tracks
	// via a stored blob credential (recommended) or username/password (fallback).
	SpotifyUsername  string
	SpotifyPassword  string
	SpotifyCredsBlob string
	SoundCloudID     string
	SoundCloudSecret string
	// VKAccessToken is a user OAuth token (vk1.a.*) with the audio scope — required for stream URLs.
	VKAccessToken string
	// VKToken is an optional service token (search/metadata only; no audio streams).
	VKToken          string
	YandexToken      string
	YandexSignKey    string
	YandexProxyURL   string
	GeniusToken      string
	// DeezerARL is a long-lived `arl` cookie from a logged-in deezer.com session.
	// When present, the Deezer provider unlocks full-track streaming via Deezer's
	// internal `gw-light` + `media.deezer.com/v1/get_url` APIs (otherwise public
	// Deezer only exposes 30-second previews).
	DeezerARL string

	// APNs (Apple Push Notification service) configuration.
	APNsKeyID    string
	APNsTeamID   string
	APNsBundleID string
	APNsKeyB64   string // Base64-encoded .p8 key file
}

func Load() (*Config, error) {
	cfg := &Config{
		Port:             getEnv("PORT", "8080"),
		DatabaseURL:      getEnv("DATABASE_URL", ""),
		JWTSecret:        getEnv("JWT_SECRET", ""),
		GoogleClientID:   getEnv("GOOGLE_CLIENT_ID", ""),
		CommentEncryptionKey: getEnv("COMMENT_ENCRYPTION_KEY", "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"),
		ChatMessageKey:       getEnv("CHAT_MESSAGE_KEY", "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"),
		S3Endpoint:       getEnv("S3_ENDPOINT", "http://localhost:9000"),
		S3AccessKey:      getEnv("S3_ACCESS_KEY", ""),
		S3SecretKey:      getEnv("S3_SECRET_KEY", ""),
		S3Bucket:         getEnv("S3_BUCKET", "sphere-uploads"),
		// Do not hardcode provider secrets — wrong defaults caused SoundCloud keys to be used for Spotify (403).
		SpotifyClientID:  getEnv("SPOTIFY_CLIENT_ID", ""),
		SpotifySecret:    getEnv("SPOTIFY_CLIENT_SECRET", ""),
		SpotifyUsername:  getEnv("SPOTIFY_USERNAME", ""),
		SpotifyPassword:  getEnv("SPOTIFY_PASSWORD", ""),
		SpotifyCredsBlob: getEnv("SPOTIFY_CREDS_BLOB", ""),
		SoundCloudID:     getEnv("SOUNDCLOUD_CLIENT_ID", ""),
		SoundCloudSecret: getEnv("SOUNDCLOUD_CLIENT_SECRET", ""),
		VKAccessToken:    getEnv("VK_ACCESS_TOKEN", ""),
		VKToken:          getEnv("VK_SERVICE_TOKEN", ""),
		YandexToken:      getEnv("YANDEX_SERVICE_TOKEN", ""),
		YandexSignKey:    getEnv("YANDEX_SIGN_KEY", ""),
		YandexProxyURL:   getEnv("YANDEX_HTTP_PROXY", ""),
		GeniusToken:      getEnv("GENIUS_TOKEN", "zTGbOmZjiWvldeVVVOMWAmmmAp0Aont38WMELq2DPqpihhThnVnj2o0FsZs9N30m"),
		DeezerARL:        getEnv("DEEZER_ARL", ""),
		APNsKeyID:        getEnv("APNS_KEY_ID", ""),
		APNsTeamID:       getEnv("APNS_TEAM_ID", ""),
		APNsBundleID:     getEnv("APNS_BUNDLE_ID", ""),
		APNsKeyB64:       getEnv("APNS_KEY_B64", ""),
		RecaptchaSecret:  getEnv("RECAPTCHA_SECRET", "6LfytsssAAAAAKgi5g2SL6wU3B6qeUglw9YKJ6J9"),
		RecaptchaSiteKey: getEnv("RECAPTCHA_SITE_KEY", "6LfytsssAAAAAITYZm3exkx5ODWZ8c8Nd_nysOBj"),
		ResendAPIKey:     getEnv("RESEND_API_KEY", "re_u4Yu3Sqg_Md9pqwsAV6hufnKA2y73mMue"),
		MailFrom:         getEnv("MAIL_FROM", "Sphere <noreply@spheremusic.space>"),
	}

	rms := getEnv("RECAPTCHA_MIN_SCORE", "0.5")
	if _, err := fmt.Sscanf(rms, "%f", &cfg.RecaptchaMinScore); err != nil || cfg.RecaptchaMinScore <= 0 {
		cfg.RecaptchaMinScore = 0.5
	}
	if getEnv("SIGNUP_LOG_CODE", "false") == "true" {
		cfg.SignupLogCode = true
	}

	if cfg.DatabaseURL == "" {
		return nil, fmt.Errorf("DATABASE_URL is required")
	}
	if cfg.JWTSecret == "" {
		return nil, fmt.Errorf("JWT_SECRET is required")
	}
	if err := validate64HexKey("COMMENT_ENCRYPTION_KEY", cfg.CommentEncryptionKey); err != nil {
		return nil, err
	}
	if err := validate64HexKey("CHAT_MESSAGE_KEY", cfg.ChatMessageKey); err != nil {
		return nil, err
	}

	return cfg, nil
}

func validate64HexKey(name, v string) error {
	s := strings.TrimSpace(v)
	b, err := hex.DecodeString(s)
	if err != nil || len(b) != 32 {
		return fmt.Errorf("%s must be exactly 64 hexadecimal characters (32 bytes)", name)
	}
	return nil
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
