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

## Render deploy: database connection failed

If deploy logs show:

```text
db connect: ping db: failed to connect to `user=postgres.<ref> database=postgres`:
  ... pooler.supabase.com ... FATAL: (ENOTFOUND) tenant/user postgres.<ref> not found
```

the Docker image built successfully, but the service **crashes on startup** because
`DATABASE_URL` points at a Supabase project that no longer exists (deleted, paused, or wrong ref).

The iOS app uses Supabase project **`dsgjedfenefzcjatfacj`** (`AuthService.swift`). If Render
still has a stale password or wrong pooler host, update it:

1. Open [Supabase Dashboard](https://supabase.com/dashboard) → project **dsgjedfenefzcjatfacj**
2. **Project Settings → Database → Connection string**
3. Choose **Transaction pooler** (port **6543**) or **Session pooler** (port **5432**)
4. Copy the URI (starts with `postgresql://postgres.dsgjedfenefzcjatfacj:…`)
5. In [Render Dashboard](https://dashboard.render.com) → **sphere-api** → **Environment**
6. Set **`DATABASE_URL`** to that URI → **Save, rebuild & deploy**

Alternative: use Render Postgres from `render.yaml` (`sphere-db`) and wire
`DATABASE_URL` via `fromDatabase` instead of Supabase. Remove any manual Supabase override
in the Dashboard so the Blueprint link wins.

After a successful deploy, `GET /health` should return `{"status":"ok"}` within ~30s.
