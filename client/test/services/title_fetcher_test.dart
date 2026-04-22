// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'package:florilegio/services/title_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

http_testing.MockClient _mockPage(String body, {int status = 200}) =>
    http_testing.MockClient((_) async => http.Response(body, status));

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
