import 'package:florilegio/data/in_memory_repository.dart';
import 'package:florilegio/domain/bookmark.dart';
import 'package:florilegio/domain/bookmark_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryBookmarkRepository repo;

  setUp(() {
    repo = InMemoryBookmarkRepository();
  });

  Bookmark makeBookmark({
    String id = '1',
    String url = 'https://example.com',
    String? title,
    List<String> tags = const [],
    DateTime? createdAt,
  }) {
    final now = DateTime.now();
    return Bookmark(
      id: id,
      url: url,
      title: title,
      tags: tags,
      createdAt: createdAt ?? now,
      updatedAt: now,
    );
  }

  group('InMemoryBookmarkRepository', () {
    test('upsert and getById', () async {
      final b = makeBookmark();
      await repo.upsert(b);
      expect(await repo.getById('1'), equals(b));
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

    test('getAll returns sorted by newest first', () async {
      await repo.upsert(makeBookmark(id: 'a', createdAt: DateTime(2024, 1, 1)));
      await repo.upsert(makeBookmark(id: 'b', createdAt: DateTime(2024, 6, 1)));
      final results = await repo.getAll(order: SortOrder.newestFirst);
      expect(results.first.id, 'b');
    });

    test('getAll returns sorted by oldest first', () async {
      await repo.upsert(makeBookmark(id: 'a', createdAt: DateTime(2024, 1, 1)));
      await repo.upsert(makeBookmark(id: 'b', createdAt: DateTime(2024, 6, 1)));
      final results = await repo.getAll(order: SortOrder.oldestFirst);
      expect(results.first.id, 'a');
    });

    test('getAll filters by query on title', () async {
      await repo.upsert(makeBookmark(id: 'a', title: 'Flutter guide'));
      await repo.upsert(makeBookmark(id: 'b', title: 'Dart tips'));
      final results = await repo.getAll(query: 'flutter');
      expect(results.length, 1);
      expect(results.first.id, 'a');
    });

    test('getAll filters by query on url', () async {
      await repo.upsert(makeBookmark(id: 'a', url: 'https://flutter.dev'));
      await repo.upsert(makeBookmark(id: 'b', url: 'https://dart.dev'));
      final results = await repo.getAll(query: 'flutter');
      expect(results.length, 1);
    });

    test('getAll filters by tag', () async {
      await repo.upsert(makeBookmark(id: 'a', tags: ['dev']));
      await repo.upsert(makeBookmark(id: 'b', tags: ['read']));
      final results = await repo.getAll(tag: 'dev');
      expect(results.length, 1);
      expect(results.first.id, 'a');
    });

    test('getAll with random order returns all bookmarks', () async {
      for (var i = 0; i < 10; i++) {
        await repo.upsert(makeBookmark(id: '$i', createdAt: DateTime(2024, 1, i + 1)));
      }
      final results = await repo.getAll(order: SortOrder.random);
      expect(results.length, 10);
      // All IDs should be present regardless of order
      expect(results.map((b) => b.id).toSet(), {for (var i = 0; i < 10; i++) '$i'});
    });

    test('getAll with byHost groups by host and sorts by date within group', () async {
      await repo.upsert(
        makeBookmark(id: 'z1', url: 'https://zebra.com/old', createdAt: DateTime(2024, 1, 1)),
      );
      await repo.upsert(
        makeBookmark(id: 'a2', url: 'https://alpha.com/newer', createdAt: DateTime(2024, 6, 1)),
      );
      await repo.upsert(
        makeBookmark(id: 'a1', url: 'https://alpha.com/older', createdAt: DateTime(2024, 1, 1)),
      );
      await repo.upsert(
        makeBookmark(id: 'z2', url: 'https://zebra.com/new', createdAt: DateTime(2024, 6, 1)),
      );

      final results = await repo.getAll(order: SortOrder.byHost);
      final ids = results.map((b) => b.id).toList();
      // alpha.com first (alphabetical), oldest first within group
      expect(ids, ['a1', 'a2', 'z1', 'z2']);
    });

    test('getAll with byHost sorts by host not full URL path', () async {
      await repo.upsert(
        makeBookmark(id: 'b1', url: 'https://beta.com/zzz', createdAt: DateTime(2024, 1, 1)),
      );
      await repo.upsert(
        makeBookmark(id: 'a1', url: 'https://alpha.com/aaa', createdAt: DateTime(2024, 1, 1)),
      );
      final results = await repo.getAll(order: SortOrder.byHost);
      // alpha.com before beta.com regardless of path
      expect(results.first.id, 'a1');
    });

    test('clear removes all', () async {
      await repo.upsert(makeBookmark());
      await repo.clear();
      final all = await repo.getAll();
      expect(all, isEmpty);
    });

    test('delete counter starts at zero', () async {
      expect(await repo.getDeleteCount(), 0);
    });

    test('incrementDeleteCount increments by 1', () async {
      await repo.incrementDeleteCount();
      await repo.incrementDeleteCount();
      expect(await repo.getDeleteCount(), 2);
    });

    test('incrementDeleteCount increments by n', () async {
      await repo.incrementDeleteCount(5);
      expect(await repo.getDeleteCount(), 5);
    });

    test('resetDeleteCount resets to zero', () async {
      await repo.incrementDeleteCount(3);
      await repo.resetDeleteCount();
      expect(await repo.getDeleteCount(), 0);
    });
  });
}
