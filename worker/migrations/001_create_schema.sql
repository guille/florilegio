CREATE TABLE IF NOT EXISTS bookmarks(
  id TEXT PRIMARY KEY, -- crypto.randomUUID()
  url TEXT NOT NULL UNIQUE,
  title TEXT,
  tags TEXT, -- comma-separated
  is_read INTEGER NOT NULL DEFAULT (0), -- 0 | 1  (SQLite has no BOOLEAN)
  created_at TEXT NOT NULL, -- ISO-8601
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_bookmarks_is_read ON bookmarks (is_read);

CREATE INDEX IF NOT EXISTS idx_bookmarks_created_at ON bookmarks (
  created_at DESC
);

-- Full-text search
CREATE VIRTUAL TABLE IF NOT EXISTS bookmarks_fts USING fts5(
  id UNINDEXED,
  title,
  url,
  content = bookmarks,
  content_rowid = rowid
);

-- Keep FTS in sync
CREATE TRIGGER IF NOT EXISTS bookmarks_ai AFTER INSERT ON bookmarks
BEGIN
  INSERT INTO bookmarks_fts(rowid, id, title, url)
  VALUES (new.rowid, new.id, new.title, new.url);
END;

CREATE TRIGGER IF NOT EXISTS bookmarks_ad AFTER DELETE ON bookmarks
BEGIN
  INSERT INTO bookmarks_fts(bookmarks_fts, rowid, id, title, url)
  VALUES ('delete', old.rowid, old.id, old.title, old.url);
END;

CREATE TRIGGER IF NOT EXISTS bookmarks_au AFTER UPDATE ON bookmarks
BEGIN
  INSERT INTO bookmarks_fts(bookmarks_fts, rowid, id, title, url)
  VALUES ('delete', old.rowid, old.id, old.title, old.url);
  INSERT INTO bookmarks_fts(rowid, id, title, url)
  VALUES (new.rowid, new.id, new.title, new.url);
END;
