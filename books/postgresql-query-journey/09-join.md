---
title: "第9章：JOINと集計は、件数によって方法をどう変えるのか"
---

## この章で分かること

読了記録に題名を付け、本ごとに読了記録を数える処理を学びます。少数のレコードを繰り返し探す方法から始め、大量のレコードをハッシュ表で照合する方法、並んだ入力を合流させる方法へ広げます。集約では入力レコード数とグループ数を区別します。結合や集計の前にレコードを減らす案が、同じ答えを返すか、何件分の処理を減らすかを考えます。

## 番号だけでは、何の本か分からない

第8章で取り出した最新20件には、本の番号`book_id`はありますが、題名はありません。一覧に題名を出すには、記録にある番号からbooksテーブルをたどり、対応するレコードを組み合わせます。この対応付けが**結合（JOIN）**&#8203;です。

![読了記録には本番号2・1・2しかなく、題名は画面の外のbooksテーブルで番号のレコードを探して付ける](/images/postgresql-query-journey/09-title-lookup.png)
*記録の「題名 ？」と、本番号からbooksテーブルへ伸びる1本の線を見てください。*

この対応付けを行う方法は三つあり、件数や入力の並び方によって使い分けられます。この後、順に比べます。

まずは3件の記録で考えます。

| 記録の本番号 | 本の一覧で探す番号 | 付ける題名 |
| --- | --- | --- |
| 2 | 2 | 海の図鑑 |
| 1 | 1 | 星の図鑑 |
| 2 | 2 | 海の図鑑 |

同じ本を2回読んだ記録があるので、海の図鑑も結果に2回登場します。JOINは、同じ番号を一つにまとめる処理ではありません。

## 20件なら、一つずつ探す

第8章のIndexを使い、最近の20件に題名を付けます。

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.book_id, b.title, r.finished_at
FROM (
  SELECT book_id, finished_at FROM reading_records
  ORDER BY finished_at DESC, book_id ASC LIMIT 20
) AS r
JOIN books AS b ON b.id = r.book_id
ORDER BY r.finished_at DESC, r.book_id ASC;
```

括弧の内側で20件を選び、その各記録に本の題名を付けています。本の主キーは一意なので、一つの記録から同じ番号の本が何冊も見つかることはありません。

一つずつ探す方法を図にします。

![①②③の記録（本2・本1・本2）が、同じ本のIndexを1回ずつたどって題名を得る](/images/postgresql-query-journey/09-nested-loop.png)
*同じ本のIndexを3回たどっていることに注目してください（説明するための図）。*

このような繰り返しが`Nested Loop`です。外側で記録を取り出し、内側で本を探します。内側に効率のよいIndexがあり、外側が少なければ合理的な方法です。名前だけでは、遅い結合かどうかは決まりません。

先ほどのSQLの実行結果です。条件は次のとおりです。

- 2026年9月26日、DockerのPostgreSQL 18.6
- 本100万冊、読了記録200万件
- 第8章の日時順のIndexあり
- 並列実行とJITは無効、`work_mem`は4MB

```sql:実行結果
Nested Loop  (cost=0.85..169.89 rows=20 width=38) (actual time=1.082..3.042 rows=20.00 loops=1)
  Buffers: shared hit=50 read=34 written=13
  ->  Limit  (cost=0.43..1.04 rows=20 width=16) (actual time=0.008..0.019 rows=20.00 loops=1)
        Buffers: shared hit=4
        ->  Index Only Scan using reading_records_order_idx on reading_records  (cost=0.43..60768.43 rows=2000000 width=16) (actual time=0.007..0.016 rows=20.00 loops=1)
              Heap Fetches: 0
              Index Searches: 1
              Buffers: shared hit=4
  ->  Index Scan using books_pkey on books b  (cost=0.42..8.44 rows=1 width=30) (actual time=0.150..0.150 rows=1.00 loops=20)
        Index Cond: (id = reading_records.book_id)
        Index Searches: 20
        Buffers: shared hit=46 read=34 written=13
Planning:
  Buffers: shared hit=18 read=2
Planning Time: 0.255 ms
Execution Time: 3.059 ms
```

外側は、日時順のIndexから20件を取り出す`Limit`です。内側は、主キーのIndexである`books_pkey`で本を1冊探す`Index Scan`で、`loops=20`になっています。記録1件ごとに本を1回探し、それを20回繰り返しました。

計画に`loops=20`があれば、その処理を20回実行しています。`actual rows`や`actual time`は、複数回実行では1回当たりの平均として表示されます。1回1件を20回返せば、全体では20件です。第7章で見たとおり親の時間は子を含むので、親子の時間をすべて足すと子の処理時間を二重に数えることになります。

図で、内側の`Index Scan`の`rows`・`loops`・`Buffers`を、1回当たりの値と20回分の合計に分けて読んでください。

![Nested Loopの内側のIndex Scanはrows=1.00、loops=20で、1回1件を20回返して全体で20件。Buffersのhit=46とread=34は20回分の合計](/images/postgresql-query-journey/09-loops.png)
*rows=1.00とloops=20を掛けると20件です。Buffersのhit=46とread=34は、20回分の合計です（実測）。*

図の`rows`と`Buffers`のように、`loops`で割って1回当たりにする項目と、割らずに全部の回を合計する項目があります。

| 項目 | `loops`が複数のときの値 |
| --- | --- |
| `actual time`、`actual`の`rows` | 1回当たりの平均 |
| `Rows Removed by Filter`などの除外したレコード数 | 1回当たりの平均 |
| `Buffers` | 全部の回の合計 |
| `Heap Fetches`、`Index Searches`、`Heap Blocks` | 全部の回の合計 |

平均の項目は`loops`を掛けると全体の量になり、合計の項目はそのまま全体の量です[^loops-source]。

[^loops-source]: どちらになるかは、[EXPLAINの出力を作るPostgreSQL 18のソース](https://github.com/postgres/postgres/blob/REL_18_STABLE/src/backend/commands/explain.c)で、`loops`で割っているかどうかから確かめました。

## 何十万回も探すなら？

対象を1週間の全記録に広げます。

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.book_id, b.title
FROM reading_records AS r
JOIN books AS b ON b.id = r.book_id
WHERE r.finished_at >= timestamp '2026-09-14'
  AND r.finished_at < timestamp '2026-09-21';
```

実行する前に予想してください。20件のときと同じ`Nested Loop`が選ばれるでしょうか。内側で本を探す回数は何回になるでしょうか。20件のときの`loops=20`を思い出してから、先を読んでください。

1週間分の記録が何十万件もあれば、Nested Loopのままでは、本のIndexを何十万回もたどることになります。別々に何十万回も探す代わりに、先に本の一覧を全部読んで、照合用の表を作っておく方法があります。

まず、本の番号から入れる箱を計算で決めておきます。図では、番号を3で割った余りを箱の番号にします。この、照合に使う値（キー。ここでは本の番号）から置き場所を決める計算を**ハッシュ**と呼び、できた照合用の表を**ハッシュ表**と呼びます。

![本1〜9を番号の余りで三つの箱に分け、記録の本8は箱2だけを見て、2と5は一致せず8で一致する](/images/postgresql-query-journey/09-hash-join.png)
*記録の本8は箱2だけを見て、中の2・5・8と番号を比べます（説明するための図）。*

記録の番号が8なら箱2を見ます。ただし箱2には2や5もあります。同じ箱に入ることと番号が等しいことは別なので、最後はキーを比較します。異なるキーが同じ場所に対応することを**衝突**と呼びます。

実際のハッシュ関数は「3で割る」より複雑ですが、置き場所を絞って照合する考え方は同じです。このように、一方の入力でハッシュ表を作り、もう一方の入力を1件ずつハッシュ表で照合する方法が`Hash Join`です。

1週間分へ広げたSQLの実行結果です。条件は20件のときと同じです[^vm-ch09]。

[^vm-ch09]: この掲載例は、テーブルの可視性マップが設定され、`Heap Fetches: 0`となった状態での結果です。可視性マップは、テーブルのページごとに「すべての読み手に見えてよいか」を記録したもので、第11章で扱います。第8章でIndexを作った直後は、Bitmap Heap Scanが選ばれたり、Index Only ScanでもHeap Fetchesが出たりします。

```sql:実行結果
Hash Join  (cost=36689.43..65899.61 rows=488229 width=30) (actual time=220.657..462.415 rows=499998.00 loops=1)
  Hash Cond: (r.book_id = b.id)
  Buffers: shared hit=6482 read=2790 written=94, temp read=7404 written=7404
  ->  Index Only Scan using reading_records_order_idx on reading_records r  (cost=0.43..17277.01 rows=488229 width=8) (actual time=0.009..35.626 rows=499998.00 loops=1)
        Index Cond: ((finished_at >= '2026-09-14 00:00:00'::timestamp without time zone) AND (finished_at < '2026-09-21 00:00:00'::timestamp without time zone))
        Heap Fetches: 0
        Index Searches: 1
        Buffers: shared hit=1919
  ->  Hash  (cost=17353.00..17353.00 rows=1000000 width=30) (actual time=220.387..220.388 rows=1000000.00 loops=1)
        Buckets: 131072  Batches: 16  Memory Usage: 4952kB
        Buffers: shared hit=4563 read=2790 written=94, temp written=5943
        ->  Seq Scan on books b  (cost=0.00..17353.00 rows=1000000 width=30) (actual time=0.008..84.017 rows=1000000.00 loops=1)
              Buffers: shared hit=4563 read=2790 written=94
Planning:
  Buffers: shared hit=15
Planning Time: 0.129 ms
Execution Time: 477.379 ms
```

今度は`Hash Join`が選ばれました。下の`Hash`は、本の一覧100万件からハッシュ表を作っています。上の`Index Only Scan`は1週間分の499,998件を返し、その各レコードをハッシュ表で照合しています。ハッシュ表を作るために読むレコード数は`Hash`の下の`rows`、照合する回数は外側の`rows`で確かめられます。

どちらの入力でハッシュ表を作ったかは、`Hash`の下にある側で読みます。今回は件数の多い本の側（100万件）で作り、少ない記録の側（約50万件）を1件ずつ照合しました。件数の少ない側で作らなかった理由は、この本では確かめていません。

20件のときとSQLの形はほとんど同じです。変わったのは、外側から届く記録の件数でした。外側の推定は、Nested Loopの計画で`rows=20`、Hash Joinの計画で`rows=488229`です。件数の違いを実行前にどう見込んだのかは、第10章で調べます。

ハッシュを使う処理には、ほかの処理にない表示が並びます。

| 表示 | 出る処理 | 読み方 |
| --- | --- | --- |
| `Buckets` | `Hash` | ハッシュ表の箱の数 |
| `Batches` | `Hash`、`HashAggregate` | 何回に分けて処理したか。1なら作業用メモリに収まった |
| `Memory Usage` | `Hash`、`HashAggregate` | 作業用メモリをいちばん多く使ったときの量 |

この出力の`Batches: 16`と`temp`の値は、ハッシュ表が作業用メモリに収まらず、一時ファイルを使ったことを示します。そのとき何をしているかは、この章の後半の「ハッシュ表がメモリに収まらないとき」で見ます。

## すでに並んでいるなら、合流できる

本の番号の列と、記録にある本の番号の列を考えます。

- 本：1、2、3、4
- 記録：3、1、4、1

まず、記録を番号順に並べて1、1、3、4にします。そのうえで先頭同士を比較し、番号が違えば小さい側を進めます。一致したら組を返します。番号順に並んだ入力をたどって結合する方法が`Merge Join`です。両方の入力が結合する番号の順にすでに並んでいるとき、たとえば両方をIndexの順に読めるときは、最初の並べ替えがいらないので向いています。

この例では、記録に1が二つあります。本1の位置を保ったまま、最初の記録1と組にし、続く記録1とも組にします。二件とも返してから次の番号へ進みます。一致するたびに両側を一つずつ進めると、二件目を取りこぼしてしまいます。

![記録を番号順に並べ、本1を保ったまま記録1の二件をそれぞれ返す。次に本2を通過して本3と記録3を組にし、本4と記録4も返す](/images/postgresql-query-journey/09-merge-join.png)
*①では本1の位置を保ち、記録の二つの1をそれぞれ返します。④までに返すのは合計4組です（説明するための図）。*

この図では本の番号は一意です。両側に重複がある一般の結合では、一致する組み合わせをすべて返す必要があります。

Merge Joinを観察するために、実験の間だけ、Hash JoinとNested Loopを選ばないように設定します。`SET LOCAL`の設定は、`BEGIN`で始めたトランザクション（複数の操作をひとまとまりとして扱う単位）の中だけ有効です。最後に`ROLLBACK`で取り消すと、設定も元に戻ります。

```sql
BEGIN;
SET LOCAL enable_hashjoin = off;
SET LOCAL enable_nestloop = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT b.id, r.finished_at
FROM books AS b JOIN reading_records AS r ON r.book_id = b.id
WHERE b.id <= 100;
ROLLBACK;
```

2026年9月26日、PostgreSQL 18.6での実行結果です。本100万冊・読了記録200万件、並列実行とJITは無効、`work_mem`は4MBです。

```sql:実行結果
Merge Join  (cost=308490.01..318500.50 rows=214 width=16) (actual time=563.927..563.970 rows=141.00 loops=1)
  Merge Cond: (r.book_id = b.id)
  …
  ->  Sort  (cost=308488.69..313488.69 rows=2000000 width=16) (actual time=563.892..563.902 rows=142.00 loops=1)
        Sort Key: r.book_id
        Sort Method: external merge  Disk: 50896kB
        …
        ->  Seq Scan on reading_records r  (cost=0.00..30811.00 rows=2000000 width=16) (actual time=0.165..125.741 rows=2000000.00 loops=1)
              …
  ->  Index Only Scan using books_pkey on books b  (cost=0.42..10.30 rows=107 width=8) (actual time=0.028..0.040 rows=100.00 loops=1)
        …
Execution Time: 568.076 ms
```

本の側は主キーのIndexから番号順に100件を返しています。記録の側はSeq Scanで200万件を読み、`Sort Key: r.book_id`で並べ替えました。並べ替えは`external merge`で、一時ファイルを使っています。Sortが親へ返したのは142件ですが、その子の入力は200万件です。並べ替えの準備まで142件で済んだ、とは読めません。

結合が返したのは141件です。本100冊のうち、記録のある本だけが、その本の記録の件数だけ組になります。記録が一度もない本は組になりません。Sortから受け取った142件のうち、最後の1件は番号が100を超えた最初の記録です。Merge Joinはそれを読んで、もう組になる本がないと分かったところで止まりました。少数の結果を返すために、大きな並べ替えが追加された例です。

200万件すべてを並べたのは、`WHERE b.id <= 100`が本の側だけの条件で、読了記録の`r.book_id`には自動で伝わらないためです。`b.id = 42`のような等号の条件なら、PostgreSQLは結合の条件をたどって`r.book_id = 42`も導きますが、`<=`のような範囲の条件は導きません。試しに`AND r.book_id <= 100`を足して同じ設定で実行すると、`Sort`に入るレコードは141件になり、`Sort Method`は`quicksort  Memory: 29kB`に変わりました[^merge-time]。

[^merge-time]: 2026年9月28日に元のSQLと条件を足したSQLを2回ずつ測ると、元のSQLは882msと715ms、条件を足したSQLは79msと66msでした。上の出力の568msは9月26日の測定なので、この2組とは比べません。

この章の方法を固定する設定は仕組みを観察するためで、本番へそのまま持ち込むものではありません。

ここまでで、記録に題名を付ける三つの方法を見ました。20件ならNested Loopが本のIndexを20回たどり、1週間分の約50万件ならHash Joinが本100万件からハッシュ表を作って照合し、Merge Joinは記録200万件を番号順に並べ替えてから本と合流させていました。ランキングには、題名を付けることのほかに、本ごとに記録を数える処理も要ります。

## 数えるときは、グループごとにメモする

ランキングでは本ごとの件数が必要です。記録が2、1、2、3、2なら、数える途中のメモは次のようになります。

| 読んだ記録 | 1の数 | 2の数 | 3の数 |
| --- | ---: | ---: | ---: |
| 2 | 0 | 1 | 0 |
| 1 | 1 | 1 | 0 |
| 2 | 1 | 2 | 0 |
| 3 | 1 | 2 | 1 |
| 2 | 1 | 3 | 1 |

入力は5件で、最後に残るグループ（本の種類）は3個です。

1冊ごとのカウンタは、Hash Joinの図と同じように、本の番号から計算した箱に置きます。記録を1件読むたびに、番号から箱を決め、その箱の中で同じ番号のカウンタを探して1増やします。見つからなければ、その番号のカウンタを新しく作ります。本ごとのカウンタをハッシュ表で探しながら数える方法が`HashAggregate`です。

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, count(*) AS read_count
FROM reading_records GROUP BY book_id;
```

同日の集約の実行結果です。

```sql:実行結果
HashAggregate  (cost=40811.00..41599.81 rows=78881 width=16) (actual time=421.904..611.755 rows=736097.00 loops=1)
  …
  Batches: 21  Memory Usage: 8257kB  Disk Usage: 27752kB
  …
  ->  Seq Scan on reading_records  (cost=0.00..30811.00 rows=2000000 width=8) (actual time=0.178..102.246 rows=2000000.00 loops=1)
        …
```

入力は200万件、`HashAggregate`が返したグループは736,097個です。記録が一度もない本はグループになりません。`Memory Usage: 8257kB`に加え、`Batches: 21`と`Disk Usage`もあります。73万個余りのカウンタを一度にメモリへ置けず、一時ファイルも使っています。どう分けて数えたかは、次の節で見ます。なお、実行前の見積もり`rows=78881`は、実際の736,097個よりかなり少なくなっています。見積もりをどう作っているかは、第10章で調べます。

別の環境で`GroupAggregate`とSortが見えたら、先に並べ替え、隣り合った同じ番号をまとめる方式です。

| 方法 | 同じ本の記録をどう見つけるか | 必要な準備 |
| --- | --- | --- |
| HashAggregate | 本番号をハッシュ表で探し、カウンタを更新する | グループごとのメモリ。足りなければ一時ファイル |
| GroupAggregate | 番号順に読み、同じ番号が続く間に数える | 入力の順序。なければSortなどで用意 |

## ハッシュ表がメモリに収まらないとき

ハッシュ表に入れる本やグループの数が多ければ、ハッシュ表も大きくなります。ハッシュ処理のメモリ上限は、`work_mem`に`hash_mem_multiplier`を掛けて計算します。ただし、出力の`Memory Usage`がこの積を上回ることはあります。プロセス全体の使用量を厳密に止める上限ではなく、目安だと読んでください。

```sql
SHOW work_mem;
SHOW hash_mem_multiplier;
```

実行結果は順に4MBと2です。

```sql:実行結果
 work_mem
----------
 4MB
(1 row)

 hash_mem_multiplier
---------------------
 2
(1 row)
```

### Hash Joinの場合

先ほどの1週間分のHash Joinは、`work_mem`が4MBの状態で`Batches: 16`となり、`temp read=7404 written=7404`も出ていました。本100万件のハッシュ表を一度にメモリへ置けなかったので、16個の組に分けて照合しています。

どの組に入れるかは、箱と同じように、本の番号のハッシュから計算で決めます。本の側でも記録の側でも同じ計算を使うので、同じ番号の本と記録は、必ず同じ組に入ります。そのうえで、次の順に進めます[^hashjoin-batch]。

1. 本を読みながら、1組目の本はメモリのハッシュ表に入れ、2組目以降の本は組ごとの一時ファイルへ書き出す。
2. 記録を読みながら、1組目の記録はその場でハッシュ表と照合し、2組目以降の記録は組ごとの一時ファイルへ書き出す。
3. 2組目の本を一時ファイルから読み戻してハッシュ表を作り直し、2組目の記録を読み戻して照合する。これを最後の組まで繰り返す。

本1〜9と記録4件を、二つの組に分けたときの様子を図にします。

![本と記録を番号の偶数・奇数で2組に分け、1組目の本6・本8はその場で照合し、2組目は一時ファイルへ書き出してから読み戻して本3・本5を照合する](/images/postgresql-query-journey/09-hash-batches.png)
*①〜③は上の手順1〜3に対応します。同じ番号の本と記録が、いつも同じ組に入っていることを見てください（説明するための図。組は偶数と奇数で分けていますが、実際は番号のハッシュから決まります）。*

同じ番号は同じ組にそろうので、ほかの組の本と比べなくても、照合の漏れは出ません。メモリに置くのは、いつも1組分のハッシュ表だけです。

組は箱の別名ではありません。ハッシュ表をいくつに分けて順に作るかの単位で、1組分のハッシュ表の中にも、番号の余りで三つの箱に分けたHash Joinの図のように、箱があります。1週間分の出力の`Buckets: 131072  Batches: 16`は、箱が131,072個あるハッシュ表を、16組に分けて1組ずつ作った、と読めます。

[^hashjoin-batch]: 組を決める計算と、組ごとの一時ファイルへの書き出しは、[PostgreSQL 18のソース](https://github.com/postgres/postgres/blob/REL_18_STABLE/src/backend/executor/nodeHashjoin.c)と、同じフォルダの`nodeHash.c`（`ExecHashGetBucketAndBatch`）で確かめました。組の数は、本を読み始める前に決めます。実行の途中で組を増やしたときは`Batches: 16 (originally 8)`のように元の数も表示されるので（[explain.c](https://github.com/postgres/postgres/blob/REL_18_STABLE/src/backend/commands/explain.c)）、今回の16は最初から決めていた数です。

出力の数字は、この手順と対応しています。親の値は子の値を含むので、`Hash Join`の`written=7404`には、子の`Hash`が手順1で本を書き出した`temp written=5943`が入っています。残りの1,461ブロックは、`Hash Join`自身が手順2で書き出した記録です。`read=7404`は、手順3で、書いた分をすべて読み戻した量です。

さらに小さなメモリで比べるなら、`BEGIN`の後に`SET LOCAL work_mem = '64kB'`を実行し、同じSQLを実行してから`ROLLBACK`します。

```sql
BEGIN;
SET LOCAL work_mem = '64kB';
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.book_id, b.title
FROM reading_records AS r
JOIN books AS b ON b.id = r.book_id
WHERE r.finished_at >= timestamp '2026-09-14'
  AND r.finished_at < timestamp '2026-09-21';
ROLLBACK;
```

64kBでの実行結果です。

```sql:実行結果
Hash Join  (cost=36689.43..65899.61 rows=488229 width=30) (actual time=216.690..418.515 rows=499998.00 loops=1)
  …
  Buffers: shared hit=6404 read=2868, temp read=7824 written=7824
  ->  Index Only Scan using reading_records_order_idx on reading_records r  (cost=0.43..17277.01 rows=488229 width=8) (actual time=0.007..35.118 rows=499998.00 loops=1)
        …
  ->  Hash  (cost=17353.00..17353.00 rows=1000000 width=30) (actual time=216.243..216.244 rows=1000000.00 loops=1)
        Buckets: 32768  Batches: 64  Memory Usage: 1249kB
        …
Execution Time: 432.850 ms
```

今回の再実行では`Batches: 64`でした。先ほどの4MBの例の16より分割が増え、`temp read/written`は7,824ブロックずつになりました。記録を読む方法は、4MBのときと同じIndex Only Scanです。ただし、設定を変えると計画全体が変わることもあるので、時間差のすべてをハッシュの分割だけの効果にはしません。

`Memory Usage`は1249kBでした。`work_mem`の64kBに`hash_mem_multiplier`の2を掛けた128kBを、大きく上回っています。どこまで上回るかの内訳は、この本では確かめていません。

### HashAggregateの場合

HashAggregateも、カウンタのハッシュ表が作業用メモリに収まらないと、組に分けて数えます。上のHash Joinは、本を読み始める前に組の数を決め、最初から2組目以降の本を書き出していました。HashAggregateは、メモリがいっぱいになるまでは、すべての記録をメモリで数えます[^hashagg-spill]。

1. 記録を読みながら、本ごとのカウンタをハッシュ表に作って数える。
2. メモリがいっぱいになったら、それ以上カウンタを増やさない。すでにカウンタがある本の記録は、そのまま数える。カウンタのない本の記録は、番号のハッシュで組に分けて、組ごとの一時ファイルへ書き出す。
3. 記録を読み終えたら、メモリで数え終えたカウンタを親へ返し、ハッシュ表を空にする。
4. 一時ファイルの組を一つずつ読み戻し、同じように数える。その組もメモリに収まらなければ、さらに分ける。

先ほどの記録2、1、2、3、2を、カウンタを2個までしか置けないハッシュ表で数えると、次のように進みます。

![記録2・1・2・3・2を2個までのハッシュ表で数え、カウンタのない本3の記録だけを一時ファイルへ書き出し、本2と本1のカウンタを返した後に本3を読み戻して数える](/images/postgresql-query-journey/09-hashagg-spill.png)
*①〜④は上の手順1〜4に対応します。②で書き出すのは、カウンタのない本3の記録だけです（説明するための図）。*

同じ本の記録は同じ組にそろうので、1冊の件数が二つの組に分かれて数えられることはありません。

[^hashagg-spill]: この順番は、[PostgreSQL 18のソース](https://github.com/postgres/postgres/blob/REL_18_STABLE/src/backend/executor/nodeAgg.c)の冒頭にある「Spilling To Disk」の説明と、`Batches`を数える処理で確かめました。

`HashAggregate`には、`Hash`にない表示が二つあります。

| 表示 | 読み方 |
| --- | --- |
| `Planned Partitions` | 収まらないと実行前に見込んだときに、最初に書き出す組の数として決めておいた数 |
| `Disk Usage` | 一時ファイルをいちばん多く使ったときの量 |

先ほどの集約の`Batches: 21`は、最初にメモリで数えた1回と、後で読み戻して数えた組を合わせた回数です。この集約では`Planned Partitions`が出ていないので、実行前には収まると見込んでいました。見込みが`rows=78881`と少なかったためで、第10章でこの見積もりを直すと、`Planned Partitions`が現れます。

## 数えてから題名を付けても、同じ答えになる？

題名をすべての記録へ付けてから数える代わりに、本の番号だけで数え、上位20冊を決めてから題名を付けられないでしょうか。

その案には、結合するレコードを減らせる可能性があります。ただし、題名で絞り込む条件があるなら、題名を見る前に上位を決めてよいとは限りません。

課題は、順序を変えても同じ答えになる条件を一つ挙げることです。主キーが一意、記録の番号に対応する本が存在する、といった約束が手掛かりになります。この案は第12章で実際に比べます。その前に、20件と50万件の違いをPostgreSQLが実行前にどう見込んだのかを、次章で調べます。

## まとめ

- 結合の方法は件数で変わる。少しの件数を繰り返し探すならNested Loop、大量の照合ならHash Join、並んだ入力どうしならMerge Join。
- `loops`が複数のとき、時間と`rows`は1回当たりの平均、`Buffers`は全部の回の合計として読む。
- 範囲の条件は、結合の相手には自動で伝わらない。両側で絞れるなら、両側に書く。

## 第10章へ

この章では、同じ形のSQLでも、外側から届く記録の件数によってNested Loop、Hash Join、Merge Joinが選び分けられるのを見ました。では、PostgreSQLは実行する前に、20件と約50万件の違いをどうやって見込んだのでしょうか。次章では、推定レコード数と、その材料になる統計情報を調べます。
