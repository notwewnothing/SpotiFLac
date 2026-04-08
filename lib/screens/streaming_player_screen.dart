import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/streaming_audio_provider.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/widgets/download_service_picker.dart';
import 'package:spotiflac_android/widgets/audio_waveform_scrubber.dart';
import 'package:spotiflac_android/utils/clickable_metadata.dart';

// ─── LRC line model ───
class _LrcLine {
  final Duration timestamp;
  final String text;
  const _LrcLine(this.timestamp, this.text);
}

List<_LrcLine> _parseLrc(String raw) {
  final lines = <_LrcLine>[];
  final regex = RegExp(r'\[(\d{1,2}):(\d{2})\.(\d{2,3})\](.*)');
  for (final line in raw.split('\n')) {
    final match = regex.firstMatch(line.trim());
    if (match != null) {
      final min = int.parse(match.group(1)!);
      final sec = int.parse(match.group(2)!);
      var ms = int.parse(match.group(3)!);
      if (ms < 100) ms *= 10;
      final ts = Duration(minutes: min, seconds: sec, milliseconds: ms);
      final text = match.group(4)?.trim() ?? '';
      if (text.isNotEmpty) {
        lines.add(_LrcLine(ts, text));
      }
    }
  }
  lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return lines;
}

int _activeLrcIndex(List<_LrcLine> lines, Duration position) {
  int idx = -1;
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].timestamp <= position) {
      idx = i;
    } else {
      break;
    }
  }
  return idx;
}

enum _PlayerViewMode { defaultView, lyrics, queue }

class StreamingPlayerScreen extends ConsumerStatefulWidget {
  final Track track;
  final String service;
  final List<Track>? playlist;
  final int? playlistStartIndex;

  const StreamingPlayerScreen({
    super.key,
    required this.track,
    required this.service,
    this.playlist,
    this.playlistStartIndex = 0,
  });

  @override
  ConsumerState<StreamingPlayerScreen> createState() =>
      _StreamingPlayerScreenState();
}

class _StreamingPlayerScreenState extends ConsumerState<StreamingPlayerScreen> {
  _PlayerViewMode _viewMode = _PlayerViewMode.defaultView;

  bool _isLoadingLyrics = false;
  String? _rawLyrics;
  List<_LrcLine> _lrcLines = [];
  List<GlobalKey> _lyricsKeys = [];
  String? _lastScrolledTrackId;

  // Background colors
  Color _dominantColor = Colors.black;
  Color _mutedColor = Colors.transparent;
  String? _lastColorExtractedUrl;

  @override
  void initState() {
    super.initState();
    _extractColors(widget.track.coverUrl);
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _extractColors(String? url) async {
    if (url == null || url == _lastColorExtractedUrl) return;
    _lastColorExtractedUrl = url;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(url),
        maximumColorCount: 10,
      );
      if (mounted) {
        setState(() {
          _dominantColor = palette.dominantColor?.color ?? Colors.black;
          _mutedColor =
              palette.darkMutedColor?.color ??
              palette.mutedColor?.color ??
              Colors.black;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchLyrics(Track track) async {
    setState(() => _isLoadingLyrics = true);
    try {
      // Step 1: For local files, try to extract embedded lyrics first
      if (_isLocalTrack(track)) {
        final localLyrics = await _getEmbeddedOrLocalLyrics(track);
        if (localLyrics != null && localLyrics.isNotEmpty) {
          if (mounted) {
            setState(() {
              _rawLyrics = localLyrics;
              _lrcLines = _parseLrc(localLyrics);
              _lyricsKeys = List.generate(_lrcLines.length, (_) => GlobalKey());
              _isLoadingLyrics = false;
            });
          }
          return; // Successfully found local lyrics
        }
      }

      // Step 2: Try online providers via platform bridge
      final result = await PlatformBridge.getLyricsLRC(
        track.id,
        track.name,
        track.artistName,
        filePath: _isLocalTrack(track) ? track.id : null,
        durationMs: track.duration * 1000,
      );
      if (mounted) {
        setState(() {
          _rawLyrics = result;
          _lrcLines = _parseLrc(result);
          _lyricsKeys = List.generate(_lrcLines.length, (_) => GlobalKey());
          _isLoadingLyrics = false;
        });
      }
    } catch (e) {
      // Step 3: On error, try embedded lyrics as final fallback for local tracks
      if (_isLocalTrack(track)) {
        try {
          final fallbackLyrics = await _getEmbeddedOrLocalLyrics(track);
          if (fallbackLyrics != null && fallbackLyrics.isNotEmpty) {
            if (mounted) {
              setState(() {
                _rawLyrics = fallbackLyrics;
                _lrcLines = _parseLrc(fallbackLyrics);
                _lyricsKeys = List.generate(_lrcLines.length, (_) => GlobalKey());
                _isLoadingLyrics = false;
              });
            }
            return;
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _rawLyrics = null;
          _lrcLines = [];
          _lyricsKeys = [];
          _isLoadingLyrics = false;
        });
      }
    }
  }

  /// Check if track is a local file
  bool _isLocalTrack(Track track) {
    return (track.source ?? '').toLowerCase() == 'local_file' ||
        track.id.startsWith('local_') ||
        track.id.contains('/');
  }

  /// Try to get embedded or local lyrics for a track
  /// Returns null if no lyrics found
  Future<String?> _getEmbeddedOrLocalLyrics(Track track) async {
    try {
      final lyricsData = await PlatformBridge.getLyricsLRCWithSource(
        track.id,
        track.name,
        track.artistName,
        filePath: track.id,
        durationMs: track.duration * 1000,
      );

      // Check if lyrics were found from embedded source
      if (lyricsData['source'] == 'embedded' ||
          lyricsData['source'] == 'local') {
        return lyricsData['lyrics'] as String?;
      }
      return lyricsData['lyrics'] as String?;
    } catch (e) {
      return null;
    }
  }

  void _setViewMode(_PlayerViewMode mode, Track? track) {
    if (_viewMode == mode) {
      setState(() => _viewMode = _PlayerViewMode.defaultView); // Toggle off
      return;
    }
    setState(() => _viewMode = mode);
    if (mode == _PlayerViewMode.lyrics && _rawLyrics == null && track != null) {
      _fetchLyrics(track);
    }
  }

  void _scrollToActiveLine(int activeIdx) {
    if (activeIdx < 0 || activeIdx >= _lyricsKeys.length) return;
    final key = _lyricsKeys[activeIdx];
    if (key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        alignment: 0.5,
      );
    }
  }

  void _downloadCurrentTrack(Track track) {
    final settings = ref.read(settingsProvider);
    if (settings.askQualityBeforeDownload) {
      DownloadServicePicker.show(
        context,
        trackName: track.name,
        artistName: track.artistName,
        coverUrl: track.coverUrl,
        onSelect: (quality, service) {
          ref
              .read(downloadQueueProvider.notifier)
              .addToQueue(track, service, qualityOverride: quality);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Added "${track.name}" to download queue')),
          );
        },
      );
    } else {
      ref
          .read(downloadQueueProvider.notifier)
          .addToQueue(track, settings.defaultService);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added "${track.name}" to download queue')),
      );
    }
  }

  void _toggleLike(Track track) async {
    final notifier = ref.read(libraryCollectionsProvider.notifier);
    final state = ref.read(libraryCollectionsProvider);
    if (state.isLoved(track)) {
      await notifier.removeFromLoved(trackCollectionKey(track));
    } else {
      await notifier.toggleLoved(track);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for track changes to update colors and lyrics
    ref.listen<StreamingAudioState>(streamingAudioProvider, (prev, next) {
      if (prev?.currentTrack?.track.id != next.currentTrack?.track.id) {
        final newTrack = next.currentTrack?.track;
        _extractColors(newTrack?.coverUrl);
        setState(() {
          _rawLyrics = null;
          _lrcLines = [];
          _lyricsKeys = [];
          _lastScrolledTrackId = null;
          // Return to default view if track completely changes? We keep the viewmode the user prefers.
        });
        if (_viewMode == _PlayerViewMode.lyrics && newTrack != null) {
          _fetchLyrics(newTrack);
        }
      }
    });

    final s = ref.watch(streamingAudioProvider);
    final notifier = ref.read(streamingAudioProvider.notifier);
    final track = s.currentTrack?.track;
    final isPlaying = s.state == PlaybackState.playing;
    final isLoading = s.state == PlaybackState.loading;

    // Auto-scroll lyrics
    if (_viewMode == _PlayerViewMode.lyrics &&
        _lrcLines.isNotEmpty &&
        track != null) {
      final activeIdx = _activeLrcIndex(_lrcLines, s.position);
      final scrollKey = '${track.id}_$activeIdx';
      if (scrollKey != _lastScrolledTrackId) {
        _lastScrolledTrackId = scrollKey;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollToActiveLine(activeIdx),
        );
      }
    }

    final isMinimisedMode = _viewMode != _PlayerViewMode.defaultView;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.black, // Deep OLED black
      body: GestureDetector(
        onPanUpdate: (details) {
          if (details.delta.dx < -10 && _viewMode != _PlayerViewMode.lyrics) {
            // Swipe left -> lyrics
            _setViewMode(_PlayerViewMode.lyrics, track);
          } else if (details.delta.dx > 10 &&
              _viewMode != _PlayerViewMode.defaultView) {
            // Swipe right -> default
            _setViewMode(_PlayerViewMode.defaultView, track);
          }
        },
        child: Stack(
          children: [
            // ── Dynamic Background Gradient ──
            AnimatedContainer(
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topLeft,
                  radius: 1.5,
                  colors: [
                    _dominantColor.withValues(alpha: 0.35),
                    _mutedColor.withValues(alpha: 0.15),
                    Colors.black,
                  ],
                ),
              ),
            ),

            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 50),
                  // ── Drag handle ──
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 8),
                      width: 36,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),

                  // ── Animated Album Art ──
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOutBack,
                    height: isMinimisedMode ? 60 : screenWidth * 0.9,
                    margin: isMinimisedMode
                        ? const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 8,
                          )
                        : EdgeInsets.symmetric(
                            horizontal: screenWidth * 0.05,
                            vertical: 24,
                          ),
                    child: Stack(
                      children: [
                        AnimatedAlign(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOutBack,
                          alignment: isMinimisedMode
                              ? Alignment.centerLeft
                              : Alignment.topCenter,
                          child: AspectRatio(
                            aspectRatio: 1.0,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 400),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  isMinimisedMode ? 8 : 24,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    blurRadius: isMinimisedMode ? 10 : 30,
                                    offset: Offset(0, isMinimisedMode ? 4 : 15),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  isMinimisedMode ? 8 : 24,
                                ),
                                child: track?.coverUrl != null
                                    ? CachedNetworkImage(
                                        imageUrl: track!.coverUrl!,
                                        fit: BoxFit.cover,
                                        placeholder: (_, __) =>
                                            _artPlaceholder(),
                                        errorWidget: (_, __, ___) =>
                                            _artPlaceholder(),
                                      )
                                    : _artPlaceholder(),
                              ),
                            ),
                          ),
                        ),

                        // Text Info placed besides the minimised album art
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 300),
                          opacity: isMinimisedMode ? 1.0 : 0.0,
                          child: IgnorePointer(
                            ignoring: !isMinimisedMode,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  left: 76.0,
                                ), // 60 width + 16 spacing
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      track?.name ?? 'Loading…',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    ClickableArtistName(
                                      artistName: track?.artistName ?? '',
                                      artistId: track?.artistId,
                                      extensionId: track?.source,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.7,
                                        ),
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Expanded Content (Lyrics or Queue) ──
                  Expanded(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      opacity: isMinimisedMode ? 1.0 : 0.0,
                      child: isMinimisedMode
                          ? (_viewMode == _PlayerViewMode.lyrics
                                ? _buildSyncedLyrics(s, notifier)
                                : _buildQueueList(s, notifier))
                          : const SizedBox(),
                    ),
                  ),

                  // ── Title, Artist & Like Row (Only visible in Default mode) ──
                  if (!isMinimisedMode)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track?.name ?? 'Loading…',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                ClickableArtistName(
                                  artistName: track?.artistName ?? '',
                                  artistId: track?.artistId,
                                  extensionId: track?.source,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          // Specific Like button requested by user
                          if (track != null)
                            Consumer(
                              builder: (context, ref, child) {
                                final isLoved = ref
                                    .watch(libraryCollectionsProvider)
                                    .isLoved(track);
                                return Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    icon: Icon(
                                      isLoved
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color: isLoved
                                          ? Colors.white
                                          : Colors.white.withValues(alpha: 0.6),
                                    ),
                                    onPressed: () => _toggleLike(track),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 12),

                  // ── Apple Progress Bar ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: SizedBox(
                      height: 40,
                      child: AppleProgressBar(
                        position: s.position,
                        duration: s.duration,
                        onSeek: (newPos) => notifier.seek(newPos),
                      ),
                    ),
                  ),

                  // Timestamps
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _fmt(s.position),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          _fmt(s.duration),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── Circular iOS Style Playback Controls ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Shuffle / Prev Control
                        IconButton(
                          iconSize: 32,
                          icon: Icon(
                            Icons.fast_rewind_rounded,
                            color: Colors.white.withValues(
                              alpha:
                                  (s.currentQueueIndex > 0 || s.shuffling) &&
                                      s.queue.isNotEmpty
                                  ? 1.0
                                  : 0.4,
                            ),
                          ),
                          onPressed:
                              (s.currentQueueIndex > 0 || s.shuffling) &&
                                  s.queue.isNotEmpty
                              ? () => notifier.playPreviousInQueue()
                              : null,
                        ),

                        // Play / Pause Circle
                        GestureDetector(
                          onTap: isLoading ? null : () => notifier.toggle(),
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: isLoading
                                ? const Padding(
                                    padding: EdgeInsets.all(22.0),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: Colors.black,
                                    ),
                                  )
                                : Icon(
                                    isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.black,
                                    size: 42,
                                  ),
                          ),
                        ),

                        // Next Control
                        IconButton(
                          iconSize: 32,
                          icon: Icon(
                            Icons.fast_forward_rounded,
                            color: Colors.white.withValues(
                              alpha:
                                  (s.currentQueueIndex < s.queue.length - 1 ||
                                          s.shuffling) &&
                                      s.queue.isNotEmpty
                                  ? 1.0
                                  : 0.4,
                            ),
                          ),
                          onPressed:
                              (s.currentQueueIndex < s.queue.length - 1 ||
                                      s.shuffling) &&
                                  s.queue.isNotEmpty
                              ? () => notifier.playNextInQueue()
                              : null,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Bottom Action Toggles (Lyrics, Queue, Download, Shuffle, Repeat) ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _iconToggle(
                          icon: Icons.library_books_rounded,
                          active: _viewMode == _PlayerViewMode.lyrics,
                          onTap: () =>
                              _setViewMode(_PlayerViewMode.lyrics, track),
                        ),
                        _iconToggle(
                          icon: Icons.shuffle_rounded,
                          active: s.shuffling,
                          onTap: () {
                            notifier.toggleShuffle();
                            // Show feedback
                            final newState = !s.shuffling;
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  newState
                                      ? '✓ Shuffle enabled - queue reordered'
                                      : '✓ Shuffle disabled - original order restored',
                                ),
                                duration: const Duration(milliseconds: 1500),
                                backgroundColor: newState
                                    ? Colors.blue
                                    : Colors.grey[800],
                              ),
                            );
                          },
                        ),
                        // Queue / List icon
                        _iconToggle(
                          icon: Icons.format_list_bulleted_rounded,
                          active: _viewMode == _PlayerViewMode.queue,
                          onTap: () =>
                              _setViewMode(_PlayerViewMode.queue, track),
                        ),
                        _iconToggle(
                          icon: s.looping
                              ? Icons.repeat_one_rounded
                              : Icons.repeat_rounded,
                          active: s.looping,
                          onTap: () => notifier.toggleLoop(),
                        ),
                        // Download icon
                        IconButton(
                          icon: Icon(
                            Icons.download_rounded,
                            color: Colors.white.withValues(alpha: 0.6),
                            size: 24,
                          ),
                          onPressed: track != null
                              ? () => _downloadCurrentTrack(track)
                              : null,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper formatting for timestamps
  String _fmt(Duration d) {
    if (d.inMilliseconds < 0) return '0:00';
    final m = d.inMinutes;
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  Widget _artPlaceholder() {
    return Container(
      color: Colors.grey[900],
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 48,
          color: Colors.grey[700],
        ),
      ),
    );
  }

  Widget _iconToggle({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: active
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 20,
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  // ── Synced Lyrics Widget ──
  Widget _buildSyncedLyrics(
    StreamingAudioState s,
    StreamingAudioNotifier notifier,
  ) {
    if (_isLoadingLyrics) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_lrcLines.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _rawLyrics ?? 'No lyrics available.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 18,
              height: 1.6,
            ),
          ),
        ),
      );
    }

    final activeIdx = _activeLrcIndex(_lrcLines, s.position);

    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: const [0.0, 0.15, 0.85, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: List.generate(_lrcLines.length, (i) {
            final line = _lrcLines[i];
            final isActive = i == activeIdx;
            return GestureDetector(
              key: _lyricsKeys[i],
              onTap: () => notifier.seek(line.timestamp),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  alignment: Alignment.centerLeft,
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 300),
                    style: TextStyle(
                      fontSize: isActive ? 30 : 20,
                      fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                      color: isActive
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.4),
                      fontFamily:
                          'SF Pro Display',
                      height: 1.4,
                    ),
                    child: Text(
                      line.text,
                      maxLines: null,
                      overflow: TextOverflow.visible,
                      softWrap: true,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  // ── Queue List Widget ──
  Widget _buildQueueList(
    StreamingAudioState s,
    StreamingAudioNotifier notifier,
  ) {
    if (s.queue.isEmpty) {
      return const Center(
        child: Text(
          'No tracks in queue',
          style: TextStyle(color: Colors.white54, fontSize: 18),
        ),
      );
    }

    final upcomingStart = s.currentQueueIndex + 1;
    final upcoming = upcomingStart < s.queue.length
        ? s.queue.sublist(upcomingStart)
        : <StreamingTrackInfo>[];

    if (upcoming.isEmpty) {
      return const Center(
        child: Text(
          'Queue finished',
          style: TextStyle(color: Colors.white54, fontSize: 18),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Shuffle Indicator ──
        if (s.shuffling)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.shuffle, color: Colors.blue, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Queue is shuffled - new order shown below',
                    style: TextStyle(
                      color: Colors.blue.withValues(alpha: 0.9),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Text(
            'Up Next',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: EdgeInsets.zero,
            itemCount: upcoming.length,
            physics: const BouncingScrollPhysics(),
            onReorder: (oldIndex, newIndex) {
              if (oldIndex < newIndex) {
                newIndex -= 1;
              }
              notifier.reorderQueue(
                upcomingStart + oldIndex,
                upcomingStart + newIndex,
              );
            },
            itemBuilder: (context, i) {
              final item = upcoming[i];
              final realIndex = upcomingStart + i;
              return Dismissible(
                key: ValueKey(
                  '${item.track.id}_${item.addedAt.millisecondsSinceEpoch}',
                ),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  color: Colors.redAccent,
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                onDismissed: (_) => notifier.removeFromQueue(realIndex),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 4,
                  ),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: item.track.coverUrl != null
                          ? CachedNetworkImage(
                              imageUrl: item.track.coverUrl!,
                              fit: BoxFit.cover,
                            )
                          : _artPlaceholder(),
                    ),
                  ),
                  title: Text(
                    item.track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    item.track.artistName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 14,
                    ),
                  ),
                  trailing: Icon(
                    Icons.drag_handle_rounded,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  onTap: () => notifier.playQueueIndex(realIndex),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
