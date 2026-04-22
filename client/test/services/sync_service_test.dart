import 'dart:convert';

import 'package:florilegio/data/api_client.dart';
import 'package:florilegio/data/in_memory_repository.dart';
import 'package:florilegio/domain/bookmark.dart';
import 'package:florilegio/services/sync_service.dart';
import 'package:florilegio/services/title_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

void main() {
  late InMemoryBookmarkRepository repo;

  setUp(() {
    repo = InMemoryBookmarkRepository();
  });

  BookmarkApiClient makeApi(http.Client client) =>
      BookmarkApiClient(baseUrl: 'https://api.test', token: 'test-token', client: client);

  final sampleBookmarks = [
    {
      'id': '1',
      'url': 'https://example.com',
      'title': 'Example',
      'tags': 'dev',
      'created_at': '2024-01-01T00:00:00.000Z',
      'updated_at': '2024-01-01T00:00:00.000Z',
      'is_read': 0,
    },
    {
      'id': '2',
      'url': 'https://other.com',
      'title': 'Other',
      'tags': null,
      'created_at': '2024-01-02T00:00:00.000Z',
      'updated_at': '2024-01-02T00:00:00.000Z',
      'is_read': 0,
    },
  ];

  group('SyncService', () {
    test('sync fetches remote and replaces local', () async {
      final client = http_testing.MockClient(
        (request) async => http.Response(jsonEncode(sampleBookmarks), 200),
      );
      final api = makeApi(client);
      final sync = SyncService(repository: repo, apiClient: api);

      final result = await sync.sync();
      expect(result.success, true);
      expect(result.count, 2);

      final local = await repo.getAll();
      expect(local.length, 2);
    });

    test('sync returns error on API failure', () async {
      final client = http_testing.MockClient((request) async => http.Response('Server error', 500));
      final api = makeApi(client);
      final sync = SyncService(repository: repo, apiClient: api);

      final result = await sync.sync();
      expect(result.success, false);
      expect(result.exception, isNotNull);
    });

    test('saveBookmark posts and stores locally on success', () async {
      final created = {
        'id': 'new-1',
        'url': 'https://new.com',
        'title': null,
        'tags': null,
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
        'is_read': 0,
      };
      final client = http_testing.MockClient((request) async {
        expect(request.method, 'POST');
        return http.Response(jsonEncode(created), 201);
      });
      final api = makeApi(client);
      final sync = SyncService(repository: repo, apiClient: api);

      final result = await sync.saveBookmark('https://new.com');
      expect(result.savedRemotely, true);
      expect(result.queuedLocally, false);
      expect(result.bookmark!.id, 'new-1');
      expect(await repo.getById('new-1'), isNotNull);
    });

    test('saveBookmark queues locally when API fails', () async {
      final client = http_testing.MockClient((request) async => http.Response('Server error', 500));
      final api = makeApi(client);
      final sync = SyncService(repository: repo, apiClient: api);

      final result = await sync.saveBookmark('https://offline.com');
      expect(result.savedRemotely, false);
      expect(result.queuedLocally, true);

      final pending = await repo.getPending();
      expect(pending.length, 1);
      expect(pending.first.url, 'https://offline.com');
    });

    test('sync flushes pending queue before fetching', () async {
      // Queue a pending bookmark
      await repo.addPending('https://queued.com');

      final createdBookmark = {
        'id': 'q-1',
        'url': 'https://queued.com/',
        'title': null,
        'tags': null,
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
        'is_read': 0,
      };

      var postCalled = false;
      final client = http_testing.MockClient((request) async {
        if (request.method == 'POST' && request.url.path == '/bookmarks') {
          postCalled = true;
          return http.Response(jsonEncode(createdBookmark), 201);
        }
        // GET /bookmarks for sync
        return http.Response(jsonEncode([createdBookmark]), 200);
      });
      final api = makeApi(client);
      final sync = SyncService(repository: repo, apiClient: api);

      final result = await sync.sync();
      expect(result.success, true);
      expect(result.flushed, 1);
      expect(postCalled, true);

      // Pending queue should be empty
      final pending = await repo.getPending();
      expect(pending.isEmpty, true);
    });

    test('sync removes 409 duplicates from pending queue', () async {
      await repo.addPending('https://already-exists.com');

      final client = http_testing.MockClient((request) async {
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode({'error': 'Bookmark already exists', 'existing_id': 'x'}),
            409,
          );
        }
        return http.Response(jsonEncode(sampleBookmarks), 200);
      });
      final api = makeApi(client);
      final sync = SyncService(repository: repo, apiClient: api);

      final result = await sync.sync();
      expect(result.success, true);
      expect(result.flushed, 1);

      final pending = await repo.getPending();
      expect(pending.isEmpty, true);
    });

    test('sync does not wipe local data on API failure', () async {
      // Pre-populate local data
      await repo.upsert(
        Bookmark(
          id: 'local-1',
          url: 'https://local.com',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final client = http_testing.MockClient((request) async => http.Response('Server error', 500));
      final api = makeApi(client);
      final sync = SyncService(repository: repo, apiClient: api);

      final result = await sync.sync();
      expect(result.success, false);

      // Local data should still be intact
      final local = await repo.getAll();
      expect(local.length, 1);
      expect(local.first.id, 'local-1');
    });

    test('deleteBookmark removes from API and local', () async {
      await repo.upsert(
        Bookmark(
          id: 'del-1',
          url: 'https://delete.me',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      final client = http_testing.MockClient((request) async {
        expect(request.method, 'DELETE');
        return http.Response('', 204);
      });
      final api = makeApi(client);
      final sync = SyncService(repository: repo, apiClient: api);

      await sync.deleteBookmark('del-1');
      expect(await repo.getById('del-1'), isNull);
    });

    test('deleteBookmark increments delete counter', () async {
      await repo.upsert(
        Bookmark(
          id: 'del-2',
          url: 'https://delete2.me',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      final client = http_testing.MockClient((request) async => http.Response('', 204));
      final api = makeApi(client);
      final sync = SyncService(repository: repo, apiClient: api);

      expect(await repo.getDeleteCount(), 0);
      await sync.deleteBookmark('del-2');
      expect(await repo.getDeleteCount(), 1);
    });

    test('saveBookmark sends title from fetcher in create request', () async {
      final created = {
        'id': 'tf-1',
        'url': 'https://titled.com',
        'title': 'Fetched Title',
        'tags': null,
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
        'is_read': 0,
      };

      Map<String, dynamic>? capturedBody;
      final apiClient = http_testing.MockClient((request) async {
        if (request.method == 'POST') {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(created), 201);
        }
        return http.Response('', 404);
      });

      // Title fetcher that returns a page with a title
      final titleClient = http_testing.MockClient(
        (_) async => http.Response('<html><head><title>Fetched Title</title></head></html>', 200),
      );
      final titleFetcher = TitleFetcher(client: titleClient);

      final api = makeApi(apiClient);
      final sync = SyncService(repository: repo, apiClient: api, titleFetcher: titleFetcher);

      final result = await sync.saveBookmark('https://titled.com');
      expect(result.savedRemotely, true);
      expect(capturedBody, isNotNull);
      expect(capturedBody!['title'], 'Fetched Title');
    });

    test('flush sends title from fetcher for pending bookmarks', () async {
      await repo.addPending('https://queued-titled.com');

      final createdBookmark = {
        'id': 'qt-1',
        'url': 'https://queued-titled.com/',
        'title': 'Queued Title',
        'tags': null,
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
        'is_read': 0,
      };

      Map<String, dynamic>? capturedBody;
      final apiClient = http_testing.MockClient((request) async {
        if (request.method == 'POST' && request.url.path == '/bookmarks') {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(createdBookmark), 201);
        }
        return http.Response(jsonEncode([createdBookmark]), 200);
      });

      final titleClient = http_testing.MockClient(
        (_) async => http.Response('<html><head><title>Queued Title</title></head></html>', 200),
      );
      final titleFetcher = TitleFetcher(client: titleClient);

      final api = makeApi(apiClient);
      final sync = SyncService(repository: repo, apiClient: api, titleFetcher: titleFetcher);

      final result = await sync.sync();
      expect(result.flushed, 1);
      expect(capturedBody, isNotNull);
      expect(capturedBody!['title'], 'Queued Title');
    });

    test('saveBookmark still works when title fetch fails', () async {
      final created = {
        'id': 'nf-1',
        'url': 'https://no-title.com',
        'title': null,
        'tags': null,
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
        'is_read': 0,
      };

      final apiClient = http_testing.MockClient((request) async {
        if (request.method == 'POST') {
          return http.Response(jsonEncode(created), 201);
        }
        return http.Response('', 404);
      });

      // Title fetcher that errors
      final titleClient = http_testing.MockClient((_) => throw Exception('network error'));
      final titleFetcher = TitleFetcher(client: titleClient);

      final api = makeApi(apiClient);
      final sync = SyncService(repository: repo, apiClient: api, titleFetcher: titleFetcher);

      final result = await sync.saveBookmark('https://no-title.com');
      expect(result.savedRemotely, true);
      expect(result.bookmark!.title, isNull);
    });

    test('sync skips replaceAll on 304 Not Modified', () async {
      // Pre-populate local data
      await repo.upsert(
        Bookmark(
          id: 'existing-1',
          url: 'https://existing.com',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      var getCalled = false;
      final client = http_testing.MockClient((request) async {
        if (request.method == 'GET') {
          getCalled = true;
          return http.Response('', 304);
        }
        return http.Response('', 404);
      });
      final api = makeApi(client);
      final sync = SyncService(repository: repo, apiClient: api);

      // First sync: will get 304
      final result = await sync.sync();
      expect(result.success, true);
      expect(result.notModified, true);
      expect(getCalled, true);

      // Local data should remain intact (not replaced with empty)
      final local = await repo.getAll();
      expect(local.length, 1);
      expect(local.first.id, 'existing-1');
    });

    test('sync sends If-Modified-Since on second sync', () async {
      const lastModifiedValue = 'Thu, 01 Jan 2024 00:00:00 GMT';
      String? capturedIms;

      var callCount = 0;
      final client = http_testing.MockClient((request) async {
        if (request.method == 'GET') {
          callCount++;
          capturedIms = request.headers['if-modified-since'];
          if (callCount == 1) {
            // First sync: return data with Last-Modified
            return http.Response(
              jsonEncode(sampleBookmarks),
              200,
              headers: {'last-modified': lastModifiedValue, 'x-total-count': '2'},
            );
          } else {
            // Second sync: 304
            return http.Response('', 304);
          }
        }
        return http.Response('', 404);
      });
      final api = makeApi(client);
      final sync = SyncService(repository: repo, apiClient: api);

      // First sync — no IMS header
      await sync.sync();
      expect(capturedIms, isNull);

      // Second sync — should send IMS from first response
      capturedIms = null;
      final result = await sync.sync();
      expect(capturedIms, lastModifiedValue);
      expect(result.notModified, true);
    });

    test('sync invalidates Last-Modified after flushing pending items', () async {
      // Set up: first sync succeeds and caches Last-Modified
      const lastModifiedValue = 'Thu, 01 Jan 2024 00:00:00 GMT';
      var callCount = 0;
      String? capturedIms;

      final createdBookmark = {
        'id': 'fl-1',
        'url': 'https://flushed.com/',
        'title': null,
        'tags': null,
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
        'is_read': 0,
      };

      final client = http_testing.MockClient((request) async {
        if (request.method == 'POST') {
          return http.Response(jsonEncode(createdBookmark), 201);
        }
        if (request.method == 'GET') {
          callCount++;
          capturedIms = request.headers['if-modified-since'];
          return http.Response(
            jsonEncode(sampleBookmarks),
            200,
            headers: {'last-modified': lastModifiedValue, 'x-total-count': '2'},
          );
        }
        return http.Response('', 404);
      });
      final api = makeApi(client);
      final sync = SyncService(repository: repo, apiClient: api);

      // First sync — caches Last-Modified
      await sync.sync();
      expect(callCount, 1);

      // Queue a pending bookmark — this should invalidate the cache
      await repo.addPending('https://flushed.com');

      // Second sync — should NOT send IMS because we flushed items
      capturedIms = 'should-be-cleared';
      await sync.sync();
      expect(capturedIms, isNull);
    });

    test('sync with force=true skips If-Modified-Since', () async {
      const lastModifiedValue = 'Thu, 01 Jan 2024 00:00:00 GMT';
      String? capturedIms;

      var callCount = 0;
      final client = http_testing.MockClient((request) async {
        if (request.method == 'GET') {
          callCount++;
          capturedIms = request.headers['if-modified-since'];
          return http.Response(
            jsonEncode(sampleBookmarks),
            200,
            headers: {'last-modified': lastModifiedValue, 'x-total-count': '2'},
          );
        }
        return http.Response('', 404);
      });
      final api = makeApi(client);
      final sync = SyncService(repository: repo, apiClient: api);

      // First sync — stores Last-Modified
      await sync.sync();
      expect(callCount, 1);
      expect(capturedIms, isNull);

      // Second sync with force — should NOT send IMS
      capturedIms = 'should-be-cleared';
      await sync.sync(force: true);
      expect(capturedIms, isNull);
      expect(callCount, 2);
    });

    test('lastModified is persisted in repository', () async {
      const lastModifiedValue = 'Thu, 01 Jan 2024 00:00:00 GMT';

      final client = http_testing.MockClient(
        (request) async => http.Response(
          jsonEncode(sampleBookmarks),
          200,
          headers: {'last-modified': lastModifiedValue, 'x-total-count': '2'},
        ),
      );
      final api = makeApi(client);
      final sync = SyncService(repository: repo, apiClient: api);

      await sync.sync();

      // Verify the value was persisted
      expect(await repo.getLastModified(), lastModifiedValue);
    });
  });
}
