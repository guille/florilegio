import 'package:florilegio/services/sync_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Minimal overlay shown when a URL is shared into the app.
/// Shows "Saving..." → "Saved!" → returns to the previous app.
class ShareSaveOverlay extends StatefulWidget {
  final String url;
  final SyncService syncService;

  /// Called when the overlay is done (success or dismiss) so the parent
  /// can clear the pending share URL.
  final VoidCallback? onDone;

  const ShareSaveOverlay({super.key, required this.url, required this.syncService, this.onDone});

  @override
  State<ShareSaveOverlay> createState() => _ShareSaveOverlayState();
}

class _ShareSaveOverlayState extends State<ShareSaveOverlay> {
  bool _saving = true;
  bool _success = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _save();
  }

  Future<void> _save() async {
    try {
      final result = await widget.syncService.saveBookmark(widget.url);
      if (!mounted) return;

      if (result.savedRemotely || result.queuedLocally) {
        setState(() {
          _saving = false;
          _success = true;
        });
        await Future<void>.delayed(const Duration(milliseconds: 800));
        _dismiss();
      } else {
        setState(() {
          _saving = false;
          _error = 'Failed to save bookmark';
        });
        await Future<void>.delayed(const Duration(seconds: 2));
        _dismiss();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Error: $e';
      });
      await Future<void>.delayed(const Duration(seconds: 2));
      _dismiss();
    }
  }

  void _dismiss() {
    widget.onDone?.call();
    if (mounted) SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _dismiss();
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Center(
          child: Card(
            elevation: 4,
            margin: const EdgeInsets.all(32),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_saving) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text('Saving...', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      widget.url,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ] else if (_success) ...[
                    Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 48),
                    const SizedBox(height: 16),
                    Text('Saved!', style: theme.textTheme.titleMedium),
                  ] else ...[
                    Icon(Icons.error_outline, color: theme.colorScheme.error, size: 48),
                    const SizedBox(height: 16),
                    Text(_error ?? 'Error', style: theme.textTheme.titleMedium),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
