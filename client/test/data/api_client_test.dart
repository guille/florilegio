import 'dart:convert';

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
    group('list', () {
      test('sends GET with auth header', () async {
        late http.Request captured;
        final client = http_testing.MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode([sampleBookmark]), 200);
        });
        final api = makeApi(client);

        await api.list();
        expect(captured.method, 'GET');
        expect(captured.url.path, '/bookmarks');
        expect(captured.headers['Authorization'], 'Bearer test-token');
      });

      test('passes query params', () async {
        late Uri captured;
        final client = http_testing.MockClient((request) async {
          captured = request.url;
          return http.Response(jsonEncode([]), 200);
        });
        final api = makeApi(client);

        await api.list(tag: 'dev', query: 'flutter');
        expect(captured.queryParameters['tag'], 'dev');
        expect(captured.queryParameters['q'], 'flutter');
      });

      test('throws ApiException on non-200', () async {
        final client = http_testing.MockClient(
          (request) async => http.Response('Unauthorized', 401),
        );
        final api = makeApi(client);

        expect(api.list, throwsA(isA<ApiException>()));
      });

      test('parses bookmarks correctly', () async {
        final client = http_testing.MockClient(
          (request) async => http.Response(jsonEncode([sampleBookmark]), 200),
        );
        final api = makeApi(client);

        final bookmarks = await api.list();
        expect(bookmarks.length, 1);
        expect(bookmarks.first.id, '1');
        expect(bookmarks.first.tags, ['dev']);
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
