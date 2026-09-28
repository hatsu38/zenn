-- 第10章：範囲の条件の見積もりが、histogram_bounds の区間の割合×件数から来ることを確かめる（2026-09-28 clarity 作業）
-- 本のテーブルは読むだけ。ANALYZE はしない。
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
SELECT now();
SELECT relname, reltuples, relpages, pg_relation_size(oid) / 8192 AS pages_now
FROM pg_class WHERE relname IN ('reading_records', 'books');
-- finished_at によく出る値（MCV）があるか、境目の数はいくつか
SELECT attname, n_distinct, most_common_vals IS NULL AS no_mcv,
       array_length(histogram_bounds::text::timestamp[], 1) AS bounds
FROM pg_stats WHERE tablename = 'reading_records' AND attname = 'finished_at';
-- 1週間の範囲に入る境目の数（区間の数は bounds - 1）
SELECT count(*) AS bounds_in_range
FROM pg_stats, unnest(histogram_bounds::text::timestamp[]) AS b
WHERE tablename = 'reading_records' AND attname = 'finished_at'
  AND b >= timestamp '2026-09-14' AND b < timestamp '2026-09-21';
EXPLAIN
SELECT r.book_id FROM reading_records AS r
WHERE r.finished_at >= timestamp '2026-09-14'
  AND r.finished_at < timestamp '2026-09-21';
-- books.id の範囲（第3章の id BETWEEN 1 AND 900000）
SELECT attname, n_distinct, most_common_vals IS NULL AS no_mcv,
       array_length(histogram_bounds::text::bigint[], 1) AS bounds
FROM pg_stats WHERE tablename = 'books' AND attname = 'id';
SELECT count(*) AS bounds_in_range
FROM pg_stats, unnest(histogram_bounds::text::bigint[]) AS b
WHERE tablename = 'books' AND attname = 'id' AND b BETWEEN 1 AND 900000;
EXPLAIN SELECT * FROM books WHERE id BETWEEN 1 AND 900000;
-- 結果（2026-09-28）：finished_at に most_common_vals はなく、境目101個のうち25個が1週間の範囲に入り、見積もりは rows=498088（200万件の約0.249）。
-- books.id も境目101個のうち90個が範囲に入り、rows=898829。範囲の見積もりが「区間の割合×件数」になっていることを確かめた。
