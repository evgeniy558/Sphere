package updates

import (
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type AppUpdate struct {
	ID        string    `json:"id"`
	Version   string    `json:"version"`
	Title     string    `json:"title"`
	Body      string    `json:"body"`
	CreatedAt time.Time `json:"created_at"`
}

type Handler struct {
	db *pgxpool.Pool
}

func NewHandler(db *pgxpool.Pool) *Handler {
	return &Handler{db: db}
}

// LatestUpdate returns the most recent app update (public endpoint).
func (h *Handler) LatestUpdate(w http.ResponseWriter, r *http.Request) {
	var u AppUpdate
	err := h.db.QueryRow(r.Context(), `
		SELECT id, version, title, body, created_at
		FROM app_updates
		ORDER BY created_at DESC
		LIMIT 1
	`).Scan(&u.ID, &u.Version, &u.Title, &u.Body, &u.CreatedAt)
	if err == pgx.ErrNoRows {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`null`))
		return
	}
	if err != nil {
		http.Error(w, `{"error":"internal"}`, http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(u)
}

// CreateUpdate inserts a new app update (admin-only endpoint).
func (h *Handler) CreateUpdate(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Version string `json:"version"`
		Title   string `json:"title"`
		Body    string `json:"body"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid body"}`, http.StatusBadRequest)
		return
	}
	if strings.TrimSpace(req.Version) == "" {
		http.Error(w, `{"error":"version is required"}`, http.StatusBadRequest)
		return
	}

	var u AppUpdate
	err := h.db.QueryRow(r.Context(), `
		INSERT INTO app_updates (version, title, body) VALUES ($1, $2, $3)
		RETURNING id, version, title, body, created_at
	`, req.Version, req.Title, req.Body).Scan(&u.ID, &u.Version, &u.Title, &u.Body, &u.CreatedAt)
	if err != nil {
		http.Error(w, `{"error":"internal"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(u)
}

// ListUpdates returns all updates, newest first (admin-only).
func (h *Handler) ListUpdates(w http.ResponseWriter, r *http.Request) {
	rows, err := h.db.Query(r.Context(), `
		SELECT id, version, title, body, created_at
		FROM app_updates
		ORDER BY created_at DESC
		LIMIT 100
	`)
	if err != nil {
		http.Error(w, `{"error":"internal"}`, http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	out := make([]AppUpdate, 0)
	for rows.Next() {
		var u AppUpdate
		if err := rows.Scan(&u.ID, &u.Version, &u.Title, &u.Body, &u.CreatedAt); err != nil {
			continue
		}
		out = append(out, u)
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(out)
}
