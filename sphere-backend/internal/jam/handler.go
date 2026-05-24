package jam

import (
	"encoding/json"
	"net/http"

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

func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	var req struct {
		Title string `json:"title"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)

	sess, err := h.svc.CreateSession(r.Context(), userID, req.Title)
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(sess)
}

func (h *Handler) Get(w http.ResponseWriter, r *http.Request) {
	sess, err := h.svc.GetSession(r.Context(), chi.URLParam(r, "id"))
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(sess)
}

func (h *Handler) Join(w http.ResponseWriter, r *http.Request) {
	sessionID := chi.URLParam(r, "id")
	userID := middleware.GetUserID(r.Context())

	if err := h.svc.JoinSession(r.Context(), sessionID, userID); err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusBadRequest)
		return
	}

	ids, _ := h.svc.GetParticipantIDs(r.Context(), sessionID)
	h.broadcast(ids, map[string]any{"type": "jam.join", "payload": map[string]string{
		"session_id": sessionID, "user_id": userID,
	}})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "joined"})
}

func (h *Handler) Leave(w http.ResponseWriter, r *http.Request) {
	sessionID := chi.URLParam(r, "id")
	userID := middleware.GetUserID(r.Context())

	ids, _ := h.svc.GetParticipantIDs(r.Context(), sessionID)
	if err := h.svc.LeaveSession(r.Context(), sessionID, userID); err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}

	h.broadcast(ids, map[string]any{"type": "jam.leave", "payload": map[string]string{
		"session_id": sessionID, "user_id": userID,
	}})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "left"})
}

func (h *Handler) End(w http.ResponseWriter, r *http.Request) {
	sessionID := chi.URLParam(r, "id")
	userID := middleware.GetUserID(r.Context())

	ids, _ := h.svc.GetParticipantIDs(r.Context(), sessionID)
	if err := h.svc.EndSession(r.Context(), sessionID, userID); err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}

	h.broadcast(ids, map[string]any{"type": "jam.end", "payload": map[string]string{"session_id": sessionID}})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ended"})
}

func (h *Handler) AddToQueue(w http.ResponseWriter, r *http.Request) {
	sessionID := chi.URLParam(r, "id")
	userID := middleware.GetUserID(r.Context())

	var item QueueItem
	if err := json.NewDecoder(r.Body).Decode(&item); err != nil || item.Provider == "" || item.TrackID == "" {
		http.Error(w, `{"error":"provider, track_id, title required"}`, http.StatusBadRequest)
		return
	}

	added, err := h.svc.AddToQueue(r.Context(), sessionID, userID, item)
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}

	ids, _ := h.svc.GetParticipantIDs(r.Context(), sessionID)
	h.broadcast(ids, map[string]any{"type": "jam.queue.add", "payload": added})

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(added)
}

func (h *Handler) RemoveFromQueue(w http.ResponseWriter, r *http.Request) {
	sessionID := chi.URLParam(r, "id")
	itemID := chi.URLParam(r, "itemID")
	userID := middleware.GetUserID(r.Context())

	if err := h.svc.RemoveFromQueue(r.Context(), sessionID, userID, itemID); err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusForbidden)
		return
	}

	ids, _ := h.svc.GetParticipantIDs(r.Context(), sessionID)
	h.broadcast(ids, map[string]any{"type": "jam.queue.remove", "payload": map[string]string{
		"session_id": sessionID, "item_id": itemID,
	}})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "removed"})
}

func (h *Handler) VoteQueue(w http.ResponseWriter, r *http.Request) {
	sessionID := chi.URLParam(r, "id")
	itemID := chi.URLParam(r, "itemID")
	userID := middleware.GetUserID(r.Context())

	var req struct {
		Vote int `json:"vote"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid body"}`, http.StatusBadRequest)
		return
	}

	updated, err := h.svc.VoteQueue(r.Context(), sessionID, userID, itemID, req.Vote)
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusBadRequest)
		return
	}

	ids, _ := h.svc.GetParticipantIDs(r.Context(), sessionID)
	h.broadcast(ids, map[string]any{"type": "jam.queue.vote", "payload": updated})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(updated)
}

func (h *Handler) GetQueue(w http.ResponseWriter, r *http.Request) {
	queue, err := h.svc.GetQueue(r.Context(), chi.URLParam(r, "id"))
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}
	if queue == nil {
		queue = []QueueItem{}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"queue": queue})
}

func (h *Handler) Sync(w http.ResponseWriter, r *http.Request) {
	sessionID := chi.URLParam(r, "id")
	userID := middleware.GetUserID(r.Context())

	var req struct {
		Provider string  `json:"provider"`
		TrackID  string  `json:"track_id"`
		Position float64 `json:"position_seconds"`
		Playing  bool    `json:"is_playing"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid body"}`, http.StatusBadRequest)
		return
	}

	if err := h.svc.SyncPlayback(r.Context(), sessionID, userID, req.Provider, req.TrackID, req.Position, req.Playing); err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusForbidden)
		return
	}

	ids, _ := h.svc.GetParticipantIDs(r.Context(), sessionID)
	h.broadcast(ids, map[string]any{"type": "jam.sync", "payload": map[string]any{
		"session_id":       sessionID,
		"track_provider":   req.Provider,
		"track_id":         req.TrackID,
		"position_seconds": req.Position,
		"is_playing":       req.Playing,
	}})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "synced"})
}

func (h *Handler) PlayNext(w http.ResponseWriter, r *http.Request) {
	sessionID := chi.URLParam(r, "id")
	userID := middleware.GetUserID(r.Context())

	next, err := h.svc.PlayNext(r.Context(), sessionID, userID)
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusBadRequest)
		return
	}

	ids, _ := h.svc.GetParticipantIDs(r.Context(), sessionID)
	h.broadcast(ids, map[string]any{"type": "jam.track.change", "payload": next})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(next)
}

func (h *Handler) Skip(w http.ResponseWriter, r *http.Request) {
	sessionID := chi.URLParam(r, "id")
	userID := middleware.GetUserID(r.Context())

	next, err := h.svc.SkipTrack(r.Context(), sessionID, userID)
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusBadRequest)
		return
	}

	ids, _ := h.svc.GetParticipantIDs(r.Context(), sessionID)
	h.broadcast(ids, map[string]any{"type": "jam.track.change", "payload": next})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(next)
}

func (h *Handler) Invite(w http.ResponseWriter, r *http.Request) {
	sessionID := chi.URLParam(r, "id")
	userID := middleware.GetUserID(r.Context())

	var req struct {
		TargetUserID string `json:"target_user_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.TargetUserID == "" {
		http.Error(w, `{"error":"target_user_id required"}`, http.StatusBadRequest)
		return
	}

	sess, err := h.svc.GetSession(r.Context(), sessionID)
	if err != nil {
		http.Error(w, `{"error":"session not found"}`, http.StatusNotFound)
		return
	}

	h.broadcast([]string{req.TargetUserID}, map[string]any{
		"type": "jam.invite",
		"payload": map[string]any{
			"session_id":    sessionID,
			"from_user_id":  userID,
			"title":         sess.Title,
			"current_track": sess.CurrentTrackID,
		},
	})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "invited"})
}
