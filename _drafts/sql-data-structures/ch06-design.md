# 第6章 設計メモ

対象：`books/sql-data-structures/06-join.md`（新規、未公開）
作成日：2026-09-21
状態：コントローラー判断で確定（ユーザー指示「最後までやっておいて」）

## 目的と成果物

「組み合わせる」。一覧に本の題名を付けるために読了記録と本を JOIN する。20 件のときは Nested Loop（外側の 1 行ごとに内側を 1 回）、500 万件のときは Hash Join（先に本 100 万冊のハッシュ表を作る）、Hash Join を止めると Merge Join（両方を並べて合流）になることを実測で見て、前処理と繰り返しのトレードオフを持ち帰る。数える（GROUP BY）ときもハッシュ表が使われることを見て、第7章のランキングの部品をそろえる。最後に「1 冊の本の読了記録」で book_id の目録を作り、目録が組み合わせの内側にも効くことを見る。

成果物: `06-join.md`、`config.yaml` への追加、実験 SQL とログ（取得済み）、README 追記。

## 決めたこと

1. 章題は「第6章 二つの表を組み合わせる、三つの方法」。ファイルは `06-join.md`。
2. 題材は「最近読み終えた 20 件に本の題名を付ける」（`JOIN books ON b.id = r.book_id ORDER BY finished_at DESC LIMIT 20`）と「1 週間分すべてに題名を付ける」。
3. Nested Loop の内側に Memoize が挟まる（PostgreSQL 18）。「同じ本を二度引かないための覚え書き。この本では読み飛ばす」と一言で済ませる。
4. ハッシュ表は「値から置き場所（バケット）を直接計算する箱。並んでいなくても 1 回で見つかる」と説明する。Hash ノードの Buckets、Batches、Memory Usage を読む。
5. Merge Join は `SET enable_hashjoin = off;` で観察する。「PostgreSQL に計画を選ばせないための実験用の設定。本番で使うものではない」と断り、公式引用を添える。RESET で戻す。
6. 3 つの方法の比較は 1 日分（714,284 件）で行い、Hash Join 約 0.93 秒、Merge Join 約 0.82 秒、Nested Loop 約 2.16 秒（内側 71 万回）の表にする。プランナが Hash Join を選んだこと、実測では Merge Join の方が少し速かったことを正直に書き、理由の分析はしない。
7. 前処理と繰り返しのトレードオフは、Hash 表を作る時間（1 週間分 0.30 秒、1 日分 0.24 秒、1 時間分 0.25 秒とほぼ一定）で示す。1 時間分では前処理が全体の 7 割。
8. `SET work_mem = '8MB'` で Hash の Batches が 8 になることを示し、第4章の外部ソートと同じく「収まらなければ一時ファイルに分ける」と結ぶ。
9. GROUP BY は HashAggregate（本ごとの箱に数を足す）で、100 万グループ、Memory 73,753kB、2.13 秒。第7章のランキングの部品として名前を結ぶ。
10. `CREATE INDEX reading_records_book_id_idx ON reading_records (book_id);` は読者の DB に残す（約 5.3 秒、148MB）。
11. 用語: JOIN（組み合わせる）、外側と内側、Nested Loop、Hash Join、Merge Join、ハッシュ表、バケット、Memoize（名前だけ）、HashAggregate。
12. 図は Mermaid 2 枚（Nested Loop の模型: 外側 20 行 → それぞれ内側の目録を 1 回引く。Hash Join の模型: 本 100 万冊 → ハッシュ表 → 記録 500 万行がそれぞれ 1 回照合）。subgraph と ~~~ は使わない。

## 実測（2026-09-21、Docker postgres:18 = PostgreSQL 18.6、設定 3 つ反映済み、読了記録 2,000 万件、finished_at の目録あり）

生ログ: `_drafts/sql-data-structures/experiments/results/ch06-join-docker-pg18-20260921.txt`

- 20 件に題名: Limit → Nested Loop → 外側 Index Scan Backward（finished_at の目録、hit=23）、内側 Memoize → Index Scan using books_pkey（loops=20）。1 回目 48.582 ms（hit=42 read=61）、2 回目 10.691 ms（hit=103）、3 回目 7.993 ms（hit=103）。103 = 外側 23 + 内側 80（20 回 × 4 ページ）。
- 1 週間分に題名: Hash Join。Hash に books 100 万冊（Buckets 1,048,576、Batches 1、Memory Usage 70,692kB、作るのに約 0.30 / 0.27 秒）。外側は Bitmap Heap Scan（finished_at の目録）。3944.234 / 3879.934 ms。
- 1 日分に題名: Hash Join、932.658 ms（Hash 作成 0.24 秒）。1 時間分: Hash Join、336.760 ms（Hash 作成 0.25 秒）。
- enable_hashjoin off（1 日分）: Merge Join。books を Index Scan using books_pkey（主キー順に 100 万冊、0.15 秒）、記録を Sort（quicksort 46,898kB）、合流。817.604 ms。
- enable_mergejoin も off（1 日分）: Nested Loop。内側 Memoize（loops=714,284）→ Index Scan using books_pkey（loops=608,465）。Buffers shared hit=2,433,849。2164.903 ms。
- work_mem 8MB（1 日分、Hash Join）: Buckets 262,144、Batches 8、Memory Usage 9,866kB、temp read=8306 written=8306。904.119 ms。
- GROUP BY book_id（1 週間分）: HashAggregate、rows 1,000,000、Batches 1、Memory Usage 73,753kB、2130.516 ms。
- 1 冊の本の読了記録（book_id 目録なし）: Sort → Hash Join → Seq Scan on reading_records（20,000,000 行、1.08 秒）と Hash（books 1 冊）。2056.071 ms。
- CREATE INDEX reading_records_book_id_idx: 5340.918 ms。18,937 ページ、148MB。
- 目録あり: Sort → Nested Loop → Index Scan using books_title_idx（1 冊）→ Index Scan using reading_records_book_id_idx（20 行）。1 回目 0.254 ms（hit=6 read=21）、2 回目 0.049 ms（hit=27）。

## 章の構成

### はじめに
第5章で一覧は 20 件を目録から取り出せるようになった。次は題名を付けたい。2 つの表を組み合わせる JOIN の仕組みを、20 件と 500 万件で見比べる。3 段落前後。序章と同じ :::message。

### 一覧に本の題名を付けたい
物語。読了記録には本の番号しかない。題名を出すには本の表と組み合わせる。序章のランキングの SQL にも JOIN があった。「2,000 万件と 100 万冊を組み合わせるって、何をするの？」会話 3 行前後。JOIN の SQL を示す。

### 20件に題名を付けるのに、本の表を何回引くか
予想。選択肢: 20 回（1 件ごとに 1 回）/ 本の表を 1 回全部読む / 2,000 万 × 100 万回。答えは示さない。

### 20件なら20回引く
出力（2 回目）を転記。Limit → Nested Loop → 外側（目録を末尾から 20 行）→ 内側（本の主キーの目録、loops=20）。公式引用（ネステッドループ、loops）。二重ループの説明。Memoize の一言。読んだページ 103 = 23 + 20 × 4 の検算。Mermaid の模型 1 枚。

### 500万件に題名を付けるなら
1 週間分の出力（1 回目）を転記。Hash Join。Hash ノードで本 100 万冊をハッシュ表に載せる（0.30 秒、70MB、Buckets 104 万）。ハッシュ表の説明。公式引用（ハッシュ結合）。外側の 500 万行がそれぞれ 1 回照合。Mermaid の模型 1 枚。1 日分、1 時間分の表（件数、Hash 作成の時間、全体）: 前処理はほぼ一定で、少ない件数では前処理が大半。前処理と繰り返しのトレードオフ。

### 並んでいれば合流できる
「両方を本の番号順に並べてから合流する方法もある」。SET enable_hashjoin = off の断り（公式引用）。1 日分の出力: Merge Join。books は主キーの目録の順に読む（並べ替え不要）、記録は Sort（quicksort 46MB）。第4章の合流と同じ考え。公式引用（マージ結合はソートされた入力）。さらに enable_mergejoin = off で Nested Loop 71 万回（2.16 秒）。RESET。

### 三つの方法の使い分け
表: 方法 / 前処理 / 1 行あたりの仕事 / 向く場面 / 1 日分の実測。Nested Loop は外側が少なく内側に目録があるとき。Hash Join は片方をメモリに載せられる大量の組み合わせ。Merge Join は両方が並んでいる（または並べる価値がある）とき。プランナは見積もりで選ぶ。今回は Hash Join が選ばれたが Merge Join の方が少し速かった（理由は追わない）。work_mem 8MB の Batches 8 を「ハッシュ表も収まらなければ一時ファイルに分ける」として一言（第4章の外部ソートと同じ）。

### 数えるときもハッシュ表を使う
1 週間分を本ごとに数える GROUP BY の出力。HashAggregate、100 万グループ、73MB、2.13 秒。本ごとの箱に数を足していく。序章のランキングの部品（JOIN、GROUP BY、ORDER BY LIMIT）が全部そろった、と一文。

### 一冊の本の読了記録
本の詳細画面に「この本の読了記録」を出したい。book_id の目録がないと Seq Scan で 2,000 万行（2.06 秒）。CREATE INDEX（約 5.3 秒、148MB）で Nested Loop、27 ページ、0.05 ms。目録は組み合わせの内側にも効く。第3章の代償の話を一文で受ける。

### この章で持ち帰ること
- 組み合わせには 3 つの方法があり、前処理と 1 行あたりの仕事のトレードオフで選ばれる
- 20 件なら目録を 20 回引く。500 万件なら片方をハッシュ表にして 1 回ずつ照合する。並んでいれば合流する
- ハッシュ表は数える（GROUP BY）ときにも使われる
- 目録は組み合わせの内側に効く。ただし作る前に、その SQL が何行を扱うかを見る

### 次の章へ
序章のランキングの SQL には、探す、数える、組み合わせる、並べる、上位 20 件の部品が全部入っている。第7章でその実行計画を最初から最後まで読み、どこに時間がかかっているかを確かめて直す。

## 文体と制約
第1章〜第5章と同じ。分量はコードブロックと Mermaid を除いて 7,500〜9,500 字（出力が多いので上限寄りでよい）。

## 対象外
- Memoize の仕組み
- Bitmap Heap Scan の仕組み（第5章で名前だけ紹介済み）
- プランナがどの結合を選ぶかのコスト計算
- Hash Join の Batches の内部（一時ファイルに分けることだけ）
