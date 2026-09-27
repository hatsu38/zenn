# 技術の確認（2026-09-28）

3視点の通読レビュー（`../../review-20260928-personas.md`）の中級者の指摘を、lab（PostgreSQL 18.6、Docker、`reading_map`、第12章まで読み進めた状態）で確かめた記録。

| 指摘 | 確かめ方 | 結果 |
| --- | --- | --- |
| PG18 では EXPLAIN ANALYZE だけで BUFFERS が出る | `EXPLAIN ANALYZE SELECT id FROM books WHERE id = 42;` | `Buffers:` の行が出た |
| SELECT でも古い版の片付けで WAL が出る | 使い捨ての DB `verify_prune` で、2回更新した150件のテーブルを CHECKPOINT の後に SELECT し、その間の WAL を `pg_waldump` で見た（DB は削除済み） | `XLOG FPI_FOR_HINT` と `Heap2 PRUNE_ON_ACCESS` が2ページ分ずつ。`data_checksums` は on |
| Merge Join で200万件を並べるのは、`b.id <= 100` が `r.book_id` に伝わらないため | `merge-join-condition-20260928.out`（`AND r.book_id <= 100` を足した版と比較） | Sort の入力が200万件から141件、`external merge Disk: 50896kB` から `quicksort Memory: 29kB`。時間は 882/715 ms から 79/66 ms |
| 範囲検索の Seq Scan 約1.8秒は照合順序の比較のため | `collate-20260928.out`（既定と `COLLATE "C"` を交互に2回ずつ） | DB の照合は `en_US.utf8`（libc）。2,347/2,313 ms と 66/65 ms。返すレコード数・除外したレコード数は同じ |
| books は shared_buffers の1/4を超える | `pg_relation_size('books')`、`SHOW shared_buffers` | 57 MB（7,353ページ）、128MB |
| 64kB で Memory Usage 1249kB | PostgreSQL 18 のリリースノートを確認 | バッチ数の決め方の変更は見つからず。内訳は確かめていない |
