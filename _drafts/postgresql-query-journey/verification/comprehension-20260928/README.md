# 理解度の診断で確かめた実測（2026-09-28）

PostgreSQL 18.6、lab の reading_map（本100万冊・読了記録200万件）。並列実行とJITは無効、work_mem 4MB。診断の台帳は `../../review-20260928-comprehension.md`（未追跡）。

| 確かめたこと | ファイル | 結果 |
| --- | --- | --- |
| 第11章：値を変えない UPDATE の Heap Fetches | `c1-heapfetches.sql`、`c1-hot.sql` | 本42のページに空きがあり HOT 更新（n_tup_hot_upd=1、Index の項目1つ）で Heap Fetches 1 |
| 第11章：値を変える UPDATE | `c1-nonhot.sql` | HOT にならず Index の項目2つ、Heap Fetches 2。どれも BEGIN〜ROLLBACK。取り消した版が残り VACUUM が Index の掃除を省いた（index scan bypassed）ので、VACUUM (INDEX_CLEANUP ON) で印を戻した（relallvisible 10811/10811） |
| 第3章：Index の数と10万件の追加 | `c2-c4.sql`、`c2-c4-run1〜3.out` | 中央値 Index なし 62.8ms・WAL 7.1MB、1本 184.9ms・16.4MB、2本 328.3ms・25.5MB |
| 第11章：VACUUM の切り詰め | 同上 | 10万件1,728ページ。前半5万件を消して VACUUM → 1,728、末尾2万5千件も消して VACUUM → 1,294、VACUUM FULL → 432 |
| 付録パターン4：続きから探す書き方 | `keyset-or-run1〜5.out`、`keyset-indexcond-run1〜5.out` | 中央値 OFFSET 100000 は 13.1ms・387ページ、OR だけ 5.0ms・387ページ（Filter で10万件除外）、finished_at <= を外に出すと 0.037ms・4ページ。EXCEPT ALL で3つとも同じ20件 |
| 本に出てこない計画 U1〜U6 と直し方 | `unseen-plans.md`、`unseen-key.md`、`fixes.sql`、`fixes.out` | 直し方は BEGIN〜ROLLBACK で確かめた |
