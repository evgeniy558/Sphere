package recommend

import (
	"context"
	"log"
	"math"
	"sort"
	"sync"

	"github.com/jackc/pgx/v5/pgxpool"

	"sphere-backend/internal/model"
)

// FindSimilarUsers returns users whose listening history overlaps with the
// given genre/artist weight maps. It queries the DB directly — no local
// package dependencies on history or favorites.
func FindSimilarUsers(
	ctx context.Context,
	db *pgxpool.Pool,
	userID string,
	userGenres, userArtists map[string]float64,
	limit int,
) []model.SimilarUserInfo {
	if limit <= 0 {
		limit = 10
	}
	if len(userGenres) == 0 && len(userArtists) == 0 {
		return []model.SimilarUserInfo{}
	}

	// ---- step 1: candidate user IDs ----
	candidates, err := fetchCandidateIDs(ctx, db, userID)
	if err != nil {
		log.Printf("[similar] candidates query error: %v", err)
		return []model.SimilarUserInfo{}
	}
	if len(candidates) == 0 {
		return []model.SimilarUserInfo{}
	}

	// ---- step 2: compute similarity in parallel ----
	type scored struct {
		id    string
		score float64
		cGenres  map[string]float64
		cArtists map[string]float64
	}

	var (
		mu      sync.Mutex
		results []scored
		wg      sync.WaitGroup
		sem     = make(chan struct{}, 10)
	)

	for _, cid := range candidates {
		wg.Add(1)
		sem <- struct{}{}
		go func(candidateID string) {
			defer wg.Done()
			defer func() { <-sem }()

			cGenres, cArtists, err := fetchCandidateWeights(ctx, db, candidateID)
			if err != nil {
				log.Printf("[similar] weights error user=%s: %v", candidateID, err)
				return
			}

			genreOverlap := jaccardWeighted(userGenres, cGenres)
			artistOverlap := jaccardWeighted(userArtists, cArtists)
			score := genreOverlap*0.6 + artistOverlap*0.4

			if score < 0.1 {
				return
			}

			mu.Lock()
			results = append(results, scored{
				id:       candidateID,
				score:    score,
				cGenres:  cGenres,
				cArtists: cArtists,
			})
			mu.Unlock()
		}(cid)
	}
	wg.Wait()

	if len(results) == 0 {
		return []model.SimilarUserInfo{}
	}

	// ---- step 3: sort & trim ----
	sort.Slice(results, func(i, j int) bool {
		return results[i].score > results[j].score
	})
	if len(results) > limit {
		results = results[:limit]
	}

	// ---- step 4: enrich with profile info ----
	out := make([]model.SimilarUserInfo, 0, len(results))
	for _, r := range results {
		info, err := fetchUserProfile(ctx, db, r.id)
		if err != nil {
			log.Printf("[similar] profile fetch error user=%s: %v", r.id, err)
			continue
		}
		info.SimilarityScore = math.Round(r.score*100) / 100
		info.SharedGenres = sharedKeys(userGenres, r.cGenres)
		info.SharedArtists = sharedKeys(userArtists, r.cArtists)
		out = append(out, info)
	}
	return out
}

// ---------- helpers ----------

func fetchCandidateIDs(ctx context.Context, db *pgxpool.Pool, userID string) ([]string, error) {
	const q = `
		SELECT DISTINCT h.user_id
		FROM listen_history h
		JOIN users u ON u.id = h.user_id
		WHERE h.user_id != $1
		  AND u.banned = false
		  AND u.private_profile = false
		  AND h.listened_at > now() - interval '30 days'
		  AND NOT EXISTS (SELECT 1 FROM subscriptions WHERE follower_id = $1 AND followee_id = h.user_id)
		LIMIT 200`

	rows, err := db.Query(ctx, q, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

func fetchCandidateWeights(ctx context.Context, db *pgxpool.Pool, userID string) (map[string]float64, map[string]float64, error) {
	genres, err := fetchWeightMap(ctx, db, userID,
		`SELECT unnest(genres) AS g, COUNT(*) AS c
		 FROM listen_history
		 WHERE user_id = $1 AND listened_at > now() - interval '30 days'
		 GROUP BY g ORDER BY c DESC LIMIT 20`)
	if err != nil {
		return nil, nil, err
	}

	artists, err := fetchWeightMap(ctx, db, userID,
		`SELECT artist, COUNT(*) AS c
		 FROM listen_history
		 WHERE user_id = $1 AND listened_at > now() - interval '30 days' AND artist <> ''
		 GROUP BY artist ORDER BY c DESC LIMIT 15`)
	if err != nil {
		return nil, nil, err
	}

	return genres, artists, nil
}

// fetchWeightMap runs a query that returns (key TEXT, count INT) rows and
// normalises the counts to 0-1 by dividing by the max count.
func fetchWeightMap(ctx context.Context, db *pgxpool.Pool, userID, query string) (map[string]float64, error) {
	rows, err := db.Query(ctx, query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	type pair struct {
		key   string
		count float64
	}
	var pairs []pair
	var maxCount float64

	for rows.Next() {
		var k string
		var c int64
		if err := rows.Scan(&k, &c); err != nil {
			return nil, err
		}
		fc := float64(c)
		pairs = append(pairs, pair{key: k, count: fc})
		if fc > maxCount {
			maxCount = fc
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	m := make(map[string]float64, len(pairs))
	if maxCount == 0 {
		return m, nil
	}
	for _, p := range pairs {
		m[p.key] = p.count / maxCount
	}
	return m, nil
}

func fetchUserProfile(ctx context.Context, db *pgxpool.Pool, userID string) (model.SimilarUserInfo, error) {
	const q = `SELECT id, username, COALESCE(name,''), COALESCE(avatar_url,''), is_verified
	            FROM users WHERE id = $1`
	var info model.SimilarUserInfo
	err := db.QueryRow(ctx, q, userID).Scan(
		&info.ID, &info.Username, &info.Name, &info.AvatarURL, &info.IsVerified,
	)
	return info, err
}

// jaccardWeighted computes sum(min(a,b)) / sum(max(a,b)) over the union of keys.
func jaccardWeighted(a, b map[string]float64) float64 {
	if len(a) == 0 && len(b) == 0 {
		return 0
	}

	union := make(map[string]struct{}, len(a)+len(b))
	for k := range a {
		union[k] = struct{}{}
	}
	for k := range b {
		union[k] = struct{}{}
	}

	var num, den float64
	for k := range union {
		va := a[k]
		vb := b[k]
		num += math.Min(va, vb)
		den += math.Max(va, vb)
	}
	if den == 0 {
		return 0
	}
	return num / den
}

// sharedKeys returns the keys present in both maps.
func sharedKeys(a, b map[string]float64) []string {
	var shared []string
	for k := range a {
		if _, ok := b[k]; ok {
			shared = append(shared, k)
		}
	}
	sort.Strings(shared)
	return shared
}
