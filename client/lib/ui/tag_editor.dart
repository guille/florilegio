import 'package:flutter/material.dart';

/// A chip-based tag editor for a single item.
///
/// Displays current tags as removable chips, available suggestions as tappable
/// chips, and a text field for adding new tags. Calls [onChanged] whenever
/// the tag list changes.
class TagEditor extends StatefulWidget {
  /// The current tags on the item being edited.
  final List<String> tags;

  /// All tags in the library, used to show suggestions.
  final Set<String> allTags;

  /// Called whenever the tag list changes.
  final ValueChanged<List<String>> onChanged;

  const TagEditor({super.key, required this.tags, required this.allTags, required this.onChanged});

  @override
  State<TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<TagEditor> {
  late List<String> _tags;
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tags = List.of(widget.tags);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Set<String> get _suggestions => widget.allTags.difference(_tags.toSet());

  void _addTag(String tag) {
    tag = tag.trim().toLowerCase();
    if (tag.isEmpty || _tags.contains(tag)) return;
    setState(() => _tags.add(tag));
    widget.onChanged(List.of(_tags));
  }

  void _removeTag(String tag) {
    setState(() => _tags.remove(tag));
    widget.onChanged(List.of(_tags));
  }

  void _submitNewTag() {
    final tag = _textController.text.trim().toLowerCase();
    if (tag.isEmpty) return;
    _addTag(tag);
    _textController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestions = _suggestions.toList()..sort();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Current tags
        if (_tags.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final tag in _tags)
                InputChip(
                  label: Text(tag),
                  onDeleted: () => _removeTag(tag),
                  deleteIcon: const Icon(Icons.close, size: 16),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],

        // Suggestions
        if (suggestions.isNotEmpty) ...[
          Text('Suggestions', style: theme.textTheme.labelSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final tag in suggestions)
                ActionChip(label: Text(tag), onPressed: () => _addTag(tag)),
            ],
          ),
          const SizedBox(height: 8),
        ],

        // New tag input
        TextField(
          controller: _textController,
          decoration: InputDecoration(
            labelText: 'Add tag',
            hintText: 'Type and press enter',
            isDense: true,
            suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: _submitNewTag),
          ),
          onSubmitted: (_) => _submitNewTag(),
        ),
      ],
    );
  }
}
