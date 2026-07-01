package crossmap

import (
	"crypto/sha256"
	"fmt"
	"math"
	"regexp"
	"strings"
	"unicode"
)

// Confidence threshold for accepting a cross-provider match.
const MatchThreshold = 0.75

// Quality ranking: higher = better.
var qualityRank = map[string]int{
	"flac":    100,
	"mp3_320": 90,
	"ogg_320": 85,
	"mp3_192": 70,
	"ogg_160": 65,
	"aac_128": 55,
	"mp3_128": 50,
	"ogg_96":  40,
	"":        0,
}

// Known provider quality capabilities.
var providerDefaultCodec = map[string]string{
	"spotify":    "ogg_320",
	"deezer":     "mp3_320",
	"youtube":    "aac_128",
	"soundcloud": "mp3_128",
	"yandex":     "mp3_192",
	"vk":         "mp3_192",
}

// junkPatterns are removed from titles for normalization.
var junkPatterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)\(official\s*(music\s*)?video\)`),
	regexp.MustCompile(`(?i)\(official\s*audio\)`),
	regexp.MustCompile(`(?i)\(lyric[s]?\s*video\)`),
	regexp.MustCompile(`(?i)\(visuali[sz]er\)`),
	regexp.MustCompile(`(?i)\[official\s*(music\s*)?video\]`),
	regexp.MustCompile(`(?i)\[lyric[s]?\]`),
	regexp.MustCompile(`(?i)\(feat\.?\s*[^)]+\)`),
	regexp.MustCompile(`(?i)\(ft\.?\s*[^)]+\)`),
	regexp.MustCompile(`(?i)\s*-\s*topic$`),
	regexp.MustCompile(`(?i)\(audio\)`),
	regexp.MustCompile(`(?i)\(hd\)`),
	regexp.MustCompile(`(?i)\(hq\)`),
}

// NormalizeTitle cleans up a track title for matching.
func NormalizeTitle(s string) string {
	s = strings.TrimSpace(s)
	for _, re := range junkPatterns {
		s = re.ReplaceAllString(s, "")
	}
	s = strings.TrimSpace(s)
	// Remove extra whitespace.
	s = regexp.MustCompile(`\s+`).ReplaceAllString(s, " ")
	// Lowercase.
	return strings.ToLower(s)
}

// NormalizeArtist cleans up an artist name.
func NormalizeArtist(s string) string {
	s = strings.TrimSpace(s)
	// Remove "- Topic" suffix (YouTube auto-generated channels).
	s = regexp.MustCompile(`(?i)\s*-\s*topic$`).ReplaceAllString(s, "")
	s = strings.TrimSpace(s)
	return strings.ToLower(s)
}

// CanonicalHash produces a deterministic key for grouping the same track across providers.
func CanonicalHash(artist, title string) string {
	key := NormalizeArtist(artist) + "|" + NormalizeTitle(title)
	h := sha256.Sum256([]byte(key))
	return fmt.Sprintf("%x", h[:16]) // 32 hex chars
}

// MatchConfidence computes a similarity score [0, 1] between two tracks.
func MatchConfidence(title1, artist1 string, dur1 int,
	title2, artist2 string, dur2 int) float64 {

	t1 := NormalizeTitle(title1)
	t2 := NormalizeTitle(title2)
	a1 := NormalizeArtist(artist1)
	a2 := NormalizeArtist(artist2)

	titleSim := stringSimilarity(t1, t2)
	artistSim := stringSimilarity(a1, a2)

	var durationSim float64
	if dur1 > 0 && dur2 > 0 {
		diff := math.Abs(float64(dur1 - dur2))
		maxDur := math.Max(float64(dur1), float64(dur2))
		durationSim = math.Max(0, 1.0-diff/maxDur)
	} else {
		durationSim = 0.5 // neutral when unknown
	}

	return titleSim*0.4 + artistSim*0.3 + durationSim*0.3
}

// QualityScore returns a numeric score for a codec string (higher = better).
func QualityScore(codec string) int {
	codec = strings.ToLower(strings.TrimSpace(codec))
	if score, ok := qualityRank[codec]; ok {
		return score
	}
	return 0
}

// DefaultCodecForProvider returns the expected codec for a provider.
func DefaultCodecForProvider(provider string) string {
	if c, ok := providerDefaultCodec[strings.ToLower(provider)]; ok {
		return c
	}
	return ""
}

// stringSimilarity computes Jaro-Winkler-like similarity between two strings.
func stringSimilarity(a, b string) float64 {
	if a == b {
		return 1.0
	}
	if len(a) == 0 || len(b) == 0 {
		return 0.0
	}

	// Simple: use longest common subsequence ratio.
	lcs := longestCommonSubsequence(a, b)
	return float64(lcs) / math.Max(float64(len(a)), float64(len(b)))
}

// longestCommonSubsequence returns the length of the LCS of two strings.
func longestCommonSubsequence(a, b string) int {
	ra := []rune(a)
	rb := []rune(b)
	m, n := len(ra), len(rb)

	// Space-optimized LCS.
	prev := make([]int, n+1)
	curr := make([]int, n+1)

	for i := 1; i <= m; i++ {
		for j := 1; j <= n; j++ {
			if unicode.ToLower(ra[i-1]) == unicode.ToLower(rb[j-1]) {
				curr[j] = prev[j-1] + 1
			} else {
				curr[j] = max(prev[j], curr[j-1])
			}
		}
		prev, curr = curr, prev
		for j := range curr {
			curr[j] = 0
		}
	}
	return prev[n]
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}
