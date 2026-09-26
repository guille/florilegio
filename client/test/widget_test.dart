import 'package:florilegio/services/settings_service.dart';
import 'package:florilegio/ui/settings_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/in_memory_repository.dart';

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

  group('SettingsView offline queue', () {
    Future<InMemoryBookmarkRepository> pumpWithRepo(
      WidgetTester tester, {
      int adds = 0,
      int deletes = 0,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService.forTest(prefs);

      final repo = InMemoryBookmarkRepository();
      for (var i = 0; i < adds; i++) {
        await repo.addPending('https://queued$i.com');
      }
      for (var i = 0; i < deletes; i++) {
        await repo.addPendingDelete('id-$i');
      }

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsView(settings: settings, repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('shows queued adds', (tester) async {
      await pumpWithRepo(tester, adds: 1);
      expect(find.text('Bookmarks in queue: +1'), findsOneWidget);
    });

    testWidgets('shows queued deletes', (tester) async {
      await pumpWithRepo(tester, deletes: 2);
      expect(find.text('Bookmarks in queue: -2'), findsOneWidget);
    });

    testWidgets('shows both queues', (tester) async {
      await pumpWithRepo(tester, adds: 1, deletes: 2);
      expect(find.text('Bookmarks in queue: +1 | -2'), findsOneWidget);
    });

    testWidgets('hides the line when both queues are empty', (tester) async {
      await pumpWithRepo(tester);
      expect(find.textContaining('Bookmarks in queue'), findsNothing);
    });
  });
}
