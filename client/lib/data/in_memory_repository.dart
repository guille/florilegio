import 'package:florilegio/domain/bookmark.dart';
import 'package:florilegio/domain/bookmark_repository.dart';

/// In-memory implementation for testing.
class InMemoryBookmarkRepository implements BookmarkRepository {
  final List<Bookmark> _bookmarks = [];
  final List<PendingBookmark> _pending = [];

  @override
  Future<List<Bookmark>> getAll({
    String? query,
    String? tag,
    SortOrder order = SortOrder.newestFirst,
  }) async {
    var results = List<Bookmark>.from(_bookmarks);

    if (query != null && query.isNotEmpty) {
      final q = query.toLowerCase();
      results = results
          .where(
            (b) => (b.title?.toLowerCase().contains(q) ?? false) || b.url.toLowerCase().contains(q),
          )
          .toList();
    }

    if (tag != null) {
      results = results.where((b) => b.tags.contains(tag)).toList();
    }

    if (order == SortOrder.random) {
      results.shuffle();
    } else if (order == SortOrder.byHost) {
      results.sort((a, b) {
        final hostA = Uri.tryParse(a.url)?.host ?? a.url;
        final hostB = Uri.tryParse(b.url)?.host ?? b.url;
        final cmp = hostA.compareTo(hostB);
        if (cmp != 0) return cmp;
        return a.createdAt.compareTo(b.createdAt);
      });
    } else {
      results.sort(
        (a, b) => order == SortOrder.newestFirst
            ? b.createdAt.compareTo(a.createdAt)
            : a.createdAt.compareTo(b.createdAt),
      );
    }

    return results;
  }

  @override
  Future<Bookmark?> getById(String id) async {
    try {
      return _bookmarks.firstWhere((b) => b.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> upsert(Bookmark bookmark) async {
    _bookmarks
      ..removeWhere((b) => b.id == bookmark.id)
      ..add(bookmark);
  }

  @override
  Future<void> upsertAll(List<Bookmark> bookmarks) async {
    for (final b in bookmarks) {
      await upsert(b);
    }
  }

  @override
  Future<void> delete(String id) async {
    _bookmarks.removeWhere((b) => b.id == id);
  }

  @override
  Future<void> replaceAll(List<Bookmark> bookmarks) async {
    _bookmarks
      ..clear()
      ..addAll(bookmarks);
  }

  @override
  Future<void> clear() async {
    _bookmarks.clear();
  }

  // ── Pending queue ────────────────────────────────────────────────────────

  @override
  Future<void> addPending(String url) async {
    if (!_pending.any((p) => p.url == url)) {
      _pending.add(PendingBookmark(url: url, createdAt: DateTime.now()));
    }
  }

  @override
  Future<List<PendingBookmark>> getPending() async => List.unmodifiable(_pending);

  @override
  Future<void> removePending(String url) async {
    _pending.removeWhere((p) => p.url == url);
  }

  @override
  Future<int> getPendingCount() async => _pending.length;

  // ── Sync metadata ──────────────────────────────────────────────────────

  String? _lastModified;

  @override
  Future<void> setLastModified(String? value) async => _lastModified = value;

  @override
  Future<String?> getLastModified() async => _lastModified;

  // ── Delete counter ─────────────────────────────────────────────────────

  int _deleteCount = 0;

  @override
  Future<int> getDeleteCount() async => _deleteCount;

  @override
  Future<void> incrementDeleteCount([int n = 1]) async => _deleteCount += n;

  @override
  Future<void> resetDeleteCount() async => _deleteCount = 0;
}
