\pset pager off
SET max_parallel_workers_per_gather = 0;
SET jit = off;
BEGIN;
-- U1: 関数を掛けた列の検索に、式の Index を作る
CREATE INDEX tmp_books_lower_title ON books (lower(title));
ANALYZE books;
EXPLAIN (ANALYZE, BUFFERS) SELECT id, title FROM books WHERE lower(title) = lower('実験用の本 42');
-- U3: OFFSET をやめて、前のページの最後の id から続ける
EXPLAIN (ANALYZE, BUFFERS) SELECT id, title FROM books WHERE id > 500000 ORDER BY id LIMIT 20;
-- U4: 式の統計を作ると、グループ数の推定が直る
CREATE STATISTICS tmp_rr_week ON (date_trunc('week', finished_at)) FROM reading_records;
ANALYZE reading_records;
EXPLAIN (ANALYZE, BUFFERS) SELECT date_trunc('week', finished_at) AS w, count(*) FROM reading_records GROUP BY 1 ORDER BY 1;
-- U5: 前方一致に使える Index と、book_id の Index
CREATE INDEX tmp_books_title_pattern ON books (title text_pattern_ops);
CREATE INDEX tmp_rr_book_id ON reading_records (book_id);
ANALYZE books; ANALYZE reading_records;
EXPLAIN (ANALYZE, BUFFERS) SELECT r.book_id, b.title, count(*) FROM reading_records r JOIN books b ON b.id = r.book_id WHERE b.title LIKE '実験用の本 12345%' GROUP BY r.book_id, b.title ORDER BY count(*) DESC;
ROLLBACK;
