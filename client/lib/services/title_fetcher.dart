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

  TitleFetcher({http.Client? client}) : _client = client ?? http.Client();

  /// Fetch the title for [url]. Returns `null` on failure or timeout.
  Future<String?> fetch(String url) async {
    try {
      final response = await _client
          .get(Uri.parse(url), headers: {'User-Agent': 'Florilegio/1.0 (bookmark service)'})
          .timeout(_timeout);

      if (response.statusCode != 200) return null;

      // Limit how much HTML we inspect — titles live in <head>, so the first
      // 64 KB is more than enough. This avoids holding multi-MB pages in memory
      // just to parse a title.
      final body = response.body.length > 65536 ? response.body.substring(0, 65536) : response.body;

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
