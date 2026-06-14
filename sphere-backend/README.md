# sphere-backend

## New endpoints (v6)

These endpoints back the redesigned iOS Node app. All require Bearer auth.

### Discover (swipe deck)

- `GET /discover/feed?limit=20&excluded=spotify:abc,deezer:xyz`
  Returns a randomized, deduped pool of catalog tracks for the swipe deck.
  Already-liked tracks are filtered out automatically.
  Response: `{ "tracks": [Track, ...], "cursor": "" }`.

- `POST /discover/feedback`
  Body: `{ "provider": "spotify", "id": "...", "action": "like|skip", "title": "...", "artist": "..." }`
  Likes are persisted via `/favorites` (the iOS client also calls that
  directly). Skips are recorded into `listen_history` with the `skipped` flag
  so the recommend engine can learn from them.

### Node Studio

- `GET /studio/summary`
  Returns the Node Studio dashboard snapshot:
  `listening_minutes`, `liked_tracks`, `recent_artists`, `top_genres`,
  `top_artists`, `history_entries`.

## Cloudflare Workers deploy (migration mode)

This repo currently contains a Go API server (`cmd/server`) that runs as a long-lived process.
Cloudflare Workers cannot run that server binary directly, so the first migration step is a
Worker proxy in `cloudflare/worker.js`.

### What was added

- `wrangler.toml`
- `cloudflare/worker.js`

The Worker forwards all requests to `BACKEND_ORIGIN` and returns the upstream response.

### Configure

Set Worker environment variable:

- `BACKEND_ORIGIN=https://<your-current-backend-origin>`

No trailing slash; HTTPS only.

### Deploy command

If your Cloudflare build root is the repository root, use:

`npx wrangler deploy -c sphere-backend/wrangler.toml`

If your build root is already `sphere-backend/`, use:

`npx wrangler deploy`

### Why your previous deploy failed

You ran `npx wrangler deploy` from a directory without `wrangler.toml` and without a Worker
entrypoint. Wrangler then tried to auto-detect a static assets directory and failed with:
"Could not detect a directory containing static files".
