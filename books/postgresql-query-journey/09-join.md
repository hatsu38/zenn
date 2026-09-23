---
title: "第9章：本と読了記録を組み合わせ、数える"
---

## この章で分かること

読了記録に題名を付け、本ごとに読了記録を数える処理を学びます。少数の行を繰り返し探す方法から始め、大量の行をハッシュ表で照合する方法、並んだ入力を合流させる方法へ広げます。集約では入力行数とグループ数を区別し、メモリとの関係も観察します。結合や集計の前に行を減らす案を、意味と仕事量の両面から考える章です。

## はじめに：番号だけでは、何の本か分からない

第8章で取り出した最新20件には、本の番号`book_id`はありますが、題名はありません。一覧に題名を出すには、本の表と対応させます。この対応付けが**結合、JOIN**です。

利用者に題名を表示するには、記録にある番号から本の一覧をたどる必要があります。

![本の番号だけでは、題名が分からない](/images/postgresql-query-journey/09-title-lookup.png)
*学ぶきっかけを描く、説明用の場面。*

同じ番号の行を対応させる操作を、この後で三つの結合方式と比べます。

まずは3件の記録で考えます。

| 記録の本番号 | 本の一覧で探す番号 | 付ける題名 |
| --- | --- | --- |
| 2 | 2 | 海の図鑑 |
| 1 | 1 | 星の図鑑 |
| 2 | 2 | 海の図鑑 |

同じ本を2回読んだ記録があるので、海の図鑑も結果に2回登場します。JOINは、同じ番号を一つにまとめる処理ではありません。

## 20件なら、一つずつ探す

第8章の索引を使い、最近の20件に題名を付けます。

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

一つずつ探す方法を模型にします。

![記録を1件取り出すたびに、本を探す](/images/postgresql-query-journey/09-nested-loop.png)
*Nested Loopの模型 ／ キャッシュによる省略は示さない。*

このような繰り返しが`Nested Loop`です。外側で記録を取り出し、内側で本を探します。内側に効率のよい索引があり、外側が少なければ合理的な方法です。名前だけで「遅い結合」と決めないでください。

先ほどのSQLの実行結果です。2026年9月23日、DockerのPostgreSQL 18.6、本100万冊、読了記録200万件、第8章の日時順の索引がある状態です。並列実行とJITは無効、`work_mem`は4MBです。

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

外側は、日時順の索引から20件を取り出す`Limit`です。内側は、主キーの索引`books_pkey`で本を1冊探す`Index Scan`で、`loops=20`になっています。記録1件ごとに本を1回探し、それを20回繰り返しました。

内側の`Memoize`は、同じ本の番号をもう一度探すときに、前の結果を使い回すための処理です。今回の20件はすべて別の本だったので、`Hits: 0  Misses: 20`となり、使い回しは起きていません。`Memoize`は第10章でも取り上げます。

計画に`loops=20`があれば、その処理を20回実行しています。`actual rows`や`actual time`は、複数回実行では1回当たりの平均として表示されます。1回1行を20回返せば、全体では20行です。親子の時間をすべて足すと、子の処理時間を二重に数えることになるため、単純には合計できません。

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

何十万回も別々に本を探す代わりに、先に照合用の表を作る方法があります。これが`Hash Join`です。

**ハッシュ**は、キーから置き場所を決めるための値を計算する仕組みです。模型として、本の番号を3で割った余りで箱を分けます。

![先に分類し、同じ箱の中で照合する](/images/postgresql-query-journey/09-hash-join.png)
*Hash Joinの模型 ／ 実際のハッシュ関数とは異なる。*

記録の番号が8なら箱2を見ます。ただし箱2には2や5もあります。**同じ箱に入ることと、番号が等しいことは別**なので、最後はキーを比較します。異なるキーが同じ場所に対応することを衝突と呼びます。

実際のハッシュ関数は「3で割る」より複雑ですが、置き場所を絞って照合する考え方は同じです。準備する表のサイズと、探す回数の両方を考えます。

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

今度は`Nested Loop`ではなく`Hash Join`が選ばれました。下の`Hash`で本の一覧100万行からハッシュ表を作り、上の`Index Only Scan`が返す1週間分の499,998件を、そのハッシュ表で照合しています。本を1冊ずつ索引で探す操作を約50万回繰り返す代わりに、表を一度作ってから照合する方法です。

20件のときとSQLの形はほとんど同じです。変わったのは、外側から届く記録の件数でした。

## すでに並んでいるなら、合流できる

本の番号が昇順の二つの列を考えます。

- 本：1、2、3、4
- 記録：1、1、3、4

先頭同士を比較して、小さい側を進めれば対応を探せます。これが`Merge Join`につながります。

![並んだ二つの入力を、先頭から合わせる](/images/postgresql-query-journey/09-merge-join.png)
*Merge Joinの模型 ／ 本の番号は一意、記録は重複あり。*

この模型では本の番号は一意です。両側に重複がある一般の結合では、一致する組み合わせをすべて返す必要があります。

方法を見るために、実験の間だけ候補を制限してみます。

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

Merge Joinが現れたら、入力をどこで並べたかも見てください。結合そのものの処理量が少なくても、入力を並べ替える処理が追加される場合があります。これは仕組みを観察する実験で、本番の方法を固定する勧めではありません。

## 数えるときは、グループごとにメモする

ランキングでは本ごとの件数が必要です。記録が2、1、2、3、2なら、数える途中のメモは次のようになります。

| 読んだ記録 | 1の数 | 2の数 | 3の数 |
| --- | ---: | ---: | ---: |
| 2 | 0 | 1 | 0 |
| 1 | 1 | 1 | 0 |
| 2 | 1 | 2 | 0 |
| 3 | 1 | 2 | 1 |
| 2 | 1 | 3 | 1 |

入力は5件、最後のグループは3個です。ハッシュ表を使って本ごとのカウンタを探すのが`HashAggregate`につながります。

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, count(*) AS read_count
FROM reading_records GROUP BY book_id;
```

別の集約方法が選ばれる場合もあります。`GroupAggregate`とSortが見えたら、並んだ同じキーをまとめる形だと考え、ハッシュ方式と区別してください。

## ハッシュ表がメモリに収まらないとき

グループの数が多ければ、メモも多くなります。ハッシュ処理のメモリ予算は`work_mem`だけでなく、`hash_mem_multiplier`にも関係します。

```sql
SHOW work_mem;
SHOW hash_mem_multiplier;
```

Hash Joinでは`Batches`、集約では方式に応じたメモリやディスクの表示を観察します。先ほどの1週間分のHash Joinは、`work_mem`が4MBの状態で`Batches: 16`となり、`temp read=7569 written=7569`も出ていました。本100万行のハッシュ表を一度にメモリへ置けず、16個に分けて一時ファイルを使いながら照合したと読めます。小さなメモリへ変更して比較するなら、`BEGIN`と`SET LOCAL work_mem = '64kB'`で囲み、同じSQLを実行して`ROLLBACK`します。一時ファイルが増えたかを確かめましょう。

## ランキングの仕事を減らす案

題名をすべての記録へ付けてから数える代わりに、本の番号だけで数え、上位20冊を決めてから題名を付けられないでしょうか。

その案には、結合する行を減らせる可能性があります。ただし、題名で絞り込む条件があるなら、題名を見る前に上位を決めてよいとは限りません。

課題は、**順序を変えても同じ答えになる条件を一つ挙げること**です。主キーが一意、記録の番号に対応する本が存在する、といった約束が手掛かりになります。

この章では、同じ二つの表を結合するSQLで、20件ならNested Loop、1週間分ならHash Joinが選ばれました。どちらの計画でも、外側の推定は`rows=20`と`rows=500739`で、実行する前から件数の違いを見込んでいます。PostgreSQLは、この件数をどうやって見積もり、方法を選んでいるのでしょうか。次章で調べます。
