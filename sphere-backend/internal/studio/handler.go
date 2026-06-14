package studio

import (
	"encoding/json"
	"net/http"

	"sphere-backend/internal/middleware"
)

// Handler wraps the Studio service in HTTP.
type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// GetSummary handles GET /studio/summary.
func (h *Handler) GetSummary(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	resp := h.svc.Summary(r.Context(), userID)
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}
