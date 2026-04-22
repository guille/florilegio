import 'package:florilegio/services/settings_service.dart';
import 'package:florilegio/ui/settings_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SettingsView', () {
    testWidgets('shows all fields', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService.forTest(prefs);

      await tester.pumpWidget(MaterialApp(home: SettingsView(settings: settings)));

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Endpoint Base URL'), findsOneWidget);
      expect(find.text('Bearer Token'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Export Bookmarks'), findsOneWidget);
    });

    testWidgets('save button is disabled until fields change', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService.forTest(prefs);

      await tester.pumpWidget(MaterialApp(home: SettingsView(settings: settings)));

      // Save button should be disabled initially
      final saveButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));
      expect(saveButton.onPressed, isNull);

      // Type in URL field
      await tester.enterText(
        find.widgetWithText(TextField, 'Endpoint Base URL'),
        'https://api.test',
      );
      await tester.pump();

      // Save button should now be enabled
      final updatedButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));
      expect(updatedButton.onPressed, isNotNull);
    });

    testWidgets('save persists settings', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService.forTest(prefs);

      await tester.pumpWidget(MaterialApp(home: SettingsView(settings: settings)));

      await tester.enterText(
        find.widgetWithText(TextField, 'Endpoint Base URL'),
        'https://api.test',
      );
      await tester.enterText(find.widgetWithText(TextField, 'Bearer Token'), 'my-token');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(settings.baseUrl, 'https://api.test');
      expect(settings.token, 'my-token');
      expect(find.text('Settings saved'), findsOneWidget);
    });

    testWidgets('export button shows configure message when no client', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService.forTest(prefs);

      await tester.pumpWidget(MaterialApp(home: SettingsView(settings: settings)));

      await tester.tap(find.text('Export Bookmarks'));
      await tester.pumpAndSettle();

      expect(find.text('Configure settings first'), findsOneWidget);
    });
  });
}
