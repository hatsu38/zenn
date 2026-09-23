# 付録 設計メモ

対象：`books/sql-data-structures/99-appendix.md`（新規、未公開）
作成日：2026-09-21
状態：コントローラー判断で確定。本文 7 章の最終稿がそろってから書く（用語と SQL を最終稿から引くため）

## 目的

読者が手元で再現するときと、読み終えたあとに引き直すときの道具置き場。新しい説明はしない。

## 構成（h2）

### 実験環境の準備と再開
Docker の起動、接続、設定 3 つ、中断と再開、後片付け。第1章、第2章、第7章から転記。

### 章ごとの実験SQL
章ごとに、読者が打った SQL を順番に列挙する（各章の本文の ```sql ブロックを、章の順に並べ直す）。長い出力は載せない。所要時間の目安（CREATE INDEX 約 14 秒、2,000 万件の INSERT など）を添える。

### 読者のDBの状態の推移
表: 章 / 表と行数 / 目録 / 設定。book-plan.md の「読者の DB の状態の推移」を読者向けに書き直す。

### EXPLAINの読み方早見表
表: 出力の項目 / 意味 / 初出の章。cost、rows、width、actual time、actual rows、loops、Rows Removed by Filter、Buffers（shared hit、read、temp）、Sort Method（quicksort、external merge、top-N heapsort）、Memory Usage、Batches、Index Cond、Filter、Heap Fetches、Planning Time、Execution Time。

### ノードの早見表
表: ノード / この本での言い換え / 初出の章。Seq Scan、Index Scan、Index Scan Backward、Index Only Scan、Bitmap Index Scan と Bitmap Heap Scan、Sort、Limit、Nested Loop、Hash と Hash Join、Merge Join、HashAggregate、Memoize。

### 用語対応表
表: この本の言い方 / 一般的な言い方 / 初出の章。目録＝インデックス、表のページ＝ヒープページ、段数＝木の高さ、全件探索＝シーケンシャルスキャン、合流＝マージ、上位 k 件＝top-N、箱＝バケットなど。

### 計算量のまとめ
表: 記法 / 章 / 何の仕事か / 1,000 倍で何倍。O(1)（ハッシュ表の 1 回の照合）、O(log n)、O(n)、O(n log k)、O(n log n)。

### 発展の学びへの案内
第7章の箇条書きを受け、公式文書の章へのリンク一覧（14 章、11 章、19.4、19.7、66.6、F.23）。

## 制約
- 本文と同じ文体規約。表が中心なので分量は 3,000〜5,000 字。
- 新しい数値を出さない。出す数値は各章の本文にあるものだけ。
- Mermaid は使わない。
