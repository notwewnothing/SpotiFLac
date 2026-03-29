import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/services/app_state_database.dart';
import 'package:spotiflac_android/utils/platform_spoof.dart' as platform;

const _maxRecentItems = 20;

/// Types of items that can be accessed
enum RecentAccessType { artist, album, track, playlist }

/// Represents a recently accessed item
class RecentAccessItem {
  final String id;
  final String name;
  final String? subtitle; // Artist name for tracks/albums, null for artists
  final String? imageUrl;
  final RecentAccessType type;
  final DateTime accessedAt;
  final String? providerId; // Extension ID or 'deezer' for built-in

  const RecentAccessItem({
    required this.id,
    required this.name,
    this.subtitle,
    this.imageUrl,
    required this.type,
    required this.accessedAt,
    this.providerId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'subtitle': subtitle,
    'imageUrl': imageUrl,
    'type': type.name,
    'accessedAt': accessedAt.toIso8601String(),
    'providerId': providerId,
  };

  factory RecentAccessItem.fromJson(Map<String, dynamic> json) {
    return RecentAccessItem(
      id: json['id'] as String,
      name: json['name'] as String,
      subtitle: json['subtitle'] as String?,
      imageUrl: json['imageUrl'] as String?,
      type: RecentAccessType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => RecentAccessType.track,
      ),
      accessedAt: DateTime.parse(json['accessedAt'] as String),
      providerId: json['providerId'] as String?,
    );
  }

  /// Create a unique key for deduplication
  String get uniqueKey => '${type.name}:${providerId ?? 'default'}:$id';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecentAccessItem &&
          runtimeType == other.runtimeType &&
          uniqueKey == other.uniqueKey;

  @override
  int get hashCode => uniqueKey.hashCode;
}

/// State for recent access history
class RecentAccessState {
  final List<RecentAccessItem> items;
  final Set<String> hiddenDownloadIds;
  final bool isLoaded;

  const RecentAccessState({
    this.items = const [],
    this.hiddenDownloadIds = const {},
    this.isLoaded = false,
  });

  RecentAccessState copyWith({
    List<RecentAccessItem>? items,
    Set<String>? hiddenDownloadIds,
    bool? isLoaded,
  }) {
    return RecentAccessState(
      items: items ?? this.items,
      hiddenDownloadIds: hiddenDownloadIds ?? this.hiddenDownloadIds,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}

/// Provider for managing recent access history
class RecentAccessNotifier extends Notifier<RecentAccessState> {
  final AppStateDatabase _appStateDb = AppStateDatabase.instance;

  @override
  RecentAccessState build() {
    _loadHistory();
    return const RecentAccessState();
  }

  Future<void> _loadHistory() async {
    try {
      await _appStateDb.migrateRecentAccessFromSharedPreferences();
      final rows = await _appStateDb.getRecentAccessRows(
        limit: _maxRecentItems,
      );
      final hiddenIds = await _appStateDb.getHiddenRecentDownloadIds();

      final items = <RecentAccessItem>[];
      for (final row in rows) {
        final itemJson = row['item_json'] as String?;
        if (itemJson == null || itemJson.isEmpty) continue;
        try {
          final decoded = jsonDecode(itemJson);
          if (decoded is! Map) continue;
          items.add(
            RecentAccessItem.fromJson(Map<String, dynamic>.from(decoded)),
          );
        } catch (_) {
          continue;
        }
      }

      state = state.copyWith(
        items: items,
        hiddenDownloadIds: hiddenIds,
        isLoaded: true,
      );
    } catch (_) {
      state = state.copyWith(isLoaded: true);
    }
  }

  /// Record an access to an artist
  void recordArtistAccess({
    required String id,
    required String name,
    String? imageUrl,
    String? providerId,
  }) {
    _recordAccess(
      RecentAccessItem(
        id: id,
        name: name,
        imageUrl: imageUrl,
        type: RecentAccessType.artist,
        accessedAt: DateTime.now(),
        providerId: providerId,
      ),
    );
  }

  /// Record an access to an album
  void recordAlbumAccess({
    required String id,
    required String name,
    String? artistName,
    String? imageUrl,
    String? providerId,
  }) {
    _recordAccess(
      RecentAccessItem(
        id: id,
        name: name,
        subtitle: artistName,
        imageUrl: imageUrl,
        type: RecentAccessType.album,
        accessedAt: DateTime.now(),
        providerId: providerId,
      ),
    );
  }

  /// Record an access to a track
  void recordTrackAccess({
    required String id,
    required String name,
    String? artistName,
    String? imageUrl,
    String? providerId,
  }) {
    _recordAccess(
      RecentAccessItem(
        id: id,
        name: name,
        subtitle: artistName,
        imageUrl: imageUrl,
        type: RecentAccessType.track,
        accessedAt: DateTime.now(),
        providerId: providerId,
      ),
    );
  }

  /// Record an access to a playlist
  void recordPlaylistAccess({
    required String id,
    required String name,
    String? ownerName,
    String? imageUrl,
    String? providerId,
  }) {
    _recordAccess(
      RecentAccessItem(
        id: id,
        name: name,
        subtitle: ownerName,
        imageUrl: imageUrl,
        type: RecentAccessType.playlist,
        accessedAt: DateTime.now(),
        providerId: providerId,
      ),
    );
  }

  void _recordAccess(RecentAccessItem item) {
    final updatedItems = state.items
        .where((e) => e.uniqueKey != item.uniqueKey)
        .toList();

    updatedItems.insert(0, item);

    RecentAccessItem? removedTail;
    if (updatedItems.length > _maxRecentItems) {
      removedTail = updatedItems.removeLast();
    }

    state = state.copyWith(items: updatedItems);
    unawaited(
      _appStateDb.upsertRecentAccessRow(
        uniqueKey: item.uniqueKey,
        itemJson: jsonEncode(item.toJson()),
        accessedAt: item.accessedAt.toIso8601String(),
      ),
    );
    if (removedTail != null) {
      unawaited(_appStateDb.deleteRecentAccessRow(removedTail.uniqueKey));
    }
  }

  /// Remove a specific item from history
  void removeItem(RecentAccessItem item) {
    final updatedItems = state.items
        .where((e) => e.uniqueKey != item.uniqueKey)
        .toList();
    state = state.copyWith(items: updatedItems);
    unawaited(_appStateDb.deleteRecentAccessRow(item.uniqueKey));
  }

  /// Hide a download item from recents (without deleting the actual download)
  void hideDownloadFromRecents(String downloadId) {
    final updatedHidden = {...state.hiddenDownloadIds, downloadId};
    state = state.copyWith(hiddenDownloadIds: updatedHidden);
    unawaited(_appStateDb.addHiddenRecentDownloadId(downloadId));
  }

  /// Check if a download is hidden from recents
  bool isDownloadHidden(String downloadId) {
    return state.hiddenDownloadIds.contains(downloadId);
  }

  /// Clear all history
  void clearHistory() {
    state = state.copyWith(items: []);
    unawaited(_appStateDb.clearRecentAccessRows());
  }

  /// Clear hidden downloads (show all again)
  void clearHiddenDownloads() {
    state = state.copyWith(hiddenDownloadIds: {});
    unawaited(_appStateDb.clearHiddenRecentDownloadIds());
  }
}

final recentAccessProvider =
    NotifierProvider<RecentAccessNotifier, RecentAccessState>(
      RecentAccessNotifier.new,
    );
