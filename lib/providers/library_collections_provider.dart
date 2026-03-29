import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/services/library_collections_database.dart';
import 'package:spotiflac_android/utils/platform_spoof.dart' as platform;

String trackCollectionKey(Track track) {
  final isrc = track.isrc?.trim();
  if (isrc != null && isrc.isNotEmpty) {
    return 'isrc:${isrc.toUpperCase()}';
  }
  final source = (track.source?.trim().isNotEmpty ?? false)
      ? track.source!.trim()
      : 'builtin';
  return '$source:${track.id}';
}

class CollectionTrackEntry {
  final String key;
  final Track track;
  final DateTime addedAt;

  const CollectionTrackEntry({
    required this.key,
    required this.track,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
    'key': key,
    'track': track.toJson(),
    'addedAt': addedAt.toIso8601String(),
  };

  factory CollectionTrackEntry.fromJson(Map<String, dynamic> json) {
    final addedAtRaw = json['addedAt'] as String?;
    return CollectionTrackEntry(
      key: json['key'] as String,
      track: Track.fromJson(Map<String, dynamic>.from(json['track'] as Map)),
      addedAt: DateTime.tryParse(addedAtRaw ?? '') ?? DateTime.now(),
    );
  }
}

class UserPlaylistCollection {
  final String id;
  final String name;
  final String? coverImagePath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<CollectionTrackEntry> tracks;
  final Set<String> _trackKeys;

  UserPlaylistCollection({
    required this.id,
    required this.name,
    this.coverImagePath,
    required this.createdAt,
    required this.updatedAt,
    required this.tracks,
    Set<String>? trackKeys,
  }) : _trackKeys = trackKeys ?? tracks.map((entry) => entry.key).toSet();

  UserPlaylistCollection copyWith({
    String? id,
    String? name,
    String? Function()? coverImagePath,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<CollectionTrackEntry>? tracks,
  }) {
    final nextTracks = tracks ?? this.tracks;
    final keepTrackIndex = identical(nextTracks, this.tracks);
    return UserPlaylistCollection(
      id: id ?? this.id,
      name: name ?? this.name,
      coverImagePath: coverImagePath != null
          ? coverImagePath()
          : this.coverImagePath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tracks: nextTracks,
      trackKeys: keepTrackIndex ? _trackKeys : null,
    );
  }

  bool containsTrack(Track track) {
    final key = trackCollectionKey(track);
    return _trackKeys.contains(key);
  }

  bool containsTrackKey(String trackKey) {
    return _trackKeys.contains(trackKey);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (coverImagePath != null) 'coverImagePath': coverImagePath,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'tracks': tracks.map((e) => e.toJson()).toList(),
  };

  factory UserPlaylistCollection.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['createdAt'] as String?;
    final updatedAtRaw = json['updatedAt'] as String?;
    final createdAt = DateTime.tryParse(createdAtRaw ?? '') ?? DateTime.now();
    final updatedAt = DateTime.tryParse(updatedAtRaw ?? '') ?? createdAt;
    final tracksRaw = (json['tracks'] as List?) ?? const [];
    return UserPlaylistCollection(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      coverImagePath: json['coverImagePath'] as String?,
      createdAt: createdAt,
      updatedAt: updatedAt,
      tracks: tracksRaw
          .whereType<Map<Object?, Object?>>()
          .map(
            (e) => CollectionTrackEntry.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false),
    );
  }
}

class LibraryCollectionsState {
  final List<CollectionTrackEntry> wishlist;
  final List<CollectionTrackEntry> loved;
  final List<UserPlaylistCollection> playlists;
  final bool isLoaded;
  final Set<String> _wishlistKeys;
  final Set<String> _lovedKeys;
  final Map<String, UserPlaylistCollection> _playlistsById;
  final Set<String> _allPlaylistTrackKeys;

  LibraryCollectionsState({
    this.wishlist = const [],
    this.loved = const [],
    this.playlists = const [],
    this.isLoaded = false,
    Set<String>? wishlistKeys,
    Set<String>? lovedKeys,
    Map<String, UserPlaylistCollection>? playlistsById,
    Set<String>? allPlaylistTrackKeys,
  }) : _wishlistKeys =
           wishlistKeys ?? wishlist.map((entry) => entry.key).toSet(),
       _lovedKeys = lovedKeys ?? loved.map((entry) => entry.key).toSet(),
       _playlistsById =
           playlistsById ??
           Map.fromEntries(
             playlists.map((playlist) => MapEntry(playlist.id, playlist)),
           ),
       _allPlaylistTrackKeys =
           allPlaylistTrackKeys ?? _buildPlaylistTrackKeys(playlists);

  int get wishlistCount => wishlist.length;
  int get lovedCount => loved.length;
  int get playlistCount => playlists.length;

  bool isInWishlist(Track track) {
    final key = trackCollectionKey(track);
    return _wishlistKeys.contains(key);
  }

  bool isLoved(Track track) {
    final key = trackCollectionKey(track);
    return _lovedKeys.contains(key);
  }

  bool containsWishlistKey(String trackKey) {
    return _wishlistKeys.contains(trackKey);
  }

  bool containsLovedKey(String trackKey) {
    return _lovedKeys.contains(trackKey);
  }

  UserPlaylistCollection? playlistById(String playlistId) {
    return _playlistsById[playlistId];
  }

  bool playlistContainsTrack(String playlistId, String trackKey) {
    final playlist = _playlistsById[playlistId];
    if (playlist == null) return false;
    return playlist.containsTrackKey(trackKey);
  }

  bool isTrackInAnyPlaylist(String trackKey) {
    return _allPlaylistTrackKeys.contains(trackKey);
  }

  bool get hasPlaylistTracks => _allPlaylistTrackKeys.isNotEmpty;

  LibraryCollectionsState copyWith({
    List<CollectionTrackEntry>? wishlist,
    List<CollectionTrackEntry>? loved,
    List<UserPlaylistCollection>? playlists,
    bool? isLoaded,
  }) {
    final nextWishlist = wishlist ?? this.wishlist;
    final nextLoved = loved ?? this.loved;
    final nextPlaylists = playlists ?? this.playlists;
    final keepWishlistIndex = identical(nextWishlist, this.wishlist);
    final keepLovedIndex = identical(nextLoved, this.loved);
    final keepPlaylistIndex = identical(nextPlaylists, this.playlists);

    return LibraryCollectionsState(
      wishlist: nextWishlist,
      loved: nextLoved,
      playlists: nextPlaylists,
      isLoaded: isLoaded ?? this.isLoaded,
      wishlistKeys: keepWishlistIndex ? _wishlistKeys : null,
      lovedKeys: keepLovedIndex ? _lovedKeys : null,
      playlistsById: keepPlaylistIndex ? _playlistsById : null,
      allPlaylistTrackKeys: keepPlaylistIndex ? _allPlaylistTrackKeys : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'wishlist': wishlist.map((e) => e.toJson()).toList(),
    'loved': loved.map((e) => e.toJson()).toList(),
    'playlists': playlists.map((e) => e.toJson()).toList(),
  };

  factory LibraryCollectionsState.fromJson(Map<String, dynamic> json) {
    final wishlistRaw = (json['wishlist'] as List?) ?? const [];
    final lovedRaw = (json['loved'] as List?) ?? const [];
    final playlistsRaw = (json['playlists'] as List?) ?? const [];

    return LibraryCollectionsState(
      wishlist: wishlistRaw
          .whereType<Map<Object?, Object?>>()
          .map(
            (e) => CollectionTrackEntry.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false),
      loved: lovedRaw
          .whereType<Map<Object?, Object?>>()
          .map(
            (e) => CollectionTrackEntry.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false),
      playlists: playlistsRaw
          .whereType<Map<Object?, Object?>>()
          .map(
            (e) =>
                UserPlaylistCollection.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false),
      isLoaded: true,
    );
  }
}

Set<String> _buildPlaylistTrackKeys(List<UserPlaylistCollection> playlists) {
  final keys = <String>{};
  for (final playlist in playlists) {
    for (final entry in playlist.tracks) {
      keys.add(entry.key);
    }
  }
  return keys;
}

class PlaylistAddBatchResult {
  final int addedCount;
  final int alreadyInPlaylistCount;

  const PlaylistAddBatchResult({
    required this.addedCount,
    required this.alreadyInPlaylistCount,
  });
}

class LibraryCollectionsNotifier extends Notifier<LibraryCollectionsState> {
  final LibraryCollectionsDatabase _db = LibraryCollectionsDatabase.instance;
  Future<void>? _loadFuture;

  @override
  LibraryCollectionsState build() {
    _loadFuture = _load();
    return LibraryCollectionsState();
  }

  Future<void> _load() async {
    try {
      await _db.migrateFromSharedPreferences();
      final snapshot = await _db.loadSnapshot();

      final wishlist = <CollectionTrackEntry>[];
      for (final row in snapshot.wishlistRows) {
        final parsed = _parseTrackEntryRow(row);
        if (parsed != null) {
          wishlist.add(parsed);
        }
      }

      final loved = <CollectionTrackEntry>[];
      for (final row in snapshot.lovedRows) {
        final parsed = _parseTrackEntryRow(row);
        if (parsed != null) {
          loved.add(parsed);
        }
      }

      final tracksByPlaylist = <String, List<CollectionTrackEntry>>{};
      for (final row in snapshot.playlistTrackRows) {
        final playlistId = row['playlist_id'] as String?;
        if (playlistId == null || playlistId.isEmpty) continue;
        final parsed = _parseTrackEntryRow(row);
        if (parsed == null) continue;
        tracksByPlaylist.putIfAbsent(playlistId, () => []).add(parsed);
      }

      final playlists = <UserPlaylistCollection>[];
      for (final row in snapshot.playlistRows) {
        final id = row['id'] as String?;
        if (id == null || id.isEmpty) continue;

        final createdAtRaw = row['created_at'] as String?;
        final updatedAtRaw = row['updated_at'] as String?;
        final createdAt =
            DateTime.tryParse(createdAtRaw ?? '') ?? DateTime.now();
        final updatedAt = DateTime.tryParse(updatedAtRaw ?? '') ?? createdAt;

        playlists.add(
          UserPlaylistCollection(
            id: id,
            name: row['name'] as String? ?? '',
            coverImagePath: row['cover_image_path'] as String?,
            createdAt: createdAt,
            updatedAt: updatedAt,
            tracks: tracksByPlaylist[id] ?? const <CollectionTrackEntry>[],
          ),
        );
      }

      state = LibraryCollectionsState(
        wishlist: wishlist,
        loved: loved,
        playlists: playlists,
        isLoaded: true,
      );
    } catch (_) {
      state = state.copyWith(isLoaded: true);
    }
  }

  Future<void> _ensureLoaded() async {
    if (state.isLoaded) return;
    await (_loadFuture ?? _load());
  }

  CollectionTrackEntry? _parseTrackEntryRow(Map<String, dynamic> row) {
    final key = row['track_key'] as String?;
    final trackJson = row['track_json'] as String?;
    if (key == null || key.isEmpty || trackJson == null || trackJson.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(trackJson);
      if (decoded is! Map) return null;
      final track = Track.fromJson(Map<String, dynamic>.from(decoded));
      final addedAtRaw = row['added_at'] as String?;
      return CollectionTrackEntry(
        key: key,
        track: track,
        addedAt: DateTime.tryParse(addedAtRaw ?? '') ?? DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  bool _replacePlaylistById(
    String playlistId,
    UserPlaylistCollection Function(UserPlaylistCollection playlist) update,
  ) {
    final playlist = state.playlistById(playlistId);
    if (playlist == null) return false;

    final playlistIndex = state.playlists.indexWhere((p) => p.id == playlistId);
    if (playlistIndex < 0) return false;

    final nextPlaylist = update(playlist);
    if (identical(nextPlaylist, playlist)) return false;

    final updatedPlaylists = [...state.playlists];
    updatedPlaylists[playlistIndex] = nextPlaylist;
    state = state.copyWith(playlists: updatedPlaylists);
    return true;
  }

  Future<bool> toggleWishlist(Track track) async {
    await _ensureLoaded();
    final key = trackCollectionKey(track);
    if (state.containsWishlistKey(key)) {
      await _db.deleteWishlistEntry(key);
      final updated = state.wishlist
          .where((entry) => entry.key != key)
          .toList(growable: false);
      state = state.copyWith(wishlist: updated);
      return false;
    }

    final entry = CollectionTrackEntry(
      key: key,
      track: track,
      addedAt: DateTime.now(),
    );
    await _db.upsertWishlistEntry(
      trackKey: key,
      trackJson: jsonEncode(track.toJson()),
      addedAt: entry.addedAt.toIso8601String(),
    );
    final updated = [entry, ...state.wishlist];
    state = state.copyWith(wishlist: updated);
    return true;
  }

  Future<bool> toggleLoved(Track track) async {
    await _ensureLoaded();
    final key = trackCollectionKey(track);
    if (state.containsLovedKey(key)) {
      await _db.deleteLovedEntry(key);
      final updated = state.loved
          .where((entry) => entry.key != key)
          .toList(growable: false);
      state = state.copyWith(loved: updated);
      return false;
    }

    final entry = CollectionTrackEntry(
      key: key,
      track: track,
      addedAt: DateTime.now(),
    );
    await _db.upsertLovedEntry(
      trackKey: key,
      trackJson: jsonEncode(track.toJson()),
      addedAt: entry.addedAt.toIso8601String(),
    );
    final updated = [entry, ...state.loved];
    state = state.copyWith(loved: updated);
    return true;
  }

  Future<void> removeFromWishlist(String trackKey) async {
    await _ensureLoaded();
    if (!state.containsWishlistKey(trackKey)) return;

    await _db.deleteWishlistEntry(trackKey);
    final updated = state.wishlist
        .where((entry) => entry.key != trackKey)
        .toList(growable: false);
    state = state.copyWith(wishlist: updated);
  }

  Future<void> removeFromLoved(String trackKey) async {
    await _ensureLoaded();
    if (!state.containsLovedKey(trackKey)) return;

    await _db.deleteLovedEntry(trackKey);
    final updated = state.loved
        .where((entry) => entry.key != trackKey)
        .toList(growable: false);
    state = state.copyWith(loved: updated);
  }

  Future<String> createPlaylist(String name) async {
    await _ensureLoaded();
    final now = DateTime.now();
    final id = 'pl_${now.microsecondsSinceEpoch}';
    final trimmedName = name.trim();

    final playlist = UserPlaylistCollection(
      id: id,
      name: trimmedName,
      createdAt: now,
      updatedAt: now,
      tracks: const [],
    );

    await _db.upsertPlaylist(
      id: id,
      name: trimmedName,
      coverImagePath: null,
      createdAt: now.toIso8601String(),
      updatedAt: now.toIso8601String(),
    );
    state = state.copyWith(playlists: [playlist, ...state.playlists]);
    return id;
  }

  Future<void> renamePlaylist(String playlistId, String newName) async {
    await _ensureLoaded();
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final playlist = state.playlistById(playlistId);
    if (playlist == null || playlist.name == trimmed) return;

    final now = DateTime.now();
    await _db.renamePlaylist(
      playlistId: playlistId,
      name: trimmed,
      updatedAt: now.toIso8601String(),
    );
    _replacePlaylistById(playlistId, (playlist) {
      return playlist.copyWith(name: trimmed, updatedAt: now);
    });
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _ensureLoaded();
    final playlistIndex = state.playlists.indexWhere((p) => p.id == playlistId);
    if (playlistIndex < 0) return;

    await _db.deletePlaylist(playlistId);
    final updatedPlaylists = [...state.playlists]..removeAt(playlistIndex);
    state = state.copyWith(playlists: updatedPlaylists);
  }

  Future<bool> addTrackToPlaylist(String playlistId, Track track) async {
    await _ensureLoaded();
    final playlist = state.playlistById(playlistId);
    if (playlist == null) return false;

    final key = trackCollectionKey(track);
    if (playlist.containsTrackKey(key)) return false;

    final now = DateTime.now();
    final entry = CollectionTrackEntry(key: key, track: track, addedAt: now);
    await _db.upsertPlaylistTrack(
      playlistId: playlistId,
      trackKey: key,
      trackJson: jsonEncode(track.toJson()),
      addedAt: entry.addedAt.toIso8601String(),
      playlistUpdatedAt: now.toIso8601String(),
    );
    final changed = _replacePlaylistById(playlistId, (playlist) {
      if (playlist.containsTrackKey(key)) return playlist;
      return playlist.copyWith(
        tracks: [entry, ...playlist.tracks],
        updatedAt: now,
      );
    });
    if (!changed) return false;
    return true;
  }

  Future<PlaylistAddBatchResult> addTracksToPlaylist(
    String playlistId,
    Iterable<Track> tracks,
  ) async {
    await _ensureLoaded();
    final playlist = state.playlistById(playlistId);
    if (playlist == null) {
      return const PlaylistAddBatchResult(
        addedCount: 0,
        alreadyInPlaylistCount: 0,
      );
    }

    final now = DateTime.now();
    final knownKeys = <String>{...playlist._trackKeys};
    final entriesToAdd = <CollectionTrackEntry>[];
    var alreadyInPlaylistCount = 0;

    for (final track in tracks) {
      final key = trackCollectionKey(track);
      if (!knownKeys.add(key)) {
        alreadyInPlaylistCount++;
        continue;
      }

      entriesToAdd.add(
        CollectionTrackEntry(key: key, track: track, addedAt: now),
      );
    }

    if (entriesToAdd.isEmpty) {
      return PlaylistAddBatchResult(
        addedCount: 0,
        alreadyInPlaylistCount: alreadyInPlaylistCount,
      );
    }

    await _db.upsertPlaylistTracksBatch(
      playlistId: playlistId,
      playlistUpdatedAt: now.toIso8601String(),
      tracks: entriesToAdd
          .map(
            (entry) => <String, String>{
              'track_key': entry.key,
              'track_json': jsonEncode(entry.track.toJson()),
              'added_at': entry.addedAt.toIso8601String(),
            },
          )
          .toList(growable: false),
    );
    final changed = _replacePlaylistById(playlistId, (current) {
      return current.copyWith(
        tracks: [...entriesToAdd.reversed, ...current.tracks],
        updatedAt: now,
      );
    });
    if (!changed) {
      return PlaylistAddBatchResult(
        addedCount: 0,
        alreadyInPlaylistCount: alreadyInPlaylistCount,
      );
    }
    return PlaylistAddBatchResult(
      addedCount: entriesToAdd.length,
      alreadyInPlaylistCount: alreadyInPlaylistCount,
    );
  }

  Future<void> removeTrackFromPlaylist(
    String playlistId,
    String trackKey,
  ) async {
    await _ensureLoaded();
    final playlist = state.playlistById(playlistId);
    if (playlist == null || !playlist.containsTrackKey(trackKey)) return;

    final now = DateTime.now();
    await _db.deletePlaylistTrack(
      playlistId: playlistId,
      trackKey: trackKey,
      playlistUpdatedAt: now.toIso8601String(),
    );
    _replacePlaylistById(playlistId, (playlist) {
      final nextTracks = playlist.tracks
          .where((entry) => entry.key != trackKey)
          .toList(growable: false);
      if (nextTracks.length == playlist.tracks.length) return playlist;
      return playlist.copyWith(tracks: nextTracks, updatedAt: now);
    });
  }

  Future<Directory> _playlistCoversDir() async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appDir.path, 'playlist_covers'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> setPlaylistCover(
    String playlistId,
    String sourceFilePath,
  ) async {
    await _ensureLoaded();
    final playlist = state.playlistById(playlistId);
    if (playlist == null) return;

    final coversDir = await _playlistCoversDir();
    final ext = p.extension(sourceFilePath).toLowerCase();
    final destPath = p.join(coversDir.path, '$playlistId$ext');
    if (playlist.coverImagePath == destPath) return;

    await File(sourceFilePath).copy(destPath);

    final now = DateTime.now();
    await _db.updatePlaylistCover(
      playlistId: playlistId,
      coverImagePath: destPath,
      updatedAt: now.toIso8601String(),
    );
    _replacePlaylistById(playlistId, (playlist) {
      if (playlist.coverImagePath == destPath) return playlist;
      return playlist.copyWith(coverImagePath: () => destPath, updatedAt: now);
    });
  }

  Future<void> removePlaylistCover(String playlistId) async {
    await _ensureLoaded();
    final playlist = state.playlistById(playlistId);
    if (playlist == null || playlist.coverImagePath == null) return;

    final path = playlist.coverImagePath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }

    final now = DateTime.now();
    await _db.updatePlaylistCover(
      playlistId: playlistId,
      coverImagePath: null,
      updatedAt: now.toIso8601String(),
    );
    _replacePlaylistById(playlistId, (playlist) {
      if (playlist.coverImagePath == null) return playlist;
      return playlist.copyWith(coverImagePath: () => null, updatedAt: now);
    });
  }
}

final libraryCollectionsProvider =
    NotifierProvider<LibraryCollectionsNotifier, LibraryCollectionsState>(
      LibraryCollectionsNotifier.new,
    );
