import 'dart:convert';

import 'package:florilegio/data/api_client.dart';
import 'package:florilegio/data/in_memory_repository.dart';
import 'package:florilegio/domain/bookmark.dart';
import 'package:florilegio/services/sync_service.dart';
import 'package:florilegio/ui/bookmark_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

void main() {
  late InMemoryBookmarkRepository repo;
  late SyncService syncService;
  late bool settingsTapped;

  final now = DateTime.utc(2024, 6, 1);

  final sampleBookmarks = [
    Bookmark(
      id: '1',
      url: 'https://flutter.dev',
      title: 'Flutter',
      tags: ['dev', 'mobile'],
      createdAt: DateTime(2024, 6, 1),
      updatedAt: now,
    ),
    Bookmark(
      id: '2',
      url: 'https://dart.dev',
      title: 'Dart Language',
      tags: ['dev'],
      createdAt: DateTime(2024, 5, 1),
      updatedAt: now,
    ),
    Bookmark(
      id: '3',
      url: 'https://example.com/article',
      title: 'Interesting Article',
      tags: ['read-later'],
      createdAt: DateTime(2024, 4, 1),
      updatedAt: now,
    ),
  ];

  /// Convert bookmarks to API-style JSON for mock responses.
  Map<String, dynamic> toApiJson(Bookmark b) => {
    'id': b.id,
    'url': b.url,
    'title': b.title,
    'tags': b.tags.join(','),
    'created_at': b.createdAt.toIso8601String(),
    'updated_at': b.updatedAt.toIso8601String(),
  };

  List<Map<String, dynamic>> sampleJson() => sampleBookmarks.map(toApiJson).toList();

  SyncService makeSyncService(http.Client client) {
    final api = BookmarkApiClient(baseUrl: 'https://api.test', token: 'tok', client: client);
    return SyncService(repository: repo, apiClient: api);
  }

  setUp(() {
    repo = InMemoryBookmarkRepository();
    settingsTapped = false;
    final client = http_testing.MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response(jsonEncode(sampleJson()), 200);
      }
      if (request.method == 'PATCH') {
        final id = request.url.pathSegments.last;
        final original = sampleBookmarks.firstWhere((b) => b.id == id);
        return http.Response(jsonEncode(toApiJson(original)), 200);
      }
      if (request.method == 'POST') {
        // Handle create
        return http.Response(
          jsonEncode({
            'id': '99',
            'url': 'https://new-bookmark.com',
            'title': 'New Bookmark',
            'tags': null,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          }),
          201,
        );
      }
      if (request.method == 'DELETE') {
        return http.Response('', 204);
      }
      return http.Response('Not found', 404);
    });
    syncService = makeSyncService(client);
  });

  Widget buildWidget({SyncService? overrideSyncService}) => MaterialApp(
    home: BookmarkListView(
      repository: repo,
      syncService: overrideSyncService ?? syncService,
      onSettingsTap: () => settingsTapped = true,
    ),
  );

  group('BookmarkListView', () {
    testWidgets('shows bookmarks after sync', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      expect(find.text('Flutter'), findsOneWidget);
      expect(find.text('Dart Language'), findsOneWidget);
      expect(find.text('Interesting Article'), findsOneWidget);
    });

    testWidgets('shows sync success banner', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      expect(find.textContaining('Synced'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    });

    testWidgets('shows sync failure banner with retry', (tester) async {
      final failClient = http_testing.MockClient((request) async => http.Response('error', 500));
      final failSync = makeSyncService(failClient);

      await tester.pumpWidget(buildWidget(overrideSyncService: failSync));
      await tester.pumpAndSettle();

      expect(find.textContaining('Sync failed'), findsOneWidget);
      expect(find.text('RETRY'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    });

    testWidgets('settings button calls callback', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      expect(settingsTapped, true);
    });

    testWidgets('search toggles and filters', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'Dart');
      await tester.pumpAndSettle();

      expect(find.text('Dart Language'), findsOneWidget);
      expect(find.text('Flutter'), findsNothing);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Flutter'), findsOneWidget);
      expect(find.text('Dart Language'), findsOneWidget);
    });

    testWidgets('tag filter chips appear and filter', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilterChip, 'dev'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'read-later'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'read-later'));
      await tester.pumpAndSettle();

      expect(find.text('Interesting Article'), findsOneWidget);
      expect(find.text('Flutter'), findsNothing);
    });

    testWidgets('empty state shows when no bookmarks', (tester) async {
      final emptyClient = http_testing.MockClient(
        (request) async => http.Response(jsonEncode([]), 200),
      );
      final emptySync = makeSyncService(emptyClient);

      await tester.pumpWidget(buildWidget(overrideSyncService: emptySync));
      await tester.pumpAndSettle();

      expect(find.text('No bookmarks yet'), findsOneWidget);
    });

    testWidgets('delete shows confirmation dialog', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      final menuButtons = find.byType(PopupMenuButton<String>);
      await tester.tap(menuButtons.first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete bookmark?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Flutter'), findsOneWidget);
    });

    testWidgets('delete confirmation actually deletes', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      final menuButtons = find.byType(PopupMenuButton<String>);
      await tester.tap(menuButtons.first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Bookmark deleted'), findsOneWidget);
    });

    testWidgets('popup menu shows Edit and Copy URL', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      final menuButtons = find.byType(PopupMenuButton<String>);
      await tester.tap(menuButtons.first);
      await tester.pumpAndSettle();

      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Copy URL'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('edit dialog appears', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      final menuButtons = find.byType(PopupMenuButton<String>);
      await tester.tap(menuButtons.first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Bookmark'), findsOneWidget);
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Add tag'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('bookmark with empty title displays URL as fallback', (tester) async {
      // Pre-seed a bookmark with empty-string title before sync
      await repo.upsert(
        Bookmark(
          id: '1',
          url: 'https://flutter.dev',
          title: '',
          tags: ['dev', 'mobile'],
          createdAt: DateTime(2024, 6, 1),
          updatedAt: DateTime.utc(2024, 6, 1),
        ),
      );

      // Use a failing sync so it doesn't overwrite our empty-title bookmark
      final failClient = http_testing.MockClient((request) async => http.Response('error', 500));
      final failSync = makeSyncService(failClient);

      await tester.pumpWidget(buildWidget(overrideSyncService: failSync));
      await tester.pumpAndSettle();

      // Should show the URL as display text, not empty string
      expect(find.text('https://flutter.dev'), findsOneWidget);
    });

    testWidgets('sort menu works', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.sort));
      await tester.pumpAndSettle();

      expect(find.text('Newest first'), findsOneWidget);
      expect(find.text('Oldest first'), findsOneWidget);

      await tester.tap(find.text('Oldest first'));
      await tester.pumpAndSettle();

      expect(find.text('Flutter'), findsOneWidget);
      expect(find.text('Interesting Article'), findsOneWidget);
    });

    testWidgets('FAB shows add bookmark dialog', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Add Bookmark'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'URL'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('back button closes search instead of popping route', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      // Open search
      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();

      // Verify search is open
      expect(find.byType(TextField), findsOneWidget);

      // Simulate system back button
      final WidgetsBinding widgetsBinding = tester.binding;
      // ignore: invalid_use_of_protected_member
      await widgetsBinding.handlePopRoute();
      await tester.pumpAndSettle();

      // Search should be closed, but the page should still be there
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Florilegio'), findsOneWidget);
    });

    testWidgets('back button clears search query when closing search', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      // Open search and enter a query
      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'Dart');
      await tester.pumpAndSettle();

      // Only Dart Language should be visible
      expect(find.text('Flutter'), findsNothing);

      // Simulate back button
      final WidgetsBinding widgetsBinding = tester.binding;
      // ignore: invalid_use_of_protected_member
      await widgetsBinding.handlePopRoute();
      await tester.pumpAndSettle();

      // All bookmarks should be visible again (query cleared)
      expect(find.text('Flutter'), findsOneWidget);
      expect(find.text('Dart Language'), findsOneWidget);
    });

    testWidgets('list has bottom padding so last item is not obscured by FAB', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      const expectedPadding = kFloatingActionButtonMargin + kFabHeight;
      final sliverPadding = find.byWidgetPredicate(
        (widget) =>
            widget is SliverPadding && (widget.padding as EdgeInsets).bottom >= expectedPadding,
      );
      expect(sliverPadding, findsOneWidget);
    });

    testWidgets('sort menu shows Random option and selects it', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.sort));
      await tester.pumpAndSettle();

      expect(find.text('Random'), findsOneWidget);

      await tester.tap(find.text('Random'));
      await tester.pumpAndSettle();

      // All bookmarks should still be visible (just reordered)
      expect(find.text('Flutter'), findsOneWidget);
      expect(find.text('Dart Language'), findsOneWidget);
      expect(find.text('Interesting Article'), findsOneWidget);
    });

    testWidgets('tapping logo shows stats dialog', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Florilegio'));
      await tester.pumpAndSettle();

      expect(find.text('Stats'), findsOneWidget);
      expect(find.text('You have read 0 items.'), findsOneWidget);
    });

    testWidgets('stats dialog shows correct count after delete', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Delete a bookmark
      final menuButtons = find.byType(PopupMenuButton<String>);
      await tester.tap(menuButtons.first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      // Open stats
      await tester.tap(find.text('Florilegio'));
      await tester.pumpAndSettle();

      expect(find.text('You have read 1 item.'), findsOneWidget);
    });

    testWidgets('stats dialog reset button resets counter', (tester) async {
      // Pre-increment the counter
      await repo.incrementDeleteCount(5);

      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Florilegio'));
      await tester.pumpAndSettle();

      expect(find.text('You have read 5 items.'), findsOneWidget);

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      // Dialog should be closed
      expect(find.text('Stats'), findsNothing);

      // Reopen to verify reset
      await tester.tap(find.text('Florilegio'));
      await tester.pumpAndSettle();

      expect(find.text('You have read 0 items.'), findsOneWidget);
    });

    testWidgets('logo is not tappable during search', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Open search
      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();

      // Logo text should not be visible
      expect(find.text('Florilegio'), findsNothing);

      // Stats dialog should not appear
      expect(find.text('Stats'), findsNothing);
    });

    testWidgets('sort menu shows By host option', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.sort));
      await tester.pumpAndSettle();

      expect(find.text('By host'), findsOneWidget);

      await tester.tap(find.text('By host'));
      await tester.pumpAndSettle();

      // All bookmarks should still be visible
      expect(find.text('Flutter'), findsOneWidget);
      expect(find.text('Dart Language'), findsOneWidget);
      expect(find.text('Interesting Article'), findsOneWidget);
    });

    testWidgets('FAB add bookmark saves and refreshes list', (tester) async {
      final postClient = http_testing.MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(jsonEncode(sampleJson()), 200);
        }
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode({
              'id': '99',
              'url': 'https://new-bookmark.com',
              'title': 'New Bookmark',
              'tags': null,
              'created_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
              'is_read': 0,
            }),
            201,
          );
        }
        return http.Response('Not found', 404);
      });
      final postSyncService = makeSyncService(postClient);

      await tester.pumpWidget(buildWidget(overrideSyncService: postSyncService));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'URL'), 'https://new-bookmark.com');
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 4));

      expect(find.text('Bookmark saved'), findsOneWidget);
    });

    testWidgets('has an interactive scrollbar for fast scrolling', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
      expect(scrollbar.interactive, isTrue);
    });

    testWidgets('long press enters selection mode', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Flutter'));
      await tester.pumpAndSettle();

      // Should show selection app bar with count
      expect(find.text('1 selected'), findsOneWidget);
      // Should show the tag edit button
      expect(find.byIcon(Icons.label), findsOneWidget);
    });

    testWidgets('Select menu item enters selection mode', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      // Open popup menu on first card
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('selection mode hides FAB and shows cancel', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      // FAB is visible initially
      expect(find.byType(FloatingActionButton), findsOneWidget);

      await tester.longPress(find.text('Flutter'));
      await tester.pumpAndSettle();

      // FAB hidden
      expect(find.byType(FloatingActionButton), findsNothing);
      // Cancel button (close icon in app bar)
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('cancel clears selection mode', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Flutter'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Back to normal
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('1 selected'), findsNothing);
    });

    testWidgets('bulk tag dialog opens and applies changes', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      // Select two items
      await tester.longPress(find.text('Flutter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dart Language'));
      await tester.pumpAndSettle();

      expect(find.text('2 selected'), findsOneWidget);

      // Tap tag edit button
      await tester.tap(find.byIcon(Icons.label));
      await tester.pumpAndSettle();

      // Bulk tag dialog should appear
      expect(find.text('Edit tags (2 items)'), findsOneWidget);

      // Both items have 'dev' tag, so it should be in active area
      expect(find.widgetWithText(InputChip, 'dev'), findsOneWidget);
      // 'mobile' is only on item 1 (some state)
      expect(find.widgetWithText(InputChip, 'mobile'), findsOneWidget);
      // 'read-later' is a suggestion (from item 3 which isn't selected)
      expect(find.widgetWithText(ActionChip, 'read-later'), findsOneWidget);

      // Add 'read-later' from suggestions
      await tester.tap(find.widgetWithText(ActionChip, 'read-later'));
      await tester.pumpAndSettle();

      // Apply
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // Selection should be cleared
      expect(find.text('2 selected'), findsNothing);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });
}
