import 'package:florilegio/data/sqlite_repository.dart';
import 'package:florilegio/domain/bookmark.dart';
import 'package:florilegio/domain/bookmark_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late SqliteBookmarkRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        // A fresh private in-memory DB per test; the default singleInstance
        // returns one shared cached instance for the same path.
        singleInstance: false,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE bookmarks (
              id TEXT PRIMARY KEY,
              url TEXT NOT NULL UNIQUE,
              title TEXT,
              tags TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE sync_metadata (
              key TEXT PRIMARY KEY,
              value TEXT
            )
          ''');
        },
      ),
    );
    repo = SqliteBookmarkRepository.fromDatabase(db);
  });

  Bookmark makeBookmark({
    String id = '1',
    String url = 'https://example.com',
    String? title,
    List<String> tags = const [],
    DateTime? createdAt,
  }) {
    final now = DateTime.utc(2024, 1, 1);
    return Bookmark(
      id: id,
      url: url,
      title: title,
      tags: tags,
      createdAt: createdAt ?? now,
      updatedAt: now,
    );
  }

  group('SqliteBookmarkRepository', () {
    test('upsert and getById', () async {
      final b = makeBookmark();
      await repo.upsert(b);
      final result = await repo.getById('1');
      expect(result, isNotNull);
      expect(result!.url, 'https://example.com');
    });

    test('getById returns null for missing', () async {
      expect(await repo.getById('missing'), isNull);
    });

    test('upsert replaces existing', () async {
      await repo.upsert(makeBookmark(title: 'old'));
      await repo.upsert(makeBookmark(title: 'new'));
      final result = await repo.getById('1');
      expect(result!.title, 'new');
    });

    test('delete removes bookmark', () async {
      await repo.upsert(makeBookmark());
      await repo.delete('1');
      expect(await repo.getById('1'), isNull);
    });

    test('getAll sorts newest first', () async {
      await repo.upsert(
        makeBookmark(id: 'a', url: 'https://a.com', createdAt: DateTime(2024, 1, 1)),
      );
      await repo.upsert(
        makeBookmark(id: 'b', url: 'https://b.com', createdAt: DateTime(2024, 6, 1)),
      );
      final results = await repo.getAll(order: SortOrder.newestFirst);
      expect(results.first.id, 'b');
    });

    test('getAll filters by query', () async {
      await repo.upsert(makeBookmark(id: 'a', url: 'https://a.com', title: 'Flutter'));
      await repo.upsert(makeBookmark(id: 'b', url: 'https://b.com', title: 'Dart'));
      final results = await repo.getAll(query: 'flutter');
      expect(results.length, 1);
    });

    test('getAll filters by tag', () async {
      await repo.upsert(makeBookmark(id: 'a', url: 'https://a.com', tags: ['dev']));
      await repo.upsert(makeBookmark(id: 'b', url: 'https://b.com', tags: ['read']));
      final results = await repo.getAll(tag: 'dev');
      expect(results.length, 1);
    });

    test('getAll treats LIKE metacharacters in tag literally', () async {
      await repo.upsert(makeBookmark(id: 'a', url: 'https://a.com', tags: ['dev']));
      await repo.upsert(makeBookmark(id: 'b', url: 'https://b.com', tags: ['read']));

      for (final tag in ['%', 'de_', 'd%v', '_ev']) {
        expect(await repo.getAll(tag: tag), isEmpty, reason: 'tag=$tag');
      }
    });

    test('getAll treats LIKE metacharacters in query literally', () async {
      await repo.upsert(makeBookmark(id: 'a', url: 'https://a.com', title: 'Flutter'));
      await repo.upsert(makeBookmark(id: 'b', url: 'https://b.com', title: '100% pure'));

      // As a LIKE pattern '%' matched both rows; literally it matches only the
      // title that actually contains a percent sign.
      expect((await repo.getAll(query: '%')).map((b) => b.id), ['b']);
      expect((await repo.getAll(query: '100%')).map((b) => b.id), ['b']);
      // '_' matched any character, so this used to find 'Flutter'
      expect(await repo.getAll(query: 'Flu_ter'), isEmpty);
    });

    test('getAll tag match is case-insensitive', () async {
      await repo.upsert(makeBookmark(id: 'a', url: 'https://a.com', tags: ['DevOps']));
      expect((await repo.getAll(tag: 'devops')).map((b) => b.id), ['a']);
    });

    test('getAll tag match does not match a partial tag', () async {
      await repo.upsert(makeBookmark(id: 'a', url: 'https://a.com', tags: ['devops']));
      expect(await repo.getAll(tag: 'dev'), isEmpty);
    });

    test('replaceAll clears and replaces', () async {
      await repo.upsert(makeBookmark(id: 'old', url: 'https://old.com'));
      await repo.replaceAll([makeBookmark(id: 'new', url: 'https://new.com')]);
      expect(await repo.getById('old'), isNull);
      expect(await repo.getById('new'), isNotNull);
    });

    test('clear removes all', () async {
      await repo.upsert(makeBookmark());
      await repo.clear();
      final all = await repo.getAll();
      expect(all, isEmpty);
    });

    test('delete count starts at zero and increments', () async {
      expect(await repo.getDeleteCount(), 0);
      await repo.incrementDeleteCount();
      await repo.incrementDeleteCount(2);
      expect(await repo.getDeleteCount(), 3);
    });

    test('concurrent increments do not lose updates', () async {
      await Future.wait(List.generate(10, (_) => repo.incrementDeleteCount()));
      expect(await repo.getDeleteCount(), 10);
    });

    test('resetDeleteCount zeroes the counter', () async {
      await repo.incrementDeleteCount(5);
      await repo.resetDeleteCount();
      expect(await repo.getDeleteCount(), 0);
    });
  });

  group('SqliteBookmarkRepository replaceAll', () {
    test('tolerates duplicate ids in the input', () async {
      // A torn multi-page sync can repeat a row across page boundaries. With the
      // default abort algorithm this aborted the batch and rolled back the whole
      // replacement, so the sync failed outright.
      final dupe = makeBookmark(id: 'a', url: 'https://a.com', title: 'A');
      await repo.replaceAll([
        dupe,
        makeBookmark(id: 'b', url: 'https://b.com', title: 'B'),
        dupe,
      ]);

      final all = await repo.getAll();
      expect(all.map((b) => b.id), unorderedEquals(['a', 'b']));
    });

    test('rolls nothing back when the input is clean', () async {
      await repo.replaceAll([makeBookmark(id: 'old', url: 'https://old.com')]);
      await repo.replaceAll([makeBookmark(id: 'new', url: 'https://new.com')]);

      final all = await repo.getAll();
      expect(all.map((b) => b.id), ['new']);
    });
  });

  group('SqliteBookmarkRepository sync metadata', () {
    test('sync token round-trips and clears', () async {
      expect(await repo.getSyncToken(), isNull);
      await repo.setSyncToken('"7"');
      expect(await repo.getSyncToken(), '"7"');
      await repo.setSyncToken('"8"');
      expect(await repo.getSyncToken(), '"8"');
      await repo.setSyncToken(null);
      expect(await repo.getSyncToken(), isNull);
    });

    test('last refreshed round-trips', () async {
      expect(await repo.getLastRefreshed(), isNull);
      await repo.setLastRefreshed('2026-08-19T12:00:00.000Z');
      expect(await repo.getLastRefreshed(), '2026-08-19T12:00:00.000Z');
    });

    test('sync token, last refreshed and delete count are independent', () async {
      await repo.setSyncToken('"7"');
      await repo.setLastRefreshed('2026-08-19T12:00:00.000Z');
      await repo.incrementDeleteCount(3);

      // Clearing one key must not disturb the others
      await repo.setSyncToken(null);
      expect(await repo.getLastRefreshed(), '2026-08-19T12:00:00.000Z');
      expect(await repo.getDeleteCount(), 3);
    });
  });
}
