import 'dart:async';

import 'package:florilegio/services/share_intent_handler.dart';

ShareIntentHandler createShareIntentHandler() => _NoOpHandler();

class _NoOpHandler implements ShareIntentHandler {
  @override
  StreamSubscription<dynamic>? listen({OnShareReceived? onShare}) => null;

  @override
  void dispose() {}
}
