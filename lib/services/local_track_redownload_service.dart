import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';

class LocalTrackRedownloadResolution {
  final LocalLibraryItem localItem;
  final Track? match;
  final int score;
  final String reason;

  const LocalTrackRedownloadResolution({
    required this.localItem,
    required this.match,
    required this.score,
    required this.reason,
  });

  bool get canQueue => match != null;
}

class LocalTrackRedownloadService {
  static const int _minimumConfidenceScore = 85;
  static const int _ambiguousScoreGap = 8;

  static Future<LocalTrackRedownloadResolution> resolveBestMatch(
    LocalLibraryItem item, {
    required bool includeExtensions,
  }) async {
    final query = _buildSearchQuery(item);
    final rawResults = await PlatformBridge.searchTracksWithMetadataProviders(
      query,
      limit: 10,
      includeExtensions: includeExtensions,
    );

    if (rawResults.isEmpty) {
      return LocalTrackRedownloadResolution(
        localItem: item,
        match: null,
        score: 0,
        reason: 'No candidates found',
      );
    }

    final scored =
        rawResults
            .map(
              (raw) => (
                track: _parseSearchTrack(raw),
                score: _scoreMatch(item, raw),
              ),
            )
            .where((entry) => entry.track.name.trim().isNotEmpty)
            .toList(growable: false)
          ..sort((a, b) => b.score.compareTo(a.score));

    if (scored.isEmpty) {
      return LocalTrackRedownloadResolution(
        localItem: item,
        match: null,
        score: 0,
        reason: 'No usable candidates found',
      );
    }

    final best = scored.first;
    final runnerUp = scored.length > 1 ? scored[1] : null;
    final exactIsrc =
        _normalizedIsrc(item.isrc) != null &&
        _normalizedIsrc(item.isrc) == _normalizedIsrc(best.track.isrc);
    final isAmbiguous =
        !exactIsrc &&
        runnerUp != null &&
        best.score < (_minimumConfidenceScore + 10) &&
        (best.score - runnerUp.score) <= _ambiguousScoreGap;

    if (!exactIsrc && (best.score < _minimumConfidenceScore || isAmbiguous)) {
      return LocalTrackRedownloadResolution(
        localItem: item,
        match: null,
        score: best.score,
        reason: isAmbiguous ? 'Ambiguous match' : 'Low-confidence match',
      );
    }

    return LocalTrackRedownloadResolution(
      localItem: item,
      match: best.track,
      score: best.score,
      reason: exactIsrc ? 'Exact ISRC match' : 'High-confidence metadata match',
    );
  }

  static String preferredFlacService(AppSettings settings) {
    switch (settings.defaultService.toLowerCase()) {
      case 'tidal':
      case 'qobuz':
      case 'deezer':
        return settings.defaultService.toLowerCase();
      default:
        return 'tidal';
    }
  }

  static String preferredFlacQualityForService(String service) {
    return service.toLowerCase() == 'deezer' ? 'FLAC' : 'LOSSLESS';
  }

  static String _buildSearchQuery(LocalLibraryItem item) {
    final artist = _primaryArtist(item.artistName);
    final album = item.albumName.trim();
    if (album.isNotEmpty && album.toLowerCase() != 'unknown album') {
      return '${item.trackName} $artist $album'.trim();
    }
    return '${item.trackName} $artist'.trim();
  }

  static Track _parseSearchTrack(Map<String, dynamic> data) {
    final durationMs = _extractDurationMs(data);
    final itemType = data['item_type']?.toString();

    return Track(
      id: (data['spotify_id'] ?? data['id'] ?? '').toString(),
      name: (data['name'] ?? '').toString(),
      artistName: (data['artists'] ?? data['artist'] ?? '').toString(),
      albumName: (data['album_name'] ?? data['album'] ?? '').toString(),
      albumArtist: data['album_artist']?.toString(),
      artistId: (data['artist_id'] ?? data['artistId'])?.toString(),
      albumId: data['album_id']?.toString(),
      coverUrl: (data['cover_url'] ?? data['images'])?.toString(),
      isrc: data['isrc']?.toString(),
      duration: (durationMs / 1000).round(),
      trackNumber: data['track_number'] as int?,
      discNumber: data['disc_number'] as int?,
      releaseDate: data['release_date']?.toString(),
      totalTracks: data['total_tracks'] as int?,
      source: data['source']?.toString() ?? data['provider_id']?.toString(),
      albumType: data['album_type']?.toString(),
      itemType: itemType,
    );
  }

  static int _extractDurationMs(Map<String, dynamic> data) {
    final durationMsRaw = data['duration_ms'];
    if (durationMsRaw is num && durationMsRaw > 0) {
      return durationMsRaw.toInt();
    }
    if (durationMsRaw is String) {
      final parsed = num.tryParse(durationMsRaw.trim());
      if (parsed != null && parsed > 0) {
        return parsed.toInt();
      }
    }

    final durationSecRaw = data['duration'];
    if (durationSecRaw is num && durationSecRaw > 0) {
      return (durationSecRaw * 1000).toInt();
    }
    if (durationSecRaw is String) {
      final parsed = num.tryParse(durationSecRaw.trim());
      if (parsed != null && parsed > 0) {
        return (parsed * 1000).toInt();
      }
    }

    return 0;
  }

  static int _scoreMatch(LocalLibraryItem item, Map<String, dynamic> raw) {
    final track = _parseSearchTrack(raw);
    var score = 0;

    final localIsrc = _normalizedIsrc(item.isrc);
    final candidateIsrc = _normalizedIsrc(track.isrc);
    if (localIsrc != null && candidateIsrc != null) {
      score += localIsrc == candidateIsrc ? 140 : -120;
    }

    final localTitle = _normalizedTitle(item.trackName);
    final candidateTitle = _normalizedTitle(track.name);
    if (localTitle == candidateTitle) {
      score += 45;
    } else if (_tokenOverlap(localTitle, candidateTitle) >= 0.75) {
      score += 24;
    } else {
      score -= 25;
    }

    final localArtist = _normalizedArtistGroup(item.artistName);
    final candidateArtist = _normalizedArtistGroup(track.artistName);
    final artistOverlap = _tokenOverlap(localArtist, candidateArtist);
    if (localArtist == candidateArtist) {
      score += 30;
    } else if (artistOverlap >= 0.6) {
      score += 16;
    } else {
      score -= 20;
    }

    final localAlbum = _normalizedText(item.albumName);
    final candidateAlbum = _normalizedText(track.albumName);
    if (localAlbum.isNotEmpty && candidateAlbum.isNotEmpty) {
      if (localAlbum == candidateAlbum) {
        score += 12;
      } else if (_tokenOverlap(localAlbum, candidateAlbum) >= 0.7) {
        score += 6;
      }
    }

    final localDuration = item.duration ?? 0;
    final candidateDuration = track.duration;
    if (localDuration > 0 && candidateDuration > 0) {
      final diff = (localDuration - candidateDuration).abs();
      if (diff <= 2) {
        score += 20;
      } else if (diff <= 5) {
        score += 12;
      } else if (diff <= 10) {
        score += 5;
      } else if (diff > 20) {
        score -= 30;
      }
    }

    if (item.trackNumber != null &&
        track.trackNumber != null &&
        item.trackNumber == track.trackNumber) {
      score += 6;
    }
    if (item.discNumber != null &&
        track.discNumber != null &&
        item.discNumber == track.discNumber) {
      score += 4;
    }

    final localYear = _extractYear(item.releaseDate);
    final candidateYear = _extractYear(track.releaseDate);
    if (localYear != null &&
        candidateYear != null &&
        localYear == candidateYear) {
      score += 4;
    }

    score += _versionPenalty(item.trackName, track.name);
    return score;
  }

  static String? _normalizedIsrc(String? value) {
    final normalized = value?.trim().toUpperCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  static String _normalizedTitle(String value) {
    final cleaned = _normalizedText(value)
        .replaceAll(RegExp(r'\b(feat|ft|featuring)\b.*$'), ' ')
        .replaceAll(RegExp(r'\b(remaster(?:ed)?|deluxe|bonus)\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned;
  }

  static String _normalizedArtistGroup(String value) {
    return _normalizedText(
      value
          .replaceAll(RegExp(r'\b(feat|ft|featuring|with|x)\b'), ',')
          .replaceAll('&', ','),
    );
  }

  static String _primaryArtist(String value) {
    final parts = _normalizedArtistGroup(
      value,
    ).split(',').map((part) => part.trim()).where((part) => part.isNotEmpty);
    return parts.isEmpty ? value.trim() : parts.first;
  }

  static String _normalizedText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[\(\)\[\]\{\}]'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9, ]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static double _tokenOverlap(String left, String right) {
    final leftTokens = left
        .split(RegExp(r'[\s,]+'))
        .where((token) => token.isNotEmpty)
        .toSet();
    final rightTokens = right
        .split(RegExp(r'[\s,]+'))
        .where((token) => token.isNotEmpty)
        .toSet();
    if (leftTokens.isEmpty || rightTokens.isEmpty) {
      return 0;
    }
    final intersection = leftTokens.intersection(rightTokens).length;
    final denominator = leftTokens.length > rightTokens.length
        ? leftTokens.length
        : rightTokens.length;
    return intersection / denominator;
  }

  static int _versionPenalty(String localTitle, String candidateTitle) {
    const riskyMarkers = [
      'live',
      'karaoke',
      'instrumental',
      'acoustic',
      'radio edit',
      'sped up',
      'slowed',
    ];
    final local = _normalizedText(localTitle);
    final candidate = _normalizedText(candidateTitle);
    var penalty = 0;
    for (final marker in riskyMarkers) {
      final localHas = local.contains(marker);
      final candidateHas = candidate.contains(marker);
      if (!localHas && candidateHas) {
        penalty -= 18;
      }
    }
    return penalty;
  }

  static int? _extractYear(String? date) {
    if (date == null || date.length < 4) {
      return null;
    }
    return int.tryParse(date.substring(0, 4));
  }
}
