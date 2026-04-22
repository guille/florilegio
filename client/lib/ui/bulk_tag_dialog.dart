import 'package:florilegio/domain/bulk_tag_editor.dart';
import 'package:flutter/material.dart';

/// A self-contained dialog for bulk-editing tags across multiple items.
///
/// This widget manages its own [BulkTagEditor] state and returns the computed
/// results (item id → new tag list) when the user confirms, or null on cancel.
///
/// Usage:
/// ```dart
/// final results = await showDialog<Map<String, List<String>>>(
///   context: context,
///   builder: (_) => BulkTagDialog(
///     selectedItemTags: {'id1': {'a', 'b'}, 'id2': {'a'}},
///     allLibraryTags: {'a', 'b', 'c'},
///   ),
/// );
/// ```
class BulkTagDialog extends StatefulWidget {
  /// Maps item id → set of current tags for that item.
  final Map<String, Set<String>> selectedItemTags;

  /// All tags that exist in the library.
  final Set<String> allLibraryTags;

  const BulkTagDialog({super.key, required this.selectedItemTags, required this.allLibraryTags});

  @override
  State<BulkTagDialog> createState() => _BulkTagDialogState();
}

class _BulkTagDialogState extends State<BulkTagDialog> {
  late final BulkTagEditor _editor;
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _editor = BulkTagEditor.fromSelection(
      selectedItemTags: widget.selectedItemTags,
      allLibraryTags: widget.allLibraryTags,
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _submitNewTag() {
    final tag = _textController.text.trim().toLowerCase();
    if (tag.isEmpty) return;

    setState(() {
      // Try adding as new; if it's in suggestions, add from there instead.
      if (_editor.suggestions.contains(tag)) {
        _editor.addFromSuggestion(tag);
      } else {
        _editor.addNewTag(tag);
      }
    });
    _textController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeTags = _editor.activeTags;
    final suggestions = _editor.suggestions.toList()..sort();
    final sortedActive = activeTags.keys.toList()..sort();

    return AlertDialog(
      title: Text('Edit tags (${widget.selectedItemTags.length} items)'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Active tags section
              if (sortedActive.isNotEmpty) ...[
                Text('Current tags', style: theme.textTheme.labelSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in sortedActive)
                      _TagChip(
                        tag: tag,
                        state: activeTags[tag]!,
                        onTap: () => setState(() => _editor.toggleActive(tag)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Suggestions section
              if (suggestions.isNotEmpty) ...[
                Text('Add existing', style: theme.textTheme.labelSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in suggestions)
                      ActionChip(
                        label: Text(tag),
                        onPressed: () => setState(() => _editor.addFromSuggestion(tag)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // New tag input
              TextField(
                controller: _textController,
                decoration: InputDecoration(
                  labelText: 'New tag',
                  hintText: 'Type and press enter',
                  isDense: true,
                  suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: _submitNewTag),
                ),
                onSubmitted: (_) => _submitNewTag(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Cancel')),
        FilledButton(
          onPressed: _editor.hasChanges
              ? () => Navigator.of(context).pop(_editor.computeResults())
              : null,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

/// A chip representing a tag in one of three states.
class _TagChip extends StatelessWidget {
  final String tag;
  final TagState state;
  final VoidCallback onTap;

  const _TagChip({required this.tag, required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    IconData icon;
    Color? backgroundColor;

    switch (state) {
      case TagState.all:
        icon = Icons.check;
        backgroundColor = theme.colorScheme.primaryContainer;
      case TagState.some:
        icon = Icons.remove;
        backgroundColor = theme.colorScheme.surfaceContainerHighest;
      case TagState.none:
        icon = Icons.add;
        backgroundColor = null;
    }

    return InputChip(
      label: Text(tag),
      avatar: Icon(icon, size: 18),
      backgroundColor: backgroundColor,
      selected: state == TagState.all,
      showCheckmark: false,
      onPressed: onTap,
    );
  }
}
