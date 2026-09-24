# 序章のランキング計測（2026-09-21）

`books/postgresql-query-journey/00-prologue.md` の「この数値を測った条件」の出典。2026-09-24、削除した初期版（`_drafts/sql-data-structures/experiments/`）から、SQLと生ログの3ファイルだけを移した。移す前の計測メモは、コミット 045d5ba の `_drafts/sql-data-structures/experiments/README.md` にある。

## 再実行

リポジトリのルートから、ローカルの実験用DBに接続する。

```bash
psql -X -d postgres -f _drafts/postgresql-query-journey/verification/prologue-ranking-20260921/weekly-ranking.sql
psql -X -d postgres -v book_count=1000 -v record_count=20000 -f _drafts/postgresql-query-journey/verification/prologue-ranking-20260921/weekly-ranking.sql
```

大きい方は本100万冊・読了記録2,000万件。データ領域は約902MB（本の主キーなどは別）を使う。一時テーブルで完結し、最後にROLLBACKする。文ごとのタイムアウトは90秒。既存テーブルは変更しない。

## 計測結果

2026-09-21、Apple M1 Pro / 32GiB RAM / PostgreSQL 18.3 Homebrew。work_mem=64MB、並列実行/JIT無効。読了日時は2026-08-24からの4週間に分布し、9月14日以上・21日未満を対象週にする。人気の偏りは再現していない合成データ。

| 条件 | 3回のpsql経過時間（ms） | 中央値（ms） |
| --- | --- | --- |
| 本1,000冊・記録2万件 | 2.466 / 2.140 / 2.017 | 2.140 |
| 本100万冊・記録2,000万件 | 4630.241 / 4553.647 / 4531.875 | 4553.647 |

生ログ：`results/weekly-ranking-small-pg18.3-20260921.txt` と `results/weekly-ranking-large-pg18.3-20260921.txt`。

大きい方の対象週は4,999,999件。実行計画には読了記録のSeq Scan、Hash Join、HashAggregate、top-N heapsortが現れた。別途計測したEXPLAINのExecution Timeは4611.826ms。集計結果は100万グループ、最後に20行を返す。LIMITだけで集計対象が20件になるわけではない。

本書の主実験（通常テーブル、本100万冊・読了記録200万件）とは別条件。
