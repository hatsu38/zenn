CREATE EXTENSION IF NOT EXISTS pageinspect;
BEGIN;
SELECT (ctid::text::point)[0]::int AS old_page FROM books WHERE id = 42 \gset
UPDATE books SET title = '改訂版の本 42' WHERE id = 42;
SELECT (ctid::text::point)[0]::int AS new_page FROM books WHERE id = 42 \gset
SELECT lp, t_xmin, t_xmax, t_ctid
FROM heap_page_items(get_raw_page('books', :old_page))
WHERE t_xmax = pg_current_xact_id()::xid
UNION ALL
SELECT lp, t_xmin, t_xmax, t_ctid
FROM heap_page_items(get_raw_page('books', :new_page))
WHERE t_xmin = pg_current_xact_id()::xid;
ROLLBACK;
