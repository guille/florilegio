-- Match the index to the sort the list queries actually use.
--
-- Every list orders by (created_at DESC, id ASC) — id breaks ties so paging is
-- deterministic. An index on created_at alone satisfies only the leading term,
-- leaving SQLite to sort each tie group in a temp b-tree.
DROP INDEX IF EXISTS idx_bookmarks_created_at;

CREATE INDEX idx_bookmarks_created_at ON bookmarks (created_at DESC, id ASC);
