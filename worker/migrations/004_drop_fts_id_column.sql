-- The id column in the FTS table is unused now that queries join on rowid.
-- FTS5 has no ALTER TABLE, so recreate the table and triggers without it.
DROP TRIGGER IF EXISTS bookmarks_ai;

DROP TRIGGER IF EXISTS bookmarks_ad;

DROP TRIGGER IF EXISTS bookmarks_au;

DROP TABLE IF EXISTS bookmarks_fts;

CREATE VIRTUAL TABLE bookmarks_fts USING fts5(
  title,
  url,
  content = bookmarks,
  content_rowid = rowid
);

CREATE TRIGGER bookmarks_ai AFTER INSERT ON bookmarks
BEGIN
  INSERT INTO bookmarks_fts(rowid, title, url)
  VALUES (new.rowid, new.title, new.url);
END;

CREATE TRIGGER bookmarks_ad AFTER DELETE ON bookmarks
BEGIN
  INSERT INTO bookmarks_fts(bookmarks_fts, rowid, title, url)
  VALUES ('delete', old.rowid, old.title, old.url);
END;

CREATE TRIGGER bookmarks_au AFTER UPDATE ON bookmarks
BEGIN
  INSERT INTO bookmarks_fts(bookmarks_fts, rowid, title, url)
  VALUES ('delete', old.rowid, old.title, old.url);
  INSERT INTO bookmarks_fts(rowid, title, url)
  VALUES (new.rowid, new.title, new.url);
END;

-- Repopulate the index from the content table
INSERT INTO bookmarks_fts(bookmarks_fts) VALUES ('rebuild');
