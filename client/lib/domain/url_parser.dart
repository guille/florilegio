/// Extracts the first URL from a string that may contain a bare URL
/// or rich text with embedded URLs.
String? extractUrl(String text) {
  final regex = RegExp(r'https?://[^\s<>\"\)\]]+', caseSensitive: false);
  final match = regex.firstMatch(text);
  if (match == null) return null;
  // Strip common trailing punctuation that's unlikely part of the URL
  var url = match.group(0)!;
  while (url.isNotEmpty && '.,:;!?'.contains(url[url.length - 1])) {
    url = url.substring(0, url.length - 1);
  }
  return url.isEmpty ? null : url;
}
