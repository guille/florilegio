// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:convert';

import 'package:florilegio/services/title_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

http_testing.MockClient _mockPage(String body, {int status = 200}) =>
    http_testing.MockClient((_) async => http.Response(body, status));

/// Emits the response body as separate chunks, recording how many were read.
class _ChunkedClient extends http.BaseClient {
  final List<List<int>> chunks;
  final Map<String, String> headers;
  int chunksServed = 0;

  _ChunkedClient(this.chunks, {this.headers = const {}});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    Stream<List<int>> body() async* {
      for (final chunk in chunks) {
        chunksServed++;
        yield chunk;
      }
    }

    return http.StreamedResponse(body(), 200, headers: headers);
  }
}

void main() {
  group('TitleFetcher', () {
    test('extracts og:title', () async {
      final fetcher = TitleFetcher(
        client: _mockPage(
          '<html><head>'
          '<meta property="og:title" content="OG Title">'
          '<title>Fallback</title>'
          '</head></html>',
        ),
      );
      expect(await fetcher.fetch('https://example.com'), 'OG Title');
    });

    test('extracts og:title with reversed attribute order', () async {
      final fetcher = TitleFetcher(
        client: _mockPage(
          '<html><head>'
          '<meta content="Reversed OG" property="og:title">'
          '</head></html>',
        ),
      );
      expect(await fetcher.fetch('https://example.com'), 'Reversed OG');
    });

    test('extracts twitter:title when no og:title', () async {
      final fetcher = TitleFetcher(
        client: _mockPage(
          '<html><head>'
          '<meta name="twitter:title" content="Tweet Title">'
          '<title>Fallback</title>'
          '</head></html>',
        ),
      );
      expect(await fetcher.fetch('https://example.com'), 'Tweet Title');
    });

    test('falls back to <title> tag', () async {
      final fetcher = TitleFetcher(
        client: _mockPage('<html><head><title>Page Title</title></head></html>'),
      );
      expect(await fetcher.fetch('https://example.com'), 'Page Title');
    });

    test('handles multiline title', () async {
      final fetcher = TitleFetcher(
        client: _mockPage('<html><head><title>\n  Multi\n  Line\n</title></head></html>'),
      );
      expect(await fetcher.fetch('https://example.com'), 'Multi Line');
    });

    test('decodes HTML entities', () async {
      final fetcher = TitleFetcher(
        client: _mockPage('<html><head><title>A &amp; B &lt;3&gt;</title></head></html>'),
      );
      expect(await fetcher.fetch('https://example.com'), 'A & B <3>');
    });

    test('decodes numeric HTML entities (decimal and hex)', () async {
      final fetcher = TitleFetcher(
        client: _mockPage(
          '<html><head><title>It&#039;s a &#x201C;test&#x201D;</title></head></html>',
        ),
      );
      expect(await fetcher.fetch('https://example.com'), "It's a \u201Ctest\u201D");
    });

    test('decodes &nbsp;', () async {
      final fetcher = TitleFetcher(
        client: _mockPage('<html><head><title>Hello&nbsp;World</title></head></html>'),
      );
      expect(await fetcher.fetch('https://example.com'), 'Hello World');
    });

    test('returns null on non-200 status', () async {
      final fetcher = TitleFetcher(client: _mockPage('', status: 404));
      expect(await fetcher.fetch('https://example.com'), isNull);
    });

    test('returns null when no title found', () async {
      final fetcher = TitleFetcher(
        client: _mockPage('<html><head></head><body>No title here</body></html>'),
      );
      expect(await fetcher.fetch('https://example.com'), isNull);
    });

    test('returns null on empty title', () async {
      final fetcher = TitleFetcher(
        client: _mockPage('<html><head><title>   </title></head></html>'),
      );
      expect(await fetcher.fetch('https://example.com'), isNull);
    });

    test('returns null on network error', () async {
      final fetcher = TitleFetcher(
        client: http_testing.MockClient((_) => throw Exception('network')),
      );
      expect(await fetcher.fetch('https://example.com'), isNull);
    });

    test('clamps very long titles to 2000 chars', () async {
      final longTitle = 'A' * 5000;
      final fetcher = TitleFetcher(
        client: _mockPage('<html><head><title>$longTitle</title></head></html>'),
      );
      final result = await fetcher.fetch('https://example.com');
      expect(result!.length, 2000);
    });

    test('truncates body to 64KB before parsing', () async {
      // Put the title after 64KB of padding — should not be found
      final padding = ' ' * 70000;
      final fetcher = TitleFetcher(client: _mockPage('$padding<title>Hidden</title>'));
      expect(await fetcher.fetch('https://example.com'), isNull);
    });

    test('stops reading the stream once 64KB have arrived', () async {
      final head = utf8.encode('<html><head><title>Early Title</title></head>');
      final padding = utf8.encode(' ' * 40000);
      final client = _ChunkedClient([head, padding, padding, padding, padding]);
      final fetcher = TitleFetcher(client: client);

      expect(await fetcher.fetch('https://example.com'), 'Early Title');
      // head + two padding chunks pass 64KB; the rest is never downloaded.
      expect(client.chunksServed, 3);
    });

    test('decodes UTF-8 by default when no charset is given', () async {
      final client = _ChunkedClient([
        utf8.encode('<html><head><title>Café ☕</title></head></html>'),
      ], headers: {'content-type': 'text/html'});
      final fetcher = TitleFetcher(client: client);
      expect(await fetcher.fetch('https://example.com'), 'Café ☕');
    });

    test('honors Content-Type charset', () async {
      final client = _ChunkedClient([
        latin1.encode('<html><head><title>Café</title></head></html>'),
      ], headers: {'content-type': 'text/html; charset=iso-8859-1'});
      final fetcher = TitleFetcher(client: client);
      expect(await fetcher.fetch('https://example.com'), 'Café');
    });

    test('survives a chunk boundary cutting a multibyte character', () async {
      final bytes = utf8.encode('<html><head><title>naïve</title></head></html>');
      // 'ï' is two bytes in UTF-8; split the response inside it.
      const splitAt = 25; // mid-title, inside the multibyte sequence region
      final client = _ChunkedClient([bytes.sublist(0, splitAt), bytes.sublist(splitAt)]);
      final fetcher = TitleFetcher(client: client);
      expect(await fetcher.fetch('https://example.com'), 'naïve');
    });

    test('og:title takes priority over twitter:title', () async {
      final fetcher = TitleFetcher(
        client: _mockPage(
          '<html><head>'
          '<meta property="og:title" content="OG Wins">'
          '<meta name="twitter:title" content="Twitter Loses">'
          '<title>Also Loses</title>'
          '</head></html>',
        ),
      );
      expect(await fetcher.fetch('https://example.com'), 'OG Wins');
    });

    test('handles single quotes in meta attributes', () async {
      final fetcher = TitleFetcher(
        client: _mockPage(
          "<html><head>"
          "<meta property='og:title' content='Single Quoted'>"
          "</head></html>",
        ),
      );
      expect(await fetcher.fetch('https://example.com'), 'Single Quoted');
    });
  });
}
