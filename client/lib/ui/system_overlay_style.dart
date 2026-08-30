import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Status and navigation bar styling for a surface of the given [brightness].
///
/// AppBar's computed default omits the navigation bar fields, and the engine
/// skips every nav bar call when they're null, so without these the bar keeps
/// an unclaimed platform default that follows no theme at all. Under the
/// mandatory edge-to-edge of targetSdk 36, colour is a no-op; dropping the
/// contrast scrim is what lets the bar blend into the app.
SystemUiOverlayStyle systemOverlayStyleFor(Brightness brightness) {
  final iconBrightness = brightness == Brightness.dark ? Brightness.light : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: brightness,
    statusBarIconBrightness: iconBrightness,
    systemNavigationBarIconBrightness: iconBrightness,
    systemNavigationBarContrastEnforced: false,
  );
}
