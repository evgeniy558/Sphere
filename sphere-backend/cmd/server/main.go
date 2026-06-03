package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"

	"sphere-backend/internal/admin"
	"sphere-backend/internal/auth"
	"sphere-backend/internal/blend"
	"sphere-backend/internal/chat"
	"sphere-backend/internal/comments"
	"sphere-backend/internal/config"
	"sphere-backend/internal/crossmap"
	"sphere-backend/internal/db"
	"sphere-backend/internal/favorites"
	"sphere-backend/internal/history"
	"sphere-backend/internal/jam"
	"sphere-backend/internal/karaoke"
	"sphere-backend/internal/listen"
	"sphere-backend/internal/middleware"
	"sphere-backend/internal/music"
	"sphere-backend/internal/notifications"
	"sphere-backend/internal/playlist"
	"sphere-backend/internal/preferences"
	"sphere-backend/internal/provider"
	"sphere-backend/internal/recommend"
	"sphere-backend/internal/scheduler"
	"sphere-backend/internal/social"
	"sphere-backend/internal/updates"
	"sphere-backend/internal/uploads"
	"sphere-backend/internal/user"
	"sphere-backend/internal/wave"
)

// gitCommit is overridden at build-time via `-ldflags "-X main.gitCommit=<sha>"`.
// Falls back to the `RENDER_GIT_COMMIT` env var that Render exposes to all builds.
var gitCommit = ""

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatal(err)
	}

	ctx := context.Background()
	pool, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatal("db connect: ", err)
	}
	defer pool.Close()

	if err := db.Migrate(ctx, pool); err != nil {
		log.Fatal("migrate: ", err)
	}

	// Services
	authSvc := auth.NewService(pool, cfg)
	userSvc := user.NewService(pool)
	favSvc := favorites.NewService(pool)
	historySvc := history.NewService(pool)

	s3Host := strings.TrimPrefix(strings.TrimPrefix(cfg.S3Endpoint, "https://"), "http://")
	uploadSvc, err := uploads.NewService(pool, s3Host, cfg.S3AccessKey, cfg.S3SecretKey, cfg.S3Bucket)
	if err != nil {
		log.Fatal("uploads init: ", err)
	}

	// Providers
	var spotifyRef *provider.Spotify
	var providers []provider.MusicProvider
	if cfg.SpotifyClientID != "" {
		sp := provider.NewSpotifyWithCreds(cfg.SpotifyClientID, cfg.SpotifySecret, cfg.SpotifyUsername, cfg.SpotifyPassword, cfg.SpotifyCredsBlob)
		spotifyRef = sp
		providers = append(providers, sp)
	}
	providers = append(providers, provider.NewYouTube(cfg.GeniusToken))
	if cfg.SoundCloudID != "" {
		providers = append(providers, provider.NewSoundCloud(cfg.SoundCloudID, cfg.SoundCloudSecret))
	}
	providers = append(providers, provider.NewDeezerWithARL(cfg.GeniusToken, cfg.DeezerARL))
	if cfg.YandexToken != "" {
		providers = append(providers, provider.NewYandexWithOptions(cfg.YandexToken, cfg.YandexSignKey, cfg.YandexProxyURL))
		log.Printf("music provider: yandex enabled (proxy=%v)", cfg.YandexProxyURL != "")
	}
	vkToken := cfg.VKAccessToken
	if vkToken == "" {
		vkToken = cfg.VKToken
	}
	if vkToken != "" {
		providers = append(providers, provider.NewVKMusic(vkToken))
		if cfg.VKAccessToken == "" {
			log.Printf("music provider: vk enabled with service token — stream URLs need VK_ACCESS_TOKEN (user OAuth, audio scope)")
		} else {
			log.Printf("music provider: vk enabled")
		}
	}
	musicSvc := music.NewService(providers...)
	if cfg.SoundCloudSecret == "" {
		log.Printf("[config] WARN SOUNDCLOUD_CLIENT_SECRET is empty — SoundCloud API may return 401/timeouts")
	} else {
		log.Printf("[config] SoundCloud OAuth configured (client_id len=%d)", len(cfg.SoundCloudID))
		go func() {
			probeCtx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
			defer cancel()
			if sc := musicSvc.SoundCloudProvider(); sc != nil {
				if _, err := sc.Search(probeCtx, "sphere", 1); err != nil {
					log.Printf("[config] WARN SoundCloud probe search failed: %v", err)
				} else {
					log.Printf("[config] SoundCloud probe search OK")
				}
			}
		}()
	}
	if cfg.DeezerARL == "" {
		log.Printf("[config] DEEZER_ARL is empty — Deezer plays 30s previews; full tracks use Spotify/SC/YT fallback")
	} else {
		log.Printf("[config] Deezer full-track session enabled (ARL set)")
	}
	if sp := musicSvc.SpotifyProvider(); sp != nil && sp.HasFullTrackSession() {
		log.Printf("[config] Spotify Connect configured (full-track /audio proxy for Deezer catalog)")
	} else {
		log.Printf("[config] WARN SPOTIFY_CREDS_BLOB unset — Deezer tracks cannot use Spotify fallback")
	}
	if strings.TrimSpace(os.Getenv("YTDLP_COOKIES")) == "" && strings.TrimSpace(os.Getenv("YTDLP_COOKIES_B64")) == "" {
		log.Printf("[config] WARN YTDLP_COOKIES* unset — YouTube extraction may fail on Render (bot/OOM)")
	}
	music.SetGeniusToken(cfg.GeniusToken)
	prefsSvc := preferences.NewService(pool)
	recommendSvc := recommend.NewService(pool, historySvc, musicSvc, prefsSvc, favSvc, spotifyRef)
	commentsSvc, err := comments.NewService(pool, cfg)
	if err != nil {
		log.Fatal("comments init: ", err)
	}

	chatHub := chat.NewHub()
	chatSvc, err := chat.NewService(pool, cfg, chatHub)
	if err != nil {
		log.Fatal("chat init: ", err)
	}
	socialSvc := social.NewService(pool)

	// Handlers
	authH := auth.NewHandler(authSvc, cfg)
	accountH := auth.NewAccountHandler(authSvc, userSvc, uploadSvc, cfg)
	userH := user.NewHandler(userSvc)
	musicH := music.NewHandlerWithDB(musicSvc, pool, cfg.GeniusToken)
	favH := favorites.NewHandlerWithMusic(favSvc, musicSvc)
	uploadH := uploads.NewHandler(uploadSvc)
	historyH := history.NewHandler(historySvc)
	recommendH := recommend.NewHandler(recommendSvc)
	prefsH := preferences.NewHandler(prefsSvc)
	commentsH := comments.NewHandler(commentsSvc)
	socialH := social.NewHandler(socialSvc, favSvc, historySvc)
	chatH := chat.NewHandler(chatSvc, chatHub, cfg.JWTSecret)
	playlistSvc := playlist.NewService(pool)
	jamSvc := jam.NewService(pool)
	waveSvc := wave.NewService(pool, historySvc, favSvc, musicSvc, spotifyRef)
	listenSvc := listen.NewService(pool)
	playlistH := playlist.NewHandler(playlistSvc, chatHub.BroadcastJSON)
	jamH := jam.NewHandler(jamSvc, chatHub.BroadcastJSON)
	waveH := wave.NewHandler(waveSvc)
	listenH := listen.NewHandler(listenSvc, chatHub.BroadcastJSON)
	updatesH := updates.NewHandler(pool)
	adminH := admin.NewHandler(pool)

	// NodeX Karaoke
	var s3Client = uploadSvc.S3Client()
	karaokeSvc := karaoke.NewService(pool, s3Client, cfg.S3Bucket, musicSvc)
	karaokeH := karaoke.NewHandler(karaokeSvc)

	// Blend
	blendSvc := blend.NewService(pool, historySvc, favSvc, musicSvc, spotifyRef)
	blendH := blend.NewHandler(blendSvc, chatHub.BroadcastJSON)

	// Cross-provider track mapping
	crossmapSvc := crossmap.NewService(pool, musicSvc)
	crossmapH := crossmap.NewHandler(crossmapSvc)

	// Push notifications
	notifSvc := notifications.NewService(pool, cfg.APNsKeyID, cfg.APNsTeamID, cfg.APNsBundleID, cfg.APNsKeyB64)
	notifH := notifications.NewHandler(notifSvc)

	// Scheduler (availability guard)
	sched := scheduler.New(pool, musicSvc, crossmapSvc, notifSvc, blendSvc)
	sched.Start()
	defer sched.Stop()

	// Router
	r := chi.NewRouter()
	r.Use(chimw.Logger)
	r.Use(chimw.Recoverer)
	r.Use(chimw.RealIP)
	r.Use(middleware.CORS([]string{
		"http://localhost:3001",
		"http://127.0.0.1:3001",
		"https://spheremusic.space",
		"https://www.spheremusic.space",
	}))

	r.Get("/health", func(w http.ResponseWriter, _ *http.Request) {
		w.Write([]byte(`{"status":"ok"}`))
	})

	// /version exposes the build's git commit (set via -ldflags '-X main.gitCommit=<sha>'
	// or via the `RENDER_GIT_COMMIT` env var that Render injects automatically).
	// Useful for verifying which revision is actually running in production.
	r.Get("/version", func(w http.ResponseWriter, _ *http.Request) {
		commit := strings.TrimSpace(gitCommit)
		if commit == "" {
			commit = strings.TrimSpace(os.Getenv("RENDER_GIT_COMMIT"))
		}
		if commit == "" {
			commit = "unknown"
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"commit":"` + commit + `"}`))
	})

	// Auth (public)
	r.Get("/auth/public-config", authH.PublicConfig)
	r.Get("/auth/recaptcha-embed", authH.RecaptchaEmbedPage)
	r.Post("/auth/signup-code", authH.SendSignupCode)
	r.Post("/auth/register", authH.Register)
	r.Post("/auth/login", authH.Login)
	r.Post("/auth/2fa/verify", authH.TwoFactorVerify)
	r.Post("/auth/google", authH.Google)

	r.Post("/auth/qr/start", authH.QRLoginStart)
	r.Get("/auth/qr/poll", authH.QRLoginPoll)

	r.Get("/public/avatar/{userID}/{filename}", accountH.PublicAvatar)

	// Music endpoints (public — no auth required for testing)
	r.Get("/search", musicH.Search)
	r.Get("/tracks/{provider}/{id}", musicH.GetTrack)
	r.Get("/tracks/{provider}/{id}/stream", musicH.GetTrackStream)
	r.Get("/tracks/{provider}/{id}/audio", musicH.ProxyStream)
	r.Get("/tracks/{provider}/{id}/audio/hq", musicH.ProxyStreamHQ)
	r.Get("/tracks/{provider}/{id}/lyrics", musicH.GetLyrics)
	r.With(middleware.OptionalJWTAuth(cfg.JWTSecret)).Get("/tracks/{provider}/{id}/comments", commentsH.List)
	r.Get("/lyrics", musicH.GetLyricsByName)
	r.Get("/artists/{provider}/{id}", musicH.GetArtist)
	r.Get("/artists/{provider}/{id}/albums", musicH.GetArtistAlbums)
	r.Get("/artists/{provider}/{id}/fans-also-like", musicH.FansAlsoLike)
	r.Get("/artists/unified/{name}", musicH.GetUnifiedArtist)
	r.Get("/albums/{provider}/{id}", musicH.GetAlbum)
	r.Get("/playlists/{provider}/{id}", musicH.GetPlaylist)

	// Public: latest app update
	r.Get("/updates/latest", updatesH.LatestUpdate)

	// Chat WebSocket (auth via ?token=JWT)
	r.Get("/ws", chatH.WS)

	// Protected routes (require JWT)
	r.Group(func(r chi.Router) {
		r.Use(middleware.JWTAuth(cfg.JWTSecret))

		r.Get("/user/me", userH.GetMe)
		r.Put("/user/me", userH.UpdateMe)

		r.Post("/account/change-password", accountH.ChangePassword)
		r.Post("/account/change-email/start", accountH.ChangeEmailStart)
		r.Post("/account/change-email/confirm", accountH.ChangeEmailConfirm)
		r.Post("/account/avatar", accountH.UploadAvatar)

		r.Post("/account/2fa/totp/setup", accountH.TOTPSetup)
		r.Post("/account/2fa/totp/enable", accountH.TOTPEnable)
		r.Post("/account/2fa/totp/disable", accountH.TOTPDisable)
		r.Post("/account/2fa/email/enable", accountH.Email2FAEnable)
		r.Post("/account/2fa/email/disable", accountH.Email2FADisable)
		r.Patch("/account/privacy", accountH.UpdatePrivacy)

		r.Post("/auth/qr/approve", authH.QRApprove)

		r.With(middleware.AdminOnly(pool)).Get("/admin/users", adminH.ListUsers)
		r.With(middleware.AdminOnly(pool)).Get("/admin/users/{id}", adminH.GetUser)
		r.With(middleware.AdminOnly(pool)).Post("/admin/users/{id}/ban", adminH.Ban)
		r.With(middleware.AdminOnly(pool)).Post("/admin/users/{id}/unban", adminH.Unban)
		r.With(middleware.AdminOnly(pool)).Put("/admin/users/{id}/verified", adminH.SetVerified)
		r.With(middleware.AdminOnly(pool)).Put("/admin/users/{id}/badge", adminH.SetBadge)

		r.Get("/user/preferences", prefsH.Get)
		r.Post("/user/preferences", prefsH.Save)

		r.Get("/recommendations", recommendH.Get)
		r.Get("/daily-mixes", recommendH.DailyMixes)
		r.Get("/history", historyH.List)
		r.Post("/history", historyH.Record)

		r.Get("/favorites", favH.List)
		r.Post("/favorites", favH.Add)
		r.Delete("/favorites/{id}", favH.Delete)
		r.Get("/playlists/liked", favH.LikedPlaylist)

		// Offline downloads
		r.Get("/tracks/{provider}/{id}/download", musicH.DownloadTrack)
		r.Get("/playlists/{provider}/{id}/download-manifest", musicH.PlaylistDownloadManifest)
		r.Get("/albums/{provider}/{id}/download-manifest", musicH.AlbumDownloadManifest)

		// NodeX Karaoke (vocal removal)
		r.Post("/tracks/{provider}/{id}/karaoke/prepare", karaokeH.Prepare)
		r.Get("/tracks/{provider}/{id}/karaoke", karaokeH.Stream)

		// Cross-provider track mapping
		r.Get("/tracks/{provider}/{id}/alternatives", crossmapH.Alternatives)
		r.Get("/tracks/{provider}/{id}/best-source", crossmapH.BestSource)
		r.Post("/tracks/match", crossmapH.BatchMatch)
		r.Post("/user/track-source", crossmapH.SetPreferred)

		// Push notifications
		r.Post("/devices", notifH.Register)
		r.Delete("/devices/{token}", notifH.Unregister)
		r.Get("/notifications", notifH.History)

		r.Post("/tracks/{provider}/{id}/comments", commentsH.Create)
		r.Post("/comments/{id}/vote", commentsH.Vote)
		r.Post("/lyrics", musicH.SubmitLyrics)

		r.Post("/uploads", uploadH.Upload)
		r.Get("/uploads", uploadH.List)
		r.Get("/uploads/{id}/stream", uploadH.Stream)
		r.Delete("/uploads/{id}", uploadH.Delete)

		// Social/profile
		r.Get("/users/search", socialH.SearchUsers)
		r.Get("/users/{id}/profile", socialH.GetProfile)
		r.Get("/users/{id}/favorites", socialH.GetUserFavorites)
		r.Get("/users/{id}/history", socialH.GetUserHistory)
		r.Get("/users/{id}/subscriptions", socialH.ListSubscriptions)
		r.Get("/users/{id}/subscribers", socialH.ListSubscribers)
		r.Post("/users/{id}/subscribe", socialH.Subscribe)
		r.Delete("/users/{id}/subscribe", socialH.Unsubscribe)

		r.Get("/me/subscription-requests", socialH.ListIncomingRequests)
		r.Post("/me/subscription-requests/{requestID}/approve", socialH.ApproveRequest)
		r.Post("/me/subscription-requests/{requestID}/deny", socialH.DenyRequest)

		// Chat REST
		r.Get("/chats", chatH.ListChats)
		r.Post("/chats", chatH.OpenOrCreateDM)
		r.Get("/chats/{id}/messages", chatH.ListMessages)
		r.Post("/chats/{id}/messages", chatH.SendMessage)
		r.Get("/chats/{id}/streak", chatH.GetStreak)

		// Listen-together sessions
		r.Post("/listen/sessions", listenH.Create)
		r.Get("/listen/sessions/{id}", listenH.Get)
		r.Post("/listen/sessions/{id}/join", listenH.Join)
		r.Post("/listen/sessions/{id}/leave", listenH.Leave)
		r.Post("/listen/sessions/{id}/invite", listenH.Invite)
		r.Post("/listen/sessions/{id}/sync", listenH.Sync)
		r.Post("/listen/sessions/{id}/webrtc", listenH.WebRTCSignal)
		r.Delete("/listen/sessions/{id}", listenH.End)

		// Group playlists
		r.Post("/playlists/create", playlistH.Create)
		r.Get("/playlists/mine", playlistH.ListMine)
		r.Get("/playlists/user/{id}", playlistH.GetByID)
		r.Put("/playlists/user/{id}", playlistH.Update)
		r.Delete("/playlists/user/{id}", playlistH.Delete)
		r.Post("/playlists/user/{id}/tracks", playlistH.AddTrack)
		r.Delete("/playlists/user/{id}/tracks/{trackID}", playlistH.RemoveTrack)
		r.Put("/playlists/user/{id}/tracks/reorder", playlistH.ReorderTracks)
		r.Post("/playlists/user/{id}/members", playlistH.AddMember)
		r.Delete("/playlists/user/{id}/members/{userID}", playlistH.RemoveMember)
		r.Get("/playlists/user/{id}/members", playlistH.ListMembers)

		// Playlist suggestions, votes, activity
		r.Post("/playlists/user/{id}/suggestions", playlistH.SuggestTrack)
		r.Get("/playlists/user/{id}/suggestions", playlistH.ListSuggestions)
		r.Post("/playlists/user/{id}/suggestions/{suggestionID}/approve", playlistH.ApproveSuggestion)
		r.Post("/playlists/user/{id}/suggestions/{suggestionID}/reject", playlistH.RejectSuggestion)
		r.Post("/playlists/user/{id}/tracks/{trackID}/vote", playlistH.VoteTrack)
		r.Get("/playlists/user/{id}/activity", playlistH.ListActivity)

		// Blend (taste-merged playlists)
		r.Post("/blends", blendH.Create)
		r.Get("/blends", blendH.ListMine)
		r.Get("/blends/{id}", blendH.GetByID)
		r.Delete("/blends/{id}", blendH.Delete)
		r.Post("/blends/{id}/accept", blendH.AcceptInvite)
		r.Post("/blends/{id}/decline", blendH.DeclineInvite)
		r.Post("/blends/{id}/regenerate", blendH.Regenerate)

		// Jam (group listening with queue)
		r.Post("/jam/sessions", jamH.Create)
		r.Get("/jam/sessions/{id}", jamH.Get)
		r.Post("/jam/sessions/{id}/join", jamH.Join)
		r.Post("/jam/sessions/{id}/leave", jamH.Leave)
		r.Delete("/jam/sessions/{id}", jamH.End)
		r.Post("/jam/sessions/{id}/queue", jamH.AddToQueue)
		r.Delete("/jam/sessions/{id}/queue/{itemID}", jamH.RemoveFromQueue)
		r.Post("/jam/sessions/{id}/queue/{itemID}/vote", jamH.VoteQueue)
		r.Get("/jam/sessions/{id}/queue", jamH.GetQueue)
		r.Post("/jam/sessions/{id}/sync", jamH.Sync)
		r.Post("/jam/sessions/{id}/next", jamH.PlayNext)
		r.Post("/jam/sessions/{id}/skip", jamH.Skip)
		r.Post("/jam/sessions/{id}/invite", jamH.Invite)

		// My Wave
		r.Post("/wave/start", waveH.StartSession)
		r.Get("/wave/next", waveH.NextTracks)
		r.Post("/wave/event", waveH.RecordEvent)
		r.Get("/wave/profile", waveH.GetProfile)
		r.Get("/wave/offline-package", waveH.GetOfflinePackage)
		r.Post("/wave/sync", waveH.SyncOfflineEvents)

		// Admin: updates management
		r.With(middleware.AdminOnly(pool)).Post("/admin/updates", updatesH.CreateUpdate)
		r.With(middleware.AdminOnly(pool)).Get("/admin/updates", updatesH.ListUpdates)

		// Admin: manual availability check
		r.With(middleware.AdminOnly(pool)).Post("/admin/jobs/check-availability", sched.TriggerAvailability)
	})

	// Server
	srv := &http.Server{
		Addr:    ":" + cfg.Port,
		Handler: r,
	}

	go func() {
		log.Printf("Sphere API listening on :%s", cfg.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal(err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	srv.Shutdown(ctx)
	log.Println("Server stopped")
}
