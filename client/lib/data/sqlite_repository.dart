import 'package:florilegio/domain/bookmark.dart';
import 'package:florilegio/domain/bookmark_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class SqliteBookmarkRepository implements BookmarkRepository {
  final Database _db;

  SqliteBookmarkRepository._(this._db);

  static Future<SqliteBookmarkRepository> open({String? path}) async {
    final dbPath = path ?? p.join(await getDatabasesPath(), 'florilegio.db');
    final db = await openDatabase(
      dbPath,
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE bookmarks (
            id TEXT PRIMARY KEY,
            url TEXT NOT NULL UNIQUE,
            title TEXT,
            tags TEXT,
            is_read INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE pending_bookmarks (
            url TEXT PRIMARY KEY,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE sync_metadata (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Migrate from v1 (read_at INTEGER, created_at INTEGER) to v2
          await db.execute('DROP TABLE IF EXISTS bookmarks');
          await db.execute('''
            CREATE TABLE bookmarks (
              id TEXT PRIMARY KEY,
              url TEXT NOT NULL UNIQUE,
              title TEXT,
              tags TEXT,
              is_read INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS pending_bookmarks (
              url TEXT PRIMARY KEY,
              created_at TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS sync_metadata (
              key TEXT PRIMARY KEY,
              value TEXT
            )
          ''');
        }
      },
    );
    return SqliteBookmarkRepository._(db);
  }

  /// Create from an already-opened Database (useful for tests with sqflite_common_ffi).
  static SqliteBookmarkRepository fromDatabase(Database db) => SqliteBookmarkRepository._(db);

  @override
  Future<List<Bookmark>> getAll({
    String? query,
    String? tag,
    SortOrder order = SortOrder.newestFirst,
  }) async {
    final where = <String>[];
    final args = <dynamic>[];

    // instr() rather than LIKE: a LIKE pattern would treat % and _ in the
    // user's search text or tag as wildcards. lower() on both sides preserves
    // LIKE's ASCII case-insensitivity.
    if (query != null && query.isNotEmpty) {
      where.add('(instr(lower(title), lower(?)) > 0 OR instr(lower(url), lower(?)) > 0)');
      args
        ..add(query)
        ..add(query);
    }

    if (tag != null) {
      where.add("instr(lower(',' || tags || ','), lower(?)) > 0");
      args.add(',$tag,');
    }

    final orderBy = switch (order) {
      SortOrder.newestFirst => 'created_at DESC',
      SortOrder.oldestFirst => 'created_at ASC',
      SortOrder.random => 'RANDOM()',
      // Extract host: strip scheme (everything up to "://"), then take up to the next "/".
      SortOrder.byHost =>
        "SUBSTR(SUBSTR(url, INSTR(url, '://') + 3), 1, "
            "CASE WHEN INSTR(SUBSTR(url, INSTR(url, '://') + 3), '/') > 0 "
            "THEN INSTR(SUBSTR(url, INSTR(url, '://') + 3), '/') - 1 "
            "ELSE LENGTH(SUBSTR(url, INSTR(url, '://') + 3)) END) ASC, "
            'created_at ASC',
    };

    final rows = await _db.query(
      'bookmarks',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: orderBy,
    );

    return rows.map(Bookmark.fromRow).toList();
  }

  @override
  Future<Bookmark?> getById(String id) async {
    final rows = await _db.query('bookmarks', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Bookmark.fromRow(rows.first);
  }

  @override
  Future<void> upsert(Bookmark bookmark) async {
    await _db.insert('bookmarks', bookmark.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> upsertAll(List<Bookmark> bookmarks) async {
    final batch = _db.batch();
    for (final b in bookmarks) {
      batch.insert('bookmarks', b.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> delete(String id) async {
    await _db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> replaceAll(List<Bookmark> bookmarks) async {
    await _db.transaction((txn) async {
      await txn.delete('bookmarks');
      final batch = txn.batch();
      for (final b in bookmarks) {
        // replace, not the default abort: a duplicate id or url anywhere in the
        // input would otherwise roll back the entire replacement.
        batch.insert('bookmarks', b.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<void> clear() async {
    await _db.delete('bookmarks');
  }

  // ── Pending queue ────────────────────────────────────────────────────────

  @override
  Future<void> addPending(String url) async {
    await _db.insert('pending_bookmarks', {
      'url': url,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  @override
  Future<List<PendingBookmark>> getPending() async {
    final rows = await _db.query('pending_bookmarks', orderBy: 'created_at ASC');
    return rows
        .map(
          (r) => PendingBookmark(
            url: r['url']! as String,
            createdAt: DateTime.parse(r['created_at']! as String),
          ),
        )
        .toList();
  }

  @override
  Future<void> removePending(String url) async {
    await _db.delete('pending_bookmarks', where: 'url = ?', whereArgs: [url]);
  }

  @override
  Future<int> getPendingCount() async {
    final count = Sqflite.firstIntValue(
      await _db.rawQuery('SELECT COUNT(*) FROM pending_bookmarks'),
    );
    return count ?? 0;
  }

  // ── Sync metadata ──────────────────────────────────────────────────────

  Future<void> _setMeta(String key, String? value) async {
    if (value == null) {
      await _db.delete('sync_metadata', where: 'key = ?', whereArgs: [key]);
    } else {
      await _db.insert('sync_metadata', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<String?> _getMeta(String key) async {
    final rows = await _db.query('sync_metadata', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  @override
  Future<void> setSyncToken(String? value) => _setMeta('sync_token', value);

  @override
  Future<String?> getSyncToken() => _getMeta('sync_token');

  @override
  Future<void> setLastRefreshed(String? value) => _setMeta('last_refreshed', value);

  @override
  Future<String?> getLastRefreshed() => _getMeta('last_refreshed');

  // ── Delete counter ─────────────────────────────────────────────────────

  @override
  Future<int> getDeleteCount() async {
    final rows = await _db.query('sync_metadata', where: "key = 'delete_count'");
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.first['value'] as String? ?? '') ?? 0;
  }

  @override
  Future<void> incrementDeleteCount([int n = 1]) async {
    // Single-statement increment so concurrent deletes can't lose updates.
    // ON CONFLICT DO UPDATE would be cleaner but needs SQLite 3.24 (not
    // guaranteed until Android 11); this form works on any version.
    // CAST keeps the TEXT column holding a string, as getDeleteCount expects.
    await _db.rawInsert(
      "INSERT OR REPLACE INTO sync_metadata(key, value) VALUES('delete_count', "
      "CAST(COALESCE((SELECT value FROM sync_metadata WHERE key = 'delete_count'), 0) + ? "
      'AS TEXT))',
      [n],
    );
  }

  @override
  Future<void> resetDeleteCount() async {
    await _db.delete('sync_metadata', where: "key = 'delete_count'");
  }

  Future<void> close() => _db.close();
}
