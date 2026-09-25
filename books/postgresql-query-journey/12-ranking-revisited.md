---
title: "第12章：ランキングを読み解き、改善を選ぶ"
---

## この章で分かること

序章のランキングを、ここまで学んだ観察方法、アルゴリズム、内部構造から読み解きます。Indexの追加、集計と結合の順序の変更、事前集計について、減る処理と残る処理を予想して比較します。結果が同じか、必要な鮮度を満たすか、更新の負担は何かも確かめます。AIや検索で得た案を、自分の条件と根拠で判断するところまでを本の到達点にします。

:::message
第8章の日時Indexが必要です。一時ビューはこの章で作ります。読み直しで集計テーブルが残っている場合は、第1章末の再開手順で片付けます。
:::

## 最初の問いに戻る

「20冊のランキングなのに、なぜ待たされる？」

序章では、返す冊数しか手掛かりがありませんでした。今なら、ランキングの処理を次の四つに分けられます。

1. テーブルを読む。
2. 記録と本を対応させる。
3. 本ごとに数える。
4. 上位を選ぶ。

さらに、これらの処理はページを読み、メモリを使います。どの方法で行うかは統計をもとに選ばれ、テーブルの更新状態にも影響されます。この章では、ページは`BUFFERS`（第3章と第5章）、メモリは`Sort Method`と`Batches`（第7章と第9章）、統計は`rows`と`actual rows`（第10章）、更新状態は`Heap Fetches`（第11章）として、一つの計画の中で読みます。

この章の基準は、手元の本100万冊と読了記録200万件です。序章の2,000万件や約4.6秒とは条件が違うので、改善前後はここで測り直します。

序章では、Indexの追加、読了記録をあらかじめ数えておく方法、表示を10冊に減らす案の三つを挙げました。この章では、Indexを案1、第9章で出てきた「数えてから題名を付ける」を案2、前もって数える事前集計を案3として比べ、10冊に減らす案は第8章の結果から考えます。

![今週のランキング画面の横に、案1〜3と四つの観点の空欄の表がある](/images/postgresql-query-journey/12-decision-notebook.png)
*案1〜3と四つの観点をならべた表は、まだ空欄です（学ぶきっかけを描く、説明用の場面）。*

## 基準となるSQLを残す

psqlを再接続した場合も、同じ設定から始めます。

```sql
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
SELECT count(*) FROM books;
SELECT count(*) FROM reading_records;
```

比較では同じSQLを何度も使うので、その接続の中だけで使えるビューを作ります。ビューは検索に付けた名前で（第6章）、結果そのものは保存しません。接続を閉じると消えるので、再開時は作り直します。

```sql
CREATE TEMP VIEW ranking_before AS
SELECT b.id, b.title, count(*) AS read_count
FROM books AS b
JOIN reading_records AS r ON r.book_id = b.id
WHERE r.finished_at >= timestamp '2026-09-14'
  AND r.finished_at < timestamp '2026-09-21'
GROUP BY b.id, b.title
ORDER BY read_count DESC, b.id ASC
LIMIT 20;

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM ranking_before;
```

2026年9月25日、PostgreSQL 18.6での実行結果です。本100万冊・読了記録200万件、並列実行とJITは無効です。 次の計画は、第1章から第10章まで進めた後、第11章のVACUUM実験より前に採取しました。章末には、第11章の実験後に3回ずつ測った比較も載せます。

:::details 基準SQLの実行結果
```sql
Limit  (cost=144679.49..144679.54 rows=20 width=38) (actual time=845.097..845.109 rows=20.00 loops=1)
  Buffers: shared hit=15508 read=4574, temp read=9964 written=12569
  ->  Sort  (cost=144679.49..145926.97 rows=498993 width=38) (actual time=845.096..845.105 rows=20.00 loops=1)
        Sort Key: (count(*)) DESC, b.id
        Sort Method: top-N heapsort  Memory: 27kB
        Buffers: shared hit=15508 read=4574, temp read=9964 written=12569
        ->  HashAggregate  (cost=119589.36..131401.46 rows=498993 width=38) (actual time=692.218..802.384 rows=492722.00 loops=1)
              Group Key: b.id
              Planned Partitions: 8  Batches: 9  Memory Usage: 8281kB  Disk Usage: 23568kB
              Buffers: shared hit=15508 read=4574, temp read=9964 written=12569
              ->  Hash Join  (cost=49484.11..79825.86 rows=498993 width=30) (actual time=206.603..553.852 rows=499998.00 loops=1)
                    Hash Cond: (r.book_id = b.id)
                    Buffers: shared hit=15508 read=4574, temp read=7441 written=7441
                    ->  Bitmap Heap Scan on reading_records r  (cost=12795.11..31091.00 rows=498993 width=8) (actual time=21.234..84.550 rows=499998.00 loops=1)
                          Recheck Cond: ((finished_at >= '2026-09-14 00:00:00'::timestamp without time zone) AND (finished_at < '2026-09-21 00:00:00'::timestamp without time zone))
                          Heap Blocks: exact=10811
                          Buffers: shared hit=12729
                          ->  Bitmap Index Scan on reading_records_order_idx  (cost=0.00..12670.36 rows=498993 width=0) (actual time=20.191..20.191 rows=499998.00 loops=1)
                                Index Cond: ((finished_at >= '2026-09-14 00:00:00'::timestamp without time zone) AND (finished_at < '2026-09-21 00:00:00'::timestamp without time zone))
                                Index Searches: 1
                                Buffers: shared hit=1918
                    ->  Hash  (cost=17353.00..17353.00 rows=1000000 width=30) (actual time=184.698..184.704 rows=1000000.00 loops=1)
                          Buckets: 131072  Batches: 16  Memory Usage: 4872kB
                          Buffers: shared hit=2779 read=4574, temp written=5815
                          ->  Seq Scan on books b  (cost=0.00..17353.00 rows=1000000 width=30) (actual time=0.008..71.297 rows=1000000.00 loops=1)
                                Buffers: shared hit=2779 read=4574
Planning:
  Buffers: shared hit=21
Planning Time: 0.199 ms
Execution Time: 847.516 ms
```
:::

下から読むと、対象週499,998件を取り出し、Hash Joinで同じ499,998件へ題名を付けています。HashAggregateで492,722冊に数え、最後のSortとLimitで20冊を選びました。20件へ減るのは、題名を付けた後です。

自分の環境でも、レコード数、方式、時間、BUFFERSを残してください。キャッシュや実行順でも時間は変わるので、1回だけの小さな差で勝ち負けを決めません。

## 案1：Indexで減る処理を確かめる

第8章で日時順のIndexを作りました。いまの計画は、それを使っているでしょうか。使っていても、その後の結合や集約に渡すレコードが多ければ、そこには処理が残ります。

比較の手掛かりとして、実験の間だけIndexを使わないようにした計画も見ます。

```sql
BEGIN;
SET LOCAL enable_indexscan = off;
SET LOCAL enable_indexonlyscan = off;
SET LOCAL enable_bitmapscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM ranking_before;
ROLLBACK;
```

:::details Indexを使う候補を制限した実行結果
```sql
Limit  (cost=154399.49..154399.54 rows=20 width=38) (actual time=876.207..876.217 rows=20.00 loops=1)
  Buffers: shared hit=13684 read=4480, temp read=9964 written=12569
  ->  Sort  (cost=154399.49..155646.97 rows=498993 width=38) (actual time=876.206..876.214 rows=20.00 loops=1)
        Sort Key: (count(*)) DESC, b.id
        Sort Method: top-N heapsort  Memory: 27kB
        Buffers: shared hit=13684 read=4480, temp read=9964 written=12569
        ->  HashAggregate  (cost=129309.36..141121.46 rows=498993 width=38) (actual time=706.797..829.648 rows=492722.00 loops=1)
              Group Key: b.id
              Planned Partitions: 8  Batches: 9  Memory Usage: 8281kB  Disk Usage: 23568kB
              Buffers: shared hit=13684 read=4480, temp read=9964 written=12569
              ->  Hash Join  (cost=36689.00..89545.86 rows=498993 width=30) (actual time=182.946..570.437 rows=499998.00 loops=1)
                    Hash Cond: (r.book_id = b.id)
                    Buffers: shared hit=13684 read=4480, temp read=7441 written=7441
                    ->  Seq Scan on reading_records r  (cost=0.00..40811.00 rows=498993 width=8) (actual time=0.062..102.692 rows=499998.00 loops=1)
                          Filter: ((finished_at >= '2026-09-14 00:00:00'::timestamp without time zone) AND (finished_at < '2026-09-21 00:00:00'::timestamp without time zone))
                          Rows Removed by Filter: 1500002
                          Buffers: shared hit=10811
                    ->  Hash  (cost=17353.00..17353.00 rows=1000000 width=30) (actual time=179.468..179.469 rows=1000000.00 loops=1)
                          Buckets: 131072  Batches: 16  Memory Usage: 4872kB
                          Buffers: shared hit=2873 read=4480, temp written=5815
                          ->  Seq Scan on books b  (cost=0.00..17353.00 rows=1000000 width=30) (actual time=0.010..68.463 rows=1000000.00 loops=1)
                                Buffers: shared hit=2873 read=4480
Planning:
  Buffers: shared hit=12
Planning Time: 0.186 ms
Execution Time: 878.667 ms
```
:::

日時のIndexを使ったBitmap Heap Scanから、200万件を読むSeq Scanへ変わりました。ただし、どちらも結合へ渡すレコードは499,998件で、その後の集計と上位選びも残ります。Indexだけでランキング全体の処理がなくなるわけではありません。

これはIndexを物理的に削除した測定ではなく、候補を制限する診断実験です。この2回の時間差だけではIndexの効果を断定せず、アクセス方法と後続へ渡すレコード数を対応させて読みます。

## レコードの数が、どこで変わる？

次の案を考える前に、6件の読了記録から上位2冊を返す小さな例で、レコード数の変わり方を見ます。題名を付ける段階では何件あるかを見てください。図は処理を整理した例で、実行計画のノードが必ずこの順に並ぶわけではありません。

![6記録すべてに題名を付けてから数え、上位2冊だけが残る](/images/postgresql-query-journey/12-ranking-before.png)
*題名を付ける段階が6件のままである点に注目してください（実際は499,998件、図は6記録）。*

レコードが20件まで減るのが最後の段なら、それより前の段では多くのレコードを扱うことになります。推定レコード数と実測レコード数も比べましょう。見積もりが外れている問題と、見積もりが合っていても処理が多い問題は分けます。

時間の読み方は第7章と第9章のとおりで、親の時間は子を含み、`loops`が複数なら1回当たりの平均です。時間の数字を「クエリ開始から何秒後」として引き算しないでください。まずレコード数と方式から、減らせそうな処理を探します。

## 案2：数えてから、題名を付ける

第9章の問いを試します。まず本の番号だけで数え、上位20冊を選んでから、本の題名を付けます。

```sql
CREATE TEMP VIEW ranking_after AS
SELECT b.id, b.title, top_books.read_count
FROM (
  SELECT book_id, count(*) AS read_count
  FROM reading_records
  WHERE finished_at >= timestamp '2026-09-14'
    AND finished_at < timestamp '2026-09-21'
  GROUP BY book_id
  ORDER BY read_count DESC, book_id ASC
  LIMIT 20
) AS top_books
JOIN books AS b ON b.id = top_books.book_id
ORDER BY top_books.read_count DESC, b.id ASC;

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM ranking_after;
```

同じ6件の例で、先に数えて上位2冊を選びます。前の図と並べて、題名を付ける対象が何件になるかを見てください。

![6件の読了記録を本ごとに数え、本1が3件・本2が2件・本3が1件になり、上位2冊の本1と本2だけに題名を結び付ける](/images/postgresql-query-journey/12-ranking-after.png)
*本ごとに数えてから、上位2冊だけに題名を結び付けます（説明するための図）。*

どこへ渡すレコードが少なくなるか予想してから、実際の計画を読みましょう。

:::details 集計してから題名を付けた実行結果
```sql
Nested Loop  (cost=79010.08..79178.76 rows=20 width=38) (actual time=315.882..316.888 rows=20.00 loops=1)
  Buffers: shared hit=12803 read=6, temp read=1366 written=3079
  ->  Limit  (cost=79009.66..79009.71 rows=20 width=16) (actual time=315.840..315.844 rows=20.00 loops=1)
        Buffers: shared hit=12729, temp read=1366 written=3079
        ->  Sort  (cost=79009.66..80098.98 rows=435730 width=16) (actual time=315.838..315.841 rows=20.00 loops=1)
              Sort Key: (count(*)) DESC, reading_records.book_id
              Sort Method: top-N heapsort  Memory: 26kB
              Buffers: shared hit=12729, temp read=1366 written=3079
              ->  HashAggregate  (cost=59159.36..67415.04 rows=435730 width=16) (actual time=195.561..285.591 rows=492722.00 loops=1)
                    Group Key: reading_records.book_id
                    Planned Partitions: 8  Batches: 9  Memory Usage: 8281kB  Disk Usage: 15248kB
                    Buffers: shared hit=12729, temp read=1366 written=3079
                    ->  Bitmap Heap Scan on reading_records  (cost=12795.11..31091.00 rows=498993 width=8) (actual time=19.915..72.414 rows=499998.00 loops=1)
                          Recheck Cond: ((finished_at >= '2026-09-14 00:00:00'::timestamp without time zone) AND (finished_at < '2026-09-21 00:00:00'::timestamp without time zone))
                          Heap Blocks: exact=10811
                          Buffers: shared hit=12729
                          ->  Bitmap Index Scan on reading_records_order_idx  (cost=0.00..12670.36 rows=498993 width=0) (actual time=18.809..18.809 rows=499998.00 loops=1)
                                Index Cond: ((finished_at >= '2026-09-14 00:00:00'::timestamp without time zone) AND (finished_at < '2026-09-21 00:00:00'::timestamp without time zone))
                                Index Searches: 1
                                Buffers: shared hit=1918
  ->  Index Scan using books_pkey on books b  (cost=0.42..8.44 rows=1 width=30) (actual time=0.051..0.051 rows=1.00 loops=20)
        Index Cond: (id = reading_records.book_id)
        Index Searches: 20
        Buffers: shared hit=74 read=6
Planning:
  Buffers: shared hit=7
Planning Time: 0.203 ms
Execution Time: 318.503 ms
```
:::

記録499,998件を数える処理は残っています。一方、Limitが先に20冊を選び、その後の`books_pkey`のIndex Scanは`rows=1 loops=20`です。題名を探す処理が20回になりました。基準SQLのHash Joinでは499,998件を照合していたので、ここが減った処理です。

## 速くても、答えが変わったら困る

今回の書き換えが同じ結果を返すには、次の三つが前提です。

- 本の番号が一意である。
- 各記録に対応する本が存在する。
- 題名による絞り込みがない。

今回は外部キー制約（記録の本番号がbooksテーブルに必ずあることを保証する約束）を付けていません。そこで、booksテーブルに番号が見つからない記録が0件かどうかを確かめます。

```sql
SELECT count(*) AS records_without_book
FROM reading_records AS r
WHERE NOT EXISTS (SELECT 1 FROM books AS b WHERE b.id = r.book_id);
```

実行結果です。

```sql
 records_without_book
----------------------
                    0
(1 row)
```

対応する本のない記録は0件でした。0でなければ、先に上位を決める方法で結果が変わる可能性があります。

両方の結果に差がないかも調べます。

```sql
SELECT count(*) AS differing_rows FROM (
  (SELECT * FROM ranking_before EXCEPT ALL SELECT * FROM ranking_after)
  UNION ALL
  (SELECT * FROM ranking_after EXCEPT ALL SELECT * FROM ranking_before)
) AS differences;
```

実行結果です。

```sql
 differing_rows
----------------
              0
(1 row)
```

このデータでは、レコードの内容と個数に差がありませんでした。ただし、この比較は表示順を調べません。両方のSQLで読了数の降順、同数なら本番号の昇順を指定していることも確認します。

一つのデータで一致したことだけで、あらゆる場合の証明になるわけではありません。なぜ同じ結果になるかという前提と、実際の確認の両方が必要です。

## 案3：表示する前に数えておく

今度は、集計結果を本当にテーブルへ保存します。ビューと違って、値を持つテーブルです。

```sql
\timing on
CREATE TABLE weekly_read_counts AS
SELECT book_id, count(*) AS read_count
FROM reading_records
WHERE finished_at >= timestamp '2026-09-14'
  AND finished_at < timestamp '2026-09-21'
GROUP BY book_id;
CREATE INDEX weekly_read_counts_order_idx
ON weekly_read_counts (read_count DESC, book_id ASC);
ANALYZE weekly_read_counts;

EXPLAIN (ANALYZE, BUFFERS)
SELECT b.id, b.title, w.read_count
FROM weekly_read_counts AS w JOIN books AS b ON b.id = w.book_id
ORDER BY w.read_count DESC, w.book_id ASC LIMIT 20;
```

同日の準備の実行結果です。psqlが測った経過時間も分けて残します。

```sql
SELECT 492722
Time: 478.098 ms
CREATE INDEX
Time: 211.821 ms
ANALYZE
Time: 21.638 ms
```

作成済みのテーブルから読み出した実行結果です。

:::details 事前集計テーブルの読み出し
```sql
Limit  (cost=0.85..12.21 rows=20 width=46) (actual time=0.030..0.097 rows=20.00 loops=1)
  Buffers: shared hit=100 read=3
  ->  Nested Loop  (cost=0.85..279979.69 rows=492722 width=46) (actual time=0.029..0.095 rows=20.00 loops=1)
        Buffers: shared hit=100 read=3
        ->  Index Only Scan using weekly_read_counts_order_idx on weekly_read_counts w  (cost=0.42..21558.21 rows=492722 width=16) (actual time=0.024..0.052 rows=20.00 loops=1)
              Heap Fetches: 20
              Index Searches: 1
              Buffers: shared hit=20 read=3
        ->  Index Scan using books_pkey on books b  (cost=0.42..0.52 rows=1 width=30) (actual time=0.002..0.002 rows=1.00 loops=20)
              Index Cond: (id = w.book_id)
              Index Searches: 20
              Buffers: shared hit=80
Planning:
  Buffers: shared hit=18 read=1
Planning Time: 0.179 ms
Execution Time: 0.111 ms
```
:::

集計テーブルのIndexから20件を取り出し、本の題名を20回探しています。表示時の計画にはAggregateもSortもありません。ただし、作成直後の集計テーブルでは`Heap Fetches: 20`となり、テーブルのレコードも確認しています。第11章と同じく、値がIndexにあることと、テーブルへの確認を省けることは別です。その準備として、492,722件のテーブルとIndexを作った負担が別にあります。

中身は記録が増えたり週が替わったりするたびに作り直すか更新します。ここで測った作成時間は初回の値で、運用中の継続更新や同時アクセスの負担はまだ測っていません。psqlの経過時間とEXPLAINのExecution Timeは測る範囲も違うので、混ぜて一つの処理時間にはしません。

事前集計を使うと、表示時に読了記録を数える必要がなくなります。その代わり、集計テーブルの作成や更新時に記録を数えます。比較では、読み出しと集計テーブルの更新を分けて測ります。

![集計テーブルが3件のまま読了記録が1件増え、数え直すまで画面はその3件を上位20件として表示する](/images/postgresql-query-journey/12-preaggregation.png)
*オレンジの帯「表示が古い時間」を見てください（説明するための図）。*

事前集計には、結果を保存するマテリアライズドビューを更新する方法や、トリガーなどで変更を反映する方法もあります。どの仕組みでも、更新の負担と表示の鮮度を一緒に考えます。

では、更新前に新しい記録が届いたらどうでしょう。表示は最新より少し古くなります。削除や訂正、週の切り替わりも反映する必要があります。

## 10冊に減らせば、速くなる？

序章の三つめの案は、表示を20冊から10冊に減らすことでした。第8章のtop-N heapsortを思い出してください。順序が分からない入力から上位を選ぶには、入力を最後まで確かめる必要がありました。LIMITを小さくすると、候補として保持する件数と、返す件数は減りますが、入力を調べる件数は減りません。

基準のランキングSQLが、対象週の記録をすべて集計してからtop-Nで選ぶ計画なら、同じことが言えます。20冊を10冊にしても、対象週の記録を読み、本ごとに数える処理は残ります。上位を選ぶ段より前のレコード数が変わったかを、実行計画で確かめます。

一方、案2のように上位を選んだ後で題名を付けるなら、結合する件数も20件から10件へ減らせます。案3で件数順のIndexから取り出す計画なら、集計テーブルから取り出す件数も減らせます。どの案でも同じ効果とは限らないので、LIMITの前後にどの処理があるかを見て判断します。

## このサービスで、何を選ぶ？

第11章の更新とVACUUMの実験後、同じDBで3方式を3回ずつ測りました。PostgreSQL 18.6、`work_mem=4MB`、並列実行とJITは無効です。キャッシュを空にせず、基準SQL、案2、案3の順に実行しました。他のDBも動く共有コンテナでの値なので、改善倍率を他環境へ当てはめるための測定ではありません。

| 方式 | 3回のExecution Time（ms） | 中央値（ms） | 減った処理・残った負担 |
| --- | --- | ---: | --- |
| 日時Indexを使う基準SQL | 695.730 / 703.906 / 684.870 | 695.730 | 期間で絞れても、499,998件の結合と集計が残る |
| 案2：集計後に題名を付ける | 240.353 / 242.852 / 256.120 | 242.852 | 題名を探すのは20回。期間内の集計は残る |
| 案3：作成済みの集計テーブルを読む | 0.120 / 0.038 / 0.034 | 0.038 | 表示時の集計が消える。集計テーブルの作成・更新は別に必要 |

この再測定では、基準SQLと案2の記録の取得がIndex Only Scanになりました。先に載せたBitmap Heap Scanの計画と違うのは、VACUUMなどを経てテーブルの状態と統計が変わった後だからです。取得方法が変わっても、基準では約50万件へ題名を付け、案2では20件へ付けるという違いは残りました。

ここでは「新しい記録を次の表示に反映したい」「まずは数百ミリ秒程度まで短くしたい」というサービスの条件を置き、**日時Indexを残して案2を採用する**判断にします。別の集計テーブルを維持せず、今回の測定では約243msまで短くなり、結果の同値性も確認できたためです。これは今回の条件での判断で、応答時間の保証ではありません。

「多数のアクセスでも、さらに短い応答が必要」「5分前までの集計でよい」という条件なら案3を次に検証します。更新が5分以内に完了するか、更新中も表示できるか、訂正・削除・週替わりを正しく反映できるかを確かめてから採用します。0.038msという読み出しだけの値では、その判断まで済みません。

:::details 調査メモの完成例
- 困りごと：20冊の表示なのに、結合へ約50万件が渡っていた。
- 仮説：本番号で集計し、上位を決めてから題名を付ければ結合対象を減らせる。
- そろえた条件：同じDB、期間、Index、設定で比較した。時間の測定は第11章の実験後にまとめて行った。
- 観察：題名の取得が20回になり、3回の中央値は695.730msから242.852msへ変わった。
- 正しさ：対応する本のない記録は0件、双方向の差分も0件。主キーと並び順も確認した。
- 判断：今回は案2。継続更新の仕組みが必要になる案3は、負荷と鮮度の条件を決めてから検証する。
- 残る疑問：実際の人気の偏り、同時アクセス、対象期間の変更でも同じ計画と応答になるか。
:::

基本データでは、各本の全期間の記録はちょうど2件ずつです。対象週は1件の本が485,446冊、2件の本が7,276冊で、上位20冊もすべて2件です。これは仕組みを観察しやすくするためのデータで、現実の人気の分布を再現したものではありません。少数の本へ記録が集中すれば、集計後のグループ数や、集計を先にする効果も変わります。実サービスへ当てはめるときは、自分のデータの偏りも調べます。

## 最後の課題：AIの案を検証する

AIから「`work_mem`を増やすと改善します」と提案されたとします。すぐに採用する前に、次の短い調査メモを書いてください。

1. このSQLで減るはずの処理は何か。
2. データ量、Index、設定、更新状態をどうそろえるか。
3. どの計画、レコード数、ページアクセスを見るか。
4. 結果が同じことをどう確認するか。
5. 時間と運用上の負担から、何を採用するか。
6. まだ分からず、追加で調べたいことは何か。

対象期間を1日、1週間、全期間に変えた場合も、同じ結論でしょうか。一度の成功から適用範囲を考えることが、学んだ仕組みを使う練習になります。

## 調べたいことから、仕組みへ戻る

読了後、自分のSQLを調べるときは、次の表を入口にしてください。

| 仕組み | 処理中に持つもの・必要な前提 | 実行計画で見るところ | 戻る章 |
| --- | --- | --- | --- |
| 線形探索 | いま調べているレコード。条件に合うか順に確かめる | Seq ScanのrowsとRows Removed by Filter。LIMITが途中で止めたか | 第2章 |
| B-tree | 並んだキーとレコードの場所を持つIndex | Index Cond、取り出したレコード数、BUFFERS | 第3〜4章 |
| 全体のソート | 入力を並べる作業領域。収まらなければ一時ファイル | Sortの子のrows、Sort Method、Memory・Disk・temp | 第7章 |
| top-N | 上位k件の候補。入力の順序がなければ全入力を調べる | Sortの子のrowsと、Limitのrowsを分ける | 第8章 |
| ハッシュ結合・集約 | キーで相手やカウンタを探すハッシュ表 | HashやHashAggregateのMemory Usage、Batches、入力と出力のrows | 第9章 |
| Merge Join | 結合キー順の入力と、同じキーの組を返すための状態 | 入力を並べるSortやIndex、重複を含む出力レコード数 | 第9章 |
| 計画の選択 | 統計と設定から作る見積もり | rowsとactual rowsのずれ。costは時間と分ける | 第10章 |
| 可視性の確認 | レコードバージョンと可視性マップ | Index Only ScanのHeap Fetchesと、更新・VACUUMの履歴 | 第11章 |

## 20冊のために、何を調べていたのか

20冊を返すまでに、PostgreSQLは対象週の記録（手元のデータでは約50万件、序章の条件では約500万件）を読み、題名と対応させ、本ごとに数えてから上位を選んでいました。返す20冊より前の段で、この途中のレコード数を扱っていました。待ち時間を減らす手掛かりは、このレコード数にあります。三つの案は、この途中のレコード数をどこで減らすか、あるいは表示の前に済ませておくかの違いです。

SQLを受け取るプロセス、データを格納するページ、ソートや集計に使うメモリは、それぞれ実行計画の処理と対応しています。仕組みから処理を予想し、EXPLAINの出力や実測値と比べることで、改善案を検討できます。

知らないノードに出会っても、最初から全名称を覚え直す必要はありません。「何を受け取り、どんな状態を持ち、何を返す処理か」と問い、観察するところから始められます。

序章で書いた予想を読み返してください。選ぶ案が同じでも、理由や確かめ方が増えていれば、第12章までの観察が役に立っています。

## 実験を終える

事前集計テーブルは、この実験のために作りました。比較を終えたら片付け、psqlの時間表示も戻します。

```sql
DROP TABLE weekly_read_counts;
\timing off
```

テーブルに付いたIndexも削除されます。基本データのbooksとreading_records、前の章で作ったIndexは残ります。一時ビューは接続を閉じると消えます。
