package wave

import (
	"encoding/json"
	"net/http"
	"strconv"

	"sphere-backend/internal/middleware"
)

// Handler exposes HTTP endpoints for the My Wave personalized radio.
type Handler struct {
	svc *Service
}

// NewHandler creates a new wave Handler.
func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// StartSession handles POST /wave/start.
func (h *Handler) StartSession(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	session, err := h.svc.StartSession(r.Context(), userID)
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(session)
}

// NextTracks handles GET /wave/next?session_id=X&count=N.
func (h *Handler) NextTracks(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	sessionID := r.URL.Query().Get("session_id")
	if sessionID == "" {
		http.Error(w, `{"error":"session_id required"}`, http.StatusBadRequest)
		return
	}

	count := 10
	if c := r.URL.Query().Get("count"); c != "" {
		if n, err := strconv.Atoi(c); err == nil && n > 0 {
			count = n
		}
	}
	if count > 30 {
		count = 30
	}

	tracks, err := h.svc.NextTracks(r.Context(), userID, sessionID, count)
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"tracks": tracks})
}

// RecordEvent handles POST /wave/event.
func (h *Handler) RecordEvent(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())

	var req struct {
		SessionID       string  `json:"session_id"`
		Provider        string  `json:"provider"`
		TrackID         string  `json:"track_id"`
		EventType       string  `json:"event_type"`
		PositionSeconds float64 `json:"position_seconds"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request"}`, http.StatusBadRequest)
		return
	}
	if req.SessionID == "" || req.Provider == "" || req.TrackID == "" || req.EventType == "" {
		http.Error(w, `{"error":"session_id, provider, track_id, and event_type required"}`, http.StatusBadRequest)
		return
	}

	validTypes := map[string]bool{
		"play": true, "like": true, "dislike": true,
		"skip": true, "finish": true, "add_to_library": true,
	}
	if !validTypes[req.EventType] {
		http.Error(w, `{"error":"invalid event_type"}`, http.StatusBadRequest)
		return
	}

	event := WaveEvent{
		Provider:        req.Provider,
		TrackID:         req.TrackID,
		EventType:       req.EventType,
		PositionSeconds: req.PositionSeconds,
	}
	if err := h.svc.RecordEvent(r.Context(), userID, req.SessionID, event); err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusCreated)
}

// GetProfile handles GET /wave/profile.
func (h *Handler) GetProfile(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	profile, err := h.svc.GetProfile(r.Context(), userID)
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}
	if profile == nil {
		http.Error(w, `{"error":"no profile found"}`, http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(profile)
}

// GetOfflinePackage handles GET /wave/offline-package.
func (h *Handler) GetOfflinePackage(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	pkg, err := h.svc.GetOfflinePackage(r.Context(), userID)
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(pkg)
}

// SyncOfflineEvents handles POST /wave/sync.
func (h *Handler) SyncOfflineEvents(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())

	var req struct {
		Events []WaveEvent `json:"events"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request"}`, http.StatusBadRequest)
		return
	}

	if err := h.svc.SyncOfflineEvents(r.Context(), userID, req.Events); err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"synced": len(req.Events)})
}
