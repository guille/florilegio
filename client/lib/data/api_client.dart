import 'dart:async';
import 'dart:convert';

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

class BookmarkApiClient {
  final String baseUrl;
  final String token;
  final http.Client _client;

  /// Request timeout. 30s is generous for mobile on poor connections.
  static const _timeout = Duration(seconds: 30);

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

  /// Wraps requests with a timeout and a user-friendly error message.
  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(_timeout);
    } on TimeoutException {
      throw ApiException(0, 'Request timed out — check your connection and try again');
    }
  }

  /// Fetch a single page. Returns (bookmarks, totalCount, lastModified) or
  /// null if the server returned 304 Not Modified.
  Future<(List<Bookmark>, int, String?)?> _listPage({
    String? tag,
    String? query,
    int limit = 200,
    int offset = 0,
    String? ifModifiedSince,
  }) async {
    final params = <String, String>{'limit': limit.toString(), 'offset': offset.toString()};
    if (tag != null) params['tag'] = tag;
    if (query != null) params['q'] = query;

    final headers = Map<String, String>.from(_headers);
    if (ifModifiedSince != null) headers['If-Modified-Since'] = ifModifiedSince;

    final response = await _send(() => _client.get(_uri('/bookmarks', params), headers: headers));
    if (response.statusCode == 304) return null;
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
    final data = jsonDecode(response.body) as List<dynamic>;
    final bookmarks = data.map((j) => Bookmark.fromJson(j as Map<String, dynamic>)).toList();
    final total = int.tryParse(response.headers['x-total-count'] ?? '') ?? bookmarks.length;
    final lastModified = response.headers['last-modified'];
    return (bookmarks, total, lastModified);
  }

  /// Fetch all bookmarks, paginating automatically until exhausted.
  /// If [ifModifiedSince] is provided and the server returns 304, returns null
  /// (meaning "no changes"). Otherwise returns the full list and the
  /// Last-Modified value from the server (if present).
  Future<({List<Bookmark> bookmarks, String? lastModified})?> listAll({
    String? tag,
    String? query,
    String? ifModifiedSince,
  }) async {
    const pageSize = 200;
    final all = <Bookmark>[];
    var offset = 0;
    String? lastModified;

    while (true) {
      final result = await _listPage(
        tag: tag,
        query: query,
        limit: pageSize,
        offset: offset,
        ifModifiedSince: offset == 0 ? ifModifiedSince : null,
      );
      if (result == null) return null; // 304

      final (page, _, lm) = result;
      if (offset == 0) lastModified = lm;
      all.addAll(page);
      if (page.length < pageSize) break;
      offset += pageSize;
    }
    return (bookmarks: all, lastModified: lastModified);
  }

  /// Fetch a single page of bookmarks (for UI display with pagination).
  Future<List<Bookmark>> list({String? tag, String? query}) async {
    final result = await _listPage(tag: tag, query: query);
    final (bookmarks, _, _) = result!;
    return bookmarks;
  }

  Future<Bookmark> create(String url, {String? title}) async {
    final payload = <String, dynamic>{'url': url};
    if (title != null) payload['title'] = title;
    final response = await _send(
      () => _client.post(_uri('/bookmarks'), headers: _headers, body: jsonEncode(payload)),
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
      () => _client.patch(_uri('/bookmarks/$id'), headers: _headers, body: jsonEncode(body)),
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
    return Bookmark.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    final response = await _send(() => _client.delete(_uri('/bookmarks/$id'), headers: _headers));
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  /// Export all bookmarks as raw JSON string.
  Future<String> exportJson() async {
    final response = await _send(() => _client.get(_uri('/bookmarks/export'), headers: _headers));
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
    return response.body;
  }

  /// Import bookmarks from a JSON array string.
  /// Returns a map with { imported, skipped, errors }.
  Future<Map<String, dynamic>> importJson(String jsonBody) async {
    final response = await _send(
      () => _client.post(_uri('/bookmarks/import'), headers: _headers, body: jsonBody),
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void dispose() => _client.close();
}
