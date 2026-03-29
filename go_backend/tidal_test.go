package gobackend

import "testing"

func TestParseTidalURL(t *testing.T) {
	tests := []struct {
		name      string
		input     string
		wantType  string
		wantID    string
		expectErr bool
	}{
		{
			name:     "track url",
			input:    "https://tidal.com/track/77616174",
			wantType: "track",
			wantID:   "77616174",
		},
		{
			name:     "browse album url",
			input:    "https://listen.tidal.com/browse/album/77616169",
			wantType: "album",
			wantID:   "77616169",
		},
		{
			name:     "artist url",
			input:    "https://www.tidal.com/artist/3852143",
			wantType: "artist",
			wantID:   "3852143",
		},
		{
			name:     "playlist url",
			input:    "https://tidal.com/playlist/edf3b7d2-cb42-41d7-93c0-afa2a395521b",
			wantType: "playlist",
			wantID:   "edf3b7d2-cb42-41d7-93c0-afa2a395521b",
		},
		{
			name:      "unsupported host",
			input:     "https://example.com/track/123",
			expectErr: true,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			gotType, gotID, err := parseTidalURL(test.input)
			if test.expectErr {
				if err == nil {
					t.Fatalf("expected error, got none")
				}
				return
			}
			if err != nil {
				t.Fatalf("expected no error, got %v", err)
			}
			if gotType != test.wantType || gotID != test.wantID {
				t.Fatalf("parseTidalURL(%q) = (%q, %q), want (%q, %q)", test.input, gotType, gotID, test.wantType, test.wantID)
			}
		})
	}
}

func TestParseTidalRequestTrackID(t *testing.T) {
	tests := []struct {
		input string
		want  int64
		ok    bool
	}{
		{input: "40681594", want: 40681594, ok: true},
		{input: "tidal:40681594", want: 40681594, ok: true},
		{input: " tidal:40681594 ", want: 40681594, ok: true},
		{input: "", want: 0, ok: false},
		{input: "tidal:not-a-number", want: 0, ok: false},
	}

	for _, test := range tests {
		got, ok := parseTidalRequestTrackID(test.input)
		if got != test.want || ok != test.ok {
			t.Fatalf("parseTidalRequestTrackID(%q) = (%d, %v), want (%d, %v)", test.input, got, ok, test.want, test.ok)
		}
	}
}

func TestTidalImageURL(t *testing.T) {
	got := tidalImageURL("fc18a64b-d76b-4582-962a-224cb05193f3", "1280x1280")
	want := "https://resources.tidal.com/images/fc18a64b/d76b/4582/962a/224cb05193f3/1280x1280.jpg"
	if got != want {
		t.Fatalf("tidalImageURL() = %q, want %q", got, want)
	}
}

func TestTidalTrackToTrackMetadata(t *testing.T) {
	track := &TidalTrack{
		ID:           77616174,
		Title:        "Bruckner: Symphony No. 5",
		ISRC:         "GBUM71507433",
		Duration:     1172,
		TrackNumber:  5,
		VolumeNumber: 1,
		URL:          "http://www.tidal.com/track/77616174",
	}
	track.Artist.ID = 3852143
	track.Artist.Name = "Staatskapelle Berlin"
	track.Artists = []struct {
		ID      int64  `json:"id"`
		Name    string `json:"name"`
		Type    string `json:"type"`
		Picture string `json:"picture"`
	}{
		{ID: 3852143, Name: "Staatskapelle Berlin", Type: "MAIN"},
		{ID: 12430, Name: "Daniel Barenboim", Type: "FEATURED"},
	}
	track.Album.ID = 77616169
	track.Album.Title = "Bruckner: Symphonies 4-9"
	track.Album.Cover = "fc18a64b-d76b-4582-962a-224cb05193f3"
	track.Album.ReleaseDate = "2016-02-26"

	got := tidalTrackToTrackMetadata(track)
	if got.SpotifyID != "tidal:77616174" {
		t.Fatalf("unexpected track ID: %q", got.SpotifyID)
	}
	if got.Artists != "Staatskapelle Berlin, Daniel Barenboim" {
		t.Fatalf("unexpected artists: %q", got.Artists)
	}
	if got.AlbumID != "tidal:77616169" {
		t.Fatalf("unexpected album ID: %q", got.AlbumID)
	}
	if got.ArtistID != "tidal:3852143" {
		t.Fatalf("unexpected artist ID: %q", got.ArtistID)
	}
	if got.Images == "" || got.ExternalURL != "https://www.tidal.com/track/77616174" {
		t.Fatalf("unexpected image/url: %q / %q", got.Images, got.ExternalURL)
	}
}

func TestTidalAlbumToArtistAlbum(t *testing.T) {
	album := &tidalPublicAlbum{
		ID:             77616169,
		Title:          "Bruckner: Symphonies 4-9",
		Type:           "ALBUM",
		Cover:          "fc18a64b-d76b-4582-962a-224cb05193f3",
		ReleaseDate:    "2016-02-26",
		NumberOfTracks: 23,
		Artists: []tidalPublicArtist{
			{ID: 3852143, Name: "Staatskapelle Berlin", Type: "MAIN"},
			{ID: 12430, Name: "Daniel Barenboim", Type: "FEATURED"},
		},
	}

	got := tidalAlbumToArtistAlbum(album)
	if got.ID != "tidal:77616169" {
		t.Fatalf("unexpected album ID: %q", got.ID)
	}
	if got.AlbumType != "album" {
		t.Fatalf("unexpected album type: %q", got.AlbumType)
	}
	if got.Artists != "Staatskapelle Berlin, Daniel Barenboim" {
		t.Fatalf("unexpected artists: %q", got.Artists)
	}
	if got.Images == "" {
		t.Fatalf("expected image URL, got empty string")
	}
}

func TestTidalAlbumToArtistAlbumWithFallbackType(t *testing.T) {
	album := &tidalPublicAlbum{
		ID:             490623904,
		Title:          "LET 'EM KNOW",
		Cover:          "fc18a64b-d76b-4582-962a-224cb05193f3",
		NumberOfTracks: 1,
	}

	got := tidalAlbumToArtistAlbumWithType(album, "single")
	if got.AlbumType != "single" {
		t.Fatalf("unexpected fallback album type: %q", got.AlbumType)
	}
}

func TestTidalArtistAlbumTypeFromModuleTitle(t *testing.T) {
	tests := []struct {
		title string
		want  string
	}{
		{title: "Albums", want: "album"},
		{title: "EP & Singles", want: "single"},
		{title: "Compilations", want: "album"},
		{title: "Appears On", want: "album"},
		{title: "Unknown", want: ""},
	}

	for _, test := range tests {
		if got := tidalArtistAlbumTypeFromModuleTitle(test.title); got != test.want {
			t.Fatalf("tidalArtistAlbumTypeFromModuleTitle(%q) = %q, want %q", test.title, got, test.want)
		}
	}
}

func TestTidalPlaylistImageUsesOrigin(t *testing.T) {
	got := tidalImageURL("e6b59fd3-6995-40f0-8a32-174db3a8f4f2", "origin")
	want := "https://resources.tidal.com/images/e6b59fd3/6995/40f0/8a32/174db3a8f4f2/origin.jpg"
	if got != want {
		t.Fatalf("unexpected origin playlist image URL: %q", got)
	}
}

func TestTidalPlaylistOwnerName(t *testing.T) {
	editorial := &tidalPublicPlaylist{Type: "EDITORIAL"}
	if got := tidalPlaylistOwnerName(editorial); got != "TIDAL" {
		t.Fatalf("unexpected editorial owner: %q", got)
	}

	artist := &tidalPublicPlaylist{Type: "ARTIST"}
	if got := tidalPlaylistOwnerName(artist); got != "Artist" {
		t.Fatalf("unexpected artist owner: %q", got)
	}

	user := &tidalPublicPlaylist{}
	user.Creator.Name = "djtest"
	if got := tidalPlaylistOwnerName(user); got != "djtest" {
		t.Fatalf("unexpected creator owner: %q", got)
	}
}
