package notifications

import (
	"encoding/json"
	"net/http"
	"strconv"

	"sphere-backend/internal/middleware"
)

// Handler provides HTTP endpoints for device registration and notification history.
type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// Register adds or updates a device token.
// POST /devices
func (h *Handler) Register(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	if userID == "" {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		return
	}

	var req struct {
		Platform string `json:"platform"`
		Token    string `json:"token"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid JSON"}`, http.StatusBadRequest)
		return
	}
	if req.Platform == "" || req.Token == "" {
		http.Error(w, `{"error":"platform and token required"}`, http.StatusBadRequest)
		return
	}
	if req.Platform != "ios" && req.Platform != "android" && req.Platform != "web" {
		http.Error(w, `{"error":"platform must be ios, android, or web"}`, http.StatusBadRequest)
		return
	}

	if err := h.svc.RegisterDevice(r.Context(), userID, req.Platform, req.Token); err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

// Unregister removes a device token.
// DELETE /devices/{token}
func (h *Handler) Unregister(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	if userID == "" {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		return
	}

	// Token from URL path.
	token := r.PathValue("token")
	if token == "" {
		// Fallback: chi param.
		token = r.URL.Path[len("/devices/"):]
	}
	if token == "" {
		http.Error(w, `{"error":"token required"}`, http.StatusBadRequest)
		return
	}

	if err := h.svc.UnregisterDevice(r.Context(), userID, token); err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

// History returns recent notifications for the authenticated user.
// GET /notifications
func (h *Handler) History(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	if userID == "" {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		return
	}

	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	entries, err := h.svc.History(r.Context(), userID, limit)
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}
	if entries == nil {
		entries = []NotificationEntry{}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"notifications": entries})
}
