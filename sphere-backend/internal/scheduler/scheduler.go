package scheduler

import (
	"context"
	"log"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/robfig/cron/v3"

	"sphere-backend/internal/crossmap"
	"sphere-backend/internal/music"
	"sphere-backend/internal/notifications"
)

// BlendRegenerator is implemented by blend.Service to avoid import cycles.
type BlendRegenerator interface {
	RegenerateAll(ctx context.Context) error
}

// Scheduler manages periodic background jobs.
type Scheduler struct {
	cron     *cron.Cron
	db       *pgxpool.Pool
	music    *music.Service
	crossmap *crossmap.Service
	notif    *notifications.Service
	blend    BlendRegenerator
}

// New creates a scheduler with all required services.
func New(db *pgxpool.Pool, musicSvc *music.Service, crossmapSvc *crossmap.Service, notifSvc *notifications.Service, blend BlendRegenerator) *Scheduler {
	return &Scheduler{
		cron:     cron.New(),
		db:       db,
		music:    musicSvc,
		crossmap: crossmapSvc,
		notif:    notifSvc,
		blend:    blend,
	}
}

// Start registers all scheduled jobs and starts the cron scheduler.
func (s *Scheduler) Start() {
	// Weekly availability check: every Sunday at 3:00 AM UTC.
	_, err := s.cron.AddFunc("0 3 * * 0", s.runAvailabilityCheck)
	if err != nil {
		log.Printf("[scheduler] failed to register availability job: %v", err)
	} else {
		log.Println("[scheduler] registered weekly availability check (Sun 3:00 UTC)")
	}

	// Daily blend regeneration at 4:00 AM UTC.
	if s.blend != nil {
		_, err = s.cron.AddFunc("0 4 * * *", s.runBlendRegeneration)
		if err != nil {
			log.Printf("[scheduler] failed to register blend job: %v", err)
		} else {
			log.Println("[scheduler] registered daily blend regeneration (4:00 UTC)")
		}
	}

	s.cron.Start()
	log.Println("[scheduler] started")
}

// Stop gracefully shuts down the scheduler.
func (s *Scheduler) Stop() {
	ctx := s.cron.Stop()
	<-ctx.Done()
	log.Println("[scheduler] stopped")
}

// TriggerAvailability is an admin endpoint to manually trigger the availability check.
// POST /admin/jobs/check-availability
func (s *Scheduler) TriggerAvailability(w http.ResponseWriter, r *http.Request) {
	go s.runAvailabilityCheck()
	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"status":"started","message":"availability check triggered"}`))
}

func (s *Scheduler) runBlendRegeneration() {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
	defer cancel()
	log.Println("[scheduler] starting daily blend regeneration...")
	if err := s.blend.RegenerateAll(ctx); err != nil {
		log.Printf("[scheduler] blend regeneration error: %v", err)
	}
}
