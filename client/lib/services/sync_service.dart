import 'package:florilegio/data/api_client.dart';
import 'package:florilegio/domain/bookmark.dart';
import 'package:florilegio/domain/bookmark_repository.dart';
import 'package:florilegio/services/title_fetcher.dart';

class SyncResult {
  final bool success;
  final Object? exception;
  final int count;
  final int flushed; // pending bookmarks pushed to remote during this sync
  final bool notModified; // true when server returned 304

  SyncResult({
    required this.success,
    this.exception,
    this.count = 0,
    this.flushed = 0,
    this.notModified = false,
  });
}

/// Result of saving a bookmark — distinguishes remote, local-only, and
/// already-saved outcomes.
class SaveResult {
  final Bookmark? bookmark;
  final bool savedRemotely;
  final bool queuedLocally;
  final bool alreadyExists;
  final Object? error;

  SaveResult.remote(this.bookmark)
    : savedRemotely = true,
      queuedLocally = false,
      alreadyExists = false,
      error = null;
  SaveResult.queued()
    : bookmark = null,
      savedRemotely = false,
      queuedLocally = true,
      alreadyExists = false,
      error = null;
  SaveResult.duplicate()
    : bookmark = null,
      savedRemotely = false,
      queuedLocally = false,
      alreadyExists = true,
      error = null;
  SaveResult.failed(this.error)
    : bookmark = null,
      savedRemotely = false,
      queuedLocally = false,
      alreadyExists = false;
}

class SyncService {
  final BookmarkRepository _repository;
  final BookmarkApiClient _apiClient;
  final TitleFetcher? _titleFetcher;

  SyncService({required this._repository, required this._apiClient, this._titleFetcher});

  /// Exposed for UI needs that hit the API directly (e.g. favicon URLs).
  BookmarkApiClient get apiClient => _apiClient;

  /// Full sync: flush pending queue, then fetch all remote bookmarks and replace local data.
  /// When [force] is true (user-initiated refresh), skips If-Modified-Since.
  Future<SyncResult> sync({bool force = false}) async {
    // 1. Flush pending queue first (best-effort, don't fail the whole sync).
    final flushed = await _flushPendingQueue();

    // If we flushed items, invalidate the cached Last-Modified since
    // the server data has changed.
    if (flushed > 0) {
      await _repository.setLastModified(null);
    }

    // 2. Fetch all remote bookmarks and replace local.
    try {
      final ifModifiedSince = force ? null : await _repository.getLastModified();
      final result = await _apiClient.listAll(ifModifiedSince: ifModifiedSince);
      if (result == null) {
        // 304 Not Modified — local data is already up to date.
        return SyncResult(success: true, flushed: flushed, notModified: true);
      }
      await _repository.replaceAll(result.bookmarks);
      await _repository.setLastModified(result.lastModified);
      return SyncResult(success: true, count: result.bookmarks.length, flushed: flushed);
    } catch (e) {
      return SyncResult(success: false, exception: e, flushed: flushed);
    }
  }

  /// Flush the pending queue: try to push each URL to the API.
  /// Returns the number of successfully flushed bookmarks.
  Future<int> _flushPendingQueue() async {
    final pending = await _repository.getPending();
    if (pending.isEmpty) return 0;

    var flushed = 0;
    for (final p in pending) {
      try {
        final title = await _fetchTitleQuietly(p.url);
        await _apiClient.create(p.url, title: title);
        await _repository.removePending(p.url);
        flushed++;
      } on ApiException catch (e) {
        if (e.statusCode == 409) {
          // Already exists on server — remove from queue silently.
          await _repository.removePending(p.url);
          flushed++;
        }
        // Other API errors: leave in queue for next sync.
      } catch (_) {
        // Network error: leave in queue, stop trying (we're probably offline).
        break;
      }
    }
    return flushed;
  }

  /// Save a new bookmark. Tries API first; on failure, queues locally.
  /// A 409 means the bookmark is already on the server — reported as such,
  /// not queued. If the bookmark has no title, attempts to fetch one from
  /// the page.
  ///
  /// Never throws: every failure mode is reported through [SaveResult].
  Future<SaveResult> saveBookmark(String url) async {
    try {
      final title = await _fetchTitleQuietly(url);
      final bookmark = await _apiClient.create(url, title: title);
      await _repository.upsert(bookmark);
      return SaveResult.remote(bookmark);
    } on ApiException catch (e) {
      if (e.statusCode == 409) return SaveResult.duplicate();
      return _queueLocally(url);
    } catch (_) {
      return _queueLocally(url);
    }
  }

  Future<SaveResult> _queueLocally(String url) async {
    try {
      await _repository.addPending(url);
      return SaveResult.queued();
    } catch (e) {
      return SaveResult.failed(e);
    }
  }

  /// Update a bookmark via API and store locally.
  Future<Bookmark> updateBookmark(String id, {String? title, List<String>? tags}) async {
    final bookmark = await _apiClient.update(id, title: title, tags: tags);
    await _repository.upsert(bookmark);
    return bookmark;
  }

  /// Delete a bookmark via API and remove locally.
  Future<void> deleteBookmark(String id) async {
    await _apiClient.delete(id);
    await _repository.delete(id);
    await _repository.incrementDeleteCount();
  }

  /// Best-effort title fetch. Returns null on any failure.
  Future<String?> _fetchTitleQuietly(String url) async {
    if (_titleFetcher == null) return null;
    try {
      return await _titleFetcher.fetch(url);
    } catch (_) {
      return null;
    }
  }
}
