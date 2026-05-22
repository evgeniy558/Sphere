package scheduler

import (
	"log"
	"net/http"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/robfig/cron/v3"

	"sphere-backend/internal/crossmap"
	"sphere-backend/internal/music"
	"sphere-backend/internal/notifications"
)

// Scheduler manages periodic background jobs.
type Scheduler struct {
	cron     *cron.Cron
	db       *pgxpool.Pool
	music    *music.Service
	crossmap *crossmap.Service
	notif    *notifications.Service
}

// New creates a scheduler with all required services.
func New(db *pgxpool.Pool, musicSvc *music.Service, crossmapSvc *crossmap.Service, notifSvc *notifications.Service) *Scheduler {
	return &Scheduler{
		cron:     cron.New(),
		db:       db,
		music:    musicSvc,
		crossmap: crossmapSvc,
		notif:    notifSvc,
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
