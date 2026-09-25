\set ON_ERROR_STOP on
SET max_parallel_workers_per_gather=0; SET jit=off; SET work_mem='4MB';
-- 候補の分布ごとに reading_records 相当の表を作る
DROP TABLE IF EXISTS v_s08, v_s09, v_mix09;
CREATE TABLE v_s08 AS SELECT ((floor(power(1 + u * (power(1000001::float8, 0.2) - 1), 5))::bigint * 386413) % 1000000) + 1 AS book_id,
  timestamp '2026-08-24' + ((n::bigint * 104729) % 2419200) * interval '1 second' AS finished_at
  FROM (SELECT n, n * 0.6180339887498949::float8 - floor(n * 0.6180339887498949::float8) AS u FROM generate_series(1, 2000000) n) s;
CREATE TABLE v_s09 AS SELECT ((floor(power(1 + u * (power(1000001::float8, 0.1) - 1), 10))::bigint * 386413) % 1000000) + 1 AS book_id,
  timestamp '2026-08-24' + ((n::bigint * 104729) % 2419200) * interval '1 second' AS finished_at
  FROM (SELECT n, n * 0.6180339887498949::float8 - floor(n * 0.6180339887498949::float8) AS u FROM generate_series(1, 2000000) n) s;
-- 奇数番目は今と同じ一様な割り当て、偶数番目は s=0.9 の人気順
CREATE TABLE v_mix09 AS SELECT CASE WHEN n % 2 = 1 THEN ((n::bigint * 7919) % 1000000) + 1
  ELSE ((floor(power(1 + u * (power(1000001::float8, 0.1) - 1), 10))::bigint * 386413) % 1000000) + 1 END AS book_id,
  timestamp '2026-08-24' + ((n::bigint * 104729) % 2419200) * interval '1 second' AS finished_at
  FROM (SELECT n, n * 0.6180339887498949::float8 - floor(n * 0.6180339887498949::float8) AS u FROM generate_series(1, 2000000) n) s;
CREATE INDEX ON v_s08 (finished_at DESC, book_id); CREATE INDEX ON v_s09 (finished_at DESC, book_id); CREATE INDEX ON v_mix09 (finished_at DESC, book_id);
VACUUM ANALYZE v_s08; VACUUM ANALYZE v_s09; VACUUM ANALYZE v_mix09; VACUUM ANALYZE books;
