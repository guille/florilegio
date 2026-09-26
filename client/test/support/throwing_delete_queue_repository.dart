import 'in_memory_repository.dart';

/// Repository whose delete queue fails, for exercising the enqueue-failure
/// path of SyncService.deleteBookmark(s).
class ThrowingDeleteQueueRepository extends InMemoryBookmarkRepository {
  /// Ids whose enqueue fails. Null fails every id.
  final Set<String>? failFor;

  ThrowingDeleteQueueRepository({this.failFor});

  @override
  Future<void> addPendingDelete(String id) {
    if (failFor?.contains(id) ?? true) throw StateError('storage failed');
    return super.addPendingDelete(id);
  }
}
