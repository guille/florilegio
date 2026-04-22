import 'dart:convert';
import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:florilegio/data/api_client.dart';
import 'package:florilegio/domain/bookmark_repository.dart';
import 'package:florilegio/services/settings_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

class SettingsView extends StatefulWidget {
  final SettingsService settings;
  final bool showBackButton;
  final BookmarkApiClient? apiClient;
  final BookmarkRepository? repository;

  const SettingsView({
    super.key,
    required this.settings,
    this.showBackButton = true,
    this.apiClient,
    this.repository,
  });

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late TextEditingController _urlController;
  late TextEditingController _tokenController;
  bool _dirty = false;
  bool _exporting = false;
  bool _importing = false;
  String? _lastRefreshed;
  int _offlineQueueSize = 0;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.settings.baseUrl);
    _tokenController = TextEditingController(text: widget.settings.token);
    _loadLastRefreshed();
    _loadOfflineQueueSize();
  }

  Future<void> _loadLastRefreshed() async {
    final lm = await widget.repository?.getLastModified();
    if (mounted) setState(() => _lastRefreshed = lm);
  }

  Future<void> _loadOfflineQueueSize() async {
    final lm = await widget.repository?.getPendingCount();
    if (mounted) setState(() => _offlineQueueSize = lm ?? 0);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.settings.setBaseUrl(_urlController.text.trim());
    await widget.settings.setToken(_tokenController.text.trim());
    setState(() => _dirty = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
    }
  }

  Future<void> _export() async {
    final client = widget.apiClient;
    if (client == null) {
      _showSnack('Configure settings first');
      return;
    }
    setState(() => _exporting = true);
    try {
      final json = await client.exportJson();
      // Pretty-print for readability
      final pretty = const JsonEncoder.withIndent('  ').convert(jsonDecode(json));
      final bytes = utf8.encode(pretty);

      final path = await FilePicker.saveFile(
        dialogTitle: 'Save export',
        fileName: 'florilegio-export.json',
        bytes: bytes,
      );
      _showSnack(kIsWeb || path != null ? 'Exported successfully' : 'Export cancelled');
    } on ApiException catch (e) {
      _showSnack('Export failed: ${e.userMessage}');
    } catch (e) {
      _showSnack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _import() async {
    final client = widget.apiClient;
    if (client == null) {
      _showSnack('Configure settings first');
      return;
    }

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final pickedFile = result.files.first;
    var bytes = pickedFile.bytes;
    if (bytes == null && !kIsWeb) {
      // On native platforms, bytes may be null; read from the file path
      final path = pickedFile.path;
      if (path != null) {
        bytes = await File(path).readAsBytes();
      }
    }
    if (bytes == null || bytes.isEmpty) {
      _showSnack('Could not read file');
      return;
    }

    final jsonStr = utf8.decode(bytes);

    // Validate it's a JSON array before sending
    try {
      final parsed = jsonDecode(jsonStr);
      if (parsed is! List) {
        _showSnack('File must contain a JSON array of bookmarks');
        return;
      }
    } on FormatException {
      _showSnack('File is not valid JSON');
      return;
    }

    setState(() => _importing = true);
    try {
      final res = await client.importJson(jsonStr);
      final imported = res['imported'] ?? 0;
      final skipped = (res['skipped'] as int?) ?? 0;
      final errors = (res['errors'] as List?)?.length ?? 0;
      var msg = 'Imported $imported bookmark${imported == 1 ? '' : 's'}';
      if (skipped > 0) msg += ', $skipped skipped';
      if (errors > 0) msg += ', $errors errors';
      _showSnack(msg);
    } on ApiException catch (e) {
      _showSnack('Import failed: ${e.userMessage}');
    } catch (e) {
      _showSnack('Import failed: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _showSnack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  /// Parse an HTTP date (e.g. "Thu, 01 Jan 2024 00:00:00 GMT") into a
  /// human-readable local time string.
  String _formatHttpDate(String httpDate) {
    try {
      // HTTP dates follow RFC 1123: "Thu, 01 Jan 2024 00:00:00 GMT"
      // Dart's DateTime.parse doesn't handle this format, so parse manually.
      const monthMap = {
        'Jan': 1,
        'Feb': 2,
        'Mar': 3,
        'Apr': 4,
        'May': 5,
        'Jun': 6,
        'Jul': 7,
        'Aug': 8,
        'Sep': 9,
        'Oct': 10,
        'Nov': 11,
        'Dec': 12,
      };
      final parts = httpDate.split(' ');
      // "Thu," "01" "Jan" "2024" "00:00:00" "GMT"
      final day = int.parse(parts[1]);
      final month = monthMap[parts[2]]!;
      final year = int.parse(parts[3]);
      final timeParts = parts[4].split(':');
      final dt = DateTime.utc(
        year,
        month,
        day,
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
        int.parse(timeParts[2]),
      ).toLocal();

      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at $hour:$minute';
    } catch (_) {
      return httpDate; // fallback to raw value
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings'), automaticallyImplyLeading: widget.showBackButton),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Theme
            const Text('Theme', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System')),
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ],
              selected: {widget.settings.themeMode},
              onSelectionChanged: (modes) {
                widget.settings.setThemeMode(modes.first);
                setState(() {});
              },
            ),
            const SizedBox(height: 24),

            // Base URL
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Endpoint Base URL',
                hintText: 'https://api.example.com',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _dirty = true),
            ),
            const SizedBox(height: 16),

            // Token
            TextField(
              controller: _tokenController,
              decoration: const InputDecoration(
                labelText: 'Bearer Token',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              onChanged: (_) => setState(() => _dirty = true),
            ),
            const SizedBox(height: 16),

            // Save button
            FilledButton(onPressed: _dirty ? _save : null, child: const Text('Save')),
            const SizedBox(height: 24),

            // Export
            FilledButton.tonal(
              onPressed: _exporting ? null : _export,
              child: _exporting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Export Bookmarks'),
            ),
            const SizedBox(height: 8),

            // Import
            FilledButton.tonal(
              onPressed: _importing ? null : _import,
              child: _importing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Import Bookmarks'),
            ),

            if (_lastRefreshed != null) ...[
              const SizedBox(height: 24),
              Text(
                'Last refreshed: ${_formatHttpDate(_lastRefreshed!)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
            ],
            if (_offlineQueueSize > 0) ...[
              const SizedBox(height: 24),
              Text(
                'Bookmarks in queue: $_offlineQueueSize',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
