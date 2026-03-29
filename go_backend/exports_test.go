package gobackend

import "testing"

func TestBuildDownloadSuccessResponsePrefersRequestedAlbumMetadata(t *testing.T) {
	req := DownloadRequest{
		TrackName:   "Bonus Track",
		ArtistName:  "Artist",
		AlbumName:   "Album (Deluxe)",
		AlbumArtist: "Artist",
		ReleaseDate: "2024-01-01",
		TrackNumber: 14,
		DiscNumber:  1,
		ISRC:        "REQ123",
		CoverURL:    "https://example.com/cover.jpg",
		Genre:       "Pop",
		Label:       "Label",
		Copyright:   "Copyright",
	}

	result := DownloadResult{
		Title:       "Bonus Track",
		Artist:      "Artist",
		Album:       "Album",
		ReleaseDate: "2023-12-01",
		TrackNumber: 2,
		DiscNumber:  9,
		ISRC:        "RES456",
	}

	resp := buildDownloadSuccessResponse(
		req,
		result,
		"tidal",
		"ok",
		"/tmp/test.flac",
		false,
	)

	if resp.Album != req.AlbumName {
		t.Fatalf("album = %q, want %q", resp.Album, req.AlbumName)
	}
	if resp.ReleaseDate != req.ReleaseDate {
		t.Fatalf("release date = %q, want %q", resp.ReleaseDate, req.ReleaseDate)
	}
	if resp.TrackNumber != req.TrackNumber {
		t.Fatalf("track number = %d, want %d", resp.TrackNumber, req.TrackNumber)
	}
	if resp.DiscNumber != req.DiscNumber {
		t.Fatalf("disc number = %d, want %d", resp.DiscNumber, req.DiscNumber)
	}
	if resp.Artist != result.Artist {
		t.Fatalf("artist = %q, want provider artist %q", resp.Artist, result.Artist)
	}
	if resp.ISRC != result.ISRC {
		t.Fatalf("isrc = %q, want provider isrc %q", resp.ISRC, result.ISRC)
	}
}

func TestPreferredReleaseMetadataPrefersRequestValues(t *testing.T) {
	album, releaseDate, trackNumber, discNumber := preferredReleaseMetadata(
		DownloadRequest{
			AlbumName:   "Album (Deluxe Edition)",
			ReleaseDate: "2024-01-01",
			TrackNumber: 13,
			DiscNumber:  2,
		},
		"Album",
		"2023-01-01",
		3,
		1,
	)

	if album != "Album (Deluxe Edition)" {
		t.Fatalf("album = %q", album)
	}
	if releaseDate != "2024-01-01" {
		t.Fatalf("release date = %q", releaseDate)
	}
	if trackNumber != 13 {
		t.Fatalf("track number = %d", trackNumber)
	}
	if discNumber != 2 {
		t.Fatalf("disc number = %d", discNumber)
	}
}
