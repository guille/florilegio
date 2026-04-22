import 'package:florilegio/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SettingsService', () {
    test('returns empty strings when nothing is set', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService.forTest(prefs);

      expect(settings.baseUrl, '');
      expect(settings.token, '');
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.isConfigured, false);
    });

    test('persists and retrieves baseUrl', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService.forTest(prefs);

      await settings.setBaseUrl('https://api.test');
      expect(settings.baseUrl, 'https://api.test');
    });

    test('persists and retrieves token', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService.forTest(prefs);

      await settings.setToken('my-token');
      expect(settings.token, 'my-token');
    });

    test('isConfigured is true when both are set', () async {
      SharedPreferences.setMockInitialValues({
        'base_url': 'https://api.test',
        'bearer_token': 'tok',
      });
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService.forTest(prefs);

      expect(settings.isConfigured, true);
    });

    test('isConfigured is false when only baseUrl is set', () async {
      SharedPreferences.setMockInitialValues({'base_url': 'https://api.test'});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService.forTest(prefs);

      expect(settings.isConfigured, false);
    });

    test('theme mode roundtrips', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService.forTest(prefs);

      await settings.setThemeMode(ThemeMode.dark);
      expect(settings.themeMode, ThemeMode.dark);

      await settings.setThemeMode(ThemeMode.light);
      expect(settings.themeMode, ThemeMode.light);

      await settings.setThemeMode(ThemeMode.system);
      expect(settings.themeMode, ThemeMode.system);
    });

    test('notifies listeners on changes', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService.forTest(prefs);

      var notifyCount = 0;
      settings.addListener(() => notifyCount++);

      await settings.setBaseUrl('url');
      await settings.setToken('tok');
      await settings.setThemeMode(ThemeMode.dark);

      expect(notifyCount, 3);
    });
  });
}
