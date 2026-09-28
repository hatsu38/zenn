\pset pager off
SET max_parallel_workers_per_gather = 0;
SET jit = off;
BEGIN;
CREATE INDEX c1_visibility_idx ON reading_records (book_id, finished_at);
SELECT n_tup_upd, n_tup_hot_upd FROM pg_stat_xact_user_tables WHERE relname = 'reading_records';
UPDATE reading_records SET finished_at = finished_at WHERE book_id = 42;
SELECT n_tup_upd, n_tup_hot_upd FROM pg_stat_xact_user_tables WHERE relname = 'reading_records';
-- テーブルのページ 10810 の 151・152 番目
SELECT lp, t_xmin, t_xmax, t_ctid,
       (t_infomask2 & 16384) <> 0 AS hot_updated,
       (t_infomask2 & 32768) <> 0 AS heap_only
FROM heap_page_items(get_raw_page('reading_records', 10810)) WHERE lp IN (151, 152);
-- Index の中で book_id = 42 の項目の数（Index をたどって葉のページを探す）
SELECT count(*) AS index_items_for_42
FROM generate_series(1, (pg_relation_size('c1_visibility_idx') / 8192)::int - 1) AS blk,
     LATERAL bt_page_items('c1_visibility_idx', blk) i
WHERE i.data LIKE '2a 00 00 00 00 00 00 00 %' AND bt_page_stats('c1_visibility_idx', blk) IS NOT NULL
  AND (SELECT type FROM bt_page_stats('c1_visibility_idx', blk)) = 'l';
ROLLBACK;
