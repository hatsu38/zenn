-- 第4章：1ページに入る件数（10文字は185件、200文字は34件）の内訳を確かめる
-- 本文と同じ作り方で二つのテーブルを作り、ページの中身を pageinspect で読む。最後に ROLLBACK で取り消す。
SET max_parallel_workers_per_gather = 0; SET jit = off; SET work_mem = '4MB';
SELECT version();
BEGIN;
CREATE EXTENSION IF NOT EXISTS pageinspect;
CREATE TABLE size_short AS
SELECT n AS id, repeat('a', 10) AS note
FROM generate_series(1, 1000) AS n;
CREATE TABLE size_long AS
SELECT n AS id, repeat('a', 200) AS note
FROM generate_series(1, 1000) AS n;
-- ページ0の見出し（lower=項目の並びの終わり、upper=レコードの並びの始まり）
SELECT 'size_short' AS t, lower, upper, special FROM page_header(get_raw_page('size_short', 0))
UNION ALL
SELECT 'size_long', lower, upper, special FROM page_header(get_raw_page('size_long', 0));
-- 先頭3件のレコードの長さ（lp_len）と、レコードの先頭の管理情報の長さ（t_hoff）
SELECT 'size_short' AS t, lp, lp_off, lp_len, t_hoff FROM heap_page_items(get_raw_page('size_short', 0)) WHERE lp <= 3
UNION ALL
SELECT 'size_long', lp, lp_off, lp_len, t_hoff FROM heap_page_items(get_raw_page('size_long', 0)) WHERE lp <= 3
ORDER BY 1, 2;
-- 各値の大きさ
SELECT pg_column_size(1::int) AS id_bytes, pg_column_size(repeat('a',10)) AS note10_bytes, pg_column_size(repeat('a',200)) AS note200_bytes;
-- ページ0に入った件数
SELECT 'size_short' AS t, count(*) FROM heap_page_items(get_raw_page('size_short', 0))
UNION ALL
SELECT 'size_long', count(*) FROM heap_page_items(get_raw_page('size_long', 0));
ROLLBACK;
SELECT pid, state FROM pg_stat_activity WHERE state LIKE 'idle in%';
