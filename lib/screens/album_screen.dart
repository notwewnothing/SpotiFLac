import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:spotiflac_android/services/cover_cache_manager.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/recent_access_provider.dart';
import 'package:spotiflac_android/providers/streaming_audio_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/playback_provider.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/widgets/track_collection_quick_actions.dart';
import 'package:spotiflac_android/widgets/download_service_picker.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/widgets/playlist_picker_sheet.dart';
import 'package:spotiflac_android/utils/clickable_metadata.dart';

class _AlbumCache {
  static final Map<String, _CacheEntry> _cache = {};
  static const Duration _ttl = Duration(minutes: 10);

  static List<Track>? get(String albumId) {
    final entry = _cache[albumId];
    if (entry == null) return null;
    if (DateTime.now().isAfter(entry.expiresAt)) {
      _cache.remove(albumId);
      return null;
    }
    return entry.tracks;
  }

  static void set(String albumId, List<Track> tracks) {
    _cache[albumId] = _CacheEntry(tracks, DateTime.now().add(_ttl));
  }
}

class _CacheEntry {
  final List<Track> tracks;
  final DateTime expiresAt;
  _CacheEntry(this.tracks, this.expiresAt);
}

class AlbumScreen extends ConsumerStatefulWidget {
  final String albumId;
  final String albumName;
  final String? coverUrl;
  final List<Track>? tracks;
  final String? extensionId;
  final String? artistId;
  final String? artistName;

  const AlbumScreen({
    super.key,
    required this.albumId,
    required this.albumName,
    this.coverUrl,
    this.tracks,
    this.extensionId,
    this.artistId,
    this.artistName,
  });

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen> {
  List<Track>? _tracks;
  bool _isLoading = false;
  String? _error;
  bool _showTitleInAppBar = false;
  String? _artistId;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final providerId =
          widget.extensionId ??
          (() {
            if (widget.albumId.startsWith('deezer:')) return 'deezer';
            if (widget.albumId.startsWith('qobuz:')) return 'qobuz';
            if (widget.albumId.startsWith('tidal:')) return 'tidal';
            return 'spotify';
          })();
      ref
          .read(recentAccessProvider.notifier)
          .recordAlbumAccess(
            id: widget.albumId,
            name: widget.albumName,
            artistName: widget.artistName ?? widget.tracks?.firstOrNull?.albumArtist ?? widget.tracks?.firstOrNull?.artistName,
            imageUrl: widget.coverUrl,
            providerId: providerId,
          );
    });

    if (widget.tracks != null && widget.tracks!.isNotEmpty) {
      _tracks = widget.tracks;
    } else {
      _tracks = _AlbumCache.get(widget.albumId);
    }
    _artistId = widget.artistId;

    if (_tracks == null || _tracks!.isEmpty) {
      _fetchTracks();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final expandedHeight = _calculateExpandedHeight(context);
    final shouldShow =
        _scrollController.offset > (expandedHeight - kToolbarHeight - 20);
    if (shouldShow != _showTitleInAppBar) {
      setState(() => _showTitleInAppBar = shouldShow);
    }
  }

  double _calculateExpandedHeight(BuildContext context) {
    final mediaSize = MediaQuery.of(context).size;
    return (mediaSize.height * 0.55).clamp(360.0, 520.0);
  }

  /// Upgrade cover URL to a higher resolution for full-screen display.
  String? _highResCoverUrl(String? url) {
    if (url == null) return null;
    // Spotify CDN: upgrade 300 → 640 only (no intermediate between 640 and 2000)
    if (url.contains('ab67616d00001e02')) {
      return url.replaceAll('ab67616d00001e02', 'ab67616d0000b273');
    }
    // Deezer CDN: upgrade to 1000x1000
    final deezerRegex = RegExp(r'/(\d+)x(\d+)-(\d+)-(\d+)-(\d+)-(\d+)\.jpg$');
    if (url.contains('cdn-images.dzcdn.net') && deezerRegex.hasMatch(url)) {
      return url.replaceAllMapped(
        deezerRegex,
        (m) => '/1000x1000-${m[3]}-${m[4]}-${m[5]}-${m[6]}.jpg',
      );
    }
    return url;
  }

  String _formatReleaseDate(String date) {
    if (date.length >= 10) {
      final parts = date.substring(0, 10).split('-');
      if (parts.length == 3) {
        return '${parts[2]}/${parts[1]}/${parts[0]}';
      }
    } else if (date.length >= 7) {
      final parts = date.split('-');
      if (parts.length >= 2) {
        return '${parts[1]}/${parts[0]}';
      }
    }
    return date;
  }

  Future<void> _fetchTracks() async {
    setState(() => _isLoading = true);
    try {
      Map<String, dynamic> metadata;

      if (widget.albumId.startsWith('deezer:')) {
        final deezerAlbumId = widget.albumId.replaceFirst('deezer:', '');
        metadata = await PlatformBridge.getDeezerMetadata(
          'album',
          deezerAlbumId,
        );
      } else if (widget.albumId.startsWith('qobuz:')) {
        final qobuzAlbumId = widget.albumId.replaceFirst('qobuz:', '');
        metadata = await PlatformBridge.getQobuzMetadata('album', qobuzAlbumId);
      } else if (widget.albumId.startsWith('tidal:')) {
        final tidalAlbumId = widget.albumId.replaceFirst('tidal:', '');
        metadata = await PlatformBridge.getTidalMetadata('album', tidalAlbumId);
      } else {
        final url = 'https://open.spotify.com/album/${widget.albumId}';
        metadata = await PlatformBridge.getSpotifyMetadataWithFallback(url);
      }

      final trackList = metadata['track_list'] as List<dynamic>;
      final tracks = trackList
          .map((t) => _parseTrack(t as Map<String, dynamic>))
          .toList();

      final albumInfo = metadata['album_info'] as Map<String, dynamic>?;
      final artistId = (albumInfo?['artist_id'] ?? albumInfo?['artistId'])
          ?.toString();

      _AlbumCache.set(widget.albumId, tracks);

      if (mounted) {
        setState(() {
          _tracks = tracks;
          _artistId = artistId;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Track _parseTrack(Map<String, dynamic> data) {
    return Track(
      id: data['spotify_id'] as String? ?? '',
      name: data['name'] as String? ?? '',
      artistName: data['artists'] as String? ?? '',
      albumName: data['album_name'] as String? ?? '',
      albumArtist: data['album_artist'] as String?,
      artistId:
          (data['artist_id'] ?? data['artistId'])?.toString() ?? _artistId,
      albumId: data['album_id']?.toString() ?? widget.albumId,
      coverUrl: data['images'] as String?,
      isrc: data['isrc'] as String?,
      duration: ((data['duration_ms'] as int? ?? 0) / 1000).round(),
      trackNumber: data['track_number'] as int?,
      discNumber: data['disc_number'] as int?,
      releaseDate: data['release_date'] as String?,
      albumType: data['album_type'] as String?,
      totalTracks: data['total_tracks'] as int?,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _tracks ?? [];

    return Scaffold(
      backgroundColor: Colors.black, // OLED black
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          _buildAppBar(context),
          if (!_isLoading && _error == null) _buildHeader(context, tracks),
          if (_isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator(color: Colors.white)),
              ),
            ),
          if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildErrorWidget(_error!),
              ),
            ),
          if (!_isLoading && _error == null && tracks.isNotEmpty)
            _buildTrackList(context, tracks),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: Colors.black.withValues(alpha: _showTitleInAppBar ? 0.9 : 0.0),
      elevation: 0,
      title: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _showTitleInAppBar ? 1.0 : 0.0,
        child: Text(
          widget.albumName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, List<Track> tracks) {
    final artistName = tracks.isNotEmpty ? tracks.first.artistName : null;
    final releaseDate = tracks.isNotEmpty ? tracks.first.releaseDate : null;
    
    // Calculate total duration
    int totalSecs = 0;
    for (var t in tracks) totalSecs += t.duration;
    final mins = totalSecs ~/ 60;

    final collectionsState = ref.watch(libraryCollectionsProvider);
    final allLoved = tracks.isNotEmpty && tracks.every((t) => collectionsState.isLoved(t));

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 10),
            // Large Square Album Art
            Container(
              width: MediaQuery.of(context).size.width * 0.75,
              height: MediaQuery.of(context).size.width * 0.75,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.1),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  )
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: widget.coverUrl != null
                    ? CachedNetworkImage(
                        imageUrl: _highResCoverUrl(widget.coverUrl) ?? widget.coverUrl!,
                        fit: BoxFit.cover,
                        cacheManager: CoverCacheManager.instance,
                        placeholder: (_, __) => Container(color: Colors.grey[900]),
                        errorWidget: (_, _, _) => Container(color: Colors.grey[900]),
                      )
                    : Container(
                        color: Colors.grey[900],
                        child: Icon(Icons.album, size: 80, color: Colors.grey[800]),
                      ),
              ),
            ),
            const SizedBox(height: 24),
            // ALL CAPS Title
            Text(
              widget.albumName.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            // Clickable Artist name
            if (artistName != null && artistName.isNotEmpty)
              ClickableArtistName(
                artistName: artistName,
                artistId: _artistId,
                coverUrl: widget.coverUrl,
                extensionId: widget.extensionId,
                style: const TextStyle(
                  color: Colors.redAccent, // Or a primary color
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 6),
            // Track count / duration
            Text(
              'Album · ${releaseDate != null ? _formatReleaseDate(releaseDate) + ' · ' : ''}${tracks.length} tracks, $mins min',
              style: TextStyle(color: Colors.grey[500], fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 24),
            // Primary Actions Row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Play Button (Left)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final settings = ref.watch(settingsProvider);
                      return FilledButton.icon(
                        onPressed: tracks.isEmpty ? null : () {
                          ref.read(streamingAudioProvider.notifier).playTrack(
                            tracks.first,
                            settings.defaultService,
                            playlist: tracks,
                          );
                        },
                        icon: const Icon(Icons.play_arrow_rounded, size: 24, color: Colors.black),
                        label: const Text('Play', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      );
                    }
                  ),
                ),
                const SizedBox(width: 12),
                // Download Button (Center)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: tracks.isEmpty ? null : () => _downloadAll(context, tracks),
                    icon: const Icon(Icons.cloud_download_rounded, size: 22, color: Colors.white),
                    label: const Text('Download', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.grey[850],
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Like Album Button (Right)
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.grey[850],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: IconButton(
                    onPressed: tracks.isEmpty ? null : () => _loveAll(tracks),
                    icon: Icon(
                      allLoved ? Icons.favorite : Icons.favorite_border_rounded,
                      color: allLoved ? Colors.white : Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _downloadAll(BuildContext context, List<Track> tracks) {
    if (tracks.isEmpty) return;
    final settings = ref.read(settingsProvider);
    if (settings.askQualityBeforeDownload) {
      DownloadServicePicker.show(
        context,
        trackName: '${tracks.length} tracks',
        artistName: widget.albumName,
        onSelect: (quality, service) {
          ref.read(downloadQueueProvider.notifier).addMultipleToQueue(tracks, service, qualityOverride: quality);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.snackbarAddedTracksToQueue(tracks.length))));
        },
      );
    } else {
      ref.read(downloadQueueProvider.notifier).addMultipleToQueue(tracks, settings.defaultService);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.snackbarAddedTracksToQueue(tracks.length))));
    }
  }

  Future<void> _loveAll(List<Track> tracks) async {
    final notifier = ref.read(libraryCollectionsProvider.notifier);
    final state = ref.read(libraryCollectionsProvider);
    final allLoved = tracks.every((t) => state.isLoved(t));

    if (allLoved) {
      for (final track in tracks) {
        await notifier.removeFromLoved(trackCollectionKey(track));
      }
    } else {
      for (final track in tracks) {
        if (!state.isLoved(track)) {
          await notifier.toggleLoved(track);
        }
      }
    }
  }

  Widget _buildTrackList(BuildContext context, List<Track> tracks) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final track = tracks[index];
        return KeyedSubtree(
          key: ValueKey(track.id),
          child: _AlbumTrackItem(
            track: track,
            onDownload: () => _downloadTrack(context, track),
          ),
        );
      }, childCount: tracks.length),
    );
  }

  void _downloadTrack(BuildContext context, Track track) {
  // Unused inside the unified track item which uses a Like button instead of down arrow directly, 
  // but kept for API compat. 
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
            SnackBar(
              content: Text(context.l10n.snackbarAddedToQueue(track.name)),
            ),
          );
        },
      );
    } else {
      ref
          .read(downloadQueueProvider.notifier)
          .addToQueue(track, settings.defaultService);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.snackbarAddedToQueue(track.name))),
      );
    }
  }

  Widget _buildErrorWidget(String error) {
    return Card(
      color: Colors.red.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent),
            const SizedBox(width: 12),
            Expanded(child: Text(error, style: const TextStyle(color: Colors.redAccent))),
          ],
        ),
      ),
    );
  }

}

class _AlbumTrackItem extends ConsumerWidget {
  final Track track;
  final VoidCallback onDownload;

  const _AlbumTrackItem({required this.track, required this.onDownload});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoved = ref.watch(libraryCollectionsProvider).isLoved(track);
    final queueItem = ref.watch(downloadQueueLookupProvider.select((lookup) => lookup.byTrackId[track.id]));
    final isQueued = queueItem != null;

    final mins = track.duration ~/ 60;
    final secs = (track.duration % 60).toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () => _handleTap(context, ref, isQueued: isQueued),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  '${track.trackNumber ?? 0}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[500], fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.artistName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey[400], fontSize: 13),
                    ),
                  ],
                ),
              ),
              Text(
                '$mins:$secs',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
              const SizedBox(width: 12),
              // Dedicated Like Button
              GestureDetector(
                onTap: () async {
                  final notifier = ref.read(libraryCollectionsProvider.notifier);
                  if (isLoved) {
                    await notifier.removeFromLoved(trackCollectionKey(track));
                  } else {
                    await notifier.toggleLoved(track);
                  }
                },
                child: Icon(
                  isLoved ? Icons.favorite : Icons.favorite_border_rounded,
                  color: isLoved ? Colors.white : Colors.grey[500],
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              // 3-Dot Menu (Add to Queue, Save Song)
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: Colors.grey[500], size: 20),
                color: Colors.grey[900],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (value) {
                  if (value == 'queue') {
                    ref.read(streamingAudioProvider.notifier).addToQueue(track, ref.read(settingsProvider).defaultService);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to Queue')));
                  } else if (value == 'save') {
                    onDownload();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'queue',
                    child: Text('Add to Queue', style: TextStyle(color: Colors.white)),
                  ),
                  const PopupMenuItem(
                    value: 'save',
                    child: Text('Save Song (Download)', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleTap(
    BuildContext context,
    WidgetRef ref, {
    required bool isQueued,
  }) async {
    if (isQueued) return;

    final settings = ref.read(settingsProvider);
    if (settings.appmode == 'stream') {
      await ref.read(playbackProvider.notifier).playTrack(
            track: track,
            service: settings.defaultService,
          );
      return;
    }

    final playedLocal = await _playLocalIfAvailable(context, ref);
    if (playedLocal) {
      return;
    }

    onDownload();
  }

  Future<bool> _playLocalIfAvailable(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final localState = ref.read(localLibraryProvider);
    final historyState = ref.read(downloadHistoryProvider);
    final historyNotifier = ref.read(downloadHistoryProvider.notifier);

    try {
      DownloadHistoryItem? historyItem = historyNotifier.getBySpotifyId(
        track.id,
      );
      final isrc = track.isrc?.trim();
      historyItem ??= (isrc != null && isrc.isNotEmpty)
          ? historyNotifier.getByIsrc(isrc)
          : null;
      historyItem ??= historyState.findByTrackAndArtist(
        track.name,
        track.artistName,
      );

      if (historyItem != null) {
        final exists = await fileExists(historyItem.filePath);
        if (exists) {
          await ref
              .read(playbackProvider.notifier)
              .playLocalPath(
                path: historyItem.filePath,
                title: track.name,
                artist: track.artistName,
                album: track.albumName,
                coverUrl: track.coverUrl ?? '',
              );
          return true;
        }
        historyNotifier.removeFromHistory(historyItem.id);
      }

      var localItem = (isrc != null && isrc.isNotEmpty)
          ? localState.getByIsrc(isrc)
          : null;
      localItem ??= localState.findByTrackAndArtist(
        track.name,
        track.artistName,
      );

      if (localItem != null && await fileExists(localItem.filePath)) {
        await ref
            .read(playbackProvider.notifier)
            .playLocalPath(
              path: localItem.filePath,
              title: localItem.trackName,
              artist: localItem.artistName,
              album: localItem.albumName,
              coverUrl: localItem.coverPath ?? track.coverUrl ?? '',
            );
        return true;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.snackbarCannotOpenFile('$e'))),
        );
      }
      return true;
    }

    return false;
  }
}
