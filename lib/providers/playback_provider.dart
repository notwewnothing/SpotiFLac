import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/providers/streaming_audio_provider.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/logger.dart';

final _log = AppLogger('PlaybackProvider');

class PlaybackState {
  const PlaybackState();
}

class PlaybackController extends Notifier<PlaybackState> {
  @override
  PlaybackState build() => const PlaybackState();

  /// Play a track based on app mode (streaming or download)
  Future<void> playTrack({
    required Track track,
    required String service,
    List<Track>? playlist,
    int? playlistStartIndex = 0,
  }) async {
    final settings = ref.read(settingsProvider);
    _log.d('playTrack: ${track.name} (mode: ${settings.appmode})');

    // Check if we have a local file for this track regardless of app mode
    final resolvedPath = await _resolveTrackPath(track);
    if (resolvedPath != null) {
      _log.i('Found local file for ${track.name}, using built-in player');
      await playStreamingTrack(
        track: track.copyWith(
          source: 'local_file',
          id: resolvedPath, // So JustAudio can play the raw URI
        ),
        service: service,
        playlist: playlist,
        playlistStartIndex: playlistStartIndex,
      );
      return;
    }

    if (settings.appmode == 'stream') {
      await playStreamingTrack(
        track: track,
        service: service,
        playlist: playlist,
        playlistStartIndex: playlistStartIndex,
      );
    } else {
      _log.w(
        'No local file found for ${track.name}, and app is in download mode',
      );
    }
  }

  /// Play a track in streaming mode using in-app player
  Future<void> playStreamingTrack({
    required Track track,
    required String service,
    List<Track>? playlist,
    int? playlistStartIndex = 0,
  }) async {
    _log.i('Starting streaming playback for "${track.name}"');

    await ref.read(streamingAudioProvider.notifier).playTrack(
          track,
          service,
          playlist: playlist,
          playlistStartIndex: playlistStartIndex,
        );
  }

  Future<void> playLocalPath({
    required String path,
    required String title,
    required String artist,
    String album = '',
    String coverUrl = '',
    Track? track,
  }) async {
    if (isCueVirtualPath(path)) {
      throw Exception(cueVirtualTrackRequiresSplitMessage);
    }
    _log.d('Playing local file in built-in player: $path');

    final localTrack =
        track ??
        Track(
          id: path,
          name: title,
          artistName: artist,
          albumName: album,
          duration: 0,
          coverUrl: coverUrl,
          source: 'local_file',
        );

    await playStreamingTrack(track: localTrack, service: 'local');
  }

  Future<void> playTrackList(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;

    final List<Track> playlist = [];
    for (final track in tracks) {
      final path = await _resolveTrackPath(track);
      if (path != null && !isCueVirtualPath(path)) {
        playlist.add(track.copyWith(source: 'local_file', id: path));
      } else {
        playlist.add(track);
      }
    }

    if (playlist.isEmpty) {
      throw Exception('No playable tracks found in the list');
    }

    await playStreamingTrack(
      track: playlist[startIndex],
      service: 'multi',
      playlist: playlist,
      playlistStartIndex: startIndex,
    );
  }

  Future<String?> _resolveTrackPath(Track track) async {
    final localState = ref.read(localLibraryProvider);
    final historyState = ref.read(downloadHistoryProvider);
    final historyNotifier = ref.read(downloadHistoryProvider.notifier);

    final localItem = _findLocalLibraryItemForTrack(track, localState);
    if (localItem != null && await fileExists(localItem.filePath)) {
      return localItem.filePath;
    }

    final historyItem = _findDownloadHistoryItemForTrack(track, historyState);
    if (historyItem != null) {
      if (await fileExists(historyItem.filePath)) {
        return historyItem.filePath;
      }
      historyNotifier.removeFromHistory(historyItem.id);
    }

    return null;
  }

  LocalLibraryItem? _findLocalLibraryItemForTrack(
    Track track,
    LocalLibraryState localState,
  ) {
    final isLocalSource = (track.source ?? '').toLowerCase() == 'local';
    if (isLocalSource) {
      for (final item in localState.items) {
        if (item.id == track.id) {
          return item;
        }
      }
    }

    final isrc = track.isrc?.trim();
    if (isrc != null && isrc.isNotEmpty) {
      final byIsrc = localState.getByIsrc(isrc);
      if (byIsrc != null) {
        return byIsrc;
      }
    }

    return localState.findByTrackAndArtist(track.name, track.artistName);
  }

  DownloadHistoryItem? _findDownloadHistoryItemForTrack(
    Track track,
    DownloadHistoryState historyState,
  ) {
    for (final candidateId in _spotifyIdLookupCandidates(track.id)) {
      final bySpotifyId = historyState.getBySpotifyId(candidateId);
      if (bySpotifyId != null) {
        return bySpotifyId;
      }
    }

    final isrc = track.isrc?.trim();
    if (isrc != null && isrc.isNotEmpty) {
      final byIsrc = historyState.getByIsrc(isrc);
      if (byIsrc != null) {
        return byIsrc;
      }
    }

    return historyState.findByTrackAndArtist(track.name, track.artistName);
  }

  List<String> _spotifyIdLookupCandidates(String rawId) {
    final trimmed = rawId.trim();
    if (trimmed.isEmpty) {
      return const [];
    }

    final candidates = <String>{trimmed};
    final lowered = trimmed.toLowerCase();
    if (lowered.startsWith('spotify:track:')) {
      final compact = trimmed.split(':').last.trim();
      if (compact.isNotEmpty) {
        candidates.add(compact);
      }
    } else if (!trimmed.contains(':')) {
      candidates.add('spotify:track:$trimmed');
    }

    final uri = Uri.tryParse(trimmed);
    final segments = uri?.pathSegments ?? const <String>[];
    final trackIndex = segments.indexOf('track');
    if (trackIndex >= 0 && trackIndex + 1 < segments.length) {
      final pathId = segments[trackIndex + 1].trim();
      if (pathId.isNotEmpty) {
        candidates.add(pathId);
        candidates.add('spotify:track:$pathId');
      }
    }

    return candidates.toList(growable: false);
  }
}

final playbackProvider = NotifierProvider<PlaybackController, PlaybackState>(
  PlaybackController.new,
);
