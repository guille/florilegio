import 'package:florilegio/ui/bulk_tag_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildApp({
    required Map<String, Set<String>> selectedItemTags,
    required Set<String> allLibraryTags,
  }) {
    Map<String, List<String>>? result;
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showDialog<Map<String, List<String>>>(
                context: context,
                builder: (_) => BulkTagDialog(
                  selectedItemTags: selectedItemTags,
                  allLibraryTags: allLibraryTags,
                ),
              );
            },
            child: Text(result?.toString() ?? 'open'),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(
    WidgetTester tester, {
    required Map<String, Set<String>> selectedItemTags,
    required Set<String> allLibraryTags,
  }) async {
    await tester.pumpWidget(
      buildApp(selectedItemTags: selectedItemTags, allLibraryTags: allLibraryTags),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('BulkTagDialog', () {
    testWidgets('shows active tags and suggestions', (tester) async {
      await openDialog(
        tester,
        selectedItemTags: {
          'a': {'tech'},
          'b': <String>{},
        },
        allLibraryTags: {'tech', 'news'},
      );

      // Active section: "tech" (some state since only item a has it)
      expect(find.text('Current tags'), findsOneWidget);
      // tech should appear as an InputChip
      expect(find.widgetWithText(InputChip, 'tech'), findsOneWidget);

      // Suggestions section: "news"
      expect(find.text('Add existing'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'news'), findsOneWidget);
    });

    testWidgets('tapping suggestion moves it to active', (tester) async {
      await openDialog(tester, selectedItemTags: {'a': <String>{}}, allLibraryTags: {'news'});

      // Initially news is a suggestion
      expect(find.widgetWithText(ActionChip, 'news'), findsOneWidget);

      await tester.tap(find.widgetWithText(ActionChip, 'news'));
      await tester.pumpAndSettle();

      // Now it should be an active InputChip, not an ActionChip
      expect(find.widgetWithText(InputChip, 'news'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'news'), findsNothing);
    });

    testWidgets('toggling active tag moves it back to suggestions', (tester) async {
      await openDialog(
        tester,
        selectedItemTags: {
          'a': {'tech'},
          'b': {'tech'},
        },
        allLibraryTags: {'tech'},
      );

      // tech is active (all state)
      expect(find.widgetWithText(InputChip, 'tech'), findsOneWidget);

      await tester.tap(find.widgetWithText(InputChip, 'tech'));
      await tester.pumpAndSettle();

      // Should move to suggestions
      expect(find.widgetWithText(ActionChip, 'tech'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'tech'), findsNothing);
    });

    testWidgets('adding new tag via text field', (tester) async {
      await openDialog(tester, selectedItemTags: {'a': <String>{}}, allLibraryTags: <String>{});

      await tester.enterText(find.byType(TextField), 'brand-new');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InputChip, 'brand-new'), findsOneWidget);
    });

    testWidgets('Apply button disabled when no changes', (tester) async {
      await openDialog(
        tester,
        selectedItemTags: {
          'a': {'tech'},
        },
        allLibraryTags: {'tech'},
      );

      final applyButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'));
      expect(applyButton.onPressed, isNull);
    });

    testWidgets('Apply button enabled after a change', (tester) async {
      await openDialog(tester, selectedItemTags: {'a': <String>{}}, allLibraryTags: {'news'});

      await tester.tap(find.widgetWithText(ActionChip, 'news'));
      await tester.pumpAndSettle();

      final applyButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'));
      expect(applyButton.onPressed, isNotNull);
    });

    testWidgets('Cancel returns null', (tester) async {
      Map<String, List<String>>? dialogResult = const {'sentinel': []};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  dialogResult = await showDialog<Map<String, List<String>>>(
                    context: context,
                    builder: (_) => const BulkTagDialog(
                      selectedItemTags: {
                        'a': {'tech'},
                      },
                      allLibraryTags: {'tech'},
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNull);
    });

    testWidgets('full round-trip: add suggestion, remove active, verify result', (tester) async {
      Map<String, List<String>>? dialogResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  dialogResult = await showDialog<Map<String, List<String>>>(
                    context: context,
                    builder: (_) => const BulkTagDialog(
                      selectedItemTags: {
                        'a': {'tech', 'ai'},
                        'b': {'tech'},
                      },
                      allLibraryTags: {'tech', 'ai', 'news'},
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Remove "tech" (all → remove)
      await tester.tap(find.widgetWithText(InputChip, 'tech'));
      await tester.pumpAndSettle();

      // Add "news" from suggestions
      await tester.tap(find.widgetWithText(ActionChip, 'news'));
      await tester.pumpAndSettle();

      // Apply
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // a: had {tech, ai}, remove tech, add news → {ai, news}
      // b: had {tech}, remove tech, add news → {news}
      expect(dialogResult, isNotNull);
      expect(dialogResult!['a'], ['ai', 'news']);
      expect(dialogResult!['b'], ['news']);
    });
  });
}
