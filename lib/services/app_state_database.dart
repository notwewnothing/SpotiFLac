import 'dart:convert';
import 'package:spotiflac_android/utils/platform_spoof.dart' as platform;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:spotiflac_android/utils/logger.dart';

final _log = AppLogger('AppStateDb');

const _dbFileName = 'app_state.db';
const _dbVersion = 1;

const _queueTable = 'download_queue_items';
const _recentTable = 'recent_access_items';
const _hiddenRecentTable = 'hidden_recent_downloads';

const _legacyQueueKey = 'download_queue';
const _legacyRecentAccessKey = 'recent_access_history';
const _legacyHiddenDownloadsKey = 'hidden_downloads_in_recents';

const _queueMigrationKey = 'app_state_migrated_queue_to_sqlite_v1';
const _recentMigrationKey = 'app_state_migrated_recent_to_sqlite_v1';

class AppStateDatabase {
  static final AppStateDatabase instance = AppStateDatabase._init();
  static Database? _database;

  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  AppStateDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, _dbFileName);

    _log.i('Initializing app state database at: $path');

    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        await db.rawQuery('PRAGMA journal_mode = WAL');
        await db.execute('PRAGMA synchronous = NORMAL');
      },
      onCreate: _createDb,
      onUpgrade: _upgradeDb,
    );
  }

  Future<void> _createDb(Database db, int version) async {
    _log.i('Creating app state database schema v$version');

    await db.execute('''
      CREATE TABLE $_queueTable (
        id TEXT PRIMARY KEY,
        item_json TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_${_queueTable}_status ON $_queueTable(status)',
    );
    await db.execute(
      'CREATE INDEX idx_${_queueTable}_created ON $_queueTable(created_at ASC)',
    );

    await db.execute('''
      CREATE TABLE $_recentTable (
        unique_key TEXT PRIMARY KEY,
        item_json TEXT NOT NULL,
        accessed_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_${_recentTable}_accessed ON $_recentTable(accessed_at DESC)',
    );

    await db.execute('''
      CREATE TABLE $_hiddenRecentTable (
        download_id TEXT PRIMARY KEY,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _upgradeDb(Database db, int oldVersion, int newVersion) async {
    _log.i('Upgrading app state database from v$oldVersion to v$newVersion');
  }

  Future<bool> migrateQueueFromSharedPreferences() async {
    final prefs = await _prefs;
    if (prefs.getBool(_queueMigrationKey) == true) {
      return false;
    }

    final raw = prefs.getString(_legacyQueueKey);
    if (raw == null || raw.isEmpty) {
      await prefs.setBool(_queueMigrationKey, true);
      return false;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        await prefs.setBool(_queueMigrationKey, true);
        return false;
      }

      final nowIso = DateTime.now().toIso8601String();
      final db = await database;
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (final entry in decoded.whereType<Map<Object?, Object?>>()) {
          final map = Map<String, dynamic>.from(entry);
          final id = map['id'] as String?;
          if (id == null || id.isEmpty) continue;

          final status = map['status'] as String? ?? 'queued';
          if (status != 'queued' && status != 'downloading') {
            continue;
          }

          if (status == 'downloading') {
            map['status'] = 'queued';
            map['progress'] = 0.0;
            map['speedMBps'] = 0.0;
            map['bytesReceived'] = 0;
          }

          final createdAt = map['createdAt'] as String? ?? nowIso;
          batch.insert(_queueTable, {
            'id': id,
            'item_json': jsonEncode(map),
            'status': 'queued',
            'created_at': createdAt,
            'updated_at': nowIso,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      });

      await prefs.setBool(_queueMigrationKey, true);
      _log.i('Migrated legacy queue data to SQLite');
      return true;
    } catch (e, stack) {
      _log.e('Failed queue migration to SQLite: $e', e, stack);
      return false;
    }
  }

  Future<bool> migrateRecentAccessFromSharedPreferences() async {
    final prefs = await _prefs;
    if (prefs.getBool(_recentMigrationKey) == true) {
      return false;
    }

    final rawRecent = prefs.getString(_legacyRecentAccessKey);
    final hiddenIds = prefs.getStringList(_legacyHiddenDownloadsKey);
    if ((rawRecent == null || rawRecent.isEmpty) &&
        (hiddenIds == null || hiddenIds.isEmpty)) {
      await prefs.setBool(_recentMigrationKey, true);
      return false;
    }

    try {
      final nowIso = DateTime.now().toIso8601String();
      final db = await database;
      await db.transaction((txn) async {
        if (rawRecent != null && rawRecent.isNotEmpty) {
          final decoded = jsonDecode(rawRecent);
          if (decoded is List) {
            final batch = txn.batch();
            for (final entry in decoded.whereType<Map<Object?, Object?>>()) {
              final map = Map<String, dynamic>.from(entry);
              final type = map['type'] as String?;
              final id = map['id'] as String?;
              final providerId = map['providerId'] as String?;
              if (type == null || id == null || type.isEmpty || id.isEmpty) {
                continue;
              }
              final uniqueKey = '$type:${providerId ?? 'default'}:$id';
              final accessedAt = map['accessedAt'] as String? ?? nowIso;
              batch.insert(_recentTable, {
                'unique_key': uniqueKey,
                'item_json': jsonEncode(map),
                'accessed_at': accessedAt,
              }, conflictAlgorithm: ConflictAlgorithm.replace);
            }
            await batch.commit(noResult: true);
          }
        }

        if (hiddenIds != null && hiddenIds.isNotEmpty) {
          final batch = txn.batch();
          for (final id in hiddenIds) {
            if (id.isEmpty) continue;
            batch.insert(_hiddenRecentTable, {
              'download_id': id,
              'updated_at': nowIso,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
          await batch.commit(noResult: true);
        }
      });

      await prefs.setBool(_recentMigrationKey, true);
      _log.i('Migrated legacy recent-access data to SQLite');
      return true;
    } catch (e, stack) {
      _log.e('Failed recent-access migration to SQLite: $e', e, stack);
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getPendingDownloadQueueRows() async {
    final db = await database;
    return db.query(
      _queueTable,
      where: 'status = ? OR status = ?',
      whereArgs: ['queued', 'downloading'],
      orderBy: 'created_at ASC, rowid ASC',
    );
  }

  Future<void> replacePendingDownloadQueueRows(
    List<Map<String, dynamic>> rows,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(_queueTable);
      if (rows.isEmpty) return;

      final batch = txn.batch();
      for (final row in rows) {
        batch.insert(
          _queueTable,
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Map<String, dynamic>>> getRecentAccessRows({int? limit}) async {
    final db = await database;
    return db.query(
      _recentTable,
      orderBy: 'accessed_at DESC, rowid DESC',
      limit: limit,
    );
  }

  Future<void> upsertRecentAccessRow({
    required String uniqueKey,
    required String itemJson,
    required String accessedAt,
  }) async {
    final db = await database;
    await db.insert(_recentTable, {
      'unique_key': uniqueKey,
      'item_json': itemJson,
      'accessed_at': accessedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteRecentAccessRow(String uniqueKey) async {
    final db = await database;
    await db.delete(
      _recentTable,
      where: 'unique_key = ?',
      whereArgs: [uniqueKey],
    );
  }

  Future<void> clearRecentAccessRows() async {
    final db = await database;
    await db.delete(_recentTable);
  }

  Future<Set<String>> getHiddenRecentDownloadIds() async {
    final db = await database;
    final rows = await db.query(_hiddenRecentTable, columns: ['download_id']);
    return rows
        .map((row) => row['download_id'] as String?)
        .whereType<String>()
        .toSet();
  }

  Future<void> addHiddenRecentDownloadId(String downloadId) async {
    final id = downloadId.trim();
    if (id.isEmpty) return;
    final db = await database;
    await db.insert(_hiddenRecentTable, {
      'download_id': id,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearHiddenRecentDownloadIds() async {
    final db = await database;
    await db.delete(_hiddenRecentTable);
  }
}
