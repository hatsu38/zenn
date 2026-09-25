\set ON_ERROR_STOP on
-- 密度が x^-s に比例する分布を [1, M+1) で逆関数法により作り、floor(x) を人気の順位にする。
DROP TABLE IF EXISTS rr_a, rr_b, rr_c;
CREATE TABLE rr_a AS  -- s = 0.8
SELECT ((((floor(power(1 + u * (power(1000001::float8, 0.2) - 1), 1 / 0.2)))::bigint - 1) * 7919) % 1000000) + 1 AS book_id,
       timestamp '2026-08-24' + ((n::bigint * 104729) % 2419200) * interval '1 second' AS finished_at
FROM (SELECT n, (n * 0.6180339887498949::float8) - floor(n * 0.6180339887498949::float8) AS u FROM generate_series(1, 2000000) n) s;
CREATE TABLE rr_b AS  -- s = 0.9
SELECT ((((floor(power(1 + u * (power(1000001::float8, 0.1) - 1), 1 / 0.1)))::bigint - 1) * 7919) % 1000000) + 1 AS book_id,
       timestamp '2026-08-24' + ((n::bigint * 104729) % 2419200) * interval '1 second' AS finished_at
FROM (SELECT n, (n * 0.6180339887498949::float8) - floor(n * 0.6180339887498949::float8) AS u FROM generate_series(1, 2000000) n) s;
CREATE TABLE rr_c AS  -- s = 1.0（対数で逆関数）
SELECT ((((floor(power(1000001::float8, u)))::bigint - 1) * 7919) % 1000000) + 1 AS book_id,
       timestamp '2026-08-24' + ((n::bigint * 104729) % 2419200) * interval '1 second' AS finished_at
FROM (SELECT n, (n * 0.6180339887498949::float8) - floor(n * 0.6180339887498949::float8) AS u FROM generate_series(1, 2000000) n) s;
ANALYZE rr_a; ANALYZE rr_b; ANALYZE rr_c;
