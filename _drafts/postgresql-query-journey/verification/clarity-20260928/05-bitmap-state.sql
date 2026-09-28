-- 案Aで第3章のBitmapの節を第5章へ移すときの状態の確認（2026-09-28）
-- 第5章の時点で、Bitmapの実験に要る books と books_title_idx があるか、
-- 計画が Bitmap Heap Scan のままかを確かめる。読み取りだけ。
-- lab は第12章まで進めた状態（books_observation はない、日時Indexあり）。
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
SELECT indexname FROM pg_indexes WHERE tablename IN ('books','reading_records') ORDER BY 1;
SELECT to_regclass('books_observation');
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books WHERE title >= '実験用の本 4' AND title < '実験用の本 5';
