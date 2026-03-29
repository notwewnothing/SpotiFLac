package gobackend

import (
	"strings"
	"unicode"
)

// normalizeLooseTitle collapses separators/punctuation so titles like
// "Doctor / Cops" and "Doctor _ Cops" can still match.
func normalizeLooseTitle(title string) string {
	trimmed := strings.TrimSpace(strings.ToLower(title))
	if trimmed == "" {
		return ""
	}

	var b strings.Builder
	b.Grow(len(trimmed))

	for _, r := range trimmed {
		switch {
		case unicode.IsLetter(r), unicode.IsNumber(r):
			b.WriteRune(r)
		case unicode.IsSpace(r):
			b.WriteByte(' ')
		// Treat common separators as spaces.
		case r == '/', r == '\\', r == '_', r == '-', r == '|', r == '.', r == '&', r == '+':
			b.WriteByte(' ')
		default:
			// Drop other punctuation/symbols (including emoji) for loose matching.
		}
	}

	return strings.Join(strings.Fields(b.String()), " ")
}

func hasAlphaNumericRunes(value string) bool {
	for _, r := range value {
		if unicode.IsLetter(r) || unicode.IsNumber(r) {
			return true
		}
	}
	return false
}

// normalizeSymbolOnlyTitle keeps symbol/emoji runes while dropping letters,
// digits, spaces and punctuation. This is useful for emoji-only titles such as
// "🪐", "🌎" etc, so we can compare them strictly and avoid false matches.
func normalizeSymbolOnlyTitle(title string) string {
	trimmed := strings.TrimSpace(strings.ToLower(title))
	if trimmed == "" {
		return ""
	}

	var b strings.Builder
	b.Grow(len(trimmed))

	for _, r := range trimmed {
		switch {
		case unicode.IsLetter(r), unicode.IsNumber(r), unicode.IsSpace(r), unicode.IsPunct(r):
			continue
		// Drop combining marks such as emoji variation selectors.
		case unicode.Is(unicode.Mn, r), unicode.Is(unicode.Mc, r), unicode.Is(unicode.Me, r):
			continue
		default:
			b.WriteRune(r)
		}
	}

	return b.String()
}

// ==================== Shared Track Verification ====================

// resolvedTrackInfo holds the metadata fetched from a provider for verification.
type resolvedTrackInfo struct {
	Title      string
	ArtistName string
	Duration   int // seconds
}

// trackMatchesRequest checks whether a resolved track from a provider matches
// the original download request. Returns true if the track is a plausible match.
func trackMatchesRequest(req DownloadRequest, resolved resolvedTrackInfo, logPrefix string) bool {
	if req.ArtistName != "" && resolved.ArtistName != "" &&
		!artistsMatch(req.ArtistName, resolved.ArtistName) {
		GoLog("[%s] Verification failed: artist mismatch — expected '%s', got '%s'\n",
			logPrefix, req.ArtistName, resolved.ArtistName)
		return false
	}

	if req.TrackName != "" && resolved.Title != "" &&
		!titlesMatch(req.TrackName, resolved.Title) {
		GoLog("[%s] Verification failed: title mismatch — expected '%s', got '%s'\n",
			logPrefix, req.TrackName, resolved.Title)
		return false
	}

	expectedDurationSec := req.DurationMS / 1000
	if expectedDurationSec > 0 && resolved.Duration > 0 {
		diff := expectedDurationSec - resolved.Duration
		if diff < 0 {
			diff = -diff
		}
		if diff > 10 {
			GoLog("[%s] Verification failed: duration mismatch — expected %ds, got %ds\n",
				logPrefix, expectedDurationSec, resolved.Duration)
			return false
		}
	}

	return true
}
