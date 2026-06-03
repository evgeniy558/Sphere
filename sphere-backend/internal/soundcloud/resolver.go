// Package soundcloud resolves a live SoundCloud client_id and HTTP helpers.
// Static SOUNDCLOUD_CLIENT_ID values often 401/EOF on cloud hosts; scraping matches the web app.
package soundcloud

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"time"
)

var (
	scriptRe   = regexp.MustCompile(`<script[^>]+src="(https://[^"]+sndcdn\.com/[^"]+\.js)"`)
	clientIDRe = regexp.MustCompile(`client_id\s*[:=]\s*"([0-9A-Za-z]{20,40})"`)
)

// ClientIDResolver scrapes client_id from soundcloud.com bundles (refreshed periodically).
type ClientIDResolver struct {
	mu         sync.Mutex
	clientID   string
	expiresAt  time.Time
	fallback   string
	httpClient *http.Client
	ttl        time.Duration
}

func NewClientIDResolver(fallback string) *ClientIDResolver {
	return &ClientIDResolver{
		fallback:   strings.TrimSpace(fallback),
		httpClient: DefaultHTTPClient(),
		ttl:        6 * time.Hour,
	}
}

func (r *ClientIDResolver) Get(ctx context.Context, forceRefresh bool) string {
	r.mu.Lock()
	now := time.Now()
	if !forceRefresh && r.clientID != "" && now.Before(r.expiresAt) {
		id := r.clientID
		r.mu.Unlock()
		return id
	}
	cached := r.clientID
	r.mu.Unlock()

	scraped, err := r.scrape(ctx)
	if err == nil && scraped != "" {
		r.mu.Lock()
		r.clientID = scraped
		r.expiresAt = time.Now().Add(r.ttl)
		r.mu.Unlock()
		log.Printf("[soundcloud] resolved client_id (len=%d)", len(scraped))
		return scraped
	}
	if err != nil {
		log.Printf("[soundcloud] client_id scrape failed: %v", err)
	}
	if cached != "" {
		return cached
	}
	return r.fallback
}

func (r *ClientIDResolver) scrape(ctx context.Context) (string, error) {
	homeReq, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://soundcloud.com/", nil)
	if err != nil {
		return "", err
	}
	BrowserHeaders(homeReq)
	resp, err := DoWithRetry(r.httpClient, homeReq, 2)
	if err != nil {
		return "", fmt.Errorf("home: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("home status %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 5*1024*1024))
	if err != nil {
		return "", fmt.Errorf("home body: %w", err)
	}

	matches := scriptRe.FindAllStringSubmatch(string(body), -1)
	if len(matches) == 0 {
		return "", fmt.Errorf("no SC bundle script tags")
	}
	seen := make(map[string]struct{}, len(matches))
	for i := len(matches) - 1; i >= 0; i-- {
		scriptURL := matches[i][1]
		if _, ok := seen[scriptURL]; ok {
			continue
		}
		seen[scriptURL] = struct{}{}
		if id, err := r.fetchClientIDFromScript(ctx, scriptURL); err == nil && id != "" {
			return id, nil
		}
	}
	return "", fmt.Errorf("client_id not found in bundles")
}

func (r *ClientIDResolver) fetchClientIDFromScript(ctx context.Context, src string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, src, nil)
	if err != nil {
		return "", err
	}
	BrowserHeaders(req)
	resp, err := DoWithRetry(r.httpClient, req, 2)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("script status %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 8*1024*1024))
	if err != nil {
		return "", err
	}
	m := clientIDRe.FindSubmatch(body)
	if m == nil {
		return "", nil
	}
	return string(m[1]), nil
}

func BrowserHeaders(req *http.Request) {
	req.Header.Set("Accept", "application/json, text/html,application/xhtml+xml;q=0.9,*/*;q=0.8")
	req.Header.Set("Accept-Language", "en-US,en;q=0.9")
	req.Header.Set("Cache-Control", "no-cache")
	req.Header.Set("Pragma", "no-cache")
	req.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	req.Header.Set("Origin", "https://soundcloud.com")
	req.Header.Set("Referer", "https://soundcloud.com/")
}

func DefaultHTTPClient() *http.Client {
	return &http.Client{
		Timeout: 28 * time.Second,
		Transport: &http.Transport{
			Proxy:               http.ProxyFromEnvironment,
			ForceAttemptHTTP2:   false,
			MaxIdleConns:        32,
			IdleConnTimeout:     90 * time.Second,
			TLSHandshakeTimeout: 12 * time.Second,
		},
	}
}

// DoWithRetry retries transient EOF/reset errors common from SoundCloud on cloud egress.
func DoWithRetry(client *http.Client, req *http.Request, attempts int) (*http.Response, error) {
	if attempts < 1 {
		attempts = 1
	}
	var lastErr error
	for i := 0; i < attempts; i++ {
		reqClone := req.Clone(req.Context())
		if req.GetBody != nil {
			if body, err := req.GetBody(); err == nil && body != nil {
				reqClone.Body = body
			}
		}
		resp, err := client.Do(reqClone)
		if err == nil {
			return resp, nil
		}
		lastErr = err
		if !isRetryableNetErr(err) || i == attempts-1 {
			break
		}
		time.Sleep(time.Duration(200*(i+1)) * time.Millisecond)
	}
	return nil, lastErr
}

func isRetryableNetErr(err error) bool {
	if err == nil {
		return false
	}
	if err == io.EOF || err == io.ErrUnexpectedEOF {
		return true
	}
	var ne net.Error
	if errors.As(err, &ne) && ne.Timeout() {
		return true
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "eof") ||
		strings.Contains(msg, "connection reset") ||
		strings.Contains(msg, "broken pipe") ||
		strings.Contains(msg, "timeout")
}
