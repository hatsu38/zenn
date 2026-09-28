-- 第9章：1週間分のHash Joinで、件数の多い本の側からハッシュ表を作った理由を確かめる（2026-09-28 clarity 作業）
-- 仮説：記録の book_id には同じ番号が何度も出るので、記録でハッシュ表を作ると箱の中が長くなると見積もられる
-- （costsize.c の final_cost_hashjoin は、内側の箱に入る件数 inner_rows × innerbucketsize で照合の比較回数を見積もる）
-- 統計の変更は BEGIN 〜 ROLLBACK の中だけ。
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
SELECT now();
-- 1) 今の統計のままの計画（EXPLAIN だけ）
EXPLAIN
SELECT r.book_id, b.title
FROM reading_records AS r
JOIN books AS b ON b.id = r.book_id
WHERE r.finished_at >= timestamp '2026-09-14'
  AND r.finished_at < timestamp '2026-09-21';
-- 記録の book_id の統計（よく出る番号の割合の最大値）
SELECT n_distinct, (most_common_freqs)[1] AS top_freq,
       array_length(most_common_vals::text::bigint[], 1) AS mcv_count
FROM pg_stats WHERE tablename = 'reading_records' AND attname = 'book_id';
-- 2) 記録の book_id を「すべて違う番号」に見せかけると、ハッシュ表を作る側が変わるか
BEGIN;
ALTER TABLE reading_records ALTER COLUMN book_id SET (n_distinct = -1);
ANALYZE reading_records (book_id);
SELECT n_distinct, most_common_vals IS NULL AS no_mcv
FROM pg_stats WHERE tablename = 'reading_records' AND attname = 'book_id';
EXPLAIN
SELECT r.book_id, b.title
FROM reading_records AS r
JOIN books AS b ON b.id = r.book_id
WHERE r.finished_at >= timestamp '2026-09-14'
  AND r.finished_at < timestamp '2026-09-21';
ROLLBACK;
-- 元に戻ったことの確認
SELECT n_distinct, (most_common_freqs)[1] AS top_freq
FROM pg_stats WHERE tablename = 'reading_records' AND attname = 'book_id';
SELECT pid, state FROM pg_stat_activity WHERE state LIKE 'idle in%';
-- 結果（2026-09-28）：n_distinct = -1 にしても、ハッシュ表は本の側で作ったままだった。
-- 記録の book_id には、よく出る番号の割合（most_common_freqs の最大は約1%）が残るので、
-- この実験では「件数の少ない記録の側で作らなかった理由」を確かめきれなかった。本文には理由を書かない。
