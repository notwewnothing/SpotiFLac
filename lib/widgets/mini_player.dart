import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:spotiflac_android/providers/streaming_audio_provider.dart';
import 'package:spotiflac_android/screens/streaming_player_screen.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/services/cover_cache_manager.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioState = ref.watch(streamingAudioProvider);

    if (audioState.currentTrack == null) {
      return const SizedBox.shrink();
    }

    final track = audioState.currentTrack!.track;
    final isPlaying = audioState.state == PlaybackState.playing;
    final isLoading = audioState.state == PlaybackState.loading;
    final isLoved = ref.watch(libraryCollectionsProvider).isLoved(track);

    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useRootNavigator: true,
          backgroundColor: Colors.transparent, // Let StreamingPlayerScreen handle its own background
          builder: (context) => StreamingPlayerScreen(
            track: track,
            service: audioState.currentTrack!.service,
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
          child: Container(
            margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4), // Frosted glass dark background
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    // Album Art
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: track.coverUrl != null && track.coverUrl!.isNotEmpty
                          ? Hero(
                              tag: 'album_art_${track.id}',
                              child: CachedNetworkImage(
                                imageUrl: track.coverUrl!,
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                                cacheManager: CoverCacheManager.instance,
                              ),
                            )
                          : Container(
                              width: 48,
                              height: 48,
                              color: Colors.grey[850],
                              child: Icon(Icons.music_note, color: Colors.grey[600]),
                            ),
                    ),

                    const SizedBox(width: 12),

                    // Track Info
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.artistName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Controls
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Like Button integration into mini player
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(
                            isLoved ? Icons.favorite : Icons.favorite_border_rounded,
                            color: isLoved ? Colors.white : Colors.grey[500],
                            size: 24,
                          ),
                          onPressed: () async {
                            final notifier = ref.read(libraryCollectionsProvider.notifier);
                            if (isLoved) {
                              await notifier.removeFromLoved(trackCollectionKey(track));
                            } else {
                              await notifier.toggleLoved(track);
                            }
                          },
                        ),
                        const SizedBox(width: 16),
                        // Play/Pause Button
                        GestureDetector(
                          onTap: isLoading ? null : () {
                            ref.read(streamingAudioProvider.notifier).toggle();
                          },
                          child: isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 32,
                                ),
                        ),
                        const SizedBox(width: 16),
                        // Next Button
                        GestureDetector(
                          onTap: (audioState.currentQueueIndex < audioState.queue.length - 1 || audioState.looping)
                              ? () {
                                  ref.read(streamingAudioProvider.notifier).playNextInQueue();
                                }
                              : null,
                          child: Icon(
                            Icons.skip_next_rounded,
                            color: (audioState.currentQueueIndex < audioState.queue.length - 1 || audioState.looping)
                                ? Colors.white
                                : Colors.grey[700],
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ],
                ),
              ),
              // Progress bar attached to the bottom of the pill
              if (audioState.duration.inMilliseconds > 0)
                LinearProgressIndicator(
                  value: (audioState.position.inMilliseconds / audioState.duration.inMilliseconds).clamp(0.0, 1.0),
                  minHeight: 2,
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
            ],
          ),
        ),
        ), // BackdropFilter
      ), // ClipRRect
    );
  }
}
