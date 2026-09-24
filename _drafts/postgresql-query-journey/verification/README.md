# 新構成の実験手順の確認

2026-09-22、実験用ComposeのPostgreSQL 18.6で、第4・5章の全SQL入力ブロックを抽出し、ON_ERROR_STOPで実行。各章とも終了コード0。観察用booksは1,000行。第4章のSAVEPOINTとROLLBACKを確認。終了後、book_observationスキーマがなく、public.booksが100万行、books_title_idxが残っていることを確認。既存の掲載実測は採取条件を明記して保持し、新しい検証で測った値にすり替えていない。

本全体の通し実行ではなく、順序変更で新設した観察用表の手順を中心に確認した。

## 第1章のバージョン確認出力

2026-09-23にユーザーが共有したSELECT version()の出力を掲載。PostgreSQL 18.6 (Debian 18.6-1.pgdg13+2)、aarch64-unknown-linux-gnu、gcc (Debian 14.2.0-19) 14.2.0、64-bit。プロンプトを除いて転記。今回の再実測ではない。元の構成の原稿は変更していない。

## つなぎ目の修正に伴う追加実測（2026-09-23）

章末の問いと次章冒頭の問いのずれ（3→4、9→10）を直すため、実験用ComposeのPostgreSQL 18.6で追加採取した。

- `chapter-04-page-count-20260923.log`：第4章の観察用トランザクション内で、`public.books`（100万冊・題名索引あり）が57 MB、7,353ページであることと、`books_title_idx`のB-treeが`level=2`（3段）であることを確認。第3章の`shared hit=7353`（Seq Scan）および`hit=1 read=3`（Index Scan）と対応させた。ROLLBACK後にpageinspectとbook_observationが残らないことも確認。
- `chapter-09-joins-20260923.log`：DBに第8章の`reading_records_order_idx`がなかったため、トランザクション内で作成してから第9章の2つの結合SQLを実行し、ROLLBACKした。並列実行とJITは無効、work_mem=4MB。20件はNested Loop（内側にMemoize、Hits 0 / Misses 20）、1週間分はHash Join（Batches 16、temp read/written 7569）。

## 初期100万冊への変更（2026-09-23）

第1章から本100万冊・読了記録200万件を使う変更の実測と、本文から抽出したSQLの検証は[million-start-20260923](million-start-20260923/README.md)を参照。旧版の条件・ログは履歴として保持する。

## 第4章の準備SQLのユーザー提供出力（2026-09-23）

ユーザーが共有したBEGINからSELECT count(*)までの実行結果を、第4章の入力SQLの直後へ掲載。入力とプロンプトを除き、BEGIN、CREATE SCHEMA、CREATE TABLE、ALTER TABLE、INSERT 0 1000、SET、ANALYZE、count=1000を転記した。今回の再実測ではない。トランザクションを開いたまま観察し、章末のROLLBACKで片付ける説明も追記した。

## 第4章の行幅比較のユーザー提供出力（2026-09-23）

ユーザーが共有したSAVEPOINT row_widthからROLLBACK TO SAVEPOINT row_widthまでの出力を掲載。SAVEPOINT、SELECT 1000（2回）、short_bytes=65536、long_bytes=262144、ROLLBACKを転記した。旧版の独立したBEGIN〜ROLLBACKによる出力を置き換え、外側のトランザクションは続くことを説明した。今回の再実測ではない。同じメッセージに含まれるctid検索は結果の行が提示されていないため、その掲載結果は変更していない。

## 第5章の準備と1回目のユーザー提供出力（2026-09-24）

観察用スキーマの準備（count=1000）と、題名検索の実行計画を転記。Seq Scan、actual rows=1.00、loops=1、除外999行、実行時shared hit=8、計画時shared hit=3、Planning Time=0.508 ms、Execution Time=0.168 ms。エージェントによる再実測ではない。今回の2・3回目は未共有のため、既存の3回比較は過去の別実験として明示し、今回の結果と混ぜて比較しない。

## 第5章の4回比較への更新（2026-09-24）

追加共有された計4回の出力をchapter05-user-results-20260924.txtに保存。最初の0.168 msは直前に共有された1回目と同じ出力として扱い、重複して5回とは数えない。本文の旧3回比較と今回の1回目の別掲を、この4回比較へ統合した。実行時間は0.168 / 0.516 / 0.112 / 0.250 ms。すべてSeq Scan・出力1行・除外999行・loops=1・実行時shared hit=8。時間が単調に短くなるという旧説明を、処理方法・行数・アクセスが同じでも上下するという説明へ更新。エージェントによる再実測ではない。

## 第5章の掲載結果を指定の3回へ変更（2026-09-24）

ユーザー指定の新しい3回分をchapter05-user-selected-three-runs-20260924.txtに保存し、本文の掲載計画・比較表・回数・時間の説明を更新。実行時間は0.104 / 0.190 / 0.117 ms、計画時間は0.123 / 0.167 / 0.105 ms。以前の4回分のログは履歴として保持し、今回の比較には混ぜていない。エージェントによる再実測ではない。

## 第5章の追い出し後の3回比較（2026-09-25）

実験用ComposeのPostgreSQL 18.6（検証専用DB `journey_million_20260923`、本100万冊・題名索引あり）で、第5章の観察用トランザクションの中に`CREATE EXTENSION pg_buffercache`と`pg_buffercache_evict_relation('books')`を加え、追い出し直後から同じ題名検索を3回実行した。並列実行とJITは無効、work_mem=4MB、shared_buffers=128MB。各EXPLAIN ANALYZEは1回。ログは`chapter05-evict-20260925.log`。

- 追い出しの結果はevicted=11、flushed=8、skipped=0。内訳は表本体8ページ（挿入直後でdirty）と空き領域マップ3ページ。内訳は別の確認実行`chapter05-evict-forks-20260925.log`で、relforknumber 0が8ページ、1が3ページ、`pg_relation_size`でmain=8・fsm=3・vm=0と確認した。
- 1回目は`shared read=8`、2回目と3回目は`shared hit=8`。Rows Removed by Filterは3回とも999。実行時間は1.079 / 0.040 / 0.073 ms。
- ROLLBACK後にbook_observationスキーマとpg_buffercache拡張が残らず、public.booksが100万行であることを確認。
- これはエージェントによる再実測。2026-09-24のユーザー提供の3回（すべてhit=8）は履歴として保持し、本文の掲載結果はこの再実測に置き換えた。

## 序章の過去実測の移設（2026-09-24）

序章「この数値を測った条件」の出典（2026-09-21、Homebrew PostgreSQL 18.3、一時テーブル、本100万冊・読了記録2,000万件）を、削除した初期版の `_drafts/sql-data-structures/experiments/` から [prologue-ranking-20260921](prologue-ranking-20260921/README.md) へ移した。値は再実測していない。

## 本文初稿の検証記録の移設（2026-09-24）

コピー元の12章版で2026-09-22にまとめた本文初稿の検証記録（第7章の`Memory: 27913kB`、第11章の2接続と可視性、第12章の`EXCEPT ALL`差分など）を、削除した `_drafts/postgresql-structures-explain/reader-verification/` から [first-draft-20260922](first-draft-20260922/README.md) へ移した。章番号は元の12章版のもの。値は再実測していない。
