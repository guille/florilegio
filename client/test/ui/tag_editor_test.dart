import 'package:florilegio/ui/tag_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> lastTags;

  Widget buildWidget({List<String> tags = const [], Set<String> allTags = const {}}) {
    lastTags = [];
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TagEditor(tags: tags, allTags: allTags, onChanged: (t) => lastTags = t),
        ),
      ),
    );
  }

  group('TagEditor', () {
    testWidgets('shows current tags as InputChips', (tester) async {
      await tester.pumpWidget(buildWidget(tags: ['tech', 'ai'], allTags: {'tech', 'ai'}));

      expect(find.widgetWithText(InputChip, 'tech'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'ai'), findsOneWidget);
    });

    testWidgets('shows suggestions for tags not on item', (tester) async {
      await tester.pumpWidget(buildWidget(tags: ['tech'], allTags: {'tech', 'news', 'ai'}));

      expect(find.text('Suggestions'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'ai'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'news'), findsOneWidget);
      // 'tech' should NOT be in suggestions
      expect(find.widgetWithText(ActionChip, 'tech'), findsNothing);
    });

    testWidgets('tapping suggestion adds it', (tester) async {
      await tester.pumpWidget(buildWidget(tags: [], allTags: {'news'}));

      await tester.tap(find.widgetWithText(ActionChip, 'news'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InputChip, 'news'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'news'), findsNothing);
      expect(lastTags, ['news']);
    });

    testWidgets('deleting a chip removes tag', (tester) async {
      await tester.pumpWidget(buildWidget(tags: ['tech', 'ai'], allTags: {'tech', 'ai'}));

      // Tap the delete icon on 'tech' chip
      // InputChip delete buttons are found via the deleteIcon
      final techChip = find.widgetWithText(InputChip, 'tech');
      // Find the close icon within the tech chip's subtree
      final deleteIcon = find.descendant(of: techChip, matching: find.byIcon(Icons.close));
      await tester.tap(deleteIcon);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InputChip, 'tech'), findsNothing);
      expect(lastTags, ['ai']);
    });

    testWidgets('typing a new tag and submitting adds it', (tester) async {
      await tester.pumpWidget(buildWidget(tags: [], allTags: {}));

      await tester.enterText(find.byType(TextField), 'brand-new');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InputChip, 'brand-new'), findsOneWidget);
      expect(lastTags, ['brand-new']);
    });

    testWidgets('duplicate tag is not added', (tester) async {
      await tester.pumpWidget(buildWidget(tags: ['tech'], allTags: {'tech'}));

      await tester.enterText(find.byType(TextField), 'tech');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Still just one 'tech' chip
      expect(find.widgetWithText(InputChip, 'tech'), findsOneWidget);
    });

    testWidgets('removed tag appears in suggestions', (tester) async {
      await tester.pumpWidget(buildWidget(tags: ['tech'], allTags: {'tech', 'ai'}));

      final deleteIcon = find.descendant(
        of: find.widgetWithText(InputChip, 'tech'),
        matching: find.byIcon(Icons.close),
      );
      await tester.tap(deleteIcon);
      await tester.pumpAndSettle();

      // tech should now be in suggestions
      expect(find.widgetWithText(ActionChip, 'tech'), findsOneWidget);
    });

    testWidgets('no suggestions section when all tags are on item', (tester) async {
      await tester.pumpWidget(buildWidget(tags: ['tech', 'ai'], allTags: {'tech', 'ai'}));

      expect(find.text('Suggestions'), findsNothing);
    });
  });
}
