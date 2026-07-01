package provider

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"sphere-backend/internal/model"
)

type VKMusic struct {
	token      string
	httpClient *http.Client
}

func NewVKMusic(token string) *VKMusic {
	return &VKMusic{
		token:      token,
		httpClient: &http.Client{Timeout: 15 * time.Second},
	}
}

func (v *VKMusic) Name() string { return "vk" }

type vkAPIError struct {
	Code    int    `json:"error_code"`
	Message string `json:"error_msg"`
}

func (v *VKMusic) apiGet(ctx context.Context, method string, params url.Values) (*http.Response, error) {
	params.Set("access_token", v.token)
	params.Set("v", "5.199")
	u := "https://api.vk.com/method/" + method + "?" + params.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	return v.httpClient.Do(req)
}

func (v *VKMusic) decodeAPI(resp *http.Response, dest any) error {
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 2<<20))
	if err != nil {
		return err
	}
	var envelope struct {
		Error *vkAPIError `json:"error"`
	}
	if err := json.Unmarshal(body, &envelope); err == nil && envelope.Error != nil {
		return fmt.Errorf("vk api: %s (code %d)", envelope.Error.Message, envelope.Error.Code)
	}
	if dest == nil {
		return nil
	}
	return json.Unmarshal(body, dest)
}

func (v *VKMusic) Search(ctx context.Context, query string, limit int) (*model.SearchResult, error) {
	if limit <= 0 {
		limit = 20
	}
	params := url.Values{"q": {query}, "count": {fmt.Sprint(limit)}}
	resp, err := v.apiGet(ctx, "audio.search", params)
	if err != nil {
		return nil, err
	}

	var vkResp struct {
		Response struct {
			Items []vkAudio `json:"items"`
		} `json:"response"`
	}
	if err := v.decodeAPI(resp, &vkResp); err != nil {
		return nil, err
	}

	result := &model.SearchResult{}
	for _, a := range vkResp.Response.Items {
		result.Tracks = append(result.Tracks, a.toTrack())
	}
	return result, nil
}

func (v *VKMusic) GetTrack(ctx context.Context, id string) (*model.Track, error) {
	params := url.Values{"audios": {id}}
	resp, err := v.apiGet(ctx, "audio.getById", params)
	if err != nil {
		return nil, err
	}

	var vkResp struct {
		Response []vkAudio `json:"response"`
	}
	if err := v.decodeAPI(resp, &vkResp); err != nil {
		return nil, err
	}
	if len(vkResp.Response) == 0 {
		return nil, fmt.Errorf("track not found")
	}
	track := vkResp.Response[0].toTrack()
	if track.StreamURL == "" {
		return nil, fmt.Errorf("vk: no stream url (use VK_ACCESS_TOKEN with audio scope, not a service token)")
	}
	return &track, nil
}

func (v *VKMusic) GetTrackStreamURL(ctx context.Context, id string) (string, error) {
	t, err := v.GetTrack(ctx, id)
	if err != nil {
		return "", err
	}
	return t.StreamURL, nil
}

func (v *VKMusic) GetLyrics(ctx context.Context, id string) (*model.Lyrics, error) {
	params := url.Values{"audio_id": {id}}
	resp, err := v.apiGet(ctx, "audio.getLyrics", params)
	if err != nil {
		return nil, err
	}

	var vkResp struct {
		Response struct {
			Lyrics string `json:"lyrics"`
			Text   string `json:"text"`
		} `json:"response"`
	}
	if err := v.decodeAPI(resp, &vkResp); err != nil {
		return nil, err
	}
	text := vkResp.Response.Lyrics
	if text == "" {
		text = vkResp.Response.Text
	}
	return &model.Lyrics{TrackID: id, Provider: "vk", Text: text}, nil
}

func (v *VKMusic) GetArtist(ctx context.Context, id string) (*model.Artist, error) {
	params := url.Values{"artist_id": {id}}
	resp, err := v.apiGet(ctx, "audio.getArtistById", params)
	if err != nil {
		return nil, err
	}

	var vkResp struct {
		Response struct {
			Name  string `json:"name"`
			Photo []struct {
				URL string `json:"url"`
			} `json:"photo"`
		} `json:"response"`
	}
	if err := v.decodeAPI(resp, &vkResp); err != nil {
		return nil, err
	}
	img := ""
	if len(vkResp.Response.Photo) > 0 {
		img = vkResp.Response.Photo[len(vkResp.Response.Photo)-1].URL
	}
	return &model.Artist{ID: id, Provider: "vk", Name: vkResp.Response.Name, ImageURL: img}, nil
}

func (v *VKMusic) GetAlbum(ctx context.Context, id string) (*model.Album, error) {
	ownerID, albumID, err := vkParsePlaylistID(id)
	if err != nil {
		return nil, err
	}
	params := url.Values{
		"owner_id": {ownerID},
		"album_id": {albumID},
		"count":    {"200"},
	}
	resp, err := v.apiGet(ctx, "audio.get", params)
	if err != nil {
		return nil, err
	}

	var vkResp struct {
		Response struct {
			Items []vkAudio `json:"items"`
		} `json:"response"`
	}
	if err := v.decodeAPI(resp, &vkResp); err != nil {
		return nil, err
	}
	album := &model.Album{ID: id, Provider: "vk"}
	for _, a := range vkResp.Response.Items {
		album.Tracks = append(album.Tracks, a.toTrack())
	}
	return album, nil
}

func (v *VKMusic) GetPlaylist(ctx context.Context, id string) (*model.Playlist, error) {
	ownerID, playlistID, err := vkParsePlaylistID(id)
	if err != nil {
		return nil, err
	}
	params := url.Values{
		"owner_id":    {ownerID},
		"playlist_id": {playlistID},
		"count":       {"200"},
	}
	resp, err := v.apiGet(ctx, "audio.get", params)
	if err != nil {
		return nil, err
	}

	var vkResp struct {
		Response struct {
			Items []vkAudio `json:"items"`
			Title string    `json:"title"`
		} `json:"response"`
	}
	if err := v.decodeAPI(resp, &vkResp); err != nil {
		return nil, err
	}
	title := vkResp.Response.Title
	if title == "" {
		title = "VK Playlist"
	}
	pl := &model.Playlist{
		ID: id, Provider: "vk", Title: title,
	}
	for _, a := range vkResp.Response.Items {
		pl.Tracks = append(pl.Tracks, a.toTrack())
	}
	return pl, nil
}

// vkParsePlaylistID accepts "owner_playlist" or "owner:playlist".
func vkParsePlaylistID(id string) (ownerID, playlistID string, err error) {
	id = strings.TrimSpace(id)
	for _, sep := range []string{"_", ":"} {
		if i := strings.Index(id, sep); i > 0 {
			return id[:i], id[i+1:], nil
		}
	}
	return "", "", fmt.Errorf("vk playlist id must be owner_playlist or owner:playlist, got %q", id)
}

type vkAudio struct {
	ID       int    `json:"id"`
	OwnerID  int    `json:"owner_id"`
	Title    string `json:"title"`
	Artist   string `json:"artist"`
	Duration int    `json:"duration"`
	URL      string `json:"url"`
	AlbumID  int    `json:"album_id"`
}

func (a vkAudio) toTrack() model.Track {
	stream := strings.TrimSpace(a.URL)
	return model.Track{
		ID:        fmt.Sprintf("%d_%d", a.OwnerID, a.ID),
		Provider:  "vk",
		Title:     a.Title,
		Artist:    a.Artist,
		Duration:  a.Duration,
		StreamURL: stream,
	}
}
