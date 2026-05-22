package db

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

func Connect(ctx context.Context, databaseURL string) (*pgxpool.Pool, error) {
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return nil, fmt.Errorf("connect to db: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("ping db: %w", err)
	}
	return pool, nil
}

func Migrate(ctx context.Context, pool *pgxpool.Pool) error {
	_, err := pool.Exec(ctx, migrationSQL)
	return err
}

const migrationSQL = `
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT,
    name TEXT NOT NULL DEFAULT '',
    avatar_url TEXT NOT NULL DEFAULT '',
    google_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS favorites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    item_type TEXT NOT NULL,
    provider TEXT NOT NULL,
    provider_item_id TEXT NOT NULL,
    title TEXT NOT NULL DEFAULT '',
    artist_name TEXT NOT NULL DEFAULT '',
    cover_url TEXT NOT NULL DEFAULT '',
    metadata JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, item_type, provider, provider_item_id)
);

-- favorites: enforce allowed item types + upgrade unique key
-- (PostgreSQL has no "ADD CONSTRAINT IF NOT EXISTS"; use DO blocks for idempotency)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint c
        JOIN pg_class t ON c.conrelid = t.oid
        WHERE t.relname = 'favorites' AND c.conname = 'favorites_item_type_check'
    ) THEN
        ALTER TABLE favorites ADD CONSTRAINT favorites_item_type_check
            CHECK (item_type IN ('track','album','playlist','artist'));
    END IF;
END $$;
ALTER TABLE favorites DROP CONSTRAINT IF EXISTS favorites_user_id_provider_provider_item_id_key;
DO $$
DECLARE
    has_new_unique boolean;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON c.conrelid = t.oid
        WHERE t.relname = 'favorites'
          AND c.contype = 'u'
          AND pg_get_constraintdef(c.oid) LIKE '%(user_id, item_type, provider, provider_item_id)%'
    ) INTO has_new_unique;
    IF NOT has_new_unique THEN
        ALTER TABLE favorites ADD CONSTRAINT favorites_user_item_unique
            UNIQUE (user_id, item_type, provider, provider_item_id);
    END IF;
END $$;
CREATE INDEX IF NOT EXISTS favorites_user_type_time_idx ON favorites(user_id, item_type, created_at DESC);

CREATE TABLE IF NOT EXISTS uploads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title TEXT NOT NULL DEFAULT '',
    artist_name TEXT NOT NULL DEFAULT '',
    duration INT NOT NULL DEFAULT 0,
    file_url TEXT NOT NULL,
    cover_url TEXT NOT NULL DEFAULT '',
    file_size BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS listen_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider TEXT NOT NULL,
    track_id TEXT NOT NULL,
    title TEXT NOT NULL DEFAULT '',
    artist TEXT NOT NULL DEFAULT '',
    genres TEXT[] NOT NULL DEFAULT '{}',
    listened_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS listen_history_user_time_idx ON listen_history(user_id, listened_at DESC);

CREATE TABLE IF NOT EXISTS user_preferences (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    selected_artists TEXT[] DEFAULT '{}',
    selected_genres TEXT[] DEFAULT '{}',
    onboarding_completed BOOLEAN DEFAULT false,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_lyrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    track_provider TEXT NOT NULL,
    track_id TEXT NOT NULL,
    text TEXT NOT NULL,
    user_id UUID REFERENCES users(id),
    user_name TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(track_provider, track_id)
);

CREATE TABLE IF NOT EXISTS comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    track_provider TEXT NOT NULL,
    track_id TEXT NOT NULL,
    user_id UUID REFERENCES users(id),
    user_name TEXT NOT NULL,
    user_avatar_url TEXT DEFAULT '',
    encrypted_text BYTEA NOT NULL,
    nonce BYTEA NOT NULL,
    parent_id UUID REFERENCES comments(id) ON DELETE CASCADE,
    likes INT DEFAULT 0,
    dislikes INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_comments_track ON comments(track_provider, track_id);

CREATE TABLE IF NOT EXISTS comment_votes (
    user_id UUID REFERENCES users(id),
    comment_id UUID REFERENCES comments(id) ON DELETE CASCADE,
    vote_type TEXT NOT NULL CHECK (vote_type IN ('like', 'dislike')),
    PRIMARY KEY (user_id, comment_id)
);

ALTER TABLE listen_history ADD COLUMN IF NOT EXISTS skipped BOOLEAN NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS signup_email_codes (
    email TEXT PRIMARY KEY,
    code_hash TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL
);

ALTER TABLE users ADD COLUMN IF NOT EXISTS is_verified BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS badge_text TEXT NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS badge_color TEXT NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS banned BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS banned_reason TEXT NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_secret TEXT NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_pending_secret TEXT NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_enabled BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS email_2fa_enabled BOOLEAN NOT NULL DEFAULT false;

-- Social/privacy
ALTER TABLE users ADD COLUMN IF NOT EXISTS username TEXT NOT NULL DEFAULT '';
CREATE UNIQUE INDEX IF NOT EXISTS users_username_unique_idx ON users (lower(username)) WHERE username <> '';

ALTER TABLE users ADD COLUMN IF NOT EXISTS hide_subscriptions BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS messages_mutual_only BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS private_profile BOOLEAN NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS subscriptions (
    follower_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    followee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (follower_id, followee_id)
);
CREATE INDEX IF NOT EXISTS subscriptions_followee_idx ON subscriptions(followee_id, created_at DESC);
CREATE INDEX IF NOT EXISTS subscriptions_follower_idx ON subscriptions(follower_id, created_at DESC);

CREATE TABLE IF NOT EXISTS subscription_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'denied', 'cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS subscription_requests_target_idx ON subscription_requests(target_id, created_at DESC);
CREATE INDEX IF NOT EXISTS subscription_requests_target_status_idx ON subscription_requests(target_id, status);
CREATE INDEX IF NOT EXISTS subscription_requests_requester_idx ON subscription_requests(requester_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS subscription_requests_one_pending_idx
    ON subscription_requests(requester_id, target_id)
    WHERE status = 'pending';

-- Chat
CREATE TABLE IF NOT EXISTS chats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    kind TEXT NOT NULL DEFAULT 'dm' CHECK (kind IN ('dm')),
    dm_user1 UUID REFERENCES users(id) ON DELETE CASCADE,
    dm_user2 UUID REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_message_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS chats_dm_pair_unique_idx
    ON chats(dm_user1, dm_user2)
    WHERE kind = 'dm' AND dm_user1 IS NOT NULL AND dm_user2 IS NOT NULL;
CREATE INDEX IF NOT EXISTS chats_last_message_idx ON chats(last_message_at DESC);

CREATE TABLE IF NOT EXISTS chat_participants (
    chat_id UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    last_read_at TIMESTAMPTZ,
    PRIMARY KEY (chat_id, user_id)
);
CREATE INDEX IF NOT EXISTS chat_participants_user_idx ON chat_participants(user_id);

CREATE TABLE IF NOT EXISTS chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind TEXT NOT NULL DEFAULT 'text' CHECK (kind IN ('text', 'track_share')),
    encrypted_payload BYTEA NOT NULL,
    nonce BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS chat_messages_chat_time_idx ON chat_messages(chat_id, created_at DESC);

CREATE TABLE IF NOT EXISTS email_change_codes (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    new_email TEXT NOT NULL,
    code_hash TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS qr_login_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nonce TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'pending',
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    token TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    client_ip TEXT NOT NULL DEFAULT ''
);

CREATE INDEX IF NOT EXISTS qr_login_sessions_nonce_idx ON qr_login_sessions(nonce);

CREATE TABLE IF NOT EXISTS login_2fa_challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL,
    email_sent BOOLEAN NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS login_2fa_challenges_user_idx ON login_2fa_challenges(user_id);

-- Streak system: daily activity tracking per chat pair
CREATE TABLE IF NOT EXISTS chat_daily_activity (
    user1_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user2_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    activity_date DATE NOT NULL,
    has_track_share BOOLEAN NOT NULL DEFAULT false,
    has_discussion BOOLEAN NOT NULL DEFAULT false,
    PRIMARY KEY (user1_id, user2_id, activity_date)
);

CREATE TABLE IF NOT EXISTS chat_streaks (
    user1_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user2_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    current_streak INT NOT NULL DEFAULT 0,
    last_activity_date DATE,
    longest_streak INT NOT NULL DEFAULT 0,
    PRIMARY KEY (user1_id, user2_id)
);

-- Listen-together sessions
CREATE TABLE IF NOT EXISTS listen_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    host_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    track_provider TEXT NOT NULL,
    track_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','ended')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS listen_session_participants (
    session_id UUID NOT NULL REFERENCES listen_sessions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (session_id, user_id)
);

-- App update/release notes
CREATE TABLE IF NOT EXISTS app_updates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    version TEXT NOT NULL,
    title TEXT NOT NULL DEFAULT '',
    body TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- User-created playlists (group playlists)
CREATE TABLE IF NOT EXISTS user_playlists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title TEXT NOT NULL DEFAULT '',
    description TEXT NOT NULL DEFAULT '',
    cover_url TEXT NOT NULL DEFAULT '',
    is_public BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS user_playlists_owner_idx ON user_playlists(owner_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS user_playlist_tracks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    playlist_id UUID NOT NULL REFERENCES user_playlists(id) ON DELETE CASCADE,
    provider TEXT NOT NULL,
    track_id TEXT NOT NULL,
    title TEXT NOT NULL DEFAULT '',
    artist TEXT NOT NULL DEFAULT '',
    cover_url TEXT NOT NULL DEFAULT '',
    duration INT NOT NULL DEFAULT 0,
    added_by UUID NOT NULL REFERENCES users(id),
    position INT NOT NULL DEFAULT 0,
    added_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS user_playlist_tracks_playlist_idx ON user_playlist_tracks(playlist_id, position ASC);

CREATE TABLE IF NOT EXISTS user_playlist_members (
    playlist_id UUID NOT NULL REFERENCES user_playlists(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'viewer' CHECK (role IN ('editor', 'viewer')),
    added_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (playlist_id, user_id)
);
CREATE INDEX IF NOT EXISTS user_playlist_members_user_idx ON user_playlist_members(user_id);

-- My Wave: user taste profiles
CREATE TABLE IF NOT EXISTS user_taste_profiles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    genre_weights JSONB NOT NULL DEFAULT '{}',
    artist_weights JSONB NOT NULL DEFAULT '{}',
    provider_weights JSONB NOT NULL DEFAULT '{}',
    energy_pref DOUBLE PRECISION NOT NULL DEFAULT 0.5,
    valence_pref DOUBLE PRECISION NOT NULL DEFAULT 0.5,
    tempo_pref DOUBLE PRECISION NOT NULL DEFAULT 120,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- My Wave: events (like/dislike/skip/finish)
CREATE TABLE IF NOT EXISTS wave_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_id UUID NOT NULL,
    provider TEXT NOT NULL,
    track_id TEXT NOT NULL,
    event_type TEXT NOT NULL CHECK (event_type IN ('play','like','dislike','skip','finish','add_to_library')),
    position_seconds DOUBLE PRECISION NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS wave_events_user_session_idx ON wave_events(user_id, session_id, created_at DESC);
CREATE INDEX IF NOT EXISTS wave_events_user_time_idx ON wave_events(user_id, created_at DESC);

-- Index for similar users query performance
CREATE INDEX IF NOT EXISTS listen_history_artist_user_idx ON listen_history(artist, user_id) WHERE artist <> '';

-- =====================================================================
-- NodeX Karaoke: cached vocal-removed tracks
-- =====================================================================
CREATE TABLE IF NOT EXISTS karaoke_cache (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider TEXT NOT NULL,
    track_id TEXT NOT NULL,
    s3_key TEXT NOT NULL DEFAULT '',
    file_size BIGINT NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ,
    error_message TEXT,
    UNIQUE(provider, track_id)
);
CREATE INDEX IF NOT EXISTS karaoke_cache_lookup_idx ON karaoke_cache(provider, track_id);

-- =====================================================================
-- Cross-provider track mappings (Smart Duplicates)
-- =====================================================================
CREATE TABLE IF NOT EXISTS track_mappings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    canonical_hash TEXT NOT NULL,
    canonical_artist TEXT NOT NULL,
    canonical_title TEXT NOT NULL,
    provider TEXT NOT NULL,
    track_id TEXT NOT NULL,
    bitrate_kbps INT NOT NULL DEFAULT 0,
    codec TEXT NOT NULL DEFAULT '',
    has_full_track BOOLEAN NOT NULL DEFAULT false,
    duration_seconds INT NOT NULL DEFAULT 0,
    confidence DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(provider, track_id)
);
CREATE INDEX IF NOT EXISTS track_mappings_canonical_idx ON track_mappings(canonical_hash);

CREATE TABLE IF NOT EXISTS user_track_source (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    canonical_hash TEXT NOT NULL,
    preferred_provider TEXT NOT NULL,
    preferred_track_id TEXT NOT NULL,
    reason TEXT NOT NULL DEFAULT 'manual',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, canonical_hash)
);

-- =====================================================================
-- Push notifications: device tokens + log
-- =====================================================================
CREATE TABLE IF NOT EXISTS device_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    platform TEXT NOT NULL CHECK (platform IN ('ios', 'android', 'web')),
    token TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, token)
);
CREATE INDEX IF NOT EXISTS device_tokens_user_idx ON device_tokens(user_id);

CREATE TABLE IF NOT EXISTS notifications_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind TEXT NOT NULL,
    title TEXT NOT NULL DEFAULT '',
    body TEXT NOT NULL DEFAULT '',
    payload JSONB NOT NULL DEFAULT '{}',
    sent_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS notifications_log_user_idx ON notifications_log(user_id, sent_at DESC);

-- =====================================================================
-- Track Availability Guard
-- =====================================================================
CREATE TABLE IF NOT EXISTS track_availability (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider TEXT NOT NULL,
    track_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'available',
    last_checked_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    replacement_provider TEXT,
    replacement_track_id TEXT,
    UNIQUE(provider, track_id)
);
CREATE INDEX IF NOT EXISTS track_availability_status_idx ON track_availability(status) WHERE status != 'available';
`
