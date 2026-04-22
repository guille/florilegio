import 'package:florilegio/domain/bookmark.dart';

enum SortOrder { newestFirst, oldestFirst, random, byHost }

/// A URL queued for saving when the device was offline.
class PendingBookmark {
  final String url;
  final DateTime createdAt;
  const PendingBookmark({required this.url, required this.createdAt});
}

/// Abstract repository for local bookmark storage.
abstract class BookmarkRepository {
  Future<List<Bookmark>> getAll({
    String? query,
    String? tag,
    SortOrder order = SortOrder.newestFirst,
  });

  Future<Bookmark?> getById(String id);

  Future<void> upsert(Bookmark bookmark);

  Future<void> upsertAll(List<Bookmark> bookmarks);

  Future<void> delete(String id);

  /// Replace all local data with the given list (full sync).
  Future<void> replaceAll(List<Bookmark> bookmarks);

  Future<void> clear();

  // ── Pending queue (offline saves) ──────────────────────────────────────

  /// Queue a URL for saving when connectivity is restored.
  Future<void> addPending(String url);

  /// Get all pending URLs.
  Future<List<PendingBookmark>> getPending();

  /// Remove a URL from the pending queue (after successful push).
  Future<void> removePending(String url);

  /// Get count of pending URLs.
  Future<int> getPendingCount();

  // ── Sync metadata ──────────────────────────────────────────────────────

  /// Store the Last-Modified value from the most recent successful sync.
  Future<void> setLastModified(String? value);

  /// Retrieve the stored Last-Modified value, or null if not set.
  Future<String?> getLastModified();

  // ── Delete counter ─────────────────────────────────────────────────────

  /// Get the running count of deleted bookmarks.
  Future<int> getDeleteCount();

  /// Increment the delete counter by [n].
  Future<void> incrementDeleteCount([int n = 1]);

  /// Reset the delete counter to zero.
  Future<void> resetDeleteCount();
}
