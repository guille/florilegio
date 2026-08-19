-- Replace the last_modified timestamp with a monotonic version counter.
--
-- HTTP dates have 1-second resolution, so a Last-Modified truncated to the
-- second could not distinguish two writes landing in the same second: a client
-- that read between them kept revalidating against a timestamp that never
-- advanced and never saw the second write. A counter has no resolution to lose.
CREATE TABLE bookmarks_state(
  id INTEGER PRIMARY KEY CHECK (id = 1), -- singleton
  version INTEGER NOT NULL
) STRICT;

INSERT INTO bookmarks_state(id, version) VALUES (1, 1);

DROP TRIGGER IF EXISTS sync_meta_after_insert;

DROP TRIGGER IF EXISTS sync_meta_after_update;

DROP TRIGGER IF EXISTS sync_meta_after_delete;

DROP TABLE IF EXISTS sync_metadata;

CREATE TRIGGER bookmarks_version_ai AFTER INSERT ON bookmarks
BEGIN
  UPDATE bookmarks_state SET version = version + 1 WHERE id = 1;
END;

CREATE TRIGGER bookmarks_version_au AFTER UPDATE ON bookmarks
BEGIN
  UPDATE bookmarks_state SET version = version + 1 WHERE id = 1;
END;

CREATE TRIGGER bookmarks_version_ad AFTER DELETE ON bookmarks
BEGIN
  UPDATE bookmarks_state SET version = version + 1 WHERE id = 1;
END;
