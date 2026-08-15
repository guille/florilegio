import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Fetches the page title from a URL by looking at (in priority order):
/// 1. `<meta property="og:title" content="...">`
/// 2. `<meta name="twitter:title" content="...">`
/// 3. `<title>...</title>`
///
/// Returns `null` on any failure or if no title is found.
class TitleFetcher {
  final http.Client _client;
  static const _timeout = Duration(milliseconds: 1500);

  /// Titles live in `<head>`, which fits comfortably in the first 64 KB —
  /// stop reading (and downloading) there.
  static const _maxBytes = 65536;

  TitleFetcher({http.Client? client}) : _client = client ?? http.Client();

  /// Fetch the title for [url]. Returns `null` on failure or timeout.
  Future<String?> fetch(String url) async {
    try {
      final body = await _fetchHead(url).timeout(_timeout);
      if (body == null) return null;

      // 1. og:title
      final ogTitle = _extractMetaContent(body, 'og:title', attribute: 'property');
      if (ogTitle != null) return ogTitle;

      // 2. twitter:title
      final twitterTitle = _extractMetaContent(body, 'twitter:title', attribute: 'name');
      if (twitterTitle != null) return twitterTitle;

      // 3. <title>
      final titleMatch = RegExp(
        '<title[^>]*>(.*?)</title>',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(body);
      if (titleMatch != null) {
        final raw = _decodeEntities(titleMatch.group(1)!.trim());
        if (raw.isNotEmpty) return _clamp(raw);
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  /// Stream the response and decode only the first [_maxBytes]; the rest of
  /// the page is never downloaded. Returns what arrived even if the
  /// connection drops mid-stream, or null on a non-200 / empty response.
  Future<String?> _fetchHead(String url) async {
    final request = http.Request('GET', Uri.parse(url))
      ..headers['User-Agent'] = 'Florilegio/1.0 (bookmark service)';
    final response = await _client.send(request);
    if (response.statusCode != 200) return null;

    final buffer = BytesBuilder(copy: false);
    try {
      await for (final chunk in response.stream) {
        buffer.add(chunk);
        // Breaking cancels the subscription, which closes the connection.
        if (buffer.length >= _maxBytes) break;
      }
    } catch (_) {
      // Connection dropped mid-stream — parse whatever arrived.
    }
    if (buffer.isEmpty) return null;

    final bytes = buffer.takeBytes();
    return _decode(
      bytes.length > _maxBytes ? Uint8List.sublistView(bytes, 0, _maxBytes) : bytes,
      response.headers['content-type'],
    );
  }

  /// Decode using the Content-Type charset when given, defaulting to UTF-8.
  /// Malformed sequences (wrong guess, or a chunk boundary that cut a
  /// multibyte character) become U+FFFD instead of throwing.
  static String _decode(Uint8List bytes, String? contentType) {
    final charset = RegExp('charset="?([^\\s;"]+)', caseSensitive: false)
        .firstMatch(contentType ?? '')
        ?.group(1)
        ?.toLowerCase();
    return switch (charset) {
      'iso-8859-1' || 'latin-1' || 'latin1' || 'us-ascii' || 'ascii' => latin1.decode(bytes),
      _ => utf8.decode(bytes, allowMalformed: true),
    };
  }

  /// Extract `content` from a `<meta>` tag matching [attribute]=[value].
  static String? _extractMetaContent(String html, String value, {required String attribute}) {
    assert(
      RegExp(r'^[a-zA-Z\-]+$').hasMatch(attribute),
      'attribute must be a plain identifier, got: $attribute',
    );
    // Match both orderings: attribute before content and content before attribute.
    // e.g. <meta property="og:title" content="Hello">
    // e.g. <meta content="Hello" property="og:title">
    final patterns = [
      RegExp(
        '<meta[^>]+$attribute\\s*=\\s*["\']${RegExp.escape(value)}["\'][^>]+content\\s*=\\s*["\']([^"\']*)["\']',
        caseSensitive: false,
      ),
      RegExp(
        '<meta[^>]+content\\s*=\\s*["\']([^"\']*)["\'][^>]+$attribute\\s*=\\s*["\']${RegExp.escape(value)}["\']',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null) {
        final raw = _decodeEntities(match.group(1)!.trim());
        if (raw.isNotEmpty) return _clamp(raw);
      }
    }
    return null;
  }

  static String _decodeEntities(String s) {
    // Decode numeric entities first: &#NNN; (decimal) and &#xHHH; (hex).
    // This handles ALL numeric entities generically.
    var result = s.replaceAllMapped(RegExp('&#x([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(1)!, radix: 16);
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    });
    result = result.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    });
    // Decode common named entities (covers the vast majority of real titles).
    const named = {
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&apos;': "'",
      '&nbsp;': ' ',
      '&ndash;': '\u2013',
      '&mdash;': '\u2014',
      '&lsquo;': '\u2018',
      '&rsquo;': '\u2019',
      '&ldquo;': '\u201C',
      '&rdquo;': '\u201D',
      '&hellip;': '\u2026',
      '&bull;': '\u2022',
      '&trade;': '\u2122',
      '&copy;': '\u00A9',
      '&reg;': '\u00AE',
    };
    for (final entry in named.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result.replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _clamp(String s) => s.length > 2000 ? s.substring(0, 2000) : s;

  void dispose() => _client.close();
}
