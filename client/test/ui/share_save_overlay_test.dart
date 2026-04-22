import 'dart:convert';

import 'package:florilegio/data/api_client.dart';
import 'package:florilegio/data/in_memory_repository.dart';
import 'package:florilegio/services/sync_service.dart';
import 'package:florilegio/ui/share_save_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

void main() {
  late InMemoryBookmarkRepository repo;

  setUp(() {
    repo = InMemoryBookmarkRepository();
  });

  SyncService makeSyncService(http.Client client) {
    final api = BookmarkApiClient(baseUrl: 'https://api.test', token: 'test-token', client: client);
    return SyncService(repository: repo, apiClient: api);
  }

  final successResponse = {
    'id': 'share-1',
    'url': 'https://shared.com/',
    'title': null,
    'tags': null,
    'created_at': '2024-01-01T00:00:00.000Z',
    'updated_at': '2024-01-01T00:00:00.000Z',
    'is_read': 0,
  };

  group('ShareSaveOverlay', () {
    testWidgets('shows saved state on success and calls onDone', (tester) async {
      final client = http_testing.MockClient(
        (_) async => http.Response(jsonEncode(successResponse), 201),
      );
      final syncService = makeSyncService(client);

      var doneCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ShareSaveOverlay(
            url: 'https://shared.com',
            syncService: syncService,
            onDone: () => doneCalled = true,
          ),
        ),
      );

      // Initially shows saving
      expect(find.text('Saving...'), findsOneWidget);
      expect(find.text('https://shared.com'), findsOneWidget);

      // Let save complete
      await tester.pump();
      expect(find.text('Saved!'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      // Flush the 800ms delay + dismiss
      await tester.pump(const Duration(seconds: 1));
      expect(doneCalled, true);
    });

    testWidgets('shows saved when queued locally (offline)', (tester) async {
      final client = http_testing.MockClient((_) => throw Exception('network'));
      final syncService = makeSyncService(client);

      var doneCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ShareSaveOverlay(
            url: 'https://offline.com',
            syncService: syncService,
            onDone: () => doneCalled = true,
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Saved!'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(doneCalled, true);
    });
  });
}
