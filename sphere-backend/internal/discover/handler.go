package discover

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"strings"

	"sphere-backend/internal/middleware"
	"sphere-backend/internal/model"
)

// Handler exposes the discover endpoints over HTTP.
type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// Feed handles GET /discover/feed.
//
// Query parameters:
//   - limit:     int, defaults to 20 (max 60)
//   - excluded:  optional comma-separated `provider:id` tokens to skip.
func (h *Handler) Feed(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	lang := r.Header.Get("Accept-Language")

	limit := 20
	if v := r.URL.Query().Get("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			limit = n
		}
	}

	excluded := map[string]bool{}
	if v := r.URL.Query().Get("excluded"); v != "" {
		for _, tok := range strings.Split(v, ",") {
			tok = strings.ToLower(strings.TrimSpace(tok))
			if tok != "" {
				excluded[tok] = true
			}
		}
	}

	resp := h.svc.Feed(r.Context(), userID, lang, limit, excluded)
	if resp.Tracks == nil {
		resp.Tracks = []model.Track{}
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}

// Feedback handles POST /discover/feedback.
//
// Body:
//
//	{"provider":"spotify","id":"...","action":"like|skip","title":"...","artist":"..."}
//
// Likes are persisted by the iOS client through /favorites; this endpoint
// records skips into listen_history so the recommend engine can learn from it.
func (h *Handler) Feedback(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())

	var req struct {
		Provider string `json:"provider"`
		ID       string `json:"id"`
		Action   string `json:"action"`
		Title    string `json:"title"`
		Artist   string `json:"artist"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request"}`, http.StatusBadRequest)
		return
	}
	req.Action = strings.ToLower(strings.TrimSpace(req.Action))
	if req.Provider == "" || req.ID == "" || (req.Action != "like" && req.Action != "skip") {
		http.Error(w, `{"error":"provider, id, and action(like|skip) required"}`, http.StatusBadRequest)
		return
	}

	if err := h.svc.Feedback(r.Context(), userID, req.Provider, req.ID, req.Action, req.Title, req.Artist); err != nil {
		log.Printf("[discover/feedback] user=%s err=%v", userID, err)
	}
	w.WriteHeader(http.StatusNoContent)
}
