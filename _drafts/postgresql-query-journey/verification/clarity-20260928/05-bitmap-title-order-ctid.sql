-- 第5章「目録の順に取りに行くと、同じページに何度も戻る」の SELECT に ctid を足して取り直す（2026-09-28）
-- 本文の「400009の次に40001が来て、その次は400010に戻る」と、ページ2941・294の記述を、
-- 出力で確かめられるようにするため。読み取りだけ。lab は第12章まで進めた状態。
SELECT version();
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
SELECT id, title, ctid FROM books
WHERE title >= '実験用の本 4' AND title < '実験用の本 5'
ORDER BY title LIMIT 17;
