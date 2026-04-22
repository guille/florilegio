CREATE TABLE IF NOT EXISTS sync_metadata(
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

INSERT OR IGNORE INTO sync_metadata(key, value)
VALUES ('last_modified', strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));

-- Bump last_modified on every bookmark insert, update, or delete.
CREATE TRIGGER IF NOT EXISTS sync_meta_after_insert AFTER INSERT ON bookmarks
BEGIN
  UPDATE sync_metadata
  SET
    value = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
  WHERE
    key = 'last_modified';
END;

CREATE TRIGGER IF NOT EXISTS sync_meta_after_update AFTER UPDATE ON bookmarks
BEGIN
  UPDATE sync_metadata
  SET
    value = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
  WHERE
    key = 'last_modified';
END;

CREATE TRIGGER IF NOT EXISTS sync_meta_after_delete AFTER DELETE ON bookmarks
BEGIN
  UPDATE sync_metadata
  SET
    value = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
  WHERE
    key = 'last_modified';
END;
