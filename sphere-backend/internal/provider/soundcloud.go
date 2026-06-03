package provider

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"sphere-backend/internal/model"
)

type SoundCloud struct {
	clientID     string
	clientSecret string
	httpClient   *http.Client

	mu          sync.Mutex
	accessToken string
	tokenExpiry time.Time
}

func NewSoundCloud(clientID, clientSecret string) *SoundCloud {
	return &SoundCloud{
		clientID:     clientID,
		clientSecret: clientSecret,
		httpClient:   &http.Client{Timeout: 22 * time.Second},
	}
}

func (s *SoundCloud) Name() string { return "soundcloud" }

func (s *SoundCloud) ensureAccessToken(ctx context.Context) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.accessToken != "" && time.Now().Before(s.tokenExpiry.Add(-30*time.Second)) {
		return nil
	}
	if s.clientSecret == "" {
		return nil
	}
	form := url.Values{}
	form.Set("grant_type", "client_credentials")
	form.Set("client_id", s.clientID)
	form.Set("client_secret", s.clientSecret)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		"https://secure.soundcloud.com/oauth/token",
		strings.NewReader(form.Encode()))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return fmt.Errorf("soundcloud oauth %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	var tok struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&tok); err != nil {
		return err
	}
	if tok.AccessToken == "" {
		return fmt.Errorf("soundcloud oauth: empty token")
	}
	s.accessToken = tok.AccessToken
	if tok.ExpiresIn <= 0 {
		tok.ExpiresIn = 3600
	}
	s.tokenExpiry = time.Now().Add(time.Duration(tok.ExpiresIn) * time.Second)
	return nil
}

func (s *SoundCloud) apiGet(ctx context.Context, path string) (*http.Response, error) {
	if err := s.ensureAccessToken(ctx); err != nil {
		return nil, err
	}
	sep := "?"
	if len(path) > 0 && containsQuery(path) {
		sep = "&"
	}
	u := "https://api-v2.soundcloud.com" + path + sep + "client_id=" + url.QueryEscape(s.clientID)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/json")
	s.mu.Lock()
	tok := s.accessToken
	s.mu.Unlock()
	if tok != "" {
		req.Header.Set("Authorization", "OAuth "+tok)
	}
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode == http.StatusUnauthorized && s.clientSecret != "" {
		resp.Body.Close()
		s.mu.Lock()
		s.accessToken = ""
		s.mu.Unlock()
		if err := s.ensureAccessToken(ctx); err != nil {
			return nil, err
		}
		return s.apiGet(ctx, path)
	}
	return resp, nil
}

func containsQuery(path string) bool {
	for _, c := range path {
		if c == '?' {
			return true
		}
	}
	return false
}

func (s *SoundCloud) Search(ctx context.Context, query string, limit int) (*model.SearchResult, error) {
	if limit <= 0 {
		limit = 20
	}
	resp, err := s.apiGet(ctx, fmt.Sprintf("/search/tracks?q=%s&limit=%d", url.QueryEscape(query), limit))
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var wrapper struct {
		Collection []scTrack `json:"collection"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&wrapper); err != nil {
		return nil, err
	}

	result := &model.SearchResult{}
	for _, t := range wrapper.Collection {
		result.Tracks = append(result.Tracks, t.toTrack())
	}
	return result, nil
}

func (s *SoundCloud) GetTrack(ctx context.Context, id string) (*model.Track, error) {
	resp, err := s.apiGet(ctx, "/tracks/"+id)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var t scTrack
	if err := json.NewDecoder(resp.Body).Decode(&t); err != nil {
		return nil, err
	}
	track := t.toTrack()
	return &track, nil
}

func (s *SoundCloud) GetTrackStreamURL(ctx context.Context, id string) (string, error) {
	t, err := s.GetTrack(ctx, id)
	if err != nil {
		return "", err
	}
	if t.StreamURL == "" {
		return "", fmt.Errorf("no stream available")
	}
	sep := "?"
	if containsQuery(t.StreamURL) {
		sep = "&"
	}
	resolveURL := t.StreamURL + sep + "client_id=" + url.QueryEscape(s.clientID)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, resolveURL, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("Accept", "application/json")
	s.mu.Lock()
	if tok := s.accessToken; tok != "" {
		req.Header.Set("Authorization", "OAuth "+tok)
	}
	s.mu.Unlock()
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("resolve stream: %w", err)
	}
	defer resp.Body.Close()
	var result struct {
		URL string `json:"url"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", fmt.Errorf("decode stream url: %w", err)
	}
	if result.URL == "" {
		return "", fmt.Errorf("empty resolved stream url")
	}
	return result.URL, nil
}

func (s *SoundCloud) GetLyrics(_ context.Context, _ string) (*model.Lyrics, error) {
	return nil, fmt.Errorf("lyrics not available via SoundCloud API")
}

func (s *SoundCloud) GetArtist(ctx context.Context, id string) (*model.Artist, error) {
	resp, err := s.apiGet(ctx, "/users/"+id)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var u scUser
	if err := json.NewDecoder(resp.Body).Decode(&u); err != nil {
		return nil, err
	}
	avatarURL := soundCloudArtworkURL(u.AvatarURL)
	artist := model.Artist{ID: fmt.Sprint(u.ID), Provider: "soundcloud", Name: u.Username, ImageURL: avatarURL}

	tracksResp, err := s.apiGet(ctx, fmt.Sprintf("/users/%s/tracks?limit=10", id))
	if err == nil {
		defer tracksResp.Body.Close()
		var tracks []scTrack
		if json.NewDecoder(tracksResp.Body).Decode(&tracks) == nil {
			for _, t := range tracks {
				artist.Tracks = append(artist.Tracks, t.toTrack())
			}
		}
	}
	return &artist, nil
}

func (s *SoundCloud) GetAlbum(ctx context.Context, id string) (*model.Album, error) {
	resp, err := s.apiGet(ctx, "/playlists/"+id)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var p scPlaylist
	if err := json.NewDecoder(resp.Body).Decode(&p); err != nil {
		return nil, err
	}
	cover := soundCloudArtworkURL(p.ArtworkURL)
	if cover == "" && len(p.Tracks) > 0 {
		cover = p.Tracks[0].toTrack().CoverURL
	}
	album := model.Album{ID: fmt.Sprint(p.ID), Provider: "soundcloud", Title: p.Title, CoverURL: cover}
	for _, t := range p.Tracks {
		album.Tracks = append(album.Tracks, t.toTrack())
	}
	return &album, nil
}

func (s *SoundCloud) GetPlaylist(ctx context.Context, id string) (*model.Playlist, error) {
	resp, err := s.apiGet(ctx, "/playlists/"+id)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var p scPlaylist
	if err := json.NewDecoder(resp.Body).Decode(&p); err != nil {
		return nil, err
	}
	cover := soundCloudArtworkURL(p.ArtworkURL)
	if cover == "" && len(p.Tracks) > 0 {
		cover = p.Tracks[0].toTrack().CoverURL
	}
	playlist := model.Playlist{ID: fmt.Sprint(p.ID), Provider: "soundcloud", Title: p.Title, CoverURL: cover}
	for _, t := range p.Tracks {
		playlist.Tracks = append(playlist.Tracks, t.toTrack())
	}
	return &playlist, nil
}

type scTrack struct {
	ID         int    `json:"id"`
	Title      string `json:"title"`
	User       scUser `json:"user"`
	ArtworkURL string `json:"artwork_url"`
	Duration   int    `json:"duration"`
	Media      struct {
		Transcodings []struct {
			URL    string `json:"url"`
			Preset string `json:"preset"`
			Format struct {
				Protocol string `json:"protocol"`
				MimeType string `json:"mime_type"`
			} `json:"format"`
		} `json:"transcodings"`
	} `json:"media"`
}

func (t scTrack) toTrack() model.Track {
	streamURL := ""
	for _, tc := range t.Media.Transcodings {
		if tc.Format.Protocol == "progressive" {
			streamURL = tc.URL
			break
		}
	}
	if streamURL == "" && len(t.Media.Transcodings) > 0 {
		streamURL = t.Media.Transcodings[0].URL
	}
	// Do not fall back to uploader avatar — many tracks would share one image.
	cover := soundCloudArtworkURL(t.ArtworkURL)
	// StreamURL in API payloads must be a resolved CDN URL from GetTrackStreamURL.
	// The transcoding resolver endpoint is not playable by AVPlayer.
	_ = streamURL
	return model.Track{
		ID: fmt.Sprint(t.ID), Provider: "soundcloud", Title: t.Title,
		Artist: t.User.Username, CoverURL: cover,
		Duration: t.Duration / 1000,
	}
}

func soundCloudArtworkURL(raw string) string {
	if raw == "" {
		return ""
	}
	return strings.Replace(raw, "-large", "-t500x500", 1)
}

type scUser struct {
	ID        int    `json:"id"`
	Username  string `json:"username"`
	AvatarURL string `json:"avatar_url"`
}

type scPlaylist struct {
	ID         int       `json:"id"`
	Title      string    `json:"title"`
	ArtworkURL string    `json:"artwork_url"`
	Tracks     []scTrack `json:"tracks"`
}
