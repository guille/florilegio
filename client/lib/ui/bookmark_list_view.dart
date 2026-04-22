import 'dart:async';

import 'package:florilegio/data/api_client.dart';
import 'package:florilegio/domain/bookmark.dart';
import 'package:florilegio/domain/bookmark_repository.dart';
import 'package:florilegio/services/sync_service.dart';
import 'package:florilegio/ui/bulk_tag_dialog.dart';
import 'package:florilegio/ui/tag_editor.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Height of a standard [FloatingActionButton] (Material 3 default).
/// Flutter doesn't expose this as a public constant.
const kFabHeight = 56.0;

String _friendlyError(Object e) {
  if (e is ApiException) return e.userMessage;
  final s = e.toString();
  if (s.contains('SocketException') || s.contains('HandshakeException')) {
    return 'No internet connection';
  }
  return 'Something went wrong';
}

class BookmarkListView extends StatefulWidget {
  final BookmarkRepository repository;
  final SyncService syncService;
  final VoidCallback onSettingsTap;

  const BookmarkListView({
    super.key,
    required this.repository,
    required this.syncService,
    required this.onSettingsTap,
  });

  @override
  State<BookmarkListView> createState() => _BookmarkListViewState();
}

class _BookmarkListViewState extends State<BookmarkListView> {
  List<Bookmark> _bookmarks = [];
  bool _loading = true;
  bool _syncing = false;
  String? _syncMessage;
  bool _syncSuccess = true;
  String _query = '';
  SortOrder _sortOrder = SortOrder.newestFirst;
  bool _showSearch = false;
  String? _selectedTag;
  Timer? _bannerTimer;
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  /// IDs of bookmarks currently selected for bulk operations.
  final Set<String> _selectedIds = {};

  bool get _selectionMode => _selectedIds.isNotEmpty;

  /// All unique tags across bookmarks, for the filter chips.
  Set<String> _allTags = {};

  void _updateAllTags() {
    final tags = <String>{};
    for (final b in _bookmarks) {
      tags.addAll(b.tags);
    }
    _allTags = tags;
  }

  @override
  void initState() {
    super.initState();
    _loadAndSync();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _closeSearch() {
    setState(() {
      _showSearch = false;
      _query = '';
    });
    _loadBookmarks();
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _clearSelection() {
    setState(_selectedIds.clear);
  }

  Future<void> _showBulkTagDialog() async {
    final selectedBookmarks = _bookmarks.where((b) => _selectedIds.contains(b.id)).toList();
    if (selectedBookmarks.isEmpty) return;

    final selectedItemTags = <String, Set<String>>{
      for (final b in selectedBookmarks) b.id: b.tags.toSet(),
    };

    final result = await showDialog<Map<String, List<String>>>(
      context: context,
      builder: (_) => BulkTagDialog(selectedItemTags: selectedItemTags, allLibraryTags: _allTags),
    );

    if (result == null || !mounted) return;

    // Apply changes via N PATCH calls.
    for (final entry in result.entries) {
      await widget.syncService.updateBookmark(entry.key, tags: entry.value);
    }

    _clearSelection();
    await _loadBookmarks();
  }

  Future<void> _loadAndSync({bool force = false}) async {
    setState(() => _loading = true);
    await _loadBookmarks();
    await _sync(force: force);
  }

  Future<void> _loadBookmarks() async {
    final bookmarks = await widget.repository.getAll(
      query: _query.isEmpty ? null : _query,
      tag: _selectedTag,
      order: _sortOrder,
    );
    if (mounted) {
      setState(() {
        _bookmarks = bookmarks;
        _updateAllTags();
        _loading = false;
      });
    }
  }

  Future<void> _sync({bool force = false}) async {
    setState(() => _syncing = true);
    try {
      final result = await widget.syncService.sync(force: force);
      if (!mounted) return;
      if (result.success) {
        String msg;
        if (result.notModified) {
          msg = 'Already up to date';
          if (result.flushed > 0) {
            msg += ' (${result.flushed} queued ${result.flushed == 1 ? "item" : "items"} pushed)';
          }
        } else {
          msg = 'Synced ${result.count} bookmarks';
          if (result.flushed > 0) {
            msg += ' (${result.flushed} queued ${result.flushed == 1 ? "item" : "items"} pushed)';
          }
        }
        setState(() {
          _syncMessage = msg;
          _syncSuccess = true;
        });
        if (!result.notModified) await _loadBookmarks();
      } else {
        setState(() {
          _syncMessage = 'Sync failed: ${_friendlyError(result.exception!)}';
          _syncSuccess = false;
        });
      }
      _bannerTimer?.cancel();
      _bannerTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _syncMessage = null);
      });
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _confirmDelete(Bookmark bookmark) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete bookmark?'),
        content: Text(
          'Are you sure you want to delete "${bookmark.title?.isNotEmpty == true ? bookmark.title! : bookmark.url}"?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _deleteBookmark(bookmark);
    }
  }

  Future<void> _deleteBookmark(Bookmark bookmark) async {
    try {
      await widget.syncService.deleteBookmark(bookmark.id);
      if (!mounted) return;
      setState(() {
        _bookmarks.removeWhere((b) => b.id == bookmark.id);
        _updateAllTags();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bookmark deleted')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: ${_friendlyError(e)}')));
      }
    }
  }

  void _copyUrl(Bookmark bookmark) {
    Clipboard.setData(ClipboardData(text: bookmark.url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('URL copied to clipboard'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _showStatsDialog() async {
    final count = await widget.repository.getDeleteCount();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stats'),
        content: Text('You have read $count ${count == 1 ? "item" : "items"}.'),
        actions: [
          TextButton(
            onPressed: () async {
              await widget.repository.resetDeleteCount();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Reset'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  void _showAddDialog() {
    final urlController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Bookmark'),
        content: TextField(
          controller: urlController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'URL', hintText: 'https://example.com'),
          keyboardType: TextInputType.url,
          onSubmitted: (_) {
            Navigator.pop(ctx);
            _addBookmark(urlController.text.trim());
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _addBookmark(urlController.text.trim());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _addBookmark(String url) async {
    if (url.isEmpty) return;
    final result = await widget.syncService.saveBookmark(url);
    if (!mounted) return;
    if (result.savedRemotely) {
      await _loadBookmarks();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bookmark saved')));
    } else if (result.queuedLocally) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved locally — will sync when online')));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save: ${_friendlyError(result.error!)}')));
    }
  }

  void _showEditDialog(Bookmark bookmark) {
    final titleController = TextEditingController(text: bookmark.title ?? '');
    var tags = List<String>.from(bookmark.tags);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Bookmark'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Tags', style: Theme.of(context).textTheme.titleSmall),
                ),
                const SizedBox(height: 8),
                TagEditor(tags: tags, allTags: _allTags, onChanged: (newTags) => tags = newTags),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await widget.syncService.updateBookmark(
                  bookmark.id,
                  title: titleController.text.trim().isEmpty ? null : titleController.text.trim(),
                  tags: tags,
                );
                await _loadBookmarks();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Failed to update: ${_friendlyError(e)}')));
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_showSearch && !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_selectionMode) {
            _clearSelection();
          } else {
            _closeSearch();
          }
        }
      },
      child: Scaffold(
        appBar: _selectionMode
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cancel selection',
                  onPressed: _clearSelection,
                ),
                title: Text('${_selectedIds.length} selected'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.label),
                    tooltip: 'Edit tags',
                    onPressed: _showBulkTagDialog,
                  ),
                ],
              )
            : AppBar(
                title: _showSearch
                    ? TextField(
                        focusNode: _searchFocusNode,
                        autofocus: true,
                        style: TextStyle(color: theme.colorScheme.onSurface),
                        decoration: InputDecoration(
                          hintText: 'Search bookmarks...',
                          hintStyle: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                          border: InputBorder.none,
                        ),
                        onChanged: (val) {
                          _query = val;
                          _loadBookmarks();
                        },
                      )
                    : InkWell(
                        onTap: _showStatsDialog,
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset('assets/icon.png', width: 28, height: 28),
                            const SizedBox(width: 8),
                            const Text('Florilegio'),
                          ],
                        ),
                      ),
                actions: [
                  IconButton(
                    icon: Icon(_showSearch ? Icons.close : Icons.search),
                    tooltip: _showSearch ? 'Close search' : 'Search',
                    onPressed: () {
                      if (_showSearch) {
                        _closeSearch();
                      } else {
                        setState(() => _showSearch = true);
                      }
                    },
                  ),
                  IconButton(
                    icon: _syncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    tooltip: 'Sync',
                    onPressed: _loading || _syncing ? null : () => _loadAndSync(force: true),
                  ),
                  PopupMenuButton<SortOrder>(
                    icon: const Icon(Icons.sort),
                    tooltip: 'Sort order',
                    onSelected: (order) {
                      _sortOrder = order;
                      _loadBookmarks();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: SortOrder.newestFirst,
                        child: Row(
                          children: [
                            if (_sortOrder == SortOrder.newestFirst)
                              const Icon(Icons.check, size: 18),
                            if (_sortOrder == SortOrder.newestFirst) const SizedBox(width: 8),
                            const Text('Newest first'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: SortOrder.oldestFirst,
                        child: Row(
                          children: [
                            if (_sortOrder == SortOrder.oldestFirst)
                              const Icon(Icons.check, size: 18),
                            if (_sortOrder == SortOrder.oldestFirst) const SizedBox(width: 8),
                            const Text('Oldest first'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: SortOrder.random,
                        child: Row(
                          children: [
                            if (_sortOrder == SortOrder.random) const Icon(Icons.check, size: 18),
                            if (_sortOrder == SortOrder.random) const SizedBox(width: 8),
                            const Text('Random'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: SortOrder.byHost,
                        child: Row(
                          children: [
                            if (_sortOrder == SortOrder.byHost) const Icon(Icons.check, size: 18),
                            if (_sortOrder == SortOrder.byHost) const SizedBox(width: 8),
                            const Text('By host'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings),
                    tooltip: 'Settings',
                    onPressed: widget.onSettingsTap,
                  ),
                ],
              ),
        floatingActionButton: _selectionMode
            ? null
            : FloatingActionButton(
                onPressed: _showAddDialog,
                tooltip: 'Add bookmark',
                child: const Icon(Icons.add),
              ),
        body: Scrollbar(
          controller: _scrollController,
          interactive: true,
          thumbVisibility: kIsWeb,
          child: RefreshIndicator(
            onRefresh: () => _loadAndSync(force: true),
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                // Sync banner
                if (_syncMessage != null)
                  SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: MaterialBanner(
                          backgroundColor: _syncSuccess
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.errorContainer,
                          content: Text(
                            _syncMessage!,
                            style: TextStyle(
                              color: _syncSuccess
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.onErrorContainer,
                            ),
                          ),
                          actions: [
                            if (!_syncSuccess)
                              TextButton(
                                onPressed: () {
                                  setState(() => _syncMessage = null);
                                  _sync(force: true);
                                },
                                child: const Text('RETRY'),
                              ),
                            TextButton(
                              onPressed: () => setState(() => _syncMessage = null),
                              child: const Text('DISMISS'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                // Tag filter chips
                if (_allTags.isNotEmpty && !_loading)
                  SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: SizedBox(
                          height: 48,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            children: [
                              for (final tag in _allTags.toList()..sort())
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: FilterChip(
                                    label: Text(tag),
                                    selected: _selectedTag == tag,
                                    onSelected: (selected) {
                                      setState(() => _selectedTag = selected ? tag : null);
                                      _loadBookmarks();
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                // Content
                if (_loading)
                  const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
                else if (_bookmarks.isEmpty)
                  SliverFillRemaining(
                    child: _EmptyState(hasFilters: _query.isNotEmpty || _selectedTag != null),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final bookmark = _bookmarks[index];
                      final card = _BookmarkCard(
                        bookmark: bookmark,
                        selected: _selectedIds.contains(bookmark.id),
                        selectionMode: _selectionMode,
                        onTap: _selectionMode
                            ? () => _toggleSelection(bookmark.id)
                            : () => _openUrl(bookmark.url),
                        onLongPress: () => _toggleSelection(bookmark.id),
                        onEdit: () => _showEditDialog(bookmark),
                        onDelete: () => _confirmDelete(bookmark),
                        onSelect: () => _toggleSelection(bookmark.id),
                        onCopy: () => _copyUrl(bookmark),
                      );
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 600),
                          child: _selectionMode
                              ? card
                              : Dismissible(
                                  key: ValueKey(bookmark.id),
                                  direction: DismissDirection.startToEnd,
                                  confirmDismiss: (_) async {
                                    unawaited(_confirmDelete(bookmark));
                                    return false; // Dialog handles the actual delete
                                  },
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 20),
                                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.errorContainer,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.delete,
                                      color: Theme.of(context).colorScheme.onErrorContainer,
                                    ),
                                  ),
                                  child: card,
                                ),
                        ),
                      );
                    }, childCount: _bookmarks.length),
                  ),
                // Extra bottom padding so the FAB doesn't obscure the last item.
                const SliverPadding(
                  padding: EdgeInsets.only(bottom: kFloatingActionButtonMargin + kFabHeight),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasFilters;
  const _EmptyState({required this.hasFilters});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasFilters ? Icons.filter_list_off : Icons.bookmark_border,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              hasFilters ? 'No bookmarks match your filters' : 'No bookmarks yet',
              style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilters
                  ? 'Try adjusting your search or filters'
                  : 'Share a URL from any app to save it here',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _BookmarkCard extends StatelessWidget {
  final Bookmark bookmark;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSelect;
  final VoidCallback onCopy;

  const _BookmarkCard({
    required this.bookmark,
    this.selected = false,
    this.selectionMode = false,
    required this.onTap,
    required this.onLongPress,
    required this.onEdit,
    required this.onDelete,
    required this.onSelect,
    required this.onCopy,
  });

  String get _faviconUrl {
    final host = Uri.tryParse(bookmark.url)?.host ?? '';
    return 'https://icons.duckduckgo.com/ip3/$host.ico';
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 365) return '${diff.inDays ~/ 365}y ago';
    if (diff.inDays > 30) return '${diff.inDays ~/ 30}mo ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Selection checkbox
                  if (selectionMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, top: 2),
                      child: Icon(
                        selected ? Icons.check_circle : Icons.circle_outlined,
                        size: 22,
                        color: selected ? theme.colorScheme.primary : theme.colorScheme.outline,
                      ),
                    ),
                  // Favicon (skipped on web due to CORS)
                  Padding(
                    padding: const EdgeInsets.only(right: 10, top: 2),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: kIsWeb
                          ? Icon(Icons.language, size: 20, color: theme.colorScheme.outline)
                          : Image.network(
                              _faviconUrl,
                              width: 20,
                              height: 20,
                              errorBuilder: (_, e, st) =>
                                  Icon(Icons.language, size: 20, color: theme.colorScheme.outline),
                            ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bookmark.title?.isNotEmpty == true ? bookmark.title! : bookmark.url,
                          style: theme.textTheme.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${Uri.tryParse(bookmark.url)?.host ?? bookmark.url}  ·  ${_timeAgo(bookmark.createdAt)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    popUpAnimationStyle: const AnimationStyle(
                      duration: Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                      reverseDuration: Duration(milliseconds: 100),
                      reverseCurve: Curves.easeIn,
                    ),
                    onSelected: (action) {
                      switch (action) {
                        case 'edit':
                          onEdit();
                        case 'copy':
                          onCopy();
                        case 'delete':
                          onDelete();
                        case 'select':
                          onSelect();
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          title: Text('Edit'),
                          leading: Icon(Icons.edit),
                          dense: true,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'select',
                        child: ListTile(
                          title: Text('Select'),
                          leading: Icon(Icons.check_circle_outline),
                          dense: true,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'copy',
                        child: ListTile(
                          title: Text('Copy URL'),
                          leading: Icon(Icons.copy),
                          dense: true,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          title: Text('Delete'),
                          leading: Icon(Icons.delete),
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (bookmark.tags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: bookmark.tags
                      .map(
                        (tag) => Chip(
                          label: Text(tag, style: const TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: EdgeInsets.zero,
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
