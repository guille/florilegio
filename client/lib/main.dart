import 'package:florilegio/data/api_client.dart';
import 'package:florilegio/data/in_memory_repository.dart';
import 'package:florilegio/data/sqlite_repository.dart';
import 'package:florilegio/domain/bookmark_repository.dart';
import 'package:florilegio/services/settings_service.dart';
import 'package:florilegio/services/share_intent_handler.dart';
import 'package:florilegio/services/sync_service.dart';
import 'package:florilegio/services/title_fetcher.dart';
import 'package:florilegio/ui/bookmark_list_view.dart';
import 'package:florilegio/ui/settings_view.dart';
import 'package:florilegio/ui/share_save_overlay.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Parallelize independent async init work.
  final prefsFuture = SharedPreferences.getInstance();
  final repoFuture = kIsWeb
      ? Future.value(InMemoryBookmarkRepository() as BookmarkRepository)
      : SqliteBookmarkRepository.open();

  final results = await Future.wait([prefsFuture, repoFuture]);
  final prefs = results[0] as SharedPreferences;
  final repository = results[1] as BookmarkRepository;
  final settings = await SettingsService.create(prefs);

  runApp(FlorilegioApp(settings: settings, repository: repository));
}

class FlorilegioApp extends StatefulWidget {
  final SettingsService settings;
  final BookmarkRepository repository;

  const FlorilegioApp({super.key, required this.settings, required this.repository});

  @override
  State<FlorilegioApp> createState() => _FlorilegioAppState();
}

class _FlorilegioAppState extends State<FlorilegioApp> {
  BookmarkApiClient? _apiClient;
  SyncService? _syncService;
  final TitleFetcher _titleFetcher = TitleFetcher();
  late final ShareIntentHandler _shareHandler;

  /// URL received via share intent, pending save.
  String? _pendingShareUrl;

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_onSettingsChanged);
    _rebuildServices();
    _shareHandler = createShareIntentHandler();
    _shareHandler.listen(
      onShare: (url) {
        if (mounted) setState(() => _pendingShareUrl = url);
      },
    );
  }

  void _onSettingsChanged() {
    _rebuildServices();
    setState(() {});
  }

  void _rebuildServices() {
    _apiClient?.dispose();
    if (widget.settings.isConfigured) {
      _apiClient = BookmarkApiClient(
        baseUrl: widget.settings.baseUrl,
        token: widget.settings.token,
      );
      _syncService = SyncService(
        repository: widget.repository,
        apiClient: _apiClient!,
        titleFetcher: _titleFetcher,
      );
    } else {
      _apiClient = null;
      _syncService = null;
    }
  }

  @override
  void dispose() {
    _shareHandler.dispose();
    _titleFetcher.dispose();
    widget.settings.removeListener(_onSettingsChanged);
    _apiClient?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Florilegio',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3E7FA9)),
      fontFamily: "Atkinson Hyperlegible Next",
      fontFamilyFallback: ["Atkinson Hyperlegible Next"],
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF3E7FA9),
        brightness: Brightness.dark,
      ),
    ),
    themeMode: widget.settings.themeMode,
    home: _pendingShareUrl != null && _syncService != null
        ? ShareSaveOverlay(
            url: _pendingShareUrl!,
            syncService: _syncService!,
            onDone: () {
              if (mounted) setState(() => _pendingShareUrl = null);
            },
          )
        : _HomeRouter(
            settings: widget.settings,
            repository: widget.repository,
            syncService: _syncService,
            apiClient: _apiClient,
          ),
  );
}

class _HomeRouter extends StatelessWidget {
  final SettingsService settings;
  final BookmarkRepository repository;
  final SyncService? syncService;
  final BookmarkApiClient? apiClient;

  const _HomeRouter({
    required this.settings,
    required this.repository,
    required this.syncService,
    required this.apiClient,
  });

  @override
  Widget build(BuildContext context) {
    if (!settings.isConfigured || syncService == null) {
      return SettingsView(
        settings: settings,
        showBackButton: false,
        apiClient: apiClient,
        repository: repository,
      );
    }
    return BookmarkListView(
      repository: repository,
      syncService: syncService!,
      onSettingsTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SettingsView(
              settings: settings,
              showBackButton: true,
              apiClient: apiClient,
              repository: repository,
            ),
          ),
        );
      },
    );
  }
}
