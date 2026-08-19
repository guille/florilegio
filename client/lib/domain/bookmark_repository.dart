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

  /// Store the validator (ETag) the server issued for the last synced
  /// snapshot. Opaque: echoed back verbatim, never parsed.
  Future<void> setSyncToken(String? value);

  /// Retrieve the stored sync validator, or null if there is none.
  Future<String?> getSyncToken();

  /// Store when this device last completed a sync (ISO-8601).
  Future<void> setLastRefreshed(String? value);

  /// Retrieve when this device last completed a sync, or null if never.
  Future<String?> getLastRefreshed();

  // ── Delete counter ─────────────────────────────────────────────────────

  /// Get the running count of deleted bookmarks.
  Future<int> getDeleteCount();

  /// Increment the delete counter by [n].
  Future<void> incrementDeleteCount([int n = 1]);

  /// Reset the delete counter to zero.
  Future<void> resetDeleteCount();
}
