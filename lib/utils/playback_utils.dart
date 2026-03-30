import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/services/library_database.dart';

class PlaybackUtils {
  /// Resolves the local file path for a track by checking the local library and download history.
  /// Returns null if no local file is found or if it does not exist on disk.
  static Future<String?> resolveTrackPath({
    required Track track,
    required LocalLibraryState localState,
    required DownloadHistoryState historyState,
  }) async {
    // 1. Check Local Library (User-added folders)
    final localItem = _findLocalLibraryItemForTrack(track, localState);
    if (localItem != null) {
      final path = await validateOrFixIosPath(localItem.filePath);
      if (await fileExists(path)) {
        return path;
      }
    }

    // 2. Check Download History (App-managed downloads)
    final historyItem = _findDownloadHistoryItemForTrack(track, historyState);
    if (historyItem != null) {
      final path = await validateOrFixIosPath(historyItem.filePath);
      if (await fileExists(path)) {
        return path;
      }
    }

    return null;
  }

  static LocalLibraryItem? _findLocalLibraryItemForTrack(
    Track track,
    LocalLibraryState localState,
  ) {
    // If clearly a local track, match by ID (which is the path)
    if ((track.source ?? '').toLowerCase() == 'local_file') {
      for (final item in localState.items) {
        if (item.id == track.id || item.filePath == track.id) {
          return item;
        }
      }
    }

    // Try ISRC matching
    final isrc = track.isrc?.trim();
    if (isrc != null && isrc.isNotEmpty) {
      final byIsrc = localState.getByIsrc(isrc);
      if (byIsrc != null) {
        return byIsrc;
      }
    }

    // Fallback to name/artist matching
    return localState.findByTrackAndArtist(track.name, track.artistName);
  }

  static DownloadHistoryItem? _findDownloadHistoryItemForTrack(
    Track track,
    DownloadHistoryState historyState,
  ) {
    // Try Spotify ID matching with various candidate formats
    for (final candidateId in _spotifyIdLookupCandidates(track.id)) {
      final bySpotifyId = historyState.getBySpotifyId(candidateId);
      if (bySpotifyId != null) {
        return bySpotifyId;
      }
    }

    // Try ISRC matching
    final isrc = track.isrc?.trim();
    if (isrc != null && isrc.isNotEmpty) {
      final byIsrc = historyState.getByIsrc(isrc);
      if (byIsrc != null) {
        return byIsrc;
      }
    }

    // Fallback to name/artist matching
    return historyState.findByTrackAndArtist(track.name, track.artistName);
  }

  static List<String> _spotifyIdLookupCandidates(String rawId) {
    final trimmed = rawId.trim();
    if (trimmed.isEmpty) {
      return const [];
    }

    final candidates = <String>{trimmed};
    final lowered = trimmed.toLowerCase();
    
    // Handle spotify:track:ID
    if (lowered.startsWith('spotify:track:')) {
      final compact = trimmed.split(':').last.trim();
      if (compact.isNotEmpty) {
        candidates.add(compact);
      }
    } else if (!trimmed.contains(':') && !trimmed.contains('/')) {
      // Handle plain ID -> spotify:track:ID
      candidates.add('spotify:track:$trimmed');
    }

    // Handle URLs
    try {
      final uri = Uri.tryParse(trimmed);
      if (uri != null) {
        final segments = uri.pathSegments;
        final trackIndex = segments.indexOf('track');
        if (trackIndex >= 0 && trackIndex + 1 < segments.length) {
          final pathId = segments[trackIndex + 1].trim();
          if (pathId.isNotEmpty) {
            candidates.add(pathId);
            candidates.add('spotify:track:$pathId');
          }
        }
      }
    } catch (_) {}

    return candidates.toList(growable: false);
  }
}
