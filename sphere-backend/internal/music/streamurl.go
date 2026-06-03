package music

import (
	"context"
	"fmt"
	"net/http"
	"net/url"
	"strings"
)

// IsProviderStreamEndpoint reports URLs that return JSON/metadata, not audio bytes.
func IsProviderStreamEndpoint(raw string) bool {
	s := strings.ToLower(strings.TrimSpace(raw))
	if s == "" {
		return true
	}
	if strings.Contains(s, "api.soundcloud.com") {
		return true
	}
	if strings.Contains(s, "/transcodings/") {
		return true
	}
	if strings.Contains(s, "soundcloud.com/transcoding") {
		return true
	}
	return false
}

// ValidateResolvedStreamURL ensures a resolved stream URL is safe to hand to AVPlayer or proxyUpstream.
func ValidateResolvedStreamURL(raw string) error {
	s := strings.TrimSpace(raw)
	if s == "" {
		return fmt.Errorf("empty stream url")
	}
	u, err := url.Parse(s)
	if err != nil {
		return fmt.Errorf("invalid stream url: %w", err)
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return fmt.Errorf("unsupported scheme %q", u.Scheme)
	}
	if IsProviderStreamEndpoint(s) {
		return fmt.Errorf("provider stream endpoint is not playable audio")
	}
	return nil
}

// UpstreamRequestForStream builds an HTTP request to fetch audio bytes from a CDN URL.
func UpstreamRequestForStream(ctx context.Context, streamURL string, clientRange string) (*http.Request, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, streamURL, nil)
	if err != nil {
		return nil, err
	}
	if clientRange != "" {
		req.Header.Set("Range", clientRange)
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")
	req.Header.Set("Accept", "*/*")

	lower := strings.ToLower(streamURL)
	switch {
	case strings.Contains(lower, "googlevideo.com") || strings.Contains(lower, "youtube.com"):
		req.Header.Set("Referer", "https://www.youtube.com/")
		req.Header.Set("Origin", "https://www.youtube.com")
	case strings.Contains(lower, "sndcdn.com") || strings.Contains(lower, "soundcloud.com"):
		req.Header.Set("Referer", "https://soundcloud.com/")
	case strings.Contains(lower, "scdn.co") || strings.Contains(lower, "spotifycdn.com") || strings.Contains(lower, "p.scdn.co"):
		req.Header.Set("Referer", "https://open.spotify.com/")
	case strings.Contains(lower, "deezer.com"):
		req.Header.Set("Referer", "https://www.deezer.com/")
	}
	return req, nil
}
