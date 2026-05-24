package playlist

import (
	"encoding/json"
	"net/http"
	"strings"

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

// ---------------------------------------------------------------------------
// Playlist CRUD
// ---------------------------------------------------------------------------

func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())

	var req struct {
		Title       string `json:"title"`
		Description string `json:"description"`
		IsPublic    bool   `json:"is_public"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid body"}`, http.StatusBadRequest)
		return
	}

	p, err := h.svc.Create(r.Context(), userID, req.Title, req.Description, req.IsPublic)
	if err != nil {
		http.Error(w, `{"error":"create failed"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(p)
}

func (h *Handler) ListMine(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())

	list, err := h.svc.ListMine(r.Context(), userID)
	if err != nil {
		http.Error(w, `{"error":"list failed"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(list)
}

func (h *Handler) GetByID(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	playlistID := chi.URLParam(r, "id")

	detail, err := h.svc.GetByID(r.Context(), playlistID, userID)
	if err != nil {
		if strings.Contains(err.Error(), "forbidden") {
			http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
			return
		}
		http.Error(w, `{"error":"not found"}`, http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(detail)
}

func (h *Handler) Update(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	playlistID := chi.URLParam(r, "id")

	var req struct {
		Title       string `json:"title"`
		Description string `json:"description"`
		CoverURL    string `json:"cover_url"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid body"}`, http.StatusBadRequest)
		return
	}

	if err := h.svc.Update(r.Context(), playlistID, userID, req.Title, req.Description, req.CoverURL); err != nil {
		if strings.Contains(err.Error(), "forbidden") {
			http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
			return
		}
		http.Error(w, `{"error":"update failed"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]bool{"ok": true})
}

func (h *Handler) Delete(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	playlistID := chi.URLParam(r, "id")

	if err := h.svc.Delete(r.Context(), playlistID, userID); err != nil {
		if strings.Contains(err.Error(), "forbidden") {
			http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
			return
		}
		http.Error(w, `{"error":"delete failed"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]bool{"ok": true})
}

// ---------------------------------------------------------------------------
// Tracks
// ---------------------------------------------------------------------------

func (h *Handler) AddTrack(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	playlistID := chi.URLParam(r, "id")

	var req struct {
		Provider string `json:"provider"`
		TrackID  string `json:"track_id"`
		Title    string `json:"title"`
		Artist   string `json:"artist"`
		CoverURL string `json:"cover_url"`
		Duration int    `json:"duration"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid body"}`, http.StatusBadRequest)
		return
	}

	t := PlaylistTrack{
		Provider: req.Provider,
		TrackID:  req.TrackID,
		Title:    req.Title,
		Artist:   req.Artist,
		CoverURL: req.CoverURL,
		Duration: req.Duration,
	}

	if err := h.svc.AddTrack(r.Context(), playlistID, userID, t); err != nil {
		if strings.Contains(err.Error(), "forbidden") {
			http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
			return
		}
		http.Error(w, `{"error":"add track failed"}`, http.StatusInternalServerError)
		return
	}

	// Broadcast to all playlist members
	if h.broadcast != nil {
		ids := h.svc.GetPlaylistMemberIDs(r.Context(), playlistID)
		h.broadcast(ids, map[string]any{
			"type": "playlist.track.added",
			"payload": map[string]any{"playlist_id": playlistID, "track": t, "added_by": userID},
		})
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]bool{"ok": true})
}

func (h *Handler) RemoveTrack(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	playlistID := chi.URLParam(r, "id")
	trackID := chi.URLParam(r, "trackID")

	if err := h.svc.RemoveTrack(r.Context(), playlistID, userID, trackID); err != nil {
		if strings.Contains(err.Error(), "forbidden") {
			http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
			return
		}
		http.Error(w, `{"error":"remove track failed"}`, http.StatusInternalServerError)
		return
	}

	if h.broadcast != nil {
		ids := h.svc.GetPlaylistMemberIDs(r.Context(), playlistID)
		h.broadcast(ids, map[string]any{
			"type": "playlist.track.removed",
			"payload": map[string]any{"playlist_id": playlistID, "track_id": trackID, "removed_by": userID},
		})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]bool{"ok": true})
}

func (h *Handler) ReorderTracks(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	playlistID := chi.URLParam(r, "id")

	var req struct {
		TrackIDs []string `json:"track_ids"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid body"}`, http.StatusBadRequest)
		return
	}

	if err := h.svc.ReorderTracks(r.Context(), playlistID, userID, req.TrackIDs); err != nil {
		if strings.Contains(err.Error(), "forbidden") {
			http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
			return
		}
		http.Error(w, `{"error":"reorder failed"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]bool{"ok": true})
}

// ---------------------------------------------------------------------------
// Members
// ---------------------------------------------------------------------------

func (h *Handler) AddMember(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	playlistID := chi.URLParam(r, "id")

	var req struct {
		UserID string `json:"user_id"`
		Role   string `json:"role"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid body"}`, http.StatusBadRequest)
		return
	}

	if err := h.svc.AddMember(r.Context(), playlistID, userID, req.UserID, req.Role); err != nil {
		if strings.Contains(err.Error(), "forbidden") {
			http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
			return
		}
		http.Error(w, `{"error":"add member failed"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]bool{"ok": true})
}

func (h *Handler) RemoveMember(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	playlistID := chi.URLParam(r, "id")
	targetUserID := chi.URLParam(r, "userID")

	if err := h.svc.RemoveMember(r.Context(), playlistID, userID, targetUserID); err != nil {
		if strings.Contains(err.Error(), "forbidden") {
			http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
			return
		}
		http.Error(w, `{"error":"remove member failed"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]bool{"ok": true})
}

func (h *Handler) ListMembers(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	playlistID := chi.URLParam(r, "id")

	members, err := h.svc.ListMembers(r.Context(), playlistID, userID)
	if err != nil {
		if strings.Contains(err.Error(), "forbidden") {
			http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
			return
		}
		http.Error(w, `{"error":"list members failed"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(members)
}

// ---------------------------------------------------------------------------
// Suggestions
// ---------------------------------------------------------------------------

func (h *Handler) SuggestTrack(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	playlistID := chi.URLParam(r, "id")

	var req struct {
		Provider string `json:"provider"`
		TrackID  string `json:"track_id"`
		Title    string `json:"title"`
		Artist   string `json:"artist"`
		CoverURL string `json:"cover_url"`
		Duration int    `json:"duration"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid body"}`, http.StatusBadRequest)
		return
	}

	sg, err := h.svc.SuggestTrack(r.Context(), playlistID, userID, PlaylistTrack{
		Provider: req.Provider, TrackID: req.TrackID, Title: req.Title,
		Artist: req.Artist, CoverURL: req.CoverURL, Duration: req.Duration,
	})
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusForbidden)
		return
	}

	if h.broadcast != nil {
		ids := h.svc.GetPlaylistMemberIDs(r.Context(), playlistID)
		h.broadcast(ids, map[string]any{"type": "playlist.suggestion.new", "payload": sg})
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(sg)
}

func (h *Handler) ListSuggestions(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	playlistID := chi.URLParam(r, "id")
	status := r.URL.Query().Get("status")

	list, err := h.svc.ListSuggestions(r.Context(), playlistID, userID, status)
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusForbidden)
		return
	}
	if list == nil {
		list = []Suggestion{}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"suggestions": list})
}

func (h *Handler) ApproveSuggestion(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	playlistID := chi.URLParam(r, "id")
	suggestionID := chi.URLParam(r, "suggestionID")

	if err := h.svc.ApproveSuggestion(r.Context(), playlistID, userID, suggestionID); err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusForbidden)
		return
	}

	if h.broadcast != nil {
		ids := h.svc.GetPlaylistMemberIDs(r.Context(), playlistID)
		h.broadcast(ids, map[string]any{"type": "playlist.suggestion.approved",
			"payload": map[string]string{"playlist_id": playlistID, "suggestion_id": suggestionID}})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "approved"})
}

func (h *Handler) RejectSuggestion(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	playlistID := chi.URLParam(r, "id")
	suggestionID := chi.URLParam(r, "suggestionID")

	if err := h.svc.RejectSuggestion(r.Context(), playlistID, userID, suggestionID); err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusForbidden)
		return
	}

	if h.broadcast != nil {
		ids := h.svc.GetPlaylistMemberIDs(r.Context(), playlistID)
		h.broadcast(ids, map[string]any{"type": "playlist.suggestion.rejected",
			"payload": map[string]string{"playlist_id": playlistID, "suggestion_id": suggestionID}})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "rejected"})
}

func (h *Handler) VoteTrack(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	playlistID := chi.URLParam(r, "id")
	trackID := chi.URLParam(r, "trackID")

	var req struct {
		Vote int `json:"vote"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid body"}`, http.StatusBadRequest)
		return
	}

	if err := h.svc.VoteTrack(r.Context(), playlistID, userID, trackID, req.Vote); err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "voted"})
}

func (h *Handler) ListActivity(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	playlistID := chi.URLParam(r, "id")

	list, err := h.svc.ListActivity(r.Context(), playlistID, userID, 50)
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusForbidden)
		return
	}
	if list == nil {
		list = []ActivityEntry{}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"activity": list})
}
