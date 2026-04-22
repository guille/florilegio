import 'dart:async';

import 'package:florilegio/domain/url_parser.dart';
import 'package:florilegio/services/share_intent_handler.dart';
import 'package:flutter/services.dart';

/// Creates the mobile share intent handler.
ShareIntentHandler createShareIntentHandler() => _MobileHandler();

class _MobileHandler implements ShareIntentHandler {
  static const _channel = MethodChannel('com.mongui.florilegio/share');
  bool _listening = false;

  @override
  StreamSubscription<dynamic>? listen({OnShareReceived? onShare}) {
    if (_listening) return null;
    _listening = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedText') {
        final text = call.arguments as String?;
        _handleText(text, onShare);
      }
    });

    _channel
        .invokeMethod<String>('getSharedText')
        .then((text) => _handleText(text, onShare))
        .catchError((_) {});

    return null;
  }

  void _handleText(String? text, OnShareReceived? onShare) {
    if (text == null || text.isEmpty) return;
    final url = extractUrl(text);
    if (url != null && onShare != null) {
      onShare(url);
    }
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    _listening = false;
  }
}
