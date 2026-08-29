import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:florilegio/data/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

void main() {
  BookmarkApiClient makeApi(http.Client client) =>
      BookmarkApiClient(baseUrl: 'https://api.test', token: 'test-token', client: client);

  final sampleBookmark = {
    'id': '1',
    'url': 'https://example.com',
    'title': 'Example',
    'tags': 'dev',
    'created_at': '2024-01-01T00:00:00.000Z',
    'updated_at': '2024-01-01T00:00:00.000Z',
    'is_read': 0,
  };

  group('BookmarkApiClient', () {
    group('listAll', () {
      test('sends GET with auth header and pagination params', () async {
        late http.Request captured;
        final client = http_testing.MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode([sampleBookmark]), 200);
        });
        final api = makeApi(client);

        await api.listAll();
        expect(captured.method, 'GET');
        expect(captured.url.path, '/bookmarks');
        expect(captured.headers['Authorization'], 'Bearer test-token');
        expect(captured.url.queryParameters['limit'], '200');
        expect(captured.url.queryParameters['offset'], '0');
      });

      test('throws ApiException on non-200', () async {
        final client = http_testing.MockClient(
          (request) async => http.Response('Unauthorized', 401),
        );
        final api = makeApi(client);

        expect(api.listAll, throwsA(isA<ApiException>()));
      });

      test('returns null on 304', () async {
        late http.Request captured;
        final client = http_testing.MockClient((request) async {
          captured = request;
          return http.Response('', 304);
        });
        final api = makeApi(client);

        expect(await api.listAll(ifNoneMatch: '"7"'), isNull);
        expect(captured.headers['If-None-Match'], '"7"');
      });

      test('parses bookmarks correctly', () async {
        final client = http_testing.MockClient(
          (request) async => http.Response(jsonEncode([sampleBookmark]), 200),
        );
        final api = makeApi(client);

        final result = await api.listAll();
        expect(result!.bookmarks.length, 1);
        expect(result.bookmarks.first.id, '1');
        expect(result.bookmarks.first.tags, ['dev']);
      });
    });

    group('create', () {
      test('sends POST with URL in body', () async {
        late String body;
        final client = http_testing.MockClient((request) async {
          body = request.body;
          return http.Response(jsonEncode(sampleBookmark), 201);
        });
        final api = makeApi(client);

        await api.create('https://example.com');
        expect((jsonDecode(body) as Map<String, dynamic>)['url'], 'https://example.com');
      });

      test('accepts 200 and 201', () async {
        for (final code in [200, 201]) {
          final client = http_testing.MockClient(
            (request) async => http.Response(jsonEncode(sampleBookmark), code),
          );
          final api = makeApi(client);
          final b = await api.create('https://example.com');
          expect(b.id, '1');
        }
      });

      test('throws on 400', () async {
        final client = http_testing.MockClient(
          (request) async => http.Response('Bad request', 400),
        );
        final api = makeApi(client);
        expect(() => api.create('bad'), throwsA(isA<ApiException>()));
      });
    });

    group('update', () {
      test('sends PATCH with fields', () async {
        late String body;
        final client = http_testing.MockClient((request) async {
          body = request.body;
          return http.Response(jsonEncode(sampleBookmark), 200);
        });
        final api = makeApi(client);

        await api.update('1', title: 'New Title', tags: ['a', 'b']);
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        expect(decoded['title'], 'New Title');
        expect(decoded['tags'], ['a', 'b']);
      });
    });

    group('delete', () {
      test('sends DELETE request', () async {
        late String method;
        final client = http_testing.MockClient((request) async {
          method = request.method;
          return http.Response('', 204);
        });
        final api = makeApi(client);

        await api.delete('1');
        expect(method, 'DELETE');
      });

      test('accepts 200 and 204', () async {
        for (final code in [200, 204]) {
          final client = http_testing.MockClient((request) async => http.Response('', code));
          final api = makeApi(client);
          await api.delete('1');
        }
      });

      test('throws on 500', () async {
        final client = http_testing.MockClient((request) async => http.Response('error', 500));
        final api = makeApi(client);
        expect(() => api.delete('1'), throwsA(isA<ApiException>()));
      });
    });

    group('timeouts', () {
      /// A server that accepts the connection and then never answers — the
      /// shape of an ISP-level block, and what a connect timeout would miss.
      http.Client silentServer() =>
          http_testing.MockClient((request) => Completer<http.Response>().future);

      test('an unanswered request fails on the headers deadline', () {
        fakeAsync((async) {
          Object? error;
          unawaited(
            makeApi(silentServer()).listAll().then((_) {}, onError: (Object e) => error = e),
          );

          async.elapse(const Duration(seconds: 7));
          expect(error, isNull, reason: 'should still be waiting before the deadline');

          async.elapse(const Duration(seconds: 2));
          expect(error, isA<NetworkException>());
        });
      });

      /// Headers after [headersAfter], then a body that never completes.
      http.Client stallsInBody(Duration headersAfter) => http_testing.MockClient.streaming((
        request,
        _,
      ) async {
        await Future<void>.delayed(headersAfter);
        return http.StreamedResponse(StreamController<List<int>>().stream, 200, contentLength: 100);
      });

      test('the body deadline is the remainder of the total, not a fresh 15s', () {
        fakeAsync((async) {
          Object? error;
          unawaited(
            makeApi(
              stallsInBody(const Duration(seconds: 5)),
            ).listAll().then((_) {}, onError: (Object e) => error = e),
          );

          // Headers at 5s, so the body gets the remaining 10s of the 15s total.
          async.elapse(const Duration(seconds: 14));
          expect(error, isNull);

          async.elapse(const Duration(seconds: 2));
          expect(
            error,
            isA<NetworkException>(),
            reason: 'must fail at 15s total, not 5s + a fresh 15s body budget',
          );
        });
      });

      test('export waits past the interactive deadline', () {
        fakeAsync((async) {
          Object? error;
          unawaited(
            makeApi(silentServer()).exportJson().then((_) {}, onError: (Object e) => error = e),
          );

          async.elapse(const Duration(seconds: 30));
          expect(error, isNull, reason: 'bulk transfers get a longer budget');

          async.elapse(const Duration(seconds: 31));
          expect(error, isA<NetworkException>());
        });
      });
    });

    group('ApiException', () {
      test('userMessage for 401', () {
        expect(ApiException(401, '').userMessage, 'Authentication failed — check your token');
      });

      test('userMessage for 409', () {
        expect(ApiException(409, '').userMessage, 'Bookmark already exists');
      });

      test('userMessage for 500', () {
        expect(ApiException(500, '').userMessage, 'Server error (500)');
      });

      test('userMessage for 404', () {
        expect(ApiException(404, '').userMessage, 'Not found');
      });

      test('userMessage for other codes', () {
        expect(ApiException(422, '').userMessage, 'Request failed (422)');
      });
    });
  });
}
