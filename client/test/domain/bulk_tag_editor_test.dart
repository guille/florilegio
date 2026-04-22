import 'package:florilegio/domain/bulk_tag_editor.dart';
import 'package:flutter_test/flutter_test.dart';

// ignore_for_file: cascade_invocations

void main() {
  group('BulkTagEditor', () {
    group('initialization', () {
      test('tags on all items start as TagState.all', () {
        final editor = BulkTagEditor.fromSelection(
          selectedItemTags: {
            'a': {'tech', 'ai'},
            'b': {'tech', 'ai'},
          },
          allLibraryTags: {'tech', 'ai', 'news'},
        );

        expect(editor.activeTags['tech'], TagState.all);
        expect(editor.activeTags['ai'], TagState.all);
      });

      test('tags on some items start as TagState.some', () {
        final editor = BulkTagEditor.fromSelection(
          selectedItemTags: {
            'a': {'tech', 'ai'},
            'b': {'tech'},
          },
          allLibraryTags: {'tech', 'ai'},
        );

        expect(editor.activeTags['tech'], TagState.all);
        expect(editor.activeTags['ai'], TagState.some);
      });

      test('library tags not on any selected item are suggestions', () {
        final editor = BulkTagEditor.fromSelection(
          selectedItemTags: {
            'a': {'tech'},
          },
          allLibraryTags: {'tech', 'ai', 'news'},
        );

        expect(editor.suggestions, {'ai', 'news'});
        expect(editor.activeTags.containsKey('ai'), isFalse);
      });

      test('no suggestions when all library tags are on selected items', () {
        final editor = BulkTagEditor.fromSelection(
          selectedItemTags: {
            'a': {'tech', 'ai'},
          },
          allLibraryTags: {'tech', 'ai'},
        );

        expect(editor.suggestions, isEmpty);
      });

      test('empty tags on selected items means all library tags are suggestions', () {
        final editor = BulkTagEditor.fromSelection(
          selectedItemTags: {'a': <String>{}, 'b': <String>{}},
          allLibraryTags: {'tech', 'ai'},
        );

        expect(editor.activeTags, isEmpty);
        expect(editor.suggestions, {'tech', 'ai'});
      });
    });

    group('toggleActive', () {
      test('toggling TagState.some promotes to all (add action)', () {
        final editor = BulkTagEditor.fromSelection(
          selectedItemTags: {
            'a': {'tech'},
            'b': <String>{},
          },
          allLibraryTags: {'tech'},
        );

        expect(editor.activeTags['tech'], TagState.some);
        editor.toggleActive('tech');
        expect(editor.activeTags['tech'], TagState.all);
        expect(editor.actions['tech'], TagAction.add);
      });

      test('toggling TagState.all removes it and moves to suggestions', () {
        final editor = BulkTagEditor.fromSelection(
          selectedItemTags: {
            'a': {'tech'},
            'b': {'tech'},
          },
          allLibraryTags: {'tech'},
        );

        expect(editor.activeTags['tech'], TagState.all);
        editor.toggleActive('tech');
        expect(editor.activeTags.containsKey('tech'), isFalse);
        expect(editor.suggestions.contains('tech'), isTrue);
        expect(editor.actions['tech'], TagAction.remove);
      });

      test('toggling a promoted suggestion (add) removes it back to suggestions', () {
        final editor = BulkTagEditor.fromSelection(
          selectedItemTags: {'a': <String>{}},
          allLibraryTags: {'tech'},
        );

        editor.addFromSuggestion('tech');
        expect(editor.activeTags['tech'], TagState.all);
        expect(editor.suggestions.contains('tech'), isFalse);

        editor.toggleActive('tech');
        expect(editor.activeTags.containsKey('tech'), isFalse);
        expect(editor.suggestions.contains('tech'), isTrue);
        expect(editor.actions['tech'], TagAction.remove);
      });

      test('toggling non-existent tag is a no-op', () {
        final editor = BulkTagEditor.fromSelection(
          selectedItemTags: {
            'a': {'tech'},
          },
          allLibraryTags: {'tech'},
        );

        editor.toggleActive('nonexistent');
        expect(editor.activeTags.length, 1);
        expect(editor.actions, isEmpty);
      });
    });

    group('addFromSuggestion', () {
      test('moves tag from suggestions to active as all', () {
        final editor = BulkTagEditor.fromSelection(
          selectedItemTags: {'a': <String>{}},
          allLibraryTags: {'news'},
        );

        editor.addFromSuggestion('news');
        expect(editor.activeTags['news'], TagState.all);
        expect(editor.suggestions.contains('news'), isFalse);
        expect(editor.actions['news'], TagAction.add);
      });

      test('adding non-suggestion is a no-op', () {
        final editor = BulkTagEditor.fromSelection(
          selectedItemTags: {
            'a': {'tech'},
          },
          allLibraryTags: {'tech'},
        );

        editor.addFromSuggestion('tech'); // already active, not a suggestion
        expect(editor.actions, isEmpty);
      });

      test('round-trip: add from suggestion, toggle to remove, back to suggestion', () {
        final editor = BulkTagEditor.fromSelection(
          selectedItemTags: {'a': <String>{}},
          allLibraryTags: {'news'},
        );

        // Add from suggestion
        editor.addFromSuggestion('news');
        expect(editor.activeTags['news'], TagState.all);
        expect(editor.suggestions, isEmpty);

        // Toggle removes it back
        editor.toggleActive('news');
        expect(editor.activeTags.containsKey('news'), isFalse);
        expect(editor.suggestions.contains('news'), isTrue);
      });
    });

    group('addNewTag', () {
      test('adds brand-new tag to active', () {
        final editor = BulkTagEditor.fromSelection(
          selectedItemTags: {'a': <String>{}},
          allLibraryTags: <String>{},
        );

        expect(editor.addNewTag('brand-new'), isTrue);
        expect(editor.activeTags['brand-new'], TagState.all);
        expect(editor.actions['brand-new'], TagAction.add);
      });

      test('returns false if tag already active', () {
        final editor = BulkTagEditor.fromSelection(
          selectedItemTags: {
            'a': {'tech'},
          },
          allLibraryTags: {'tech'},
        );

        expect(editor.addNewTag('tech'), isFalse);
      });

      test('returns false if tag is in suggestions', () {
        final editor = BulkTagEditor.fromSelection(
          selectedItemTags: {'a': <String>{}},
          allLibraryTags: {'news'},
        );

        expect(editor.addNewTag('news'), isFalse);
      });
    });

    group('computeResults', () {
      test('no actions means original tags are preserved', () {
        final editor = BulkTagEditor.fromSelection(
          selectedItemTags: {
            'a': {'tech', 'ai'},
            'b': {'tech'},
          },
          allLibraryTags: {'tech', 'ai'},
        );

        final results = editor.computeResults();
        expect(results['a'], ['ai', 'tech']);
        expect(results['b'], ['tech']);
      });

      test('add action adds tag to items that lack it', () {
        final editor = BulkTagEditor.fromSelection(
          selectedItemTags: {
            'a': {'tech'},
            'b': <String>{},
          },
          allLibraryTags: {'tech', 'news'},
        );

        editor.addFromSuggestion('news');
        final results = editor.computeResults();
        expect(results['a'], ['news', 'tech']);
        expect(results['b'], ['news']);
      });

      test('remove action removes tag from items that have it', () {
        final editor = BulkTagEditor.fromSelection(
          selectedItemTags: {
            'a': {'tech', 'ai'},
            'b': {'tech'},
          },
          allLibraryTags: {'tech', 'ai'},
        );

        editor.toggleActive('tech'); // remove from all
        final results = editor.computeResults();
        expect(results['a'], ['ai']);
        expect(results['b'], <String>[]);
      });

      test('mixed add and remove actions', () {
        final editor = BulkTagEditor.fromSelection(
          selectedItemTags: {
            'a': {'tech', 'ai'},
            'b': {'tech'},
          },
          allLibraryTags: {'tech', 'ai', 'news'},
        );

        editor.toggleActive('tech'); // remove
        editor.addFromSuggestion('news'); // add
        editor.toggleActive('ai'); // some → add to all

        final results = editor.computeResults();
        expect(results['a'], ['ai', 'news']); // tech removed, news added, ai kept
        expect(results['b'], ['ai', 'news']); // tech removed, news added, ai added
      });

      test('add is idempotent for items that already have the tag', () {
        final editor = BulkTagEditor.fromSelection(
          selectedItemTags: {
            'a': {'tech', 'ai'},
            'b': {'tech'},
          },
          allLibraryTags: {'tech', 'ai'},
        );

        editor.toggleActive('ai'); // some → all (add)
        final results = editor.computeResults();
        expect(results['a'], ['ai', 'tech']); // already had ai, no dup
        expect(results['b'], ['ai', 'tech']); // ai added
      });
    });

    group('hasChanges', () {
      test('false initially', () {
        final editor = BulkTagEditor.fromSelection(
          selectedItemTags: {
            'a': {'tech'},
          },
          allLibraryTags: {'tech'},
        );
        expect(editor.hasChanges, isFalse);
      });

      test('true after any action', () {
        final editor = BulkTagEditor.fromSelection(
          selectedItemTags: {
            'a': {'tech'},
          },
          allLibraryTags: {'tech', 'news'},
        );
        editor.addFromSuggestion('news');
        expect(editor.hasChanges, isTrue);
      });
    });

    group('full workflow scenarios', () {
      test('user scenario: select items with no tags, add from suggestions', () {
        // Item 1 has tags "ai" and "tech", items 2 and 3 have no tags.
        // User selects items 2 and 3, taps "ai" from suggestions.
        final editor = BulkTagEditor.fromSelection(
          selectedItemTags: {'item2': <String>{}, 'item3': <String>{}},
          allLibraryTags: {'ai', 'tech'},
        );

        expect(editor.activeTags, isEmpty);
        expect(editor.suggestions, {'ai', 'tech'});

        editor.addFromSuggestion('ai');
        expect(editor.activeTags['ai'], TagState.all);
        expect(editor.suggestions, {'tech'});

        final results = editor.computeResults();
        expect(results['item2'], ['ai']);
        expect(results['item3'], ['ai']);
      });

      test('user scenario: partial tags, promote some, remove others', () {
        final editor = BulkTagEditor.fromSelection(
          selectedItemTags: {
            'a': {'tech', 'ai', 'old'},
            'b': {'tech', 'news'},
            'c': {'tech'},
          },
          allLibraryTags: {'tech', 'ai', 'old', 'news', 'archive'},
        );

        // tech: all, ai: some, old: some, news: some
        expect(editor.activeTags['tech'], TagState.all);
        expect(editor.activeTags['ai'], TagState.some);
        expect(editor.activeTags['old'], TagState.some);
        expect(editor.activeTags['news'], TagState.some);
        expect(editor.suggestions, {'archive'});

        // Promote ai to all
        editor.toggleActive('ai');
        // Remove old
        editor.toggleActive('old'); // some → all first
        expect(editor.activeTags['old'], TagState.all);
        editor.toggleActive('old'); // all → remove
        // Remove tech
        editor.toggleActive('tech');
        // Add archive from suggestions
        editor.addFromSuggestion('archive');

        final results = editor.computeResults();
        // a: had tech,ai,old → remove tech, add ai(noop), remove old, add archive = ai, archive, news? no.
        // Let's trace: a had {tech, ai, old}. Actions: ai=add, old=remove, tech=remove, archive=add
        // Result: ai + archive + (news not on a) = {ai, archive}
        expect(results['a'], ['ai', 'archive']);
        // b: had {tech, news}. Actions: ai=add, old=remove(noop), tech=remove, archive=add
        // Result: news + ai + archive = {ai, archive, news}
        expect(results['b'], ['ai', 'archive', 'news']);
        // c: had {tech}. Actions: ai=add, old=remove(noop), tech=remove, archive=add
        // Result: ai + archive = {ai, archive}
        expect(results['c'], ['ai', 'archive']);
      });
    });
  });
}
