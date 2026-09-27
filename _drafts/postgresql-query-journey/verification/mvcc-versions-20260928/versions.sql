BEGIN;
SELECT ctid, xmin, xmax, title FROM books WHERE id = 42;
UPDATE books SET title = '改訂版の本 42' WHERE id = 42;
SELECT ctid, xmin, xmax, title FROM books WHERE id = 42;
ROLLBACK;
SELECT ctid, xmin, xmax, title FROM books WHERE id = 42;
