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

type Yandex struct {
	token      string
	signKey    string
	httpClient *http.Client
}

func NewYandex(token string) *Yandex {
	return NewYandexWithOptions(token, "", "")
}

// NewYandexWithOptions configures OAuth token, optional HMAC sign key override,
// and optional HTTP proxy URL (helps when api.music.yandex.net geoblocks the host).
func NewYandexWithOptions(token, signKey, proxyURL string) *Yandex {
	transport := http.DefaultTransport.(*http.Transport).Clone()
	if proxyURL != "" {
		if u, err := url.Parse(proxyURL); err == nil {
			transport.Proxy = http.ProxyURL(u)
		}
	}
	return &Yandex{
		token:   token,
		signKey: signKey,
		httpClient: &http.Client{
			Timeout:   20 * time.Second,
			Transport: transport,
		},
	}
}

func (y *Yandex) Name() string { return "yandex" }

func yandexImageURL(coverURI string) string {
	u := strings.TrimSpace(coverURI)
	if u == "" {
		return ""
	}
	if strings.HasPrefix(u, "https://") || strings.HasPrefix(u, "http://") {
		return u
	}
	if strings.HasPrefix(u, "//") {
		return "https:" + u
	}
	return "https://" + u
}

func (y *Yandex) apiRequest(ctx context.Context, method, path string, query url.Values) (*http.Response, error) {
	u := "https://api.music.yandex.net" + path
	if len(query) > 0 {
		u += "?" + query.Encode()
	}
	req, err := http.NewRequestWithContext(ctx, method, u, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "OAuth "+y.token)
	req.Header.Set("X-Yandex-Music-Client", yandexClientHeader)
	req.Header.Set("Accept", "application/json")
	return y.httpClient.Do(req)
}

func (y *Yandex) apiGet(ctx context.Context, path string) (*http.Response, error) {
	return y.apiRequest(ctx, http.MethodGet, path, nil)
}

func (y *Yandex) decodeAPI(resp *http.Response, dest any) error {
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 2<<20))
	if err != nil {
		return err
	}
	if resp.StatusCode == http.StatusUnavailableForLegalReasons {
		return fmt.Errorf("yandex music unavailable from this region (HTTP 451); set YANDEX_HTTP_PROXY to a RU egress")
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("yandex api %s: HTTP %d: %s", resp.Request.URL.Path, resp.StatusCode, strings.TrimSpace(string(body)))
	}
	if dest == nil {
		return nil
	}
	return json.Unmarshal(body, dest)
}

func (y *Yandex) Search(ctx context.Context, query string, limit int) (*model.SearchResult, error) {
	if limit <= 0 {
		limit = 20
	}
	resp, err := y.apiGet(ctx, fmt.Sprintf("/search?text=%s&type=all&page=0&pageSize=%d", url.QueryEscape(query), limit))
	if err != nil {
		return nil, err
	}

	var yaResp struct {
		Result struct {
			Tracks struct {
				Results []yaTrack `json:"results"`
			} `json:"tracks"`
			Artists struct {
				Results []yaArtist `json:"results"`
			} `json:"artists"`
			Albums struct {
				Results []yaAlbum `json:"results"`
			} `json:"albums"`
			Playlists struct {
				Results []yaPlaylist `json:"results"`
			} `json:"playlists"`
		} `json:"result"`
	}
	if err := y.decodeAPI(resp, &yaResp); err != nil {
		return nil, err
	}

	result := &model.SearchResult{}
	for _, t := range yaResp.Result.Tracks.Results {
		result.Tracks = append(result.Tracks, t.toTrack())
	}
	for _, a := range yaResp.Result.Artists.Results {
		result.Artists = append(result.Artists, a.toArtist())
	}
	for _, a := range yaResp.Result.Albums.Results {
		result.Albums = append(result.Albums, a.toAlbum())
	}
	for _, p := range yaResp.Result.Playlists.Results {
		result.Playlists = append(result.Playlists, p.toPlaylist())
	}
	return result, nil
}

func (y *Yandex) GetTrack(ctx context.Context, id string) (*model.Track, error) {
	resp, err := y.apiGet(ctx, "/tracks/"+url.PathEscape(id))
	if err != nil {
		return nil, err
	}

	var yaResp struct {
		Result []yaTrack `json:"result"`
	}
	if err := y.decodeAPI(resp, &yaResp); err != nil {
		return nil, err
	}
	if len(yaResp.Result) == 0 {
		return nil, fmt.Errorf("track not found")
	}
	track := yaResp.Result[0].toTrack()
	return &track, nil
}

func (y *Yandex) GetTrackStreamURL(ctx context.Context, id string) (string, error) {
	if u, err := y.getFileInfoStreamURL(ctx, id); err == nil && u != "" {
		return u, nil
	}
	return y.getDownloadInfoStreamURL(ctx, id)
}

// getFileInfoStreamURL uses the signed /get-file-info endpoint (newer Android/Web flow).
func (y *Yandex) getFileInfoStreamURL(ctx context.Context, id string) (string, error) {
	sign := yandexSignRequest(id, y.signKey)
	q := url.Values{
		"ts":         {fmt.Sprint(sign.Timestamp)},
		"trackId":    {yandexNumericTrackID(id)},
		"quality":    {"hq"},
		"codecs":     {"mp3,aac,he-aac"},
		"transports": {"raw"},
		"sign":       {sign.Value},
	}
	resp, err := y.apiRequest(ctx, http.MethodGet, "/get-file-info", q)
	if err != nil {
		return "", err
	}
	var payload yandexFileInfoResponse
	if err := y.decodeAPI(resp, &payload); err != nil {
		return "", err
	}
	if u := yandexFirstFileInfoURL(&payload); u != "" {
		return u, nil
	}
	return "", fmt.Errorf("get-file-info: no urls")
}

// getDownloadInfoStreamURL uses /tracks/{id}/download-info (HLS direct or XML → get-mp3).
func (y *Yandex) getDownloadInfoStreamURL(ctx context.Context, id string) (string, error) {
	sign := yandexSignRequest(id, y.signKey)
	q := url.Values{
		"can_use_streaming": {"true"},
		"ts":                {fmt.Sprint(sign.Timestamp)},
		"sign":              {sign.Value},
	}
	resp, err := y.apiRequest(ctx, http.MethodGet, "/tracks/"+url.PathEscape(id)+"/download-info", q)
	if err != nil {
		return "", err
	}

	var yaResp struct {
		Result []yandexDownloadEntry `json:"result"`
	}
	if err := y.decodeAPI(resp, &yaResp); err != nil {
		return "", err
	}
	entry := yandexPickDownloadEntry(yaResp.Result)
	if entry == nil {
		return "", fmt.Errorf("no download info for track %s", id)
	}

	// Newer tracks expose a direct HLS/MP4 URL in downloadInfoUrl.
	if entry.Direct && entry.DownloadInfoURL != "" {
		return entry.DownloadInfoURL, nil
	}

	return yandexResolveDownloadInfoURL(y.httpClient, entry.DownloadInfoURL)
}

func (y *Yandex) GetLyrics(ctx context.Context, id string) (*model.Lyrics, error) {
	resp, err := y.apiGet(ctx, "/tracks/"+url.PathEscape(id)+"/lyrics")
	if err != nil {
		return nil, err
	}

	var yaResp struct {
		Result struct {
			FullLyrics string `json:"fullLyrics"`
		} `json:"result"`
	}
	if err := y.decodeAPI(resp, &yaResp); err != nil {
		return nil, err
	}
	return &model.Lyrics{TrackID: id, Provider: "yandex", Text: yaResp.Result.FullLyrics}, nil
}

func (y *Yandex) GetArtist(ctx context.Context, id string) (*model.Artist, error) {
	resp, err := y.apiGet(ctx, "/artists/"+url.PathEscape(id)+"/brief-info")
	if err != nil {
		return nil, err
	}

	var yaResp struct {
		Result struct {
			Artist yaArtist  `json:"artist"`
			Tracks []yaTrack `json:"popularTracks"`
		} `json:"result"`
	}
	if err := y.decodeAPI(resp, &yaResp); err != nil {
		return nil, err
	}
	artist := yaResp.Result.Artist.toArtist()
	for _, t := range yaResp.Result.Tracks {
		artist.Tracks = append(artist.Tracks, t.toTrack())
	}
	return &artist, nil
}

func (y *Yandex) GetAlbum(ctx context.Context, id string) (*model.Album, error) {
	resp, err := y.apiGet(ctx, "/albums/"+url.PathEscape(id)+"/with-tracks")
	if err != nil {
		return nil, err
	}

	var yaResp struct {
		Result struct {
			yaAlbum
			Volumes [][]yaTrack `json:"volumes"`
		} `json:"result"`
	}
	if err := y.decodeAPI(resp, &yaResp); err != nil {
		return nil, err
	}
	album := yaResp.Result.yaAlbum.toAlbum()
	for _, vol := range yaResp.Result.Volumes {
		for _, t := range vol {
			album.Tracks = append(album.Tracks, t.toTrack())
		}
	}
	return &album, nil
}

func (y *Yandex) GetPlaylist(ctx context.Context, id string) (*model.Playlist, error) {
	resp, err := y.apiGet(ctx, "/playlists/"+url.PathEscape(id))
	if err != nil {
		return nil, err
	}

	var yaResp struct {
		Result struct {
			yaPlaylist
			Tracks []struct {
				Track yaTrack `json:"track"`
			} `json:"tracks"`
		} `json:"result"`
	}
	if err := y.decodeAPI(resp, &yaResp); err != nil {
		return nil, err
	}
	playlist := yaResp.Result.yaPlaylist.toPlaylist()
	for _, item := range yaResp.Result.Tracks {
		if item.Track.ID != "" {
			playlist.Tracks = append(playlist.Tracks, item.Track.toTrack())
		}
	}
	return &playlist, nil
}

type yaTrack struct {
	ID       string     `json:"id"`
	Title    string     `json:"title"`
	Artists  []yaArtist `json:"artists"`
	Albums   []yaAlbum  `json:"albums"`
	Duration int        `json:"durationMs"`
	CoverURI string     `json:"coverUri"`
}

func (t yaTrack) toTrack() model.Track {
	artist := ""
	if len(t.Artists) > 0 {
		artist = t.Artists[0].Name
	}
	albumName := ""
	if len(t.Albums) > 0 {
		albumName = t.Albums[0].Title
	}
	cover := yandexImageURL(t.CoverURI)
	return model.Track{
		ID: t.ID, Provider: "yandex", Title: t.Title, Artist: artist,
		Album: albumName, CoverURL: cover, Duration: t.Duration / 1000,
	}
}

type yaArtist struct {
	ID    int    `json:"id"`
	Name  string `json:"name"`
	Cover struct {
		URI string `json:"uri"`
	} `json:"cover"`
}

func (a yaArtist) toArtist() model.Artist {
	img := yandexImageURL(a.Cover.URI)
	return model.Artist{ID: fmt.Sprint(a.ID), Provider: "yandex", Name: a.Name, ImageURL: img}
}

type yaAlbum struct {
	ID       int        `json:"id"`
	Title    string     `json:"title"`
	CoverURI string     `json:"coverUri"`
	Artists  []yaArtist `json:"artists"`
}

func (a yaAlbum) toAlbum() model.Album {
	cover := yandexImageURL(a.CoverURI)
	artist := ""
	if len(a.Artists) > 0 {
		artist = a.Artists[0].Name
	}
	return model.Album{ID: fmt.Sprint(a.ID), Provider: "yandex", Title: a.Title, Artist: artist, CoverURL: cover}
}

type yaPlaylist struct {
	UID      int    `json:"uid"`
	Kind     int    `json:"kind"`
	Title    string `json:"title"`
	CoverURI string `json:"ogImage"`
}

func (p yaPlaylist) toPlaylist() model.Playlist {
	cover := yandexImageURL(p.CoverURI)
	return model.Playlist{
		ID:       fmt.Sprintf("%d:%d", p.UID, p.Kind),
		Provider: "yandex", Title: p.Title, CoverURL: cover,
	}
}
