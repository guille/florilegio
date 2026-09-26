import 'package:florilegio/domain/url_parser.dart';
import 'package:flutter/services.dart';

/// Delivers URLs shared into the app from Android's share sheet.
class ShareIntentHandler {
  static const _channel = MethodChannel('com.mongui.florilegio/share');
  bool _listening = false;

  void listen(void Function(String url) onShare) {
    if (_listening) return;
    _listening = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedText') _handleText(call.arguments as String?, onShare);
    });

    _channel
        .invokeMethod<String>('getSharedText')
        .then((text) => _handleText(text, onShare))
        .catchError((_) {});
  }

  void _handleText(String? text, void Function(String url) onShare) {
    if (text == null || text.isEmpty) return;
    final url = extractUrl(text);
    if (url != null) onShare(url);
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _listening = false;
  }
}
