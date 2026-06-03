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
	RequestedProvider string
	RequestedID       string
	ProxyProvider     string
	ProxyID           string
	DirectURL         string
}

// directProviderStreamURL asks the catalog provider only — no cross-provider fallback.
func (s *Service) directProviderStreamURL(ctx context.Context, providerName, id string) (string, error) {
	p, ok := s.providers[providerName]
	if !ok {
		return "", fmt.Errorf("unknown provider: %s", providerName)
	}
	resolved, err := p.GetTrackStreamURL(ctx, id)
	if err != nil || resolved == "" {
		return "", err
	}
	if vErr := ValidateResolvedStreamURL(resolved); vErr != nil {
		return "", vErr
	}
	return resolved, nil
}

// ResolvePlayback picks a playable source for /audio, including cross-provider fallback.
func (s *Service) ResolvePlayback(ctx context.Context, providerName, id string) (PlaybackTarget, error) {
	target := PlaybackTarget{RequestedProvider: providerName, RequestedID: id}

	p, ok := s.providers[providerName]
	if !ok {
		return target, fmt.Errorf("unknown provider: %s", providerName)
	}

	// Never call GetTrackStreamURL here — it runs a slow YouTube-first fallback and starves Spotify.
	if url, err := s.directProviderStreamURL(ctx, providerName, id); err == nil {
		target.DirectURL = url
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
		log.Printf("[playback] %s/%s direct stream", providerName, id)
		return target, nil
	}

	track, tErr := p.GetTrack(ctx, id)
	if tErr != nil || track == nil {
		return target, fmt.Errorf("track metadata: %w", tErr)
	}

	if preview := strings.TrimSpace(track.PreviewURL); preview != "" {
		if err := ValidateResolvedStreamURL(preview); err == nil {
			log.Printf("[playback] %s/%s preview_url", providerName, id)
			target.DirectURL = preview
			return target, nil
		}
	}

	query := strings.TrimSpace(track.Artist + " " + track.Title)
	if query == "" {
		return target, fmt.Errorf("empty artist/title for fallback")
	}

	log.Printf("[playback] fallback %s/%s query=%q", providerName, id, query)

	if sp := s.SpotifyProvider(); sp != nil && sp.HasFullTrackSession() {
		spCtx, cancel := context.WithTimeout(ctx, 20*time.Second)
		fbID := s.searchFirstTrackID(spCtx, "spotify", query)
		cancel()
		if fbID != "" {
			log.Printf("[playback] %s/%s → spotify/%s (connect proxy)", providerName, id, fbID)
			target.ProxyProvider = "spotify"
			target.ProxyID = fbID
			return target, nil
		}
		log.Printf("[playback] spotify search empty for %q (blob configured but no match)", query)
	} else {
		log.Printf("[playback] spotify connect not configured — skipping spotify fallback")
	}

	for _, name := range []string{"soundcloud", "youtube"} {
		if name == providerName {
			continue
		}
		perCtx, cancel := context.WithTimeout(ctx, 20*time.Second)
		fbID := s.searchFirstTrackID(perCtx, name, query)
		cancel()
		if fbID == "" {
			continue
		}
		fp := s.providers[name]
		streamURL, err := fp.GetTrackStreamURL(ctx, fbID)
		if err == nil && streamURL != "" && ValidateResolvedStreamURL(streamURL) == nil {
			log.Printf("[playback] %s/%s → %s/%s", providerName, id, name, fbID)
			target.ProxyProvider = name
			target.ProxyID = fbID
			target.DirectURL = streamURL
			return target, nil
		}
	}

	return target, fmt.Errorf("no playable stream for %s/%s", providerName, id)
}

func (s *Service) searchFirstTrackID(ctx context.Context, name, query string) string {
	fp, ok := s.providers[name]
	if !ok {
		return ""
	}
	sr, err := fp.Search(ctx, query, 3)
	if err != nil || sr == nil || len(sr.Tracks) == 0 {
		log.Printf("[playback] %s search miss %q: %v", name, query, err)
		return ""
	}
	return sr.Tracks[0].ID
}

// crossProviderStreamFallback is used by GET /stream (legacy) — Spotify before YouTube.
func (s *Service) crossProviderStreamFallback(ctx context.Context, providerName, id string, query string, primaryErr error) (string, error) {
	target, err := s.ResolvePlayback(ctx, providerName, id)
	if err != nil {
		return "", primaryErr
	}
	if target.DirectURL != "" {
		return target.DirectURL, nil
	}
	if target.ProxyProvider == "spotify" && target.ProxyID != "" {
		if sp := s.SpotifyProvider(); sp != nil {
			if t, e := sp.GetTrack(ctx, target.ProxyID); e == nil && t != nil && t.PreviewURL != "" {
				return t.PreviewURL, nil
			}
		}
	}
	return "", fmt.Errorf("playback requires /audio proxy for %s/%s", target.ProxyProvider, target.ProxyID)
}
