SET max_parallel_workers_per_gather=0; SET jit=off; SET work_mem='4MB';
\echo == 第9章 20件の結合
EXPLAIN SELECT r.book_id, b.title, r.finished_at FROM (SELECT book_id, finished_at FROM :t ORDER BY finished_at DESC, book_id ASC LIMIT 20) AS r JOIN books AS b ON b.id = r.book_id ORDER BY r.finished_at DESC, r.book_id ASC;
\echo == 第9章 50万件の結合
EXPLAIN SELECT r.book_id, b.title FROM :t AS r JOIN books AS b ON b.id = r.book_id WHERE r.finished_at >= timestamp '2026-09-14' AND r.finished_at < timestamp '2026-09-21';
\echo == 第12章 基準
EXPLAIN SELECT b.id, b.title, count(*) FROM books b JOIN :t r ON r.book_id = b.id WHERE r.finished_at >= timestamp '2026-09-14' AND r.finished_at < timestamp '2026-09-21' GROUP BY b.id, b.title ORDER BY 3 DESC, b.id LIMIT 20;
SELECT 'n_distinct=' || n_distinct FROM pg_stats WHERE tablename = :'t' AND attname = 'book_id';
SELECT 'week_books=' || count(DISTINCT book_id) || ' all_books=' || (SELECT count(DISTINCT book_id) FROM :t) FROM :t WHERE finished_at >= '2026-09-14' AND finished_at < '2026-09-21';
SELECT 'top20=' || string_agg(c::text, ' ' ORDER BY c DESC) FROM (SELECT count(*) c FROM :t WHERE finished_at >= '2026-09-14' AND finished_at < '2026-09-21' GROUP BY book_id ORDER BY 1 DESC LIMIT 20) x;
