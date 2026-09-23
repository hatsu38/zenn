# 第7章 設計メモ

対象：`books/sql-data-structures/07-ranking-revisited.md`（新規、未公開）
作成日：2026-09-21
状態：コントローラー判断で確定（ユーザー指示「最後までやっておいて」）

## 目的と成果物

序章のランキング（20 冊を返すのに約 4.6 秒）に戻る。第1章〜第6章でそろえた部品（探す、目録、並べる、上位 k 件、組み合わせる、数える）で 7 段の実行計画を最初から最後まで読み、時間の内訳を出す。序章の問い「どこに時間がかかっているか」に答え、3 つの改善案（目録を足す、SQL を書き直す、集計結果を保存する）を予想してから測り、判断する。最後に本全体の持ち帰りと発展の学びを置く。

成果物: `07-ranking-revisited.md`、`config.yaml` への追加、実験 SQL とログ（取得済み）、README 追記。

## 決めたこと

1. 章題は「第7章 ランキングの時間はどこで使われていたのか」。ファイルは `07-ranking-revisited.md`。
2. いまの環境（Docker 18.6、finished_at と book_id の目録あり、work_mem 64MB）で測った約 5.4 秒を基準にする。序章の 4.6 秒（Homebrew 18.3、目録なし、一時テーブル）は「序章で測った値」として区別し、同じ SQL でも環境と目録で計画と時間が変わると一文書く。
3. 内訳は各ノードの actual time の 2 つ目（そのノードが終わった時刻）から出す。おおよそと断る。
4. Bitmap Heap Scan（第5章で名前だけ）は「目録で行の場所を集めてから、表のページ順に読む」と一言で説明する。
5. 「目録を使わせない」実験は `SET enable_bitmapscan = off; SET enable_indexscan = off;` で行い、第6章と同じく実験用の設定だと断る。序章のときの Seq Scan の形が再現され、5.46 秒で目録ありと 0.1 秒しか違わないことを示す。
6. 案 1 の (finished_at, book_id) の目録は BEGIN と ROLLBACK で試す（602MB、作成に数秒。残さない）。Index Only Scan と Heap Fetches: 0 は一言。VACUUM ANALYZE はその前に実行する（統計情報と可視性マップを整える。発展）。
7. 案 2 の書き換えは「先に読了記録だけを本ごとに数え、上位 20 冊を選んでから、20 冊だけ本と組み合わせる」。第6章の学び（組み合わせる行を減らす、20 件なら Nested Loop）。
8. 案 3 の集計表 `weekly_read_counts` は読者の DB に残す。作成約 2 秒、43MB、100 万行。目録 (read_count DESC, book_id ASC) を付ける。0.04 ms。鮮度との交換（新しい読了記録をいつ反映するか）を序章の二人の案の回収として書く。
9. 推定と実測の節では、rows=5,077,400 と実測 4,999,999、HashAggregate の rows=1,000,000 と実測 1,000,000 を並べ、「今回はほぼ合っていた」。第5章の 28 秒を「見積もりが実測と合わなかった例」として振り返る。統計情報と ANALYZE の公式引用。pg_stats の n_distinct は一言。
10. 二人の判断: まず案 2 を入れる（2 秒）。利用が増えて足りなくなったら案 3。読者にも「自分ならどうするか」を問う。
11. 「この本で身につけたこと」は 6 点（返す量と調べる量 / ページ数で数える / 木 O(log n) / ソート O(n log n) と外部ソート / ヒープと上位 k 件 / ハッシュ表と組み合わせ / 推定と実測）。
12. 「これからの学び」は発展の候補を箇条書きで: 並列読み、VACUUM と MVCC、Memoize、照合順序と前方一致、統計情報と拡張統計、Index Only Scan と可視性マップ。公式文書 14 章「性能に関するヒント」へのリンク。
13. 図は Mermaid 2 枚（いまの計画の行の流れ: Bitmap Index Scan → Bitmap Heap Scan 500 万行 → Hash Join（+ Hash 本 100 万冊）→ HashAggregate 100 万グループ → Sort top-N 20 → Limit。案 2 の流れ: Bitmap Heap Scan 500 万行 → HashAggregate 100 万 → Sort top-N 20 → Nested Loop 20 回 → 結果）。subgraph と ~~~ なし。

## 実測（2026-09-21、Docker postgres:18 = PostgreSQL 18.6、設定 3 つ反映済み）

生ログ: `_drafts/sql-data-structures/experiments/results/ch07-ranking-docker-pg18-20260921.txt`

- 表と目録: books 7,353 ページ 57MB、books_pkey 2,772 22MB、books_title_idx 5,056 40MB、reading_records 108,109 845MB、reading_records_book_id_idx 18,937 148MB、reading_records_finished_at_idx 23,124 181MB。
- ランキング（いまの状態）: Execution Time 5863.603 / 5392.609 / 5340.072 ms。2 回目の各ノードの終わり: Bitmap Index Scan 222.884、Bitmap Heap Scan 778.474（rows 4,999,999）、Seq Scan books 55.447、Hash 198.015（Memory 69,607kB）、Hash Join 3681.418、HashAggregate 5303.584（rows 1,000,000、Memory 98,329kB）、Sort（top-N heapsort 26kB）5390.017、Limit 5390.020。内訳（おおよそ）: 探す 0.78 秒、ハッシュ表 0.20 秒、組み合わせ 2.90 秒、数える 1.62 秒、並べる 0.09 秒。
- 目録を使わせない（enable_bitmapscan と enable_indexscan を off）: Seq Scan on reading_records（855.916 で終わる）→ Hash Join 3737.320 → HashAggregate 5366.477 → 5456.854 ms。
- 案 1（(finished_at, book_id) の目録、ROLLBACK）: 目録 76,998 ページ 602MB。Index Only Scan、Heap Fetches 0。Hash Join 3821.783、HashAggregate 5453.063、Execution Time 5542.512 ms。
- 案 2（先に数える書き換え）: 2167.643 / 2123.680 / 2157.189 ms。HashAggregate（読了記録だけ、rows 1,000,000、Memory 73,753kB）約 2.06〜2.10 秒で終わる → Sort top-N 26kB → Limit 20 → Nested Loop → Index Scan using books_pkey（loops=20）。
- 案 3（集計表）: CREATE TABLE AS 1982.816 ms、CREATE INDEX 329.790 ms、1,000,000 行 43MB。ランキング 0.134 / 0.042 / 0.039 ms。計画: Limit → Nested Loop → Index Only Scan using weekly_read_counts_idx（20 行）→ Index Scan using books_pkey（loops=20）。結果の 20 冊は序章と同じ（id 17、23、32、…、184、read_count 6）。
- 推定と実測: 1 週間分の rows 推定 5,077,400、実測 4,999,999。HashAggregate の rows 推定 1,000,000、実測 1,000,000。pg_stats の n_distinct: book_id 1.038649e+06、finished_at -0.13109528。

## 章の構成

### はじめに
序章の問いに戻る。部品はそろった。計画を全部読み、内訳を出し、直す。3 段落前後。:::message（会話は架空、数値は実測。序章の 4.6 秒とは環境と目録が違う）。

### 序章のランキングをもう一度測る
物語。二人が序章の SQL に戻る。いまの環境で約 5.4 秒。出力（2 回目）を転記。7 段の計画が並ぶ。会話 3 行前後。

### 実行計画を下から上へ読む
ノードごとに 1 段落。Bitmap Index Scan と Bitmap Heap Scan（500 万行）、Seq Scan books と Hash（100 万冊、70MB）、Hash Join（500 万行が出る）、HashAggregate（100 万グループ、98MB）、Sort top-N heapsort と Limit。「そのノードが終わった時刻」で内訳の表。Mermaid（行の流れ）。序章の予想（探す、数える、並べる のどこ？）の答え合わせ: 組み合わせ 2.9 秒と数える 1.6 秒で 8 割。探すは 0.8 秒、並べるは 0.1 秒。

### どの案がいちばん効くか
予想。序章で二人が挙げた案（返す件数を減らす、目録を足す、集計結果を保存する）を受け、3 案（目録を足す、SQL を書き直す、集計結果を保存する）を並べる。「内訳を見たいま、どれが効くと思うか」。会話 3 行前後。

### 案1 目録を足す
目録を使わせない実験（設定 2 つ、断り）で序章の形（Seq Scan）を再現: 5.46 秒。いまの finished_at の目録あり: 5.39 秒。0.1 秒の差。さらに (finished_at, book_id) の目録（602MB）で Index Only Scan にしても 5.54 秒。表。「目録が効くのは探す 0.8 秒の部分だけ。時間の大半は組み合わせと数える」。VACUUM ANALYZE と Heap Fetches 0 は一言（公式引用は可視性マップの文を短く）。ROLLBACK で目録は残さない。

### 案2 数えてから組み合わせる
書き換えの SQL。出力（2 回目）。HashAggregate は読了記録だけを数える（73MB）、Sort top-N で 20 冊、Nested Loop で 20 回だけ本を引く。2.1 秒。Mermaid（案 2 の流れ）。「組み合わせる行が 500 万から 20 になり、100 万冊のハッシュ表も消えた」。第6章の学び。結果の 20 冊が同じことを確認（出力を転記）。

### 案3 集計結果を保存する
序章の二人の案の回収。CREATE TABLE AS（2 秒）、目録、ANALYZE。0.04 ms。表: 3 案の時間。鮮度との交換: 新しい読了記録をいつ反映するか、更新の仕事を誰が払うか。「速さの代わりに、いつ計算するかを設計する」。

### 推定と実測を見比べる
rows 5,077,400 と 4,999,999、1,000,000 と 1,000,000。公式引用（推定行数が実測に近いか、統計情報は概算）。今回は合っていた。第5章の 28 秒は見積もりが実測と離れた例。ANALYZE の役割。仮説を立て、条件を一つ変えて測り、推定と実測を比べる、という手順が本書で繰り返してきたこと。

### 二人の判断
まず案 2（2 秒）。利用が増えたら案 3。20 件の画面に 2 秒をどう見るかは読者へ。会話 3 行前後。

### この本で身につけたこと
6 点の箇条書き。序章の「身につけたいこと」（仮説、実験、改善前後の説明）を受ける。

### これからの学び
発展の候補（箇条書き、各 1 文）と公式文書 14 章へのリンク。実験環境の後片付け（`docker stop`、削除するなら `docker rm -v`）も短く。

## 文体と制約
第1章〜第6章と同じ。分量はコードブロックと Mermaid を除いて 8,000〜9,800 字（最終章なので上限を少し広げる）。

## 対象外
- MVCC と可視性マップの仕組み（一言と引用のみ）
- 拡張統計情報
- マテリアライズドビュー（集計表は通常の表で示す。名前だけ触れてよい）
- 並列読み
