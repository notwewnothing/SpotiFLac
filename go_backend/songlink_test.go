package gobackend

import (
	"io"
	"net/http"
	"strings"
	"testing"
)

type roundTripFunc func(*http.Request) (*http.Response, error)

func (fn roundTripFunc) RoundTrip(req *http.Request) (*http.Response, error) {
	return fn(req)
}

func TestGetRetryAfterDurationMissingHeaderReturnsZero(t *testing.T) {
	resp := &http.Response{
		Header: make(http.Header),
	}

	if got := getRetryAfterDuration(resp); got != 0 {
		t.Fatalf("getRetryAfterDuration() = %v, want 0", got)
	}
}

func TestCheckTrackAvailabilityFromSpotifyPrefersSongLinkPage(t *testing.T) {
	client := &SongLinkClient{
		client: &http.Client{
			Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
				switch {
				case req.URL.Host == "api.song.link":
					t.Fatalf("api.song.link should not be called when song.link page succeeds")
					return nil, nil
				case req.URL.Host == "song.link" && req.URL.Path == "/s/testspotifyid":
					body := `<!DOCTYPE html><html><body><script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"pageData":{"sections":[{"displayName":"Listen","links":[{"platform":"spotify","url":"https://open.spotify.com/track/testspotifyid","show":true},{"platform":"deezer","url":"https://www.deezer.com/track/908604612","show":true},{"platform":"amazonMusic","url":"https://music.amazon.com/albums/B086Q2QNLH?trackAsin=B086Q41M9C","show":true},{"platform":"tidal","url":"https://listen.tidal.com/track/134858527","show":true},{"platform":"qobuz","url":"https://open.qobuz.com/track/195125822","show":true},{"platform":"youtubeMusic","url":"https://music.youtube.com/watch?v=testvideoid1","show":true}]}]}}}}</script></body></html>`
					return &http.Response{
						StatusCode: 200,
						Header:     make(http.Header),
						Body:       io.NopCloser(strings.NewReader(body)),
						Request:    req,
					}, nil
				default:
					t.Fatalf("unexpected request: %s", req.URL.String())
					return nil, nil
				}
			}),
		},
	}

	availability, err := client.CheckTrackAvailability("testspotifyid", "")
	if err != nil {
		t.Fatalf("CheckTrackAvailability() error = %v", err)
	}

	if availability.SpotifyID != "testspotifyid" {
		t.Fatalf("SpotifyID = %q, want %q", availability.SpotifyID, "testspotifyid")
	}
	if !availability.Deezer || availability.DeezerID != "908604612" {
		t.Fatalf("Deezer availability = %+v, want DeezerID 908604612", availability)
	}
	if !availability.Amazon || !availability.Tidal || !availability.Qobuz || !availability.YouTube {
		t.Fatalf("availability flags = %+v, want Amazon/Tidal/Qobuz/YouTube true", availability)
	}
	if availability.YouTubeID != "testvideoid1" {
		t.Fatalf("YouTubeID = %q, want %q", availability.YouTubeID, "testvideoid1")
	}
}

func TestCheckTrackAvailabilityFromSpotifyFallsBackToAPIWhenPageFails(t *testing.T) {
	origRetryConfig := songLinkRetryConfig
	songLinkRetryConfig = func() RetryConfig {
		return RetryConfig{
			MaxRetries:    0,
			InitialDelay:  0,
			MaxDelay:      0,
			BackoffFactor: 1,
		}
	}
	defer func() {
		songLinkRetryConfig = origRetryConfig
	}()

	client := &SongLinkClient{
		client: &http.Client{
			Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
				switch {
				case req.URL.Host == "song.link" && req.URL.Path == "/s/testspotifyid":
					return &http.Response{
						StatusCode: 500,
						Header:     make(http.Header),
						Body:       io.NopCloser(strings.NewReader("page failure")),
						Request:    req,
					}, nil
				case req.URL.Host == "api.song.link":
					body := `{"linksByPlatform":{"spotify":{"url":"https://open.spotify.com/track/testspotifyid"},"deezer":{"url":"https://www.deezer.com/track/908604612"},"amazonMusic":{"url":"https://music.amazon.com/albums/B086Q2QNLH?trackAsin=B086Q41M9C"},"tidal":{"url":"https://listen.tidal.com/track/134858527"},"qobuz":{"url":"https://open.qobuz.com/track/195125822"},"youtubeMusic":{"url":"https://music.youtube.com/watch?v=testvideoid1"}}}`
					return &http.Response{
						StatusCode: 200,
						Header:     make(http.Header),
						Body:       io.NopCloser(strings.NewReader(body)),
						Request:    req,
					}, nil
				default:
					t.Fatalf("unexpected request: %s", req.URL.String())
					return nil, nil
				}
			}),
		},
	}

	availability, err := client.CheckTrackAvailability("testspotifyid", "")
	if err != nil {
		t.Fatalf("CheckTrackAvailability() error = %v", err)
	}

	if availability.SpotifyID != "testspotifyid" {
		t.Fatalf("SpotifyID = %q, want %q", availability.SpotifyID, "testspotifyid")
	}
	if !availability.Deezer || availability.DeezerID != "908604612" {
		t.Fatalf("Deezer availability = %+v, want DeezerID 908604612", availability)
	}
	if !availability.Amazon || !availability.Tidal || !availability.Qobuz || !availability.YouTube {
		t.Fatalf("availability flags = %+v, want Amazon/Tidal/Qobuz/YouTube true", availability)
	}
	if availability.YouTubeID != "testvideoid1" {
		t.Fatalf("YouTubeID = %q, want %q", availability.YouTubeID, "testvideoid1")
	}
}
