---
title: "第12章：ランキングを速くする3つの案を、実行計画で比べる"
---

## この章で分かること

序章のランキングを、ここまで学んだ仕組みで読み解きます。20冊を返すまでに、どの処理が何件のレコードを扱っていたのかを実行計画でたどり、Indexの追加、集計と結合の順序の変更、事前集計の三つの案で、その件数がどこで減るかを比べます。書き換えても結果が同じか、更新の負担は何かも確かめます。最後に、AIが出した`work_mem`を増やす案も、同じ読み方で確かめます。

:::message
第8章で作った日時Indexを使います。
:::

## 最初の問いに戻る

「20冊のランキングなのに、なぜ待たされる？」

序章では、返す冊数しか手掛かりがありませんでした。今なら、ランキングの処理を次の四つに分けられます。

1. テーブルを読む。
2. 記録と本を対応させる。
3. 本ごとに数える。
4. 上位を選ぶ。

さらに、これらの処理はページを読み、メモリを使います。どの方法で行うかは統計をもとに選ばれ、テーブルの更新状態にも影響されます。この章では、この四つを一つの計画の中で読みます。ページは`BUFFERS`（第3章と第5章）に、メモリは`Sort Method`と`Batches`（第7章と第9章）に表れます。統計は`rows`と`actual rows`（第10章）、更新状態は`Heap Fetches`（第11章）で見ます。

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

この章で計画を載せるのは、各段のレコード数と処理の方法を読むためです。3つの案の時間は、後の「このサービスで、何を選ぶ？」の表で、条件をそろえて比べます。次の実行結果は、2026年9月26日にPostgreSQL 18.6で、第10章まで進めた後、第11章のVACUUM実験より前に採った計画です。

```sql:実行結果
Limit  (cost=129354.25..129354.30 rows=20 width=38) (actual time=576.650..576.657 rows=20.00 loops=1)
  Buffers: shared hit=6592 read=2680, temp read=9038 written=10753
  ->  Sort  (cost=129354.25..130574.82 rows=488229 width=38) (actual time=576.648..576.653 rows=20.00 loops=1)
        Sort Key: (count(*)) DESC, b.id
        Sort Method: top-N heapsort  Memory: 27kB
        Buffers: shared hit=6592 read=2680, temp read=9038 written=10753
        ->  HashAggregate  (cost=104805.36..116362.65 rows=488229 width=38) (actual time=498.999..555.530 rows=255238.00 loops=1)
              Group Key: b.id
              Planned Partitions: 8  Batches: 9  Memory Usage: 8281kB  Disk Usage: 15560kB
              Buffers: shared hit=6592 read=2680, temp read=9038 written=10753
              ->  Hash Join  (cost=36689.43..65899.61 rows=488229 width=30) (actual time=166.012..405.124 rows=499998.00 loops=1)
                    Hash Cond: (r.book_id = b.id)
                    Buffers: shared hit=6592 read=2680, temp read=7276 written=7276
                    ->  Index Only Scan using reading_records_order_idx on reading_records r  (cost=0.43..17277.01 rows=488229 width=8) (actual time=0.007..35.307 rows=499998.00 loops=1)
                          Index Cond: ((finished_at >= '2026-09-14 00:00:00'::timestamp without time zone) AND (finished_at < '2026-09-21 00:00:00'::timestamp without time zone))
                          Heap Fetches: 0
                          Index Searches: 1
                          Buffers: shared hit=1919
                    ->  Hash  (cost=17353.00..17353.00 rows=1000000 width=30) (actual time=165.769..165.771 rows=1000000.00 loops=1)
                          Buckets: 131072  Batches: 16  Memory Usage: 4883kB
                          Buffers: shared hit=4673 read=2680, temp written=5815
                          ->  Seq Scan on books b  (cost=0.00..17353.00 rows=1000000 width=30) (actual time=0.006..60.127 rows=1000000.00 loops=1)
                                Buffers: shared hit=4673 read=2680
…
```

下から読みます。まず日時のIndexから、対象週の記録499,998件を取り出しています（第8章）。次のHash Joinは、本100万冊の番号と題名でハッシュ表を作り（`Hash`の`rows=1000000.00`）、記録を1件ずつ照合します（第9章）。そのため、499,998件すべてに題名が付きます。HashAggregateは、本ごとのカウンタをハッシュ表に持って数え、255,238冊ぶんのグループを返しました。どちらのハッシュ表も作業用メモリに収まらず、`Batches`に分けて一時ファイル（`temp`）を使っています（第9章）。最後のSortはtop-N heapsortで、20冊ぶんの候補だけを持って上位を選びます（第8章）。20件へ減るのは、この最後の段です。

## 案1：Indexで減る処理を確かめる

第8章で日時順のIndexを作りました。いまの計画は、それを使っているでしょうか。使っていても、その後の結合や集約に渡すレコードが多ければ、そこには処理が残ります。

比較の手掛かりとして、実験の間だけIndexを使わないようにした計画も見ます。`SET LOCAL`の設定は、`BEGIN`で始めたトランザクション（複数の操作をひとまとまりとして扱う単位）の中だけ有効で、`ROLLBACK`で元に戻ります。

```sql
BEGIN;
SET LOCAL enable_indexscan = off;
SET LOCAL enable_indexonlyscan = off;
SET LOCAL enable_bitmapscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM ranking_before;
ROLLBACK;
```

実行結果です。基準SQLと同じ形の計画なので、変わった読了記録の読み方と、その上の段のレコード数だけを抜き出します。

```sql:実行結果
…
        ->  HashAggregate  (cost=128339.35..139896.65 rows=488229 width=38) (actual time=558.750..613.946 rows=255238.00 loops=1)
              …
              ->  Hash Join  (cost=36689.00..89433.60 rows=488229 width=30) (actual time=175.634..460.219 rows=499998.00 loops=1)
                    …
                    ->  Seq Scan on reading_records r  (cost=0.00..40811.00 rows=488229 width=8) (actual time=0.113..76.162 rows=499998.00 loops=1)
                          Filter: ((finished_at >= '2026-09-14 00:00:00'::timestamp without time zone) AND (finished_at < '2026-09-21 00:00:00'::timestamp without time zone))
                          Rows Removed by Filter: 1500002
                          …
```

日時のIndexを使ったIndex Only Scanから、200万件を読むSeq Scanへ変わりました。ただし、どちらも結合へ渡すレコードは499,998件で、その後の集計と上位選びも残ります。Indexだけでランキング全体の処理がなくなるわけではありません。

これはIndexを削除したのではなく、計画の候補から外しただけの実験です。2回の時間差ではなく、読み方と、後の段へ渡すレコード数を比べます。

## レコードの数が、どこで変わる？

次の案を考える前に、6件の読了記録から上位2冊を返す小さな例で、レコード数の変わり方を見ます。題名を付ける段階では何件あるかを見てください。図は処理を整理した例で、実行計画のノードが必ずこの順に並ぶわけではありません。

![6記録すべてに題名を付けてから数え、上位2冊だけが残る](/images/postgresql-query-journey/12-ranking-before.png)
*題名を付ける段階が6件のままである点に注目してください（実際は499,998件、図は6記録）。*

レコードが20件まで減るのが最後の段なら、それより前の段では多くのレコードを扱うことになります。推定レコード数と実測レコード数も比べましょう。見積もりが外れている問題と、見積もりが合っていても処理が多い問題は分けます。

## 案2：数えてから、題名を付ける

第9章の問いを試します。まず本の番号だけで数え、上位20冊を選んでから、本の題名を付けます。

前の図と同じ6件の例で、先に数えて上位2冊を選びます。題名を付ける対象が何件になるかを見てください。

![6件の読了記録を本ごとに数え、本1が3件・本2が2件・本3が1件になり、上位2冊の本1と本2だけに題名を結び付ける](/images/postgresql-query-journey/12-ranking-after.png)
*本ごとに数えてから、上位2冊だけに題名を結び付けます（説明するための図）。*

この順番をSQLにすると、次のようになります。

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

どこへ渡すレコードが少なくなるか予想してから、実際の計画を読みましょう。実行結果です。

```sql:実行結果
Nested Loop  (cost=22604.00..22772.68 rows=20 width=38) (actual time=164.705..165.474 rows=20.00 loops=1)
  Buffers: shared hit=1973 read=26, temp read=641 written=1378
  ->  Limit  (cost=22603.58..22603.63 rows=20 width=16) (actual time=164.674..164.680 rows=20.00 loops=1)
        Buffers: shared hit=1919, temp read=641 written=1378
        ->  Sort  (cost=22603.58..22800.62 rows=78816 width=16) (actual time=164.673..164.677 rows=20.00 loops=1)
              Sort Key: (count(*)) DESC, reading_records.book_id
              Sort Method: top-N heapsort  Memory: 26kB
              Buffers: shared hit=1919, temp read=641 written=1378
              ->  HashAggregate  (cost=19718.15..20506.31 rows=78816 width=16) (actual time=111.935..149.717 rows=255238.00 loops=1)
                    Group Key: reading_records.book_id
                    Batches: 5  Memory Usage: 8249kB  Disk Usage: 7224kB
                    Buffers: shared hit=1919, temp read=641 written=1378
                    ->  Index Only Scan using reading_records_order_idx on reading_records  (cost=0.43..17277.01 rows=488229 width=8) (actual time=0.007..32.766 rows=499998.00 loops=1)
                          Index Cond: ((finished_at >= '2026-09-14 00:00:00'::timestamp without time zone) AND (finished_at < '2026-09-21 00:00:00'::timestamp without time zone))
                          Heap Fetches: 0
                          Index Searches: 1
                          Buffers: shared hit=1919
  ->  Index Scan using books_pkey on books b  (cost=0.42..8.44 rows=1 width=30) (actual time=0.038..0.038 rows=1.00 loops=20)
        Index Cond: (id = reading_records.book_id)
        Index Searches: 20
        Buffers: shared hit=54 read=26
…
```

記録499,998件を数える処理は残っています。一方、Limitが先に20冊を選び、その後の`books_pkey`のIndex Scanは`rows=1 loops=20`です。題名を探す処理が20回になりました。基準SQLのHash Joinでは499,998件を照合していたので、ここが減った処理です。なお、`HashAggregate`の見積もり`rows=78816`は、実際の255,238グループよりかなり少なくなっています。第10章で見たとおり、本ごとの種類数を抜き出したレコードから少なく見積もったためです。

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

実行結果の`records_without_book`は0で、対応する本のない記録はありませんでした。0でなければ、先に上位を決める方法で結果が変わる可能性があります。

両方の結果に差がないかも調べます。`EXCEPT ALL`は、左の結果から、右の結果にもあるレコードを取り除きます。同じレコードが何件ずつあるかも比べます。向きを入れ替えた二つの差を`UNION ALL`でつなげ、残ったレコードを数えます。

```sql
SELECT count(*) AS differing_rows FROM (
  (SELECT * FROM ranking_before EXCEPT ALL SELECT * FROM ranking_after)
  UNION ALL
  (SELECT * FROM ranking_after EXCEPT ALL SELECT * FROM ranking_before)
) AS differences;
```

実行結果の`differing_rows`も0で、このデータでは、レコードの内容と個数に差がありませんでした。ただし、この比較は表示順を調べません。両方のSQLで読了数の降順、同数なら本番号の昇順を指定していることも確認します。

一つのデータで一致したことだけで、あらゆる場合の証明になるわけではありません。なぜ同じ結果になるかという前提と、実際の確認の両方が必要です。

## 案3：表示する前に数えておく

今度は、集計結果を本当にテーブルへ保存します。ビューと違って、値を持つテーブルです。作るのにかかった時間も見るため、先にpsqlの時間表示を有効にします。

```sql
\timing on
```

続けて、集計テーブルを作り、読み出します。

```sql
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

同日にpsqlで測った準備の時間は、255,238件の集計テーブルの作成が195.385ms、Indexの作成が93.357ms、`ANALYZE`が18.157msでした。作成済みのテーブルから読み出した実行結果です。

```sql:実行結果
Limit  (cost=0.84..13.87 rows=20 width=46) (actual time=0.038..0.137 rows=20.00 loops=1)
  Buffers: shared hit=100 read=3
  ->  Nested Loop  (cost=0.84..166283.20 rows=255238 width=46) (actual time=0.037..0.134 rows=20.00 loops=1)
        Buffers: shared hit=100 read=3
        ->  Index Only Scan using weekly_read_counts_order_idx on weekly_read_counts w  (cost=0.42..12948.39 rows=255238 width=16) (actual time=0.028..0.049 rows=20.00 loops=1)
              Heap Fetches: 20
              Index Searches: 1
              Buffers: shared hit=20 read=3
        ->  Index Scan using books_pkey on books b  (cost=0.42..0.60 rows=1 width=30) (actual time=0.004..0.004 rows=1.00 loops=20)
              Index Cond: (id = w.book_id)
              Index Searches: 20
              Buffers: shared hit=80
…
```

集計テーブルのIndexから20件を取り出し、本の題名を20回探しています。表示時の計画にはAggregateもSortもなく、読了記録を数える処理が消えました。なお、作成直後なので`Heap Fetches: 20`で、テーブルのレコードも確かめに行っています。autovacuumが済めば0になることもあります（第8章、第11章）。

その代わり、記録を数える仕事は、集計テーブルを作るときへ移りました。記録が増えたり週が替わったりするたびに、作り直すか更新します。ここで測った作成時間は初回の値で、運用中の継続更新や同時アクセスの負担は測っていません。psqlの経過時間とEXPLAINの`Execution Time`は測る範囲も違うので、足して一つの処理時間にはしません。

集計テーブルを作った後に新しい記録が届くと、表示はどうなるでしょう。

![集計テーブルが3件のまま読了記録が1件増え、数え直すまで画面はその3件を上位20件として表示する](/images/postgresql-query-journey/12-preaggregation.png)
*「表示が古い時間」と書かれた帯を見てください（説明するための図）。*

数え直すまでの間、表示は最新より少し古くなります。削除や訂正、週の切り替わりも反映する必要があります。結果を保存するマテリアライズドビューを更新する方法や、トリガー（テーブルが変更されたときに自動で動く処理）で変更を反映する方法もありますが、どの仕組みでも、更新の負担と表示の鮮度を一緒に考えます。

## 10冊に減らせば、速くなる？

序章の三つめの案は、表示を20冊から10冊に減らすことでした。第8章のtop-N heapsortを思い出してください。順序が分からない入力から上位を選ぶには、入力を最後まで確かめる必要がありました。LIMITを小さくすると、候補として保持する件数と、返す件数は減りますが、入力を調べる件数は減りません。基準のランキングSQLも、対象週の記録をすべて数えてからtop-Nで選ぶ計画です。上位を選ぶ段より前のレコード数が変わるかを、実行計画で確かめます。

基準SQLの`LIMIT 20`だけを`LIMIT 10`に変え、交互に2回ずつ測りました（2026年9月28日、第11章までの実験を終えた同じDB、共通設定のまま）。この表の時間は2本を並べるためのもので、3つの案の比較には使いません。

| 比べるもの | LIMIT 20 | LIMIT 10 |
| --- | ---: | ---: |
| Hash Joinが親へ渡したレコード | 499,998 | 499,998 |
| HashAggregateが返したグループ | 255,238 | 255,238 |
| Sort Method | top-N heapsort 27kB | top-N heapsort 26kB |
| Execution Time（2回） | 776.581 / 690.812 ms | 740.237 / 719.858 ms |

10冊にしても、結合と集計に渡るレコード数は変わりませんでした。変わったのは、上位を選ぶ段が持つ候補の量と、返すレコード数だけです。実行時間の差も、2回ずつの測定の揺れの範囲に収まっています。

一方、案2のように上位を選んだ後で題名を付ける計画なら、LIMITの後にある結合の件数は20件から10件へ減ります。LIMITの前後にどの処理があるかで、冊数を減らす効果は変わります。

## このサービスで、何を選ぶ？

第11章の更新とVACUUMの実験後、同じDBで3方式を3回ずつ測りました（PostgreSQL 18.6、共通設定のまま）。キャッシュは空にせず、基準SQL、案2、案3の順に実行しました。実験用のコンテナでの値なので、改善の倍率を他の環境へ当てはめるための測定ではありません。

| 方式 | 3回のExecution Time（ms） | 中央値（ms） | 減った処理・残った負担 |
| --- | --- | ---: | --- |
| 日時Indexを使う基準SQL | 608.768 / 629.833 / 677.358 | 629.833 | 期間で絞れても、499,998件の結合と集計が残る |
| 案2：集計後に題名を付ける | 204.982 / 194.781 / 174.590 | 194.781 | 題名を探すのは20回。期間内の集計は残る |
| 案3：作成済みの集計テーブルを読む | 0.310 / 0.088 / 0.102 | 0.102 | 表示時の集計が消える。集計テーブルの作成・更新は別に必要 |

この再測定でも、基準SQLと案2の記録の取得は、先に載せた計画と同じIndex Only Scanでした。基準では約50万件へ題名を付け、案2では20件へ付けるという違いも同じです。

3つの案が、表示のときに何件の記録を数え、何件に題名を付けているかを、帯で比べてください。

![基準SQLは499,998件を数えて499,998件に題名を付け、案2は499,998件を数えてから20件だけに題名を付け、案3は表示のときには数えずに20件に題名を付ける](/images/postgresql-query-journey/12-plan-record-counts.png)
*帯の長さで、3つの案が数える記録と題名を付ける記録を比べてください（件数は9月26日の計画、時間は3案を比べた表の中央値の実測）。*

時間の差は、題名を付ける件数と、表示のときに数えるかどうかの差に対応しています。案2は数える仕事を残したまま題名の仕事を減らし、案3は表示のときの数える仕事も集計テーブルの作成へ移しました。

ここでは「新しい記録を次の表示に反映したい」「まずは数百ミリ秒程度まで短くしたい」というサービスの条件を置き、**日時Indexを残して案2を採用する**判断にします。別の集計テーブルを維持せず、今回の測定では約195msまで短くなり、結果の同値性も確認できたためです。これは今回の条件での判断で、応答時間の保証ではありません。

「多数のアクセスでも、さらに短い応答が必要」「5分前までの集計でよい」という条件なら、案3を次に検証します。0.102msは読み出しだけの値なので、更新が5分以内に終わるか、訂正・削除・週替わりを正しく反映できるかを確かめてから採用します。

なお、基本データの人気の偏りは一つの式で作ったもので（「準備」の章）、現実の分布を再現したものではありません。記録がもっと少数の本に集中すれば、集計後のグループ数や、集計を先にする効果も変わるので、実サービスへ当てはめるときは自分のデータの偏りも調べます。

## 序章の2,000万件でも、同じ答えになるか

序章の約4.6秒は、本100万冊・読了記録2,000万件で測った時間でした。2026年9月28日に、序章と同じ作り方（人気の偏りなし、`work_mem`は64MB）で別のDBを用意して測ると、対象週の記録は4,999,999件でした。PostgreSQLは20冊を決めるために、約500万件の記録を読み、題名を付け、100万冊ぶん数えていました。これが、序章で予想してもらった問いの、この規模での答えです。3回ずつの中央値は、序章と同じSQLが約6.0秒、案2が約2.1秒で、200万件のときと同じく約3分の1になり、日時Indexを足しただけでは速くなりませんでした（同じ測定は、実験用リポジトリの`sql/12/ranking-20m.sql`で再現できます。別のDBに約2GBの領域を使います）。

## 最後の課題：AIの案を検証する

AIから「`work_mem`を増やすと改善します」と提案されたとします。すぐに採用する前に、次の短い調査メモを書いてください。

1. このSQLで減るはずの処理は何か。
2. データ量、Index、設定、更新状態をどうそろえるか。
3. どの計画、レコード数、ページアクセスを見るか。
4. 結果が同じことをどう確認するか。
5. 時間と運用上の負担から、何を採用するか。
6. まだ分からず、追加で調べたいことは何か。

対象期間を1日、1週間、全期間に変えた場合も、同じ結論でしょうか。一度の成功から適用範囲を考えることが、学んだ仕組みを使う練習になります。

:::details 考え方
基準のランキングSQLを、`BEGIN`の後の`SET LOCAL work_mem`で4MB・16MB・64MBに変え、順に2回ずつ実行しました（2026年9月28日、第11章までの実験を終えた同じDB、毎回`ROLLBACK`）。

4MBでは、Hash Joinが本100万冊のハッシュ表を`Batches: 16`の16個に分け、HashAggregateも`Batches: 9`に分けて、一時ファイルを使いながら処理していました（`temp read=9044 written=10750`、第9章）。16MBでは一時ファイルが消えましたが、計画そのものがMerge JoinとGroupAggregate（50万件をメモリ内で並べ替えて数える）に変わりました。64MBではHash JoinとHashAggregateに戻り、どちらも`Batches: 1`で一時ファイルもなくなったのに、2回の時間は1083.741msと1007.507msで、4MBの766.383msと706.532msより長くなりました。どの設定でも、結合に渡る499,998件、集計する255,238グループ、返す20件は同じです。

1. 減るはずの処理は、ハッシュ表や集計が作業用メモリからあふれて使う一時ファイルの読み書きです。
2. 同じDB、期間、Index、設定で、`work_mem`だけを変えます。
3. `Batches`、`Disk Usage`、`temp read/written`と、各段の`actual rows`を見ます。
4. SQLは変えていないので、結果は同じです。
5. 一時ファイルは消えても、扱うレコード数は変わらず、速くもなりませんでした。`work_mem`は、レコード数を減らす案ではありません。レコード数そのものを減らす案2（約195ms）を採ります。
6. 64MBで遅くなった理由は、今回の出力だけでは分かりません。また、64MBでは一つのSQLがハッシュ表と集計で合わせて約100MBを使いました（`Memory Usage: 69607kB`と`32793kB`）。同時に動く接続の数だけ、この量が必要になりうることも考えます（第7章）。
:::

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

20冊を返すまでに、PostgreSQLは対象週の記録（手元のデータでは約50万件、序章の条件では約500万件）を読み、Hash Joinですべてに題名を付け、HashAggregateで本ごとに数えてから、top-N heapsortで上位を選んでいました。返す20冊より前の段で、この途中のレコード数を扱っていました。待ち時間を減らす手掛かりは、このレコード数にあります。三つの案は、この途中のレコード数をどこで減らすか、あるいは表示の前に済ませておくかの違いです。

知らないノードに出会っても、最初から全名称を覚え直す必要はありません。「何を受け取り、どんな状態を持ち、何を返す処理か」と問い、仕組みから処理を予想して、EXPLAINの出力と比べるところから始められます。

序章で書いた予想を読み返してください。選ぶ案が同じでも、理由や確かめ方が増えていれば、第12章までの観察が役に立っています。

## まとめ

- 改善案は、どの段のレコード数が減るかで比べる。時間だけで決めない。
- SQLを書き換えたら、結果が変わっていないかを確かめる。
- 読むのを速くする案は、書き込みや更新のたびの負担と引き換えになる。

## 実験を終える

事前集計テーブルは、この実験のために作りました。比較を終えたら片付け、psqlの時間表示も戻します。

```sql
DROP TABLE weekly_read_counts;
\timing off
```

テーブルに付いたIndexも削除されます。基本データのbooksとreading_records、前の章で作ったIndexは残ります。一時ビューは接続を閉じると消えます。
