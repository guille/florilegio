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
  });
}
