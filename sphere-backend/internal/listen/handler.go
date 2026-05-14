package listen

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"

	"sphere-backend/internal/middleware"
)

type Handler struct {
	svc *Service
	broadcast func(userIDs []string, payload any)
}

func NewHandler(svc *Service, broadcast func([]string, any)) *Handler {
	return &Handler{svc: svc, broadcast: broadcast}
}

func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	var req struct {
		TrackProvider string `json:"track_provider"`
		TrackID       string `json:"track_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.TrackProvider == "" || req.TrackID == "" {
		http.Error(w, `{"error":"track_provider and track_id required"}`, http.StatusBadRequest)
		return
	}

	sess, err := h.svc.CreateSession(r.Context(), userID, req.TrackProvider, req.TrackID)
	if err != nil {
		http.Error(w, `{"error":"failed"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(sess)
}

func (h *Handler) Join(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	sessionID := chi.URLParam(r, "id")

	if err := h.svc.JoinSession(r.Context(), sessionID, userID); err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusBadRequest)
		return
	}

	// Broadcast join event to all participants.
	if ids, err := h.svc.GetParticipantIDs(r.Context(), sessionID); err == nil {
		h.broadcast(ids, map[string]any{
			"type": "listen.join",
			"payload": map[string]any{
				"session_id": sessionID,
				"user_id":    userID,
			},
		})
	}

	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"ok":true}`))
}

func (h *Handler) Leave(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	sessionID := chi.URLParam(r, "id")

	// Broadcast leave event before removing.
	if ids, err := h.svc.GetParticipantIDs(r.Context(), sessionID); err == nil {
		h.broadcast(ids, map[string]any{
			"type": "listen.leave",
			"payload": map[string]any{
				"session_id": sessionID,
				"user_id":    userID,
			},
		})
	}

	if err := h.svc.LeaveSession(r.Context(), sessionID, userID); err != nil {
		http.Error(w, `{"error":"failed"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"ok":true}`))
}

func (h *Handler) End(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	sessionID := chi.URLParam(r, "id")

	// Broadcast end event.
	if ids, err := h.svc.GetParticipantIDs(r.Context(), sessionID); err == nil {
		h.broadcast(ids, map[string]any{
			"type":    "listen.end",
			"payload": map[string]any{"session_id": sessionID},
		})
	}

	if err := h.svc.EndSession(r.Context(), sessionID, userID); err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"ok":true}`))
}

func (h *Handler) Get(w http.ResponseWriter, r *http.Request) {
	sessionID := chi.URLParam(r, "id")

	sess, err := h.svc.GetSession(r.Context(), sessionID)
	if err != nil {
		http.Error(w, `{"error":"not found"}`, http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(sess)
}

// Invite sends a listen invite to a specific user via WebSocket.
func (h *Handler) Invite(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	sessionID := chi.URLParam(r, "id")

	var req struct {
		TargetUserID  string `json:"target_user_id"`
		TrackTitle    string `json:"track_title"`
		TrackArtist   string `json:"track_artist"`
		TrackCoverURL string `json:"track_cover_url"`
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

	// Get sender username.
	var username string
	_ = h.svc.db.QueryRow(r.Context(), `SELECT COALESCE(NULLIF(username,''), name) FROM users WHERE id = $1`, userID).Scan(&username)

	h.broadcast([]string{req.TargetUserID}, map[string]any{
		"type": "listen.invite",
		"payload": InvitePayload{
			SessionID:     sessionID,
			FromUserID:    userID,
			FromUsername:   username,
			TrackProvider: sess.TrackProvider,
			TrackID:       sess.TrackID,
			TrackTitle:    req.TrackTitle,
			TrackArtist:   req.TrackArtist,
			TrackCoverURL: req.TrackCoverURL,
		},
	})

	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"ok":true}`))
}

// WebRTCSignal relays WebRTC signaling messages (offer, answer, ICE candidates)
// between participants in a listen session. The backend never inspects the payload.
func (h *Handler) WebRTCSignal(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	sessionID := chi.URLParam(r, "id")

	var req struct {
		TargetUserID string `json:"target_user_id"`
		SignalType   string `json:"signal_type"` // offer, answer, ice
		Payload      any    `json:"payload"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.TargetUserID == "" || req.SignalType == "" {
		http.Error(w, `{"error":"target_user_id, signal_type, and payload required"}`, http.StatusBadRequest)
		return
	}

	h.broadcast([]string{req.TargetUserID}, map[string]any{
		"type": "listen.webrtc." + req.SignalType,
		"payload": map[string]any{
			"session_id":    sessionID,
			"from_user_id": userID,
			"data":         req.Payload,
		},
	})

	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"ok":true}`))
}

// Sync relays playback sync from the host to all participants.
func (h *Handler) Sync(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	sessionID := chi.URLParam(r, "id")

	var req SyncPayload
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid body"}`, http.StatusBadRequest)
		return
	}
	req.SessionID = sessionID

	// Only broadcast to other participants.
	if ids, err := h.svc.GetParticipantIDs(r.Context(), sessionID); err == nil {
		others := make([]string, 0, len(ids))
		for _, id := range ids {
			if id != userID {
				others = append(others, id)
			}
		}
		h.broadcast(others, map[string]any{
			"type":    "listen.sync",
			"payload": req,
		})
	}

	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"ok":true}`))
}
