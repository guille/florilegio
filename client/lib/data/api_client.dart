import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:florilegio/domain/bookmark.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  String get userMessage {
    if (statusCode == 0) return message; // timeout or connectivity
    if (statusCode == 401) return 'Authentication failed — check your token';
    if (statusCode == 403) return 'Access denied';
    if (statusCode == 404) return 'Not found';
    if (statusCode == 409) return 'Bookmark already exists';
    if (statusCode >= 500) return 'Server error ($statusCode)';
    return 'Request failed ($statusCode)';
  }

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// The request never reached the server: timeout, DNS failure, refused or
/// black-holed connection. Status 0 because there was no response to take a
/// status from. Callers that only care about HTTP outcomes can keep catching
/// [ApiException].
class NetworkException extends ApiException {
  NetworkException(String message) : super(0, message);
}

/// A request that can be torn down before it completes.
class _AbortableRequest extends http.Request with http.Abortable {
  @override
  final Future<void>? abortTrigger;

  _AbortableRequest(super.method, super.url, this.abortTrigger);
}

class BookmarkApiClient {
  final String baseUrl;
  final String token;
  final http.Client _client;

  /// Deadline for response headers to arrive.
  static const _headersTimeout = Duration(seconds: 8);

  /// Deadline for the complete request, headers and body.
  static const _totalTimeout = Duration(seconds: 15);

  /// Export and import are bigger payloads so get a more generous timeout.
  static const _bulkTimeout = Duration(seconds: 60);

  BookmarkApiClient({required String baseUrl, required this.token, http.Client? client})
    : baseUrl = _normalizeBaseUrl(baseUrl),
      _client = client ?? http.Client();

  /// Ensure baseUrl has https:// and no trailing slash.
  static String _normalizeBaseUrl(String url) {
    var u = url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
    'Accept-Encoding': 'gzip',
  };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  /// URL of the server-side favicon proxy for [host].
  /// Image requests must send [faviconHeaders].
  String faviconUrl(String host) => '$baseUrl/favicon/$host';

  /// Auth-only headers for favicon image requests.
  Map<String, String> get faviconHeaders => {'Authorization': 'Bearer $token'};

  /// "Never reached the server" arrives as several unrelated exception types —
  /// normalize them all to [NetworkException] so callers can distinguish an
  /// unreachable server from one that answered.
  Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    String? body,
    bool bulk = false,
  }) async {
    // Letting a deadline simply abandon the request is not enough: nothing then
    // drains the response, so the socket stays checked out of the pool even
    // once the server does answer. The trigger tears it down instead.
    final abort = Completer<void>();
    final request = _AbortableRequest(method, uri, abort.future);
    if (headers != null) request.headers.addAll(headers);
    // After the headers: the body setter encodes using the charset they declare.
    if (body != null) request.body = body;

    final total = bulk ? _bulkTimeout : _totalTimeout;
    final start = clock.now();

    try {
      final response = await _client.send(request).timeout(bulk ? total : _headersTimeout);
      final remaining = total - clock.now().difference(start);
      return await http.Response.fromStream(
        response,
      ).timeout(remaining.isNegative ? Duration.zero : remaining);
    } on TimeoutException {
      abort.complete();
      throw NetworkException('Request timed out — check your connection and try again');
    } on http.ClientException {
      throw NetworkException('Could not reach the server — check your connection');
    }
  }

  /// Fetch a single page. Returns (bookmarks, totalCount, etag) or null if the
  /// server returned 304 Not Modified.
  Future<(List<Bookmark>, int, String?)?> _listPage({
    int limit = 200,
    int offset = 0,
    String? ifNoneMatch,
  }) async {
    final params = <String, String>{'limit': limit.toString(), 'offset': offset.toString()};

    final headers = Map<String, String>.from(_headers);
    if (ifNoneMatch != null) headers['If-None-Match'] = ifNoneMatch;

    final response = await _send('GET', _uri('/bookmarks', params), headers: headers);
    if (response.statusCode == 304) return null;
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
    final data = jsonDecode(response.body) as List<dynamic>;
    final bookmarks = data.map((j) => Bookmark.fromJson(j as Map<String, dynamic>)).toList();
    final total = int.tryParse(response.headers['x-total-count'] ?? '') ?? bookmarks.length;
    return (bookmarks, total, response.headers['etag']);
  }

  /// Fetch the whole collection, paginating until exhausted.
  /// If [ifNoneMatch] is provided and the server returns 304, returns null
  /// (meaning "no changes"). Otherwise returns the full list and the validator
  /// to send next time, which is null when the snapshot cannot be trusted.
  Future<({List<Bookmark> bookmarks, String? syncToken})?> listAll({String? ifNoneMatch}) async {
    const pageSize = 200;
    final all = <Bookmark>[];
    var offset = 0;
    String? firstEtag;
    var torn = false;

    while (true) {
      final result = await _listPage(
        limit: pageSize,
        offset: offset,
        ifNoneMatch: offset == 0 ? ifNoneMatch : null,
      );
      if (result == null) return null; // 304

      final (page, _, etag) = result;
      if (offset == 0) {
        firstEtag = etag;
      } else if (etag != firstEtag) {
        // A write landed between pages, so the assembled list is a torn
        // snapshot spanning two server states. Keep the rows — they are still
        // roughly current — but return no validator, so the next sync refetches
        // instead of caching a token for a state we never actually saw.
        torn = true;
      }
      all.addAll(page);
      if (page.length < pageSize) break;
      offset += pageSize;
    }

    // Offset paging over `created_at DESC` shifts rows right when a bookmark is
    // created mid-pagination — a new row sorts first — so the tail of one page
    // reappears at the head of the next. Drop those repeats: the assembled list
    // feeds replaceAll, and a duplicate id would abort the whole write.
    final seen = <String>{};
    final deduped = all.where((b) => seen.add(b.id)).toList();

    return (bookmarks: deduped, syncToken: torn ? null : firstEtag);
  }

  Future<Bookmark> create(String url, {String? title}) async {
    final payload = <String, dynamic>{'url': url};
    if (title != null) payload['title'] = title;
    final response = await _send(
      'POST',
      _uri('/bookmarks'),
      headers: _headers,
      body: jsonEncode(payload),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ApiException(response.statusCode, response.body);
    }
    return Bookmark.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Bookmark> update(String id, {String? title, List<String>? tags}) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (tags != null) body['tags'] = tags; // API accepts array, joins to CSV

    final response = await _send(
      'PATCH',
      _uri('/bookmarks/$id'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
    return Bookmark.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    final response = await _send('DELETE', _uri('/bookmarks/$id'), headers: _headers);
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  /// Export all bookmarks as raw JSON string.
  Future<String> exportJson() async {
    final response = await _send('GET', _uri('/bookmarks/export'), headers: _headers, bulk: true);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
    return response.body;
  }

  /// Import bookmarks from a JSON array string.
  /// Returns a map with { imported, skipped, errors }.
  Future<Map<String, dynamic>> importJson(String jsonBody) async {
    final response = await _send(
      'POST',
      _uri('/bookmarks/import'),
      headers: _headers,
      body: jsonBody,
      bulk: true,
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void dispose() => _client.close();
}
