import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AndroidManifest.xml', () {
    late String manifest;

    setUpAll(() {
      manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    });

    test('contains queries for https VIEW intent (required by url_launcher)', () {
      // On Android 11+ (API 30+), url_launcher's canLaunchUrl() always
      // returns false unless the manifest declares <queries> for the
      // target intent schemes. Without these, tapping bookmarks silently
      // fails to open the browser.
      expect(manifest, contains('<action android:name="android.intent.action.VIEW"/>'));
      expect(manifest, contains('<data android:scheme="https"/>'));
    });

    test('contains queries for http VIEW intent (required by url_launcher)', () {
      expect(manifest, contains('<data android:scheme="http"/>'));
    });
  });
}
