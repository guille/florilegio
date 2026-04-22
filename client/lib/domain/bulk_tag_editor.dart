/// Represents the state of a tag across multiple items.
enum TagState {
  /// Tag is present on ALL selected items.
  all,

  /// Tag is present on SOME (but not all) selected items.
  some,

  /// Tag is not present on any selected item but exists in the library.
  /// Used for the suggestions layer.
  none,
}

/// Represents an action to apply to a tag when committing changes.
enum TagAction {
  /// Add this tag to all selected items (noop for items that already have it).
  add,

  /// Remove this tag from all selected items (noop for items that don't have it).
  remove,
}

/// Pure domain class that manages tri-state tag editing for multiple items.
///
/// This class is independent of any UI framework and computes the state machine
/// for bulk tag editing: given a set of items with their tags, it tracks user
/// edits (promote from suggestions, toggle active chips) and produces per-item
/// tag diffs.
class BulkTagEditor {
  /// Tags that appear in the active editing area, mapped to their current state.
  /// Tags in state [TagState.all] will be kept on all items.
  /// Tags in state [TagState.some] represent the original indeterminate state.
  /// Tags in state [TagState.none] are not in this map (they live in suggestions).
  final Map<String, TagState> _activeTags;

  /// Tags available as suggestions (exist in library but not on any selected item).
  final Set<String> _suggestions;

  /// Explicit user actions that override the initial state.
  final Map<String, TagAction> _actions;

  /// Original tag sets per item, keyed by item id.
  final Map<String, Set<String>> _originalTags;

  BulkTagEditor._({
    required Map<String, TagState> activeTags,
    required Set<String> suggestions,
    required Map<String, Set<String>> originalTags,
  }) : _activeTags = activeTags,
       _suggestions = suggestions,
       _actions = {},
       _originalTags = originalTags;

  /// Creates a [BulkTagEditor] from the selected items' tags and all library tags.
  ///
  /// [selectedItemTags] maps item id → set of tags for that item.
  /// [allLibraryTags] is the complete set of tags across the entire library.
  factory BulkTagEditor.fromSelection({
    required Map<String, Set<String>> selectedItemTags,
    required Set<String> allLibraryTags,
  }) {
    final itemCount = selectedItemTags.length;
    assert(itemCount > 0);

    // Count how many selected items have each tag.
    final tagCounts = <String, int>{};
    for (final tags in selectedItemTags.values) {
      for (final tag in tags) {
        tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
      }
    }

    final activeTags = <String, TagState>{};
    for (final entry in tagCounts.entries) {
      activeTags[entry.key] = entry.value == itemCount ? TagState.all : TagState.some;
    }

    // Suggestions are library tags not present on any selected item.
    final suggestions = allLibraryTags.difference(tagCounts.keys.toSet());

    return BulkTagEditor._(
      activeTags: activeTags,
      suggestions: suggestions,
      originalTags: selectedItemTags,
    );
  }

  /// Current active tags and their states (includes user modifications).
  Map<String, TagState> get activeTags => Map.unmodifiable(_activeTags);

  /// Current suggestions (tags not in active area).
  Set<String> get suggestions => Set.unmodifiable(_suggestions);

  /// Current explicit actions the user has taken.
  Map<String, TagAction> get actions => Map.unmodifiable(_actions);

  /// Tap an active tag to cycle its state.
  ///
  /// - [TagState.all] → removed (action: remove, tag moves out of active)
  /// - [TagState.some] → [TagState.all] (action: add)
  ///
  /// If the tag has already been acted upon:
  /// - action [TagAction.add] (shows as all) → remove (action: remove)
  /// - action [TagAction.remove] shouldn't appear in active (guarded).
  void toggleActive(String tag) {
    final currentState = _activeTags[tag];
    if (currentState == null) return; // Not in active area.

    final existingAction = _actions[tag];

    if (existingAction == TagAction.add) {
      // User previously added it; now remove.
      _actions[tag] = TagAction.remove;
      _activeTags.remove(tag);
      // If it was originally in some/all, move back to suggestions? No —
      // it goes back to suggestions only if it was a suggestion originally.
      // If it was originally active (some/all), removing means it disappears
      // from active but we keep the remove action.
      // Actually, let's keep removed tags visible as suggestions so user can
      // re-add. But only if it existed in the library.
      _suggestions.add(tag);
    } else if (currentState == TagState.all) {
      // Originally all had it → remove from all.
      _actions[tag] = TagAction.remove;
      _activeTags.remove(tag);
      _suggestions.add(tag);
    } else if (currentState == TagState.some) {
      // Some had it → add to all.
      _actions[tag] = TagAction.add;
      _activeTags[tag] = TagState.all;
    }
  }

  /// Promote a suggestion to active (add to all selected items).
  void addFromSuggestion(String tag) {
    if (!_suggestions.contains(tag)) return;
    _suggestions.remove(tag);
    _activeTags[tag] = TagState.all;
    _actions[tag] = TagAction.add;
  }

  /// Add a brand-new tag (not in library) to all selected items.
  ///
  /// Returns false if the tag is already active or in suggestions.
  bool addNewTag(String tag) {
    if (_activeTags.containsKey(tag) || _suggestions.contains(tag)) {
      return false;
    }
    _activeTags[tag] = TagState.all;
    _actions[tag] = TagAction.add;
    return true;
  }

  /// Compute the final tag list for each item after applying all actions.
  ///
  /// Returns a map of item id → new tag list.
  Map<String, List<String>> computeResults() {
    final results = <String, List<String>>{};
    for (final entry in _originalTags.entries) {
      final itemId = entry.key;
      final original = entry.value.toSet();

      for (final actionEntry in _actions.entries) {
        final tag = actionEntry.key;
        switch (actionEntry.value) {
          case TagAction.add:
            original.add(tag);
          case TagAction.remove:
            original.remove(tag);
        }
      }

      results[itemId] = original.toList()..sort();
    }
    return results;
  }

  /// Returns true if there are any pending changes.
  bool get hasChanges => _actions.isNotEmpty;
}
