import 'package:florilegio/domain/url_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractUrl', () {
    test('extracts bare URL', () {
      expect(extractUrl('https://example.com/page'), 'https://example.com/page');
    });

    test('extracts URL from rich text', () {
      expect(
        extractUrl('Check this out: https://example.com/article some more text'),
        'https://example.com/article',
      );
    });

    test('extracts URL with query params', () {
      expect(
        extractUrl('Visit https://example.com/search?q=flutter&lang=en now'),
        'https://example.com/search?q=flutter&lang=en',
      );
    });

    test('extracts http URL', () {
      expect(extractUrl('http://example.com'), 'http://example.com');
    });

    test('returns null for no URL', () {
      expect(extractUrl('no url here'), isNull);
    });

    test('extracts first URL from multiple', () {
      expect(extractUrl('https://first.com and https://second.com'), 'https://first.com');
    });

    test('handles URL in quotes', () {
      expect(extractUrl('"https://example.com/page"'), 'https://example.com/page');
    });

    test('strips trailing punctuation', () {
      expect(extractUrl('Check https://example.com/page.'), 'https://example.com/page');
      expect(extractUrl('See https://example.com/page, and more'), 'https://example.com/page');
    });
  });
}
