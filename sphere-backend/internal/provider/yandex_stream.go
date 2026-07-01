package provider

import (
	"crypto/hmac"
	"crypto/md5"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// Reversed from Yandex Music Android client (MarshalX/yandex-music-api).
const yandexDefaultSignKey = "p93jhgh689SBReK6ghtw62"
const yandexXMLSignSalt = "XGRlBW9FXlekgbPrRHuSiA"

// yandexClientHeader mimics the official app so download-info signing is accepted.
const yandexClientHeader = "YandexMusicAndroid/24022571"

type yandexSign struct {
	Timestamp int64
	Value     string
}

func yandexSignRequest(trackID string, signKey string) yandexSign {
	if signKey == "" {
		signKey = yandexDefaultSignKey
	}
	numericID := yandexNumericTrackID(trackID)
	ts := time.Now().Unix()
	msg := fmt.Sprintf("%s%d", numericID, ts)
	mac := hmac.New(sha256.New, []byte(signKey))
	_, _ = mac.Write([]byte(msg))
	return yandexSign{
		Timestamp: ts,
		Value:     base64.StdEncoding.EncodeToString(mac.Sum(nil)),
	}
}

// yandexNumericTrackID strips non-digits (e.g. "track:123" → "123").
func yandexNumericTrackID(trackID string) string {
	var b strings.Builder
	for _, r := range trackID {
		if r >= '0' && r <= '9' {
			b.WriteRune(r)
		}
	}
	if b.Len() == 0 {
		return trackID
	}
	return b.String()
}

type yandexDownloadXML struct {
	Host string `xml:"host"`
	Path string `xml:"path"`
	TS   string `xml:"ts"`
	S    string `xml:"s"`
}

func yandexResolveDownloadInfoURL(client *http.Client, downloadInfoURL string) (string, error) {
	fetchURL := downloadInfoURL
	if !strings.Contains(fetchURL, "format=") {
		sep := "?"
		if strings.Contains(fetchURL, "?") {
			sep = "&"
		}
		fetchURL += sep + "format=json"
	}
	req, err := http.NewRequest(http.MethodGet, fetchURL, nil)
	if err != nil {
		return "", err
	}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return "", fmt.Errorf("download-info fetch: HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 64*1024))
	if err != nil {
		return "", err
	}
	trim := strings.TrimSpace(string(raw))
	if strings.HasPrefix(trim, "{") {
		var info yandexDownloadXML
		if err := json.Unmarshal(raw, &info); err == nil && info.Host != "" {
			return yandexBuildMP3URLFromFields(info.Host, info.Path, info.TS, info.S)
		}
	}
	return yandexBuildMP3URLFromXML(raw)
}

func yandexBuildMP3URLFromFields(host, path, ts, s string) (string, error) {
	if host == "" || path == "" || ts == "" || s == "" {
		return "", fmt.Errorf("download-info json: missing host/path/ts/s")
	}
	pathForSign := path
	if len(pathForSign) > 0 && pathForSign[0] == '/' {
		pathForSign = pathForSign[1:]
	}
	h := md5.Sum([]byte(yandexXMLSignSalt + pathForSign + s))
	sign := hex.EncodeToString(h[:])
	return fmt.Sprintf("https://%s/get-mp3/%s/%s%s", host, sign, ts, path), nil
}

func yandexBuildMP3URLFromXML(raw []byte) (string, error) {
	var doc yandexDownloadXML
	if err := xml.Unmarshal(raw, &doc); err != nil {
		return "", fmt.Errorf("parse download-info xml: %w", err)
	}
	return yandexBuildMP3URLFromFields(doc.Host, doc.Path, doc.TS, doc.S)
}

type yandexDownloadEntry struct {
	Codec           string `json:"codec"`
	Bitrate         int    `json:"bitrateInKbps"`
	DownloadInfoURL string `json:"downloadInfoUrl"`
	Direct          bool   `json:"direct"`
	Preview         bool   `json:"preview"`
}

func yandexPickDownloadEntry(entries []yandexDownloadEntry) *yandexDownloadEntry {
	var best *yandexDownloadEntry
	for i := range entries {
		e := &entries[i]
		if e.Preview || e.DownloadInfoURL == "" {
			continue
		}
		if best == nil || e.Bitrate > best.Bitrate {
			best = e
		}
	}
	if best != nil {
		return best
	}
	if len(entries) > 0 && entries[0].DownloadInfoURL != "" {
		return &entries[0]
	}
	return nil
}

type yandexFileInfoResponse struct {
	Result struct {
		DownloadInfo struct {
			URL  string   `json:"url"`
			URLs []string `json:"urls"`
		} `json:"downloadInfo"`
		DownloadInfoSnake struct {
			URL  string   `json:"url"`
			URLs []string `json:"urls"`
		} `json:"download_info"`
	} `json:"result"`
	DownloadInfo struct {
		URL  string   `json:"url"`
		URLs []string `json:"urls"`
	} `json:"download_info"`
}

func yandexFirstFileInfoURL(resp *yandexFileInfoResponse) string {
	if u := resp.Result.DownloadInfo.URL; u != "" {
		return u
	}
	if u := resp.Result.DownloadInfoSnake.URL; u != "" {
		return u
	}
	if u := resp.DownloadInfo.URL; u != "" {
		return u
	}
	urls := resp.Result.DownloadInfo.URLs
	if len(urls) == 0 {
		urls = resp.Result.DownloadInfoSnake.URLs
	}
	if len(urls) == 0 {
		urls = resp.DownloadInfo.URLs
	}
	if len(urls) == 0 {
		return ""
	}
	return urls[0]
}
