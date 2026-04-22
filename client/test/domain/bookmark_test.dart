import 'package:florilegio/domain/bookmark.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Bookmark', () {
    test('fromJson / toRow roundtrip', () {
      final bookmark = Bookmark(
        id: 'abc',
        url: 'https://example.com',
        title: 'Example',
        tags: ['dev', 'read'],
        createdAt: DateTime.utc(2024, 1, 1),
        updatedAt: DateTime.utc(2024, 1, 2),
      );

      final row = bookmark.toRow();
      final restored = Bookmark.fromRow(row);

      expect(restored.id, 'abc');
      expect(restored.url, 'https://example.com');
      expect(restored.title, 'Example');
      expect(restored.tags, ['dev', 'read']);
    });

    test('fromJson handles comma-separated tags', () {
      final json = {
        'id': '1',
        'url': 'https://example.com',
        'tags': 'a,b',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
        'is_read': 0,
      };
      final b = Bookmark.fromJson(json);
      expect(b.tags, ['a', 'b']);
    });

    test('fromJson handles tags as list', () {
      final json = {
        'id': '1',
        'url': 'https://example.com',
        'tags': ['a', 'b'],
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
        'is_read': 0,
      };
      final b = Bookmark.fromJson(json);
      expect(b.tags, ['a', 'b']);
    });

    test('fromJson handles null/empty tags', () {
      final json = {
        'id': '1',
        'url': 'https://example.com',
        'tags': null,
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
        'is_read': 0,
      };
      final b = Bookmark.fromJson(json);
      expect(b.tags, isEmpty);
    });

    test('copyWith works', () {
      final b = Bookmark(
        id: '1',
        url: 'https://example.com',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        tags: ['old'],
      );
      final updated = b.copyWith(title: 'New', tags: ['new']);
      expect(updated.title, 'New');
      expect(updated.tags, ['new']);
      expect(updated.url, b.url);
    });
  });
}
