package music

import (
	"context"
	"fmt"
	"log"
	"strings"
	"time"

)

// PlaybackTarget describes how ProxyStream should deliver audio bytes.
type PlaybackTarget struct {
	// Requested provider/id from the client (e.g. deezer catalog id).
	RequestedProvider string
	RequestedID       string
	// When set, ProxyStream proxies this provider/id (Spotify Connect, Deezer decrypt).
	ProxyProvider string
	ProxyID       string
	// Direct CDN/HLS/preview URL when ProxyProvider is empty.
	DirectURL string
}

// ResolvePlayback picks a playable source for /audio, including cross-provider fallback.
func (s *Service) ResolvePlayback(ctx context.Context, providerName, id string) (PlaybackTarget, error) {
	target := PlaybackTarget{RequestedProvider: providerName, RequestedID: id}

	p, ok := s.providers[providerName]
	if !ok {
		return target, fmt.Errorf("unknown provider: %s", providerName)
	}

	if url, err := s.GetTrackStreamURL(ctx, providerName, id); err == nil && url != "" {
		target.DirectURL = url
		// Encrypted Deezer / Spotify Connect must use provider-specific proxy handlers.
		if providerName == "deezer" && s.DeezerProvider() != nil && s.DeezerProvider().HasFullTrackSession() {
			target.ProxyProvider = "deezer"
			target.ProxyID = id
			target.DirectURL = ""
		} else if providerName == "spotify" {
			if sp := s.SpotifyProvider(); sp != nil && sp.HasFullTrackSession() {
				target.ProxyProvider = "spotify"
				target.ProxyID = id
				target.DirectURL = ""
			}
		}
		return target, nil
	}

	track, tErr := p.GetTrack(ctx, id)
	if tErr != nil || track == nil {
		return target, fmt.Errorf("track metadata: %w", tErr)
	}

	// 30s Deezer/Spotify previews — better than a hard 404 while fallback runs.
	if preview := strings.TrimSpace(track.PreviewURL); preview != "" {
		if err := ValidateResolvedStreamURL(preview); err == nil {
			log.Printf("[playback] %s/%s using preview_url", providerName, id)
			target.DirectURL = preview
			return target, nil
		}
	}

	query := strings.TrimSpace(track.Artist + " " + track.Title)
	if query == "" {
		return target, fmt.Errorf("empty artist/title for fallback")
	}

	log.Printf("[stream-fallback] provider=%s id=%s query=%q", providerName, id, query)

	// Spotify Connect first when configured (full tracks, no yt-dlp).
	if sp := s.SpotifyProvider(); sp != nil && sp.HasFullTrackSession() {
		if fbID := s.searchFirstTrackID(ctx, "spotify", query, 12*time.Second); fbID != "" {
			log.Printf("[stream-fallback] resolved %s/%s via=spotify/%s", providerName, id, fbID)
			target.ProxyProvider = "spotify"
			target.ProxyID = fbID
			return target, nil
		}
	}

	// SoundCloud before YouTube — lighter than yt-dlp on 512MB Render instances.
	for _, name := range []string{"soundcloud", "youtube"} {
		if name == providerName {
			continue
		}
		perProv, cancel := context.WithTimeout(ctx, 18*time.Second)
		fbID := s.searchFirstTrackID(perProv, name, query, 18*time.Second)
		cancel()
		if fbID == "" {
			continue
		}
		fp := s.providers[name]
		streamURL, err := fp.GetTrackStreamURL(ctx, fbID)
		if err == nil && streamURL != "" && ValidateResolvedStreamURL(streamURL) == nil {
			log.Printf("[stream-fallback] resolved %s/%s via=%s/%s", providerName, id, name, fbID)
			target.ProxyProvider = name
			target.ProxyID = fbID
			target.DirectURL = streamURL
			return target, nil
		}
		if name == "spotify" {
			continue
		}
	}

	return target, fmt.Errorf("no playable stream for %s/%s", providerName, id)
}

func (s *Service) searchFirstTrackID(ctx context.Context, name, query string, timeout time.Duration) string {
	fp, ok := s.providers[name]
	if !ok {
		return ""
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	sr, err := fp.Search(ctx, query, 3)
	if err != nil || sr == nil || len(sr.Tracks) == 0 {
		log.Printf("[stream-fallback] %s search miss for %q: %v", name, query, err)
		return ""
	}
	return sr.Tracks[0].ID
}
