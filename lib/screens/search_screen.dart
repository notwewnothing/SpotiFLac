import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/services/cover_cache_manager.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/track_provider.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/playback_provider.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/screens/album_screen.dart';
import 'package:spotiflac_android/screens/artist_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  final String query;

  const SearchScreen({super.key, required this.query});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late TextEditingController _searchController;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.query);
    if (widget.query.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _search(_searchController.text);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _search(String query, {String? filter}) {
    if (query.trim().isEmpty) return;
    ref.read(trackProvider.notifier).search(
          query.trim(),
          filterOverride: filter,
        );
  }

  void _downloadTrack(Track track) {
    final settings = ref.read(settingsProvider);
    ref.read(downloadQueueProvider.notifier).addToQueue(track, settings.defaultService);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added "${track.name}" to queue')),
    );
  }

  void _toggleFilter(String? currentFilter, String? targetFilter) {
    final newFilter = currentFilter == targetFilter ? null : targetFilter;
    // Just re-trigger the search with the new filter
    _search(_searchController.text, filter: newFilter);
  }

  @override
  Widget build(BuildContext context) {
    final trackState = ref.watch(trackProvider);
    final isLoading = trackState.isLoading;
    final error = trackState.error;
    final currentFilter = trackState.selectedSearchFilter;

    return Scaffold(
      backgroundColor: Colors.black, // OLED black
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Area: Search Bar ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.grey[900], // Dark gray pill
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _focusNode,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        autofocus: widget.query.isEmpty,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (val) => _search(val, filter: currentFilter),
                        decoration: InputDecoration(
                          hintText: 'Search tracks, albums, artists...',
                          hintStyle: TextStyle(color: Colors.grey[500]),
                          prefixIcon: Icon(Icons.search_rounded, color: Colors.grey[500]),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.clear_rounded, color: Colors.grey[500]),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onChanged: (val) => setState(() {}),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Filter Pills ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _buildFilterPill('Tracks', 'track', currentFilter),
                    const SizedBox(width: 8),
                    _buildFilterPill('Albums', 'album', currentFilter),
                    const SizedBox(width: 8),
                    _buildFilterPill('Artists', 'artist', currentFilter),
                  ],
                ),
              ),
            ),

            // ── Loading & Errors ──
            if (isLoading)
              const Padding(
                padding: EdgeInsets.all(24.0),
                child: CircularProgressIndicator(color: Colors.white),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(error, style: const TextStyle(color: Colors.redAccent)),
              ),

            // ── Results List ──
            Expanded(
              child: _buildResultList(trackState, currentFilter),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPill(String label, String value, String? currentFilter) {
    final isActive = currentFilter == value;
    return GestureDetector(
      onTap: () => _toggleFilter(currentFilter, value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.grey[900],
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isActive ? Colors.white : Colors.transparent, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.black : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildResultList(TrackState state, String? filter) {
    if (!state.isLoading && !state.hasContent && _searchController.text.isNotEmpty && state.error == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 60, color: Colors.grey[800]),
            const SizedBox(height: 16),
            Text(
              "Couldn't find '${_searchController.text}'",
              style: TextStyle(color: Colors.grey[500], fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (!state.hasContent) return const SizedBox.shrink();

    // Depending on filter, show the corresponding list. If no filter, maybe show all (or just tracks)
    if (filter == 'album' && state.searchAlbums != null && state.searchAlbums!.isNotEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: state.searchAlbums!.length,
        itemBuilder: (context, idx) => _buildSearchAlbumTile(state.searchAlbums![idx]),
      );
    } else if (filter == 'artist' && state.searchArtists != null && state.searchArtists!.isNotEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: state.searchArtists!.length,
        itemBuilder: (context, idx) => _buildSearchArtistTile(state.searchArtists![idx]),
      );
    } else {
      // Default to tracks
      if (state.tracks.isEmpty) return const SizedBox.shrink();
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: state.tracks.length,
        itemBuilder: (context, idx) => _buildTrackTile(state.tracks[idx]),
      );
    }
  }

  Widget _buildTrackTile(Track track) {
    final isLoved = ref.watch(libraryCollectionsProvider).isLoved(track);
    
    return InkWell(
      onTap: () {
        _focusNode.unfocus();
        final settings = ref.read(settingsProvider);
        if (settings.appmode == 'stream') {
          ref.read(playbackProvider.notifier).playTrack(track: track, service: settings.defaultService);
        } else {
          _downloadTrack(track);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: track.coverUrl != null
                  ? CachedNetworkImage(
                      imageUrl: track.coverUrl!,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      cacheManager: CoverCacheManager.instance,
                    )
                  : Container(
                      width: 52,
                      height: 52,
                      color: Colors.grey[900],
                      child: Icon(Icons.music_note, color: Colors.grey[700]),
                    ),
            ),
            const SizedBox(width: 16),
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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          track.artistName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey[400], fontSize: 14),
                        ),
                      ),
                      if (track.albumName.isNotEmpty) ...[
                        Text(' · ', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
                        Flexible(
                          child: Text(
                            track.albumName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.grey[500], fontSize: 14),
                          ),
                        ),
                      ]
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // iOS Custom Like pattern
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
            const SizedBox(width: 8),
            // Menu
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: Colors.grey[500], size: 20),
              color: Colors.grey[900],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (value) {
                if (value == 'download') _downloadTrack(track);
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'download',
                  child: Text('Download', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAlbumTile(SearchAlbum album) {
    return InkWell(
      onTap: () {
        _focusNode.unfocus();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AlbumScreen(
              albumId: album.id,
              albumName: album.name,
              coverUrl: album.imageUrl,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: album.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: album.imageUrl!,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 60,
                      height: 60,
                      color: Colors.grey[900],
                      child: Icon(Icons.album_rounded, color: Colors.grey[700]),
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Album · ${album.artists}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.grey[600]),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchArtistTile(SearchArtist artist) {
    return InkWell(
      onTap: () {
        _focusNode.unfocus();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ArtistScreen(
              artistId: artist.id,
              artistName: artist.name,
              coverUrl: artist.imageUrl,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ClipOval(
              child: artist.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: artist.imageUrl!,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 60,
                      height: 60,
                      color: Colors.grey[900],
                      child: Icon(Icons.person_rounded, color: Colors.grey[700]),
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Artist',
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.grey[600]),
          ],
        ),
      ),
    );
  }
}
