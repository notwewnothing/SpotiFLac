import 'dart:math';
import 'dart:io';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/services/ffmpeg_service.dart';
import 'package:spotiflac_android/services/streaming_service.dart';
import 'package:spotiflac_android/utils/logger.dart';
import 'package:spotiflac_android/utils/playback_utils.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/utils/file_access.dart';

final _log = AppLogger('StreamingAudioProvider');

enum PlaybackState { idle, loading, playing, paused, stopped, error }

class StreamingTrackInfo {
  final Track track;
  final String service;
  final DateTime addedAt;

  const StreamingTrackInfo({
    required this.track,
    required this.service,
    required this.addedAt,
  });
}

class StreamingAudioState {
  final PlaybackState state;
  final StreamingTrackInfo? currentTrack;
  final Duration position;
  final Duration duration;
  final double volume;
  final String? error;
  final List<StreamingTrackInfo> queue;
  final int currentQueueIndex;
  final bool looping;
  final bool shuffling;
  final List<StreamingTrackInfo> originalQueue;

  const StreamingAudioState({
    this.state = PlaybackState.idle,
    this.currentTrack,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 1.0,
    this.error,
    this.queue = const [],
    this.currentQueueIndex = -1,
    this.looping = false,
    this.shuffling = false,
    this.originalQueue = const [],
  });

  StreamingAudioState copyWith({
    PlaybackState? state,
    StreamingTrackInfo? currentTrack,
    Duration? position,
    Duration? duration,
    double? volume,
    String? error,
    List<StreamingTrackInfo>? queue,
    int? currentQueueIndex,
    bool? looping,
    bool? shuffling,
    List<StreamingTrackInfo>? originalQueue,
  }) {
    return StreamingAudioState(
      state: state ?? this.state,
      currentTrack: currentTrack ?? this.currentTrack,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      error: error,
      queue: queue ?? this.queue,
      currentQueueIndex: currentQueueIndex ?? this.currentQueueIndex,
      looping: looping ?? this.looping,
      shuffling: shuffling ?? this.shuffling,
      originalQueue: originalQueue ?? this.originalQueue,
    );
  }
}

class StreamingAudioNotifier extends Notifier<StreamingAudioState> {
  late AudioPlayer _audioPlayer;
  bool _isDisposed = false;
  bool _isTransitioning = false;
  int _playGeneration = 0;

  @override
  StreamingAudioState build() {
    _audioPlayer = AudioPlayer();
    _initializeAudioSession();

    ref.onDispose(() {
      _isDisposed = true;
      FFmpegService.stopLiveDecryptedStream();
      _audioPlayer.dispose();
    });

    // Listen to audio player events
    _setupAudioPlayerListeners();

    return const StreamingAudioState();
  }

  /// Initialize audio session for proper iOS lock screen and system control support
  Future<void> _initializeAudioSession() async {
    try {
      if (Platform.isIOS) {
        final session = await AudioSession.instance;
        await session.configure(
          const AudioSessionConfiguration.music(),
        );
        _log.d('iOS audio session configured for music playback');
      }
    } catch (e) {
      _log.e('Error initializing audio session: $e');
    }
  }

  void _setupAudioPlayerListeners() {
    _audioPlayer.playerStateStream.listen((playerState) {
      if (_isDisposed) return;

      // Only map states we care about; ignore idle during transitions
      final processingState = playerState.processingState;

      if (_isTransitioning) {
        // During track transitions, ignore idle/completed to prevent cascade
        if (processingState == ProcessingState.idle ||
            processingState == ProcessingState.completed) {
          return;
        }
      }

      final newState = switch (processingState) {
        ProcessingState.idle => PlaybackState.idle,
        ProcessingState.loading => PlaybackState.loading,
        ProcessingState.buffering => PlaybackState.loading,
        ProcessingState.ready =>
          playerState.playing ? PlaybackState.playing : PlaybackState.paused,
        ProcessingState.completed => PlaybackState.stopped,
      };

      if (state.state != newState) {
        state = state.copyWith(state: newState);
      }

      // Only auto-advance on genuine completion (not idle/stop from transitions)
      if (processingState == ProcessingState.completed &&
          state.currentTrack != null &&
          !_isTransitioning) {
        _log.d('Track completed: ${state.currentTrack!.track.name}');
        _onTrackEnded();
      }
    });

    _audioPlayer.positionStream.listen((position) {
      if (_isDisposed) return;
      state = state.copyWith(position: position);
    });

    _audioPlayer.durationStream.listen((duration) {
      if (_isDisposed) return;
      state = state.copyWith(duration: duration ?? Duration.zero);
    });
  }

  void _onTrackEnded() {
    if (_isDisposed || state.queue.isEmpty) return;

    if (state.looping) {
      _playTrackByIndex(state.currentQueueIndex);
      return;
    }

    if (state.shuffling) {
      final nextIndex = _getRandomQueueIndex(exclude: state.currentQueueIndex);
      final nextTrack = state.queue[nextIndex];
      _log.i(
        'Shuffle: next random track is ${nextTrack.track.name} (index $nextIndex)',
      );
      _playTrackByIndex(nextIndex);
      return;
    }

    final nextIndex = state.currentQueueIndex + 1;
    if (nextIndex < state.queue.length) {
      _playTrackByIndex(nextIndex);
    } else {
      _log.d('Queue finished');
      state = state.copyWith(state: PlaybackState.stopped);
    }
  }

  /// Internal: plays a track at [index] from the EXISTING queue.
  /// Does NOT modify the queue list — only updates currentTrack and currentQueueIndex.
  Future<void> _playTrackByIndex(int index) async {
    if (_isDisposed || index < 0 || index >= state.queue.length) return;

    // Increment generation to invalidate any in-flight fetches from previous calls
    final generation = ++_playGeneration;
    _isTransitioning = true;

    final trackInfo = state.queue[index];
    _log.i(
      'Loading track: ${trackInfo.track.name} by ${trackInfo.track.artistName}',
    );

    // Stop any active FFmpeg tunnel from previous Amazon playback
    await FFmpegService.stopLiveDecryptedStream();
    // Stop the player cleanly before loading new track
    try {
      await _audioPlayer.stop();
    } catch (_) {}

    // Check if a newer call superseded us
    if (generation != _playGeneration) {
      _log.d('Stale playback request (gen $generation), aborting');
      return;
    }

    state = state.copyWith(
      state: PlaybackState.loading,
      currentQueueIndex: index,
      currentTrack: trackInfo,
      position: Duration.zero,
      duration: Duration(seconds: trackInfo.track.duration),
      error: null,
    );

    try {
      final settings = ref.read(settingsProvider);
      final quality = settings.audioQuality;

      final fallbackServices = [
        'tidal',
        'amazon',
        'deezer',
        'ytmusic-spotiflac',
        'qobuz',
      ];
      if (!fallbackServices.contains(trackInfo.service)) {
        fallbackServices.insert(0, trackInfo.service);
      } else {
        fallbackServices.remove(trackInfo.service);
        fallbackServices.insert(0, trackInfo.service);
      }

      String playableUrl;
      String? decryptionKey;

      String? readablePath = trackInfo.track.source == 'local_file'
          ? trackInfo.track.id
          : null;
      if (readablePath == null) {
        final localState = ref.read(localLibraryProvider);
        final historyState = ref.read(downloadHistoryProvider);
        readablePath = await PlaybackUtils.resolveTrackPath(
          track: trackInfo.track,
          localState: localState,
          historyState: historyState,
        );
      } else {
        // Even if provided directly (e.g. from local_file source), 
        // validate the iOS GUID if needed.
        readablePath = await validateOrFixIosPath(readablePath);
      }

      if (readablePath != null) {
        _log.i('Playing local file: $readablePath');
        playableUrl = readablePath;
      } else {
        final streamingUrl = await StreamingService.getStreamingUrlWithFallback(
          track: trackInfo.track,
          services: fallbackServices,
          quality: quality,
        );

        // Abort if superseded during the async fetch
        if (generation != _playGeneration) {
          _log.d('Stale URL response (gen $generation), discarding');
          return;
        }

        _log.d(
          'Got streaming URL from ${streamingUrl.service}: ${streamingUrl.url.substring(0, streamingUrl.url.length.clamp(0, 80))}...',
        );

        playableUrl = streamingUrl.url;
        decryptionKey = streamingUrl.decryptionKey;
      }

      // If there's a decryption key (Amazon), pipe through FFmpeg live decrypt tunnel
      if (decryptionKey != null && decryptionKey.isNotEmpty) {
        _log.i(
          'Amazon encrypted stream detected, starting live decrypt tunnel...',
        );
        final liveStream =
            await FFmpegService.startEncryptedLiveDecryptedStream(
              encryptedStreamUrl: playableUrl,
              decryptionKey: decryptionKey,
            );
        if (generation != _playGeneration) return;
        if (liveStream != null) {
          playableUrl = liveStream.localUrl;
          _log.i('FFmpeg tunnel ready: $playableUrl');
        } else {
          throw Exception('Failed to start Amazon decryption tunnel');
        }
      }

      _isTransitioning = false;
      final mediaItem = MediaItem(
        id: trackInfo.track.id,
        album: trackInfo.track.albumName,
        title: trackInfo.track.name,
        artist: trackInfo.track.artistName,
        duration: Duration(seconds: trackInfo.track.duration),
        artUri: (trackInfo.track.coverUrl ?? '').isNotEmpty
            ? Uri.parse(trackInfo.track.coverUrl!)
            : null,
      );

      if (readablePath != null) {
        await _audioPlayer.setAudioSource(
          AudioSource.file(playableUrl, tag: mediaItem),
        );
      } else {
        await _audioPlayer.setAudioSource(
          AudioSource.uri(Uri.parse(playableUrl), tag: mediaItem),
        );
      }

      if (generation != _playGeneration) return;
      await _audioPlayer.play();
      state = state.copyWith(state: PlaybackState.playing);

      _log.i('Now playing: ${trackInfo.track.name}');
    } catch (e) {
      if (generation != _playGeneration) return;
      _log.e('Error playing track: $e');
      _isTransitioning = false;
      state = state.copyWith(state: PlaybackState.error, error: e.toString());
    }
  }

  /// Play a single track with optional playlist context.
  /// Sets up the queue and starts playback.
  Future<void> playTrack(
    Track track,
    String service, {
    List<Track>? playlist,
    int? playlistStartIndex = 0,
  }) async {
    if (_isDisposed) return;

    // Build the queue first, then play via _playTrackByIndex
    if (playlist != null && playlist.isNotEmpty) {
      final queueTracks = playlist
          .map(
            (t) => StreamingTrackInfo(
              track: t,
              service: service,
              addedAt: DateTime.now(),
            ),
          )
          .toList();

      final startIndex = (playlistStartIndex ?? 0).clamp(
        0,
        queueTracks.length - 1,
      );
      state = state.copyWith(
        queue: queueTracks,
        originalQueue: List.from(queueTracks),
        currentQueueIndex: startIndex,
      );
    } else {
      final trackInfo = StreamingTrackInfo(
        track: track,
        service: service,
        addedAt: DateTime.now(),
      );
      state = state.copyWith(
        queue: [trackInfo],
        originalQueue: [trackInfo],
        currentQueueIndex: 0,
      );
    }

    await _playTrackByIndex(state.currentQueueIndex);
  }

  void pause() {
    if (_isDisposed) return;
    _audioPlayer.pause();
    state = state.copyWith(state: PlaybackState.paused);
  }

  void resume() {
    if (_isDisposed) return;
    _audioPlayer.play();
    state = state.copyWith(state: PlaybackState.playing);
  }

  void toggle() {
    if (_isDisposed) return;
    if (state.state == PlaybackState.playing) {
      pause();
    } else if (state.state == PlaybackState.paused) {
      resume();
    }
  }

  void toggleLoop() {
    state = state.copyWith(looping: !state.looping);
  }

  void toggleShuffle() {
    final currentlyShuffling = state.shuffling;
    final newShuffle = !currentlyShuffling;
    _log.i('Shuffle toggled: $newShuffle');

    if (newShuffle) {
      // Shuffling ON:
      // Store current order and shuffle.
      final currentQueue = List<StreamingTrackInfo>.from(state.queue);
      final currentTrack = state.currentTrack;
      
      // Shuffle everything except possibly the current track if we want to stay on it.
      // For simplicity, shuffle all and find where the current track went.
      currentQueue.shuffle();
      
      int newIndex = -1;
      if (currentTrack != null) {
        newIndex = currentQueue.indexWhere((item) => item.track.id == currentTrack.track.id);
      }
      
      state = state.copyWith(
        shuffling: true,
        queue: currentQueue,
        currentQueueIndex: newIndex,
      );
    } else {
      // Shuffling OFF:
      // Restore original order.
      final restoredQueue = List<StreamingTrackInfo>.from(state.originalQueue);
      final currentTrack = state.currentTrack;
      
      int newIndex = -1;
      if (currentTrack != null) {
        newIndex = restoredQueue.indexWhere((item) => item.track.id == currentTrack.track.id);
      }
      
      state = state.copyWith(
        shuffling: false,
        queue: restoredQueue,
        currentQueueIndex: newIndex,
      );
    }
  }

  Future<void> stop() async {
    if (_isDisposed) return;
    await FFmpegService.stopLiveDecryptedStream();
    await _audioPlayer.stop();
    state = state.copyWith(state: PlaybackState.stopped);
  }

  Future<void> seek(Duration position) async {
    if (_isDisposed) return;
    await _audioPlayer.seek(position);
  }

  void setVolume(double volume) {
    if (_isDisposed) return;
    final clamped = volume.clamp(0.0, 1.0);
    _audioPlayer.setVolume(clamped);
    state = state.copyWith(volume: clamped);
  }

  void _playNextInQueue() {
    if (_isDisposed || state.queue.isEmpty) return;

    if (state.looping) {
      _playTrackByIndex(state.currentQueueIndex);
      return;
    }

    if (state.shuffling && state.queue.length > 1) {
      int nextIndex = _getRandomQueueIndex(exclude: state.currentQueueIndex);
      _playTrackByIndex(nextIndex);
      return;
    }

    final nextIndex = state.currentQueueIndex + 1;
    if (nextIndex < state.queue.length) {
      _playTrackByIndex(nextIndex);
    } else {
      _log.d('Queue finished');
      state = state.copyWith(state: PlaybackState.stopped);
    }
  }

  int _getRandomQueueIndex({int? exclude}) {
    if (state.queue.length <= 1) return 0;
    int next;
    final rand = Random();
    do {
      next = rand.nextInt(state.queue.length);
    } while (exclude != null && next == exclude);
    return next;
  }

  Future<void> playNextInQueue() async {
    if (_isDisposed || state.queue.isEmpty) return;

    if (state.shuffling && state.queue.length > 1) {
      final nextIndex = _getRandomQueueIndex(exclude: state.currentQueueIndex);
      await _playTrackByIndex(nextIndex);
      return;
    }

    final nextIndex = state.currentQueueIndex + 1;
    if (nextIndex < state.queue.length) {
      await _playTrackByIndex(nextIndex);
    }
  }

  Future<void> playPreviousInQueue() async {
    if (_isDisposed || state.queue.isEmpty) return;

    if (state.shuffling && state.queue.length > 1) {
      final prevIndex = _getRandomQueueIndex(exclude: state.currentQueueIndex);
      await _playTrackByIndex(prevIndex);
      return;
    }

    final prevIndex = state.currentQueueIndex - 1;
    if (prevIndex >= 0) {
      await _playTrackByIndex(prevIndex);
    }
  }

  Future<void> playQueueIndex(int index) async {
    if (_isDisposed || index < 0 || index >= state.queue.length) return;
    await _playTrackByIndex(index);
  }

  void addToQueue(Track track, String service) {
    final newTrackInfo = StreamingTrackInfo(
      track: track,
      service: service,
      addedAt: DateTime.now(),
    );

    final updatedQueue = [...state.queue, newTrackInfo];
    final updatedOriginal = [...state.originalQueue, newTrackInfo];
    state = state.copyWith(queue: updatedQueue, originalQueue: updatedOriginal);
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= state.queue.length) return;

    final updatedQueue = [...state.queue];
    final removedItem = updatedQueue.removeAt(index);
    
    final updatedOriginal = [...state.originalQueue];
    updatedOriginal.removeWhere((item) => item.track.id == removedItem.track.id);

    int newCurrentIndex = state.currentQueueIndex;
    if (index == state.currentQueueIndex && updatedQueue.isNotEmpty) {
      if (newCurrentIndex >= updatedQueue.length) {
        newCurrentIndex = updatedQueue.length - 1;
      }
      if (newCurrentIndex >= 0) {
        final nextTrack = updatedQueue[newCurrentIndex];
        state = state.copyWith(
          queue: updatedQueue,
          originalQueue: updatedOriginal,
          currentQueueIndex: newCurrentIndex,
        );
        _playTrackByIndex(newCurrentIndex);
        return;
      }
    } else if (index < state.currentQueueIndex) {
      newCurrentIndex--;
    }

    state = state.copyWith(
      queue: updatedQueue,
      currentQueueIndex: newCurrentIndex,
    );
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.queue.length) return;
    if (newIndex < 0 || newIndex > state.queue.length) return;
    if (oldIndex == newIndex) return;

    final updatedQueue = [...state.queue];
    final item = updatedQueue.removeAt(oldIndex);
    final adjustedNew = newIndex > oldIndex ? newIndex - 1 : newIndex;
    updatedQueue.insert(adjustedNew, item);

    // If we are NOT shuffling, update originalQueue to match.
    // If we ARE shuffling, originalQueue stays as is (it's the 'reference' order).
    List<StreamingTrackInfo> updatedOriginal = state.originalQueue;
    if (!state.shuffling) {
      updatedOriginal = List.from(updatedQueue);
    }

    // Track the currently playing item
    int newCurrentIndex = state.currentQueueIndex;
    if (oldIndex == state.currentQueueIndex) {
      newCurrentIndex = adjustedNew;
    } else {
      if (oldIndex < state.currentQueueIndex &&
          adjustedNew >= state.currentQueueIndex) {
        newCurrentIndex--;
      } else if (oldIndex > state.currentQueueIndex &&
          adjustedNew <= state.currentQueueIndex) {
        newCurrentIndex++;
      }
    }

    state = state.copyWith(
      queue: updatedQueue,
      currentQueueIndex: newCurrentIndex,
    );
  }

  void clearQueue() {
    stop();
    state = const StreamingAudioState();
  }
}

final streamingAudioProvider =
    NotifierProvider<StreamingAudioNotifier, StreamingAudioState>(
      StreamingAudioNotifier.new,
    );
