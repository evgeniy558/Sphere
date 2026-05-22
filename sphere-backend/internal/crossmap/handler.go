package crossmap

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"

	"sphere-backend/internal/middleware"
	"sphere-backend/internal/model"
)

// Handler provides HTTP endpoints for cross-provider track mapping.
type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// Alternatives finds the same track on other streaming services.
// GET /tracks/{provider}/{id}/alternatives
func (h *Handler) Alternatives(w http.ResponseWriter, r *http.Request) {
	provider := chi.URLParam(r, "provider")
	id := chi.URLParam(r, "id")

	alts, err := h.svc.FindAlternatives(r.Context(), provider, id)
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"source_provider": provider,
		"source_track_id": id,
		"alternatives":    alts,
	})
}

// BestSource returns the highest-quality available source for a track.
// GET /tracks/{provider}/{id}/best-source
func (h *Handler) BestSource(w http.ResponseWriter, r *http.Request) {
	provider := chi.URLParam(r, "provider")
	id := chi.URLParam(r, "id")

	best, err := h.svc.BestSource(r.Context(), provider, id)
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(best)
}

// BatchMatch maps multiple tracks to cross-provider alternatives.
// POST /tracks/match
func (h *Handler) BatchMatch(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Tracks []struct {
			Provider string `json:"provider"`
			ID       string `json:"id"`
		} `json:"tracks"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid JSON"}`, http.StatusBadRequest)
		return
	}
	if len(req.Tracks) > 50 {
		http.Error(w, `{"error":"max 50 tracks per batch"}`, http.StatusBadRequest)
		return
	}

	tracks := make([]model.Track, len(req.Tracks))
	for i, t := range req.Tracks {
		tracks[i] = model.Track{Provider: t.Provider, ID: t.ID}
	}

	result := h.svc.BatchMatch(r.Context(), tracks)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"mappings": result})
}

// SetPreferred sets the user's preferred source for a track.
// POST /user/track-source
func (h *Handler) SetPreferred(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	if userID == "" {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		return
	}

	var req struct {
		Artist   string `json:"artist"`
		Title    string `json:"title"`
		Provider string `json:"provider"`
		TrackID  string `json:"track_id"`
		Reason   string `json:"reason"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid JSON"}`, http.StatusBadRequest)
		return
	}
	if req.Provider == "" || req.TrackID == "" {
		http.Error(w, `{"error":"provider and track_id required"}`, http.StatusBadRequest)
		return
	}
	if req.Reason == "" {
		req.Reason = "manual"
	}

	canonHash := CanonicalHash(req.Artist, req.Title)
	if err := h.svc.SetPreferredSource(r.Context(), userID, canonHash, req.Provider, req.TrackID, req.Reason); err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}
