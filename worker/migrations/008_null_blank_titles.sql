-- Untitled is NULL only, so a re-save can recognise and fill it in.
UPDATE bookmarks SET title = NULL WHERE trim(title) = '';
