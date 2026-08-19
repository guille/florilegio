-- Server-side search is unused: every client syncs the full collection and
-- filters locally, so the FTS index only added write amplification.
-- Rebuildable if ever needed again (FTS is derived data — recreate the table
-- and triggers, then INSERT INTO bookmarks_fts(bookmarks_fts) VALUES ('rebuild')).
DROP TRIGGER IF EXISTS bookmarks_ai;

DROP TRIGGER IF EXISTS bookmarks_ad;

DROP TRIGGER IF EXISTS bookmarks_au;

DROP TABLE IF EXISTS bookmarks_fts;
