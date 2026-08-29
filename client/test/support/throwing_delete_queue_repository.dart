import 'package:florilegio/data/in_memory_repository.dart';

/// Repository whose delete queue always fails, for exercising the
/// enqueue-failure path of SyncService.deleteBookmark.
class ThrowingDeleteQueueRepository extends InMemoryBookmarkRepository {
  @override
  Future<void> addPendingDelete(String id) => throw StateError('storage failed');
}
