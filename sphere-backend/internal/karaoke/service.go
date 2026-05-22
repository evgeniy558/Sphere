package karaoke

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/minio/minio-go/v7"

	"sphere-backend/internal/music"
)

// karaokeSem limits concurrent vocal-removal jobs (heavy CPU + RAM).
var karaokeSem = make(chan struct{}, 1)

// Service orchestrates vocal removal: download → NodeX inference → S3 cache.
type Service struct {
	db       *pgxpool.Pool
	s3       *minio.Client
	s3Bucket string
	music    *music.Service
}

// NewService creates a karaoke service. s3Client may be nil (disables caching).
func NewService(db *pgxpool.Pool, s3Client *minio.Client, s3Bucket string, musicSvc *music.Service) *Service {
	return &Service{
		db:       db,
		s3:       s3Client,
		s3Bucket: s3Bucket,
		music:    musicSvc,
	}
}

// Status returns the current karaoke processing status for a track.
func (s *Service) Status(ctx context.Context, provider, trackID string) (string, string, error) {
	var status, s3Key string
	err := s.db.QueryRow(ctx,
		`SELECT status, s3_key FROM karaoke_cache WHERE provider = $1 AND track_id = $2`,
		provider, trackID,
	).Scan(&status, &s3Key)
	if err != nil {
		return "", "", err
	}
	return status, s3Key, nil
}

// StreamFromS3 streams a cached karaoke file from S3 to the writer.
func (s *Service) StreamFromS3(ctx context.Context, s3Key string, w io.Writer) error {
	if s.s3 == nil {
		return fmt.Errorf("s3 not configured")
	}
	obj, err := s.s3.GetObject(ctx, s.s3Bucket, s3Key, minio.GetObjectOptions{})
	if err != nil {
		return err
	}
	defer obj.Close()
	_, err = io.Copy(w, obj)
	return err
}

// Prepare starts async vocal removal processing. Returns immediately.
func (s *Service) Prepare(ctx context.Context, provider, trackID string) error {
	// Check if already cached or in progress.
	var existing string
	err := s.db.QueryRow(ctx,
		`SELECT status FROM karaoke_cache WHERE provider = $1 AND track_id = $2`,
		provider, trackID,
	).Scan(&existing)
	if err == nil {
		if existing == "ready" || existing == "pending" {
			return nil // already done or in progress
		}
	}

	// Insert pending record.
	_, err = s.db.Exec(ctx,
		`INSERT INTO karaoke_cache (provider, track_id, s3_key, status)
		 VALUES ($1, $2, '', 'pending')
		 ON CONFLICT (provider, track_id) DO UPDATE SET status = 'pending', error_message = NULL`,
		provider, trackID,
	)
	if err != nil {
		return fmt.Errorf("karaoke insert: %w", err)
	}

	// Launch processing in background goroutine.
	go s.processTrack(provider, trackID)
	return nil
}

func (s *Service) processTrack(provider, trackID string) {
	// Acquire semaphore (limit to 1 concurrent job).
	karaokeSem <- struct{}{}
	defer func() { <-karaokeSem }()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()

	log.Printf("[karaoke] starting processing %s/%s", provider, trackID)

	// Get stream URL.
	streamURL, err := s.music.GetTrackStreamURL(ctx, provider, trackID)
	if err != nil {
		s.markError(ctx, provider, trackID, fmt.Sprintf("stream URL: %v", err))
		return
	}

	// Create temp files.
	tmpDir, err := os.MkdirTemp("", "karaoke-*")
	if err != nil {
		s.markError(ctx, provider, trackID, fmt.Sprintf("tmpdir: %v", err))
		return
	}
	defer os.RemoveAll(tmpDir)

	inputPath := filepath.Join(tmpDir, "input.wav")
	outputPath := filepath.Join(tmpDir, "instrumental.mp3")

	// Download and convert to WAV via ffmpeg.
	dlCmd := exec.CommandContext(ctx,
		"ffmpeg", "-hide_banner", "-loglevel", "error",
		"-i", streamURL,
		"-vn", "-ar", "44100", "-ac", "2", "-f", "wav",
		inputPath,
	)
	if out, err := dlCmd.CombinedOutput(); err != nil {
		s.markError(ctx, provider, trackID, fmt.Sprintf("ffmpeg download: %v %s", err, string(out)))
		return
	}

	// Run NodeX Vocal inference.
	modelPath := "/models/nodex_vocal.onnx"
	if _, err := os.Stat(modelPath); os.IsNotExist(err) {
		// Fallback: use ffmpeg center-channel removal when model not available.
		log.Printf("[karaoke] NodeX model not found, using ffmpeg center-channel removal")
		fbCmd := exec.CommandContext(ctx,
			"ffmpeg", "-hide_banner", "-loglevel", "error",
			"-i", inputPath,
			"-af", "pan=stereo|c0=c0-c1|c1=c1-c0",
			"-c:a", "libmp3lame", "-b:a", "192k",
			outputPath,
		)
		if out, err := fbCmd.CombinedOutput(); err != nil {
			s.markError(ctx, provider, trackID, fmt.Sprintf("ffmpeg fallback: %v %s", err, string(out)))
			return
		}
	} else {
		inferCmd := exec.CommandContext(ctx,
			"python3", "/app/scripts/nodex/vocal/inference.py",
			"--input", inputPath,
			"--output", outputPath,
			"--model", modelPath,
		)
		inferOut, err := inferCmd.CombinedOutput()
		if err != nil {
			s.markError(ctx, provider, trackID, fmt.Sprintf("nodex inference: %v %s", err, string(inferOut)))
			return
		}

		// Parse inference output.
		var result struct {
			Status string `json:"status"`
		}
		if json.Unmarshal(inferOut, &result) == nil && result.Status != "ok" {
			s.markError(ctx, provider, trackID, fmt.Sprintf("nodex: %s", string(inferOut)))
			return
		}
	}

	// Upload to S3.
	s3Key := fmt.Sprintf("karaoke/%s/%s.mp3", provider, trackID)
	if s.s3 != nil {
		f, err := os.Open(outputPath)
		if err != nil {
			s.markError(ctx, provider, trackID, fmt.Sprintf("open output: %v", err))
			return
		}
		defer f.Close()

		stat, _ := f.Stat()
		_, err = s.s3.PutObject(ctx, s.s3Bucket, s3Key, f, stat.Size(), minio.PutObjectOptions{
			ContentType: "audio/mpeg",
		})
		if err != nil {
			s.markError(ctx, provider, trackID, fmt.Sprintf("s3 upload: %v", err))
			return
		}

		// Mark as ready.
		_, _ = s.db.Exec(ctx,
			`UPDATE karaoke_cache SET status = 'ready', s3_key = $3, file_size = $4, completed_at = now()
			 WHERE provider = $1 AND track_id = $2`,
			provider, trackID, s3Key, stat.Size(),
		)
	} else {
		// No S3 — just mark ready with empty key (will need re-processing).
		_, _ = s.db.Exec(ctx,
			`UPDATE karaoke_cache SET status = 'ready', completed_at = now()
			 WHERE provider = $1 AND track_id = $2`,
			provider, trackID,
		)
	}

	log.Printf("[karaoke] completed %s/%s → %s", provider, trackID, s3Key)
}

func (s *Service) markError(ctx context.Context, provider, trackID, msg string) {
	log.Printf("[karaoke] error %s/%s: %s", provider, trackID, msg)
	_, _ = s.db.Exec(ctx,
		`UPDATE karaoke_cache SET status = 'error', error_message = $3
		 WHERE provider = $1 AND track_id = $2`,
		provider, trackID, msg,
	)
}
