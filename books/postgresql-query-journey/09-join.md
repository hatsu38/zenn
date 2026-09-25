---
title: "第9章：本と読了記録を組み合わせ、数える"
---

## この章で分かること

読了記録に題名を付け、本ごとに読了記録を数える処理を学びます。少数のレコードを繰り返し探す方法から始め、大量のレコードをハッシュ表で照合する方法、並んだ入力を合流させる方法へ広げます。集約では入力レコード数とグループ数を区別します。結合や集計の前にレコードを減らす案が、同じ答えを返すか、何件分の処理を減らすかを考えます。

:::message
第8章の日時Indexを残して始めます。再接続した場合は第1章末の共通設定を実行し、`work_mem=4MB`、並列実行とJITが無効の状態にします。
:::

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

このような繰り返しが`Nested Loop`です。外側で記録を取り出し、内側で本を探します。内側に効率のよいIndexがあり、外側が少なければ合理的な方法です。名前だけで「遅い結合」と決めないでください。

先ほどのSQLの実行結果です。条件は次のとおりです。

- 2026年9月23日、DockerのPostgreSQL 18.6
- 本100万冊、読了記録200万件
- 第8章の日時順のIndexあり
- 並列実行とJITは無効、`work_mem`は4MB

```sql
Nested Loop  (cost=0.86..90.18 rows=20 width=38) (actual time=0.216..7.073 rows=20.00 loops=1)
  Buffers: shared hit=55 read=29
  ->  Limit  (cost=0.43..1.04 rows=20 width=16) (actual time=0.101..0.111 rows=20.00 loops=1)
        Buffers: shared hit=1 read=3
        ->  Index Only Scan using reading_records_order_idx on reading_records  (cost=0.43..60768.43 rows=2000000 width=16) (actual time=0.097..0.105 rows=20.00 loops=1)
              Heap Fetches: 0
              Index Searches: 1
              Buffers: shared hit=1 read=3
  ->  Memoize  (cost=0.43..8.45 rows=1 width=30) (actual time=0.346..0.346 rows=1.00 loops=20)
        Cache Key: reading_records.book_id
        Cache Mode: logical
        Hits: 0  Misses: 20  Evictions: 0  Overflows: 0  Memory Usage: 3kB
        Buffers: shared hit=54 read=26
        ->  Index Scan using books_pkey on books b  (cost=0.42..8.44 rows=1 width=30) (actual time=0.344..0.344 rows=1.00 loops=20)
              Index Cond: (id = reading_records.book_id)
              Index Searches: 20
              Buffers: shared hit=54 read=26
Planning:
  Buffers: shared hit=105 read=2
Planning Time: 1.981 ms
Execution Time: 7.494 ms
```

外側は、日時順のIndexから20件を取り出す`Limit`です。内側は、主キーのIndexである`books_pkey`で本を1冊探す`Index Scan`で、`loops=20`になっています。記録1件ごとに本を1回探し、それを20回繰り返しました。

内側の`Memoize`は、同じ本の番号をもう一度探すときに、前の結果を使い回すための処理です。今回の20件はすべて別の本だったので、`Hits: 0  Misses: 20`となり、使い回しは起きていません。

計画に`loops=20`があれば、その処理を20回実行しています。`actual rows`や`actual time`は、複数回実行では1回当たりの平均として表示されます。1回1件を20回返せば、全体では20件です。第7章で見たとおり親の時間は子を含むので、親子の時間をすべて足すと子の処理時間を二重に数えることになります。

図で、内側の`Index Scan`の`rows`・`loops`・`Buffers`を、1回当たりの値と20回分の合計に分けて読んでください。

![Nested Loopの内側のIndex Scanはrows=1.00、loops=20で、1回1件を20回返して全体で20件。Buffersのhit=54とread=26は20回分の合計](/images/postgresql-query-journey/09-loops.png)
*rows=1.00とloops=20を掛けると20件です。Buffersのhit=54とread=26は、20回分の合計です（実測）。*

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

実行する前に予想してください。20件のときと同じ`Nested Loop`が選ばれるでしょうか。内側で本を探す回数は何回になるでしょうか。20件のときの`loops=20`を思い出してから、出力を読んでください。

1週間分へ広げたSQLの実行結果です。条件は20件のときと同じです。

```sql
Hash Join  (cost=36689.43..66472.66 rows=500739 width=30) (actual time=307.583..649.631 rows=499998.00 loops=1)
  Hash Cond: (r.book_id = b.id)
  Buffers: shared hit=4207 read=5065, temp read=7569 written=7569
  ->  Index Only Scan using reading_records_order_idx on reading_records r  (cost=0.43..17719.21 rows=500739 width=8) (actual time=0.008..126.412 rows=499998.00 loops=1)
        Index Cond: ((finished_at >= '2026-09-14 00:00:00'::timestamp without time zone) AND (finished_at < '2026-09-21 00:00:00'::timestamp without time zone))
        Heap Fetches: 0
        Index Searches: 1
        Buffers: shared hit=4 read=1915
  ->  Hash  (cost=17353.00..17353.00 rows=1000000 width=30) (actual time=307.533..307.533 rows=1000000.00 loops=1)
        Buckets: 131072  Batches: 16  Memory Usage: 4940kB
        Buffers: shared hit=4203 read=3150, temp written=5943
        ->  Seq Scan on books b  (cost=0.00..17353.00 rows=1000000 width=30) (actual time=0.026..173.931 rows=1000000.00 loops=1)
              Buffers: shared hit=4203 read=3150
Planning:
  Buffers: shared hit=18
Planning Time: 0.170 ms
Execution Time: 664.568 ms
```

今度は`Hash Join`が選ばれました。何十万回も別々に本を探す代わりに、先に照合用のハッシュ表を作る方法です。

まず、本の番号から入れる箱を計算で決めておきます。図では、番号を3で割った余りを箱の番号にします。この、照合に使う値（キー。ここでは本の番号）から置き場所を決める計算を**ハッシュ**と呼びます。

![本1〜9を番号の余りで三つの箱に分け、記録の本8は箱2だけを見て、2と5は一致せず8で一致する](/images/postgresql-query-journey/09-hash-join.png)
*記録の本8は箱2だけを見て、中の2・5・8と番号を比べます（説明するための図）。*

記録の番号が8なら箱2を見ます。ただし箱2には2や5もあります。同じ箱に入ることと番号が等しいことは別なので、最後はキーを比較します。異なるキーが同じ場所に対応することを**衝突**と呼びます。

実際のハッシュ関数は「3で割る」より複雑ですが、置き場所を絞って照合する考え方は同じです。

この掲載例は、テーブルの可視性マップが設定され、`Heap Fetches: 0`となった状態での結果です。第8章でIndexを作った直後は、Bitmap Heap Scanが選ばれたり、Index Only ScanでもHeap Fetchesが出たりします。Indexの定義が同じでもテーブルの保守状態で変わる点は、第11章で扱います。

出力に戻ります。下の`Hash`は、本の一覧100万件からハッシュ表を作っています。上の`Index Only Scan`は1週間分の499,998件を返し、その各レコードをハッシュ表で照合しています。ハッシュ表を作るために読むレコード数は`Hash`の下の`rows`、照合する回数は外側の`rows`で確かめられます。

`Batches: 16`と`temp`の値は、ハッシュ表が作業用メモリに収まらず一時ファイルを使ったことを示します。ハッシュのメモリ量には`work_mem`に加えて`hash_mem_multiplier`も関わります。詳しくは、この章の後半で読みます。

20件のときとSQLの形はほとんど同じです。変わったのは、外側から届く記録の件数でした。外側の推定は、Nested Loopの計画で`rows=20`、Hash Joinの計画で`rows=500739`です。件数の違いを実行前にどう見込んだのかは、第10章で調べます。

## すでに並んでいるなら、合流できる

本の番号が昇順の二つの列を考えます。

- 本：1、2、3、4
- 記録：1、1、3、4

先頭同士を比較し、番号が違えば小さい側を進めます。一致したら組を返します。番号順に並んだ入力をたどって結合する方法が`Merge Join`です。

この例では、記録に1が二つあります。本1の位置を保ったまま、最初の記録1と組にし、続く記録1とも組にします。二件とも返してから次の番号へ進みます。一致するたびに両側を一つずつ進めると、二件目を取りこぼしてしまいます。

![記録を番号順に並べ、本1を保ったまま記録1の二件をそれぞれ返す。次に本2を通過して本3と記録3を組にし、本4と記録4も返す](/images/postgresql-query-journey/09-merge-join.png)
*①では本1の位置を保ち、記録の二つの1をそれぞれ返します。③までに返すのは合計4組です（説明するための図）。*

この図では本の番号は一意です。両側に重複がある一般の結合では、一致する組み合わせをすべて返す必要があります。

Merge Joinを観察するために、実験の間だけ、Hash JoinとNested Loopを選ばないように設定します。`SET LOCAL`の設定は、`BEGIN`で始めたトランザクションの中だけ有効です。最後に`ROLLBACK`すると元に戻ります。

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

2026年9月25日、PostgreSQL 18.6での実行結果です。本100万冊・読了記録200万件、並列実行とJITは無効です。 `work_mem`は4MBです。

:::details Merge Joinの実行結果
```sql
Merge Join  (cost=308490.11..318500.51 rows=220 width=16) (actual time=559.465..559.520 rows=200.00 loops=1)
  Merge Cond: (r.book_id = b.id)
  Buffers: shared hit=10815, temp read=6854 written=12751
  ->  Sort  (cost=308488.69..313488.69 rows=2000000 width=16) (actual time=559.428..559.442 rows=201.00 loops=1)
        Sort Key: r.book_id
        Sort Method: external merge  Disk: 50896kB
        Buffers: shared hit=10811, temp read=6854 written=12751
        ->  Seq Scan on reading_records r  (cost=0.00..30811.00 rows=2000000 width=16) (actual time=0.011..135.107 rows=2000000.00 loops=1)
              Buffers: shared hit=10811
  ->  Index Only Scan using books_pkey on books b  (cost=0.42..10.35 rows=110 width=8) (actual time=0.030..0.043 rows=100.00 loops=1)
        Index Cond: (id <= 100)
        Heap Fetches: 100
        Index Searches: 1
        Buffers: shared hit=4
Planning:
  Buffers: shared hit=12
Planning Time: 0.169 ms
Execution Time: 563.841 ms
```
:::

本の側は主キーのIndexから番号順に100件を返しています。記録の側はSeq Scanで200万件を読み、`Sort Key: r.book_id`で並べ替えました。Sortが親へ返したのは201件ですが、その子の入力は200万件です。並べ替えの準備まで201件で済んだ、とは読めません。

結合が返したのは200件です。このデータでは本1冊に記録が2件ずつあるので、本100冊と組になる記録は200件になります。少数の結果を返すために、大きな並べ替えが追加された例です。方法を固定する設定は仕組みを観察するためで、本番へそのまま持ち込むものではありません。

## 数えるときは、グループごとにメモする

ランキングでは本ごとの件数が必要です。記録が2、1、2、3、2なら、数える途中のメモは次のようになります。

| 読んだ記録 | 1の数 | 2の数 | 3の数 |
| --- | ---: | ---: | ---: |
| 2 | 0 | 1 | 0 |
| 1 | 1 | 1 | 0 |
| 2 | 1 | 2 | 0 |
| 3 | 1 | 2 | 1 |
| 2 | 1 | 3 | 1 |

入力は5件で、最後に残るグループ（本の種類）は3個です。本ごとのカウンタをハッシュ表で探しながら数える方法が`HashAggregate`です。

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, count(*) AS read_count
FROM reading_records GROUP BY book_id;
```

同日の集約の実行結果です。

```sql
HashAggregate  (cost=143311.00..168847.22 rows=991122 width=16) (actual time=586.125..916.907 rows=1000000.00 loops=1)
  Group Key: book_id
  Planned Partitions: 16  Batches: 17  Memory Usage: 8345kB  Disk Usage: 63520kB
  Buffers: shared hit=10811, temp read=6150 written=13645
  ->  Seq Scan on reading_records  (cost=0.00..30811.00 rows=2000000 width=8) (actual time=0.018..125.241 rows=2000000.00 loops=1)
        Buffers: shared hit=10811
Planning Time: 0.069 ms
Execution Time: 951.731 ms
```

入力は200万件、`HashAggregate`が返したグループは100万個です。1冊に2件ずつの記録があるため、件数は半分になりました。`Memory Usage: 8345kB`に加え、`Batches: 17`と`Disk Usage`もあります。100万個のカウンタを一度にメモリへ置けず、一時ファイルも使っています。

別の環境で`GroupAggregate`とSortが見えたら、先に並べ替え、隣り合った同じ番号をまとめる方式です。

| 方法 | 同じ本の記録をどう見つけるか | 必要な準備 |
| --- | --- | --- |
| HashAggregate | 本番号をハッシュ表で探し、カウンタを更新する | グループごとのメモリ。足りなければ一時ファイル |
| GroupAggregate | 番号順に読み、同じ番号が続く間に数える | 入力の順序。なければSortなどで用意 |

## ハッシュ表がメモリに収まらないとき

グループの数が多ければ、メモも多くなります。ハッシュ処理のメモリ上限は、`work_mem`に`hash_mem_multiplier`を掛けて計算します。ただし、管理用の領域などもあるため、出力の`Memory Usage`がこの積を上回ることはあります。プロセス全体の使用量を厳密に止める上限ではありません。

```sql
SHOW work_mem;
SHOW hash_mem_multiplier;
```

実行結果は順に4MBと2です。

```sql
 work_mem
----------
 4MB
(1 row)

 hash_mem_multiplier
---------------------
 2
(1 row)
```

先ほどの1週間分のHash Joinは、`work_mem`が4MBの状態で`Batches: 16`となり、`temp read=7569 written=7569`も出ていました。本100万件のハッシュ表を一度にメモリへ置けず、16個に分けて一時ファイルを使いながら照合したと読めます。

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

:::details 64kBでの実行結果
```sql
Hash Join  (cost=36689.00..89545.86 rows=498993 width=30) (actual time=228.809..523.584 rows=499998.00 loops=1)
  Hash Cond: (r.book_id = b.id)
  Buffers: shared hit=13519 read=4645, temp read=7992 written=7992
  ->  Seq Scan on reading_records r  (cost=0.00..40811.00 rows=498993 width=8) (actual time=0.015..93.837 rows=499998.00 loops=1)
        Filter: ((finished_at >= '2026-09-14 00:00:00'::timestamp without time zone) AND (finished_at < '2026-09-21 00:00:00'::timestamp without time zone))
        Rows Removed by Filter: 1500002
        Buffers: shared hit=10811
  ->  Hash  (cost=17353.00..17353.00 rows=1000000 width=30) (actual time=221.692..221.692 rows=1000000.00 loops=1)
        Buckets: 32768  Batches: 64  Memory Usage: 1236kB
        Buffers: shared hit=2708 read=4645, temp written=6218
        ->  Seq Scan on books b  (cost=0.00..17353.00 rows=1000000 width=30) (actual time=0.004..80.588 rows=1000000.00 loops=1)
              Buffers: shared hit=2708 read=4645
Planning:
  Buffers: shared hit=12
Planning Time: 0.218 ms
Execution Time: 539.429 ms
```
:::

今回の再実行では`Batches: 64`でした。先ほどの4MBの例の16より分割が増え、`temp read/written`は7,992ブロックずつになりました。記録を読む方法もSeq Scanへ変わっています。設定を変えると計画全体が変わることがあるので、時間差のすべてをハッシュの分割だけの効果にはしません。

## 数えてから題名を付けても、同じ答えになる？

題名をすべての記録へ付けてから数える代わりに、本の番号だけで数え、上位20冊を決めてから題名を付けられないでしょうか。

その案には、結合するレコードを減らせる可能性があります。ただし、題名で絞り込む条件があるなら、題名を見る前に上位を決めてよいとは限りません。

課題は、順序を変えても同じ答えになる条件を一つ挙げることです。主キーが一意、記録の番号に対応する本が存在する、といった約束が手掛かりになります。この案は第12章で実際に比べます。その前に、20件と50万件の違いをPostgreSQLが実行前にどう見込んだのかを、次章で調べます。
