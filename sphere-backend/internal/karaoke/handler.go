package karaoke

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
)

// Handler provides HTTP endpoints for karaoke (vocal removal).
type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// Prepare kicks off async vocal removal for a track.
// POST /tracks/{provider}/{id}/karaoke/prepare
func (h *Handler) Prepare(w http.ResponseWriter, r *http.Request) {
	provider := chi.URLParam(r, "provider")
	id := chi.URLParam(r, "id")

	if err := h.svc.Prepare(r.Context(), provider, id); err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)
	json.NewEncoder(w).Encode(map[string]string{
		"status":   "processing",
		"provider": provider,
		"track_id": id,
	})
}

// Stream returns the karaoke audio if ready, or status if still processing.
// GET /tracks/{provider}/{id}/karaoke
func (h *Handler) Stream(w http.ResponseWriter, r *http.Request) {
	provider := chi.URLParam(r, "provider")
	id := chi.URLParam(r, "id")

	status, s3Key, err := h.svc.Status(r.Context(), provider, id)
	if err != nil {
		// Not found — suggest preparing first.
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{
			"status":  "not_found",
			"message": "Use POST /tracks/{provider}/{id}/karaoke/prepare first",
		})
		return
	}

	switch status {
	case "ready":
		if s3Key == "" {
			http.Error(w, `{"error":"no cached file"}`, http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "audio/mpeg")
		w.Header().Set("Cache-Control", "private, max-age=86400")
		if err := h.svc.StreamFromS3(r.Context(), s3Key, w); err != nil {
			http.Error(w, `{"error":"stream failed: `+err.Error()+`"}`, http.StatusInternalServerError)
		}

	case "pending":
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusAccepted)
		json.NewEncoder(w).Encode(map[string]string{"status": "processing"})

	case "error":
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{
			"status":  "error",
			"message": "vocal removal failed, please retry",
		})

	default:
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusAccepted)
		json.NewEncoder(w).Encode(map[string]string{"status": status})
	}
}
