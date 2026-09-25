# 疑問からたどる構成案

12章版（`books/postgresql-structures-explain`）の本文・構成メモ・HTML・画像原本とPNGを複製し、章の順序を組み替えた構成案です。元の12章版は2026-09-24に削除しました（コミット 20b1122 で参照できます）。実験用リポジトリのローカルSQLも、この本の初期件数に合わせて更新しています。

## 新しい順序

- 序章：00-prologue.md（旧0章）
- 1：01-explain-basics.md（旧1章）
- 2：02-linear-search.md（旧5章）
- 3：03-btree-index.md（旧6章）
- 4：04-pages-and-storage.md（旧3章）
- 5：05-memory-and-buffers.md（旧4章）
- 6：06-process-and-execution.md（旧2章）
- 7：07-sort.md（旧7章）
- 8：08-top-n-heap.md（旧8章）
- 9：09-join.md（旧9章）
- 10：10-planner-and-statistics.md（旧10章）
- 11：11-mvcc-and-maintenance.md（旧11章）
- 12：12-ranking-revisited.md（旧12章）

## 実験状態の引き継ぎ

- 第1章：本100万冊・記録200万件を初期化する。
- 第2章：同じ100万冊でLIMITの有無と検索する題名を比較する。
- 第3章：題名のIndexを追加し、そのまま保持する。
- 第4・5章：通常テーブルを別スキーマのトランザクション内で作り、1,000冊で観察後にROLLBACK。100万冊とIndexは保持。追加手順は実行確認済み。
- 第6章：100万冊の状態で接続を調べる。掲載する計画も題名のIndexありの100万冊で採取。Sortの説明用の例は別例として区別する。
- 第7章以降：初期データの200万件を使い、並べ替えから進む。

[新しい流れ](book-flow.html) / [章別構成](CHAPTER-SUMMARIES.md)
