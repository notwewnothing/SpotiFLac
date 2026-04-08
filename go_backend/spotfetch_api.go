package gobackend

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

const DefaultSpotFetchAPIBaseURL = "https://sp.afkarxyz.qzz.io/api"

// GetSpotifyDataWithAPI fetches Spotify metadata through SpotFetch-compatible API.
// This is used as a fallback when direct Spotify API access is blocked/limited.
func GetSpotifyDataWithAPI(ctx context.Context, spotifyURL, apiBaseURL string) (interface{}, error) {
	parsed, err := parseSpotifyURI(spotifyURL)
	if err != nil {
		return nil, fmt.Errorf("invalid Spotify URL: %w", err)
	}

	base := strings.TrimSpace(apiBaseURL)
	if base == "" {
		base = DefaultSpotFetchAPIBaseURL
	}

	endpoint := fmt.Sprintf("%s/%s/%s", strings.TrimSuffix(base, "/"), parsed.Type, parsed.ID)
	req, err := http.NewRequestWithContext(ctx, "GET", endpoint, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create SpotFetch API request: %w", err)
	}
	req.Header.Set("User-Agent", getRandomUserAgent())
	req.Header.Set("Accept", "application/json")

	client := NewHTTPClientWithTimeout(30 * time.Second)
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("SpotFetch API request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("SpotFetch API error: HTTP %d", resp.StatusCode)
	}

	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read SpotFetch API response: %w", err)
	}

	switch parsed.Type {
	case "track":
		var trackResp TrackResponse
		if err := json.Unmarshal(bodyBytes, &trackResp); err != nil {
			return nil, fmt.Errorf("failed to decode track response: %w", err)
		}
		return trackResp, nil
	case "album":
		var albumResp AlbumResponsePayload
		if err := json.Unmarshal(bodyBytes, &albumResp); err != nil {
			return nil, fmt.Errorf("failed to decode album response: %w", err)
		}
		return &albumResp, nil
	case "playlist":
		var playlistResp PlaylistResponsePayload
		if err := json.Unmarshal(bodyBytes, &playlistResp); err != nil {
			return nil, fmt.Errorf("failed to decode playlist response: %w", err)
		}
		return playlistResp, nil
	case "artist":
		var artistResp ArtistResponsePayload
		if err := json.Unmarshal(bodyBytes, &artistResp); err != nil {
			return nil, fmt.Errorf("failed to decode artist response: %w", err)
		}
		return &artistResp, nil
	default:
		return nil, fmt.Errorf("unsupported Spotify type: %s", parsed.Type)
	}
}
