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
