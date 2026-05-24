package blend

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"

	"sphere-backend/internal/middleware"
)

type Handler struct {
	svc       *Service
	broadcast func(userIDs []string, payload any)
}

func NewHandler(svc *Service, broadcast func([]string, any)) *Handler {
	return &Handler{svc: svc, broadcast: broadcast}
}

// Create starts a new Blend with invited members.
// POST /blends
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())

	var req struct {
		Title     string   `json:"title"`
		MemberIDs []string `json:"member_ids"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid body"}`, http.StatusBadRequest)
		return
	}

	blend, err := h.svc.Create(r.Context(), userID, req.Title, req.MemberIDs)
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}

	// Notify invited members
	for _, uid := range req.MemberIDs {
		if uid != userID {
			h.broadcast([]string{uid}, map[string]any{
				"type": "blend.invite",
				"payload": map[string]any{
					"blend_id": blend.ID,
					"title":    blend.Title,
					"from":     userID,
				},
			})
		}
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(blend)
}

// ListMine returns all blends the user is a member of.
// GET /blends
func (h *Handler) ListMine(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	blends, err := h.svc.ListMine(r.Context(), userID)
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}
	if blends == nil {
		blends = []Blend{}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"blends": blends})
}

// GetByID returns a full blend with tracks and members.
// GET /blends/{id}
func (h *Handler) GetByID(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	blend, err := h.svc.GetByID(r.Context(), chi.URLParam(r, "id"), userID)
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(blend)
}

// Delete archives a blend (creator only).
// DELETE /blends/{id}
func (h *Handler) Delete(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	if err := h.svc.Delete(r.Context(), chi.URLParam(r, "id"), userID); err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusForbidden)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "deleted"})
}

// AcceptInvite accepts a blend invitation.
// POST /blends/{id}/accept
func (h *Handler) AcceptInvite(w http.ResponseWriter, r *http.Request) {
	blendID := chi.URLParam(r, "id")
	userID := middleware.GetUserID(r.Context())

	if err := h.svc.AcceptInvite(r.Context(), blendID, userID); err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "accepted"})
}

// DeclineInvite declines a blend invitation.
// POST /blends/{id}/decline
func (h *Handler) DeclineInvite(w http.ResponseWriter, r *http.Request) {
	blendID := chi.URLParam(r, "id")
	userID := middleware.GetUserID(r.Context())

	if err := h.svc.DeclineInvite(r.Context(), blendID, userID); err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "declined"})
}

// Regenerate manually triggers blend regeneration.
// POST /blends/{id}/regenerate
func (h *Handler) Regenerate(w http.ResponseWriter, r *http.Request) {
	blendID := chi.URLParam(r, "id")

	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
		defer cancel()
		if err := h.svc.Generate(ctx, blendID); err != nil {
			log.Printf("[blend] regenerate %s: %v", blendID, err)
		}
	}()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "regenerating"})
}
