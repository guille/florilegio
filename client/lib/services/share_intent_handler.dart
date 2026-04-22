import 'dart:async';

export 'share_intent_handler_stub.dart' if (dart.library.io) 'share_intent_handler_mobile.dart';

/// Callback invoked when a URL is shared into the app.
typedef OnShareReceived = void Function(String url);

abstract class ShareIntentHandler {
  StreamSubscription<dynamic>? listen({OnShareReceived? onShare});
  void dispose();
}
