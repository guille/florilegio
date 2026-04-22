DROP INDEX IF EXISTS idx_bookmarks_is_read;

ALTER TABLE bookmarks DROP COLUMN is_read;
