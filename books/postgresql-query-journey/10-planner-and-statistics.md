---
title: "第10章：PostgreSQLは、なぜその計画を選んだのか"
---

## この章で分かること

PostgreSQLは実行前にレコード数や処理量を見積もり、処理方法を選びます。条件の広さやデータの偏りを変え、統計情報、推定レコード数、実際の計画を対応させます。costを実時間と区別し、推定のずれが後続の処理へ及ぼす影響を考えます。期待と違う計画を見たとき、何を確かめてから改善を試すかを組み立てます。

:::message
小さな実験用テーブルをBEGINから同じ接続で作り、最後のROLLBACKで取り消します。読了記録の統計を変える実験も、BEGINとROLLBACKの間で行い、元に戻します。再接続した場合は「準備」の章の共通設定から始めます。
:::

## 20件と50万件で、方法が変わったのはなぜ？

第9章では、同じ二つのテーブルを結合するSQLで、外側が20件ならNested Loop、1週間分の約50万件ならHash Joinが選ばれました。計画は実行する前に作られます。つまりPostgreSQLは、記録を実際に取り出す前から、件数の違いを見込んでいたことになります。

同じことは第3章でも起きていました。番号のIndexがあっても、11冊を探すときは`Index Scan`、90万冊を探すときは`Seq Scan`が選ばれています。どちらの章でも、方法を分けたのは必要なレコード数の見込みでした。

![計画を作る段階では、まだ0件しか読んでいない](/images/postgresql-query-journey/10-planner-choice.png)
*「①計画を作る」の時点に注目してください（説明するための図）。*

絵の人物は、方法を選ぶPostgreSQLのたとえです。実際には、実行計画を立てる部分であるプランナ（第6章）が、テーブルについて集めた情報（統計情報。この後で見ます）とコストに基づいて計画を選びます。コストは、第1章で見た`cost`のことで、候補を同じ基準で比較するための値です。

すべての候補を実行して比較すると、結果を得るまでに余計な時間がかかります。そこでプランナは、実行前にレコード数や処理量を見積もって候補を比較します。文化祭で飲み物を仕入れる場面に似ています。来場者が50人か5,000人かによって、用意する数や運び方は変わります。来場者の人数の予想が推定レコード数、運び方の選択がNested LoopかHash Joinかの選択に当たります。

では、その予想（推定レコード数）は何を材料に作られるのでしょうか。結合の計画には材料が多く出てくるので、まずは偏りのある小さなテーブルで、推定レコード数と実際のレコード数を比べます。結合の話には、後半の「小さな見積もりの違いが、後ろへ届く」の節で戻ります。

## 同じ「1種類」でも、件数は違う

偏りのある小さな実験用テーブルを作ります。ランキング用のテーブルとは別で、最後に取り消します。

```sql
BEGIN;
CREATE TABLE stats_demo AS
SELECT n AS id,
       CASE WHEN n <= 9000 THEN 'popular' ELSE 'rare' END AS category
FROM generate_series(1, 10000) AS n;
CREATE INDEX stats_demo_category_idx ON stats_demo (category);
ANALYZE stats_demo;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM stats_demo WHERE category = 'popular';
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM stats_demo WHERE category = 'rare';
```

2026年9月25日、PostgreSQL 18.6での実行結果です。まず`popular`の計画です。

```sql:実行結果
Seq Scan on stats_demo  (cost=0.00..189.00 rows=9000 width=11) (actual time=0.006..0.682 rows=9000.00 loops=1)
  Filter: (category = 'popular'::text)
  Rows Removed by Filter: 1000
  Buffers: shared hit=64
Planning:
  Buffers: shared hit=8 read=1
Planning Time: 0.078 ms
Execution Time: 0.970 ms
```

続いて`rare`の計画です。

```sql:実行結果
Index Scan using stats_demo_category_idx on stats_demo  (cost=0.29..35.78 rows=1000 width=11) (actual time=0.023..0.106 rows=1000.00 loops=1)
  Index Cond: (category = 'rare'::text)
  Index Searches: 1
  Buffers: shared hit=7 read=3
Planning Time: 0.017 ms
Execution Time: 0.141 ms
```

`popular`は推定も実際も9,000件でSeq Scan、`rare`は推定も実際も1,000件でIndex Scanでした。「どちらも1種類を探す」ことと、「同じレコード数を探す」ことは違います。

対象になる割合を**選択率**と呼びます。この例なら90%と10%です。

## 全レコードを毎回数えず、特徴を持っておく

`ANALYZE`は値の分布などを調べ、**統計情報**を作ります。統計情報は、テーブルの特徴をまとめたメモです。

同じトランザクションの中で確認します。

```sql
SELECT attname, n_distinct, most_common_vals, most_common_freqs,
       histogram_bounds
FROM pg_stats
WHERE schemaname = current_schema() AND tablename = 'stats_demo';
```

実行結果から、`category`についての統計情報を抜粋します。

```sql:実行結果
 attname  | n_distinct | most_common_vals | most_common_freqs | histogram_bounds
----------+------------+------------------+-------------------+------------------
 category |          2 | {popular,rare}   | {0.9,0.1}         |
```

| 項目 | ざっくり何を表す？ |
| --- | --- |
| `n_distinct` | 値の種類数の見積もり。負の値はレコード数に対する割合を表す |
| `most_common_vals` | よく現れる値 |
| `most_common_freqs` | その値が現れる割合 |
| `histogram_bounds` | 残りの値の分布を区切る境界 |

`category`の列なら、`most_common_vals`に`popular`と`rare`、`most_common_freqs`にそれぞれの割合が入っているはずです。この割合が、推定レコード数を作る材料になります。

図で、メモの割合から計画の`rows`ができるまでをたどってください。

![1万件のテーブルのうち、popularの9,000件とrareの1,000件を、ANALYZEが割合0.9と0.1としてメモし、10,000×0.1＝1,000がrareを探す計画のrows=1000になる](/images/postgresql-query-journey/10-stats-to-rows.png)
*テーブルの1万件にメモの割合0.1を掛けた1,000が、計画のrowsになります（説明するための図。自分の出力の値と比べてください）。*

すべての列で、すべての項目が埋まるわけではありません。統計は一部のレコードを抜き出した標本に基づくため、完全な件数表でもありません。[レコード数見積もりの公式例](https://www.postgresql.org/docs/18/row-estimation-examples.html)には、この情報がどう使われるかが示されています。

## 古いメモで計画を立てたら

特徴が変わったのにメモが古いままだと、見積もりがずれるかもしれません。先ほどのテーブルで、多くの値を変更してみます。

```sql
UPDATE stats_demo SET category = 'rare' WHERE id <= 8000;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM stats_demo WHERE category = 'rare';
ANALYZE stats_demo;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM stats_demo WHERE category = 'rare';
ROLLBACK;
```

UPDATE後、ANALYZEする前の実行結果です。

```sql:実行結果
Index Scan using stats_demo_category_idx on stats_demo  (cost=0.29..51.55 rows=1672 width=11) (actual time=0.013..0.722 rows=9000.00 loops=1)
  Index Cond: (category = 'rare'::text)
  Index Searches: 1
  Buffers: shared hit=60
Planning Time: 0.077 ms
Execution Time: 0.996 ms
```

続いて、ANALYZE後の実行結果です。

```sql:実行結果
Seq Scan on stats_demo  (cost=0.00..232.00 rows=9000 width=9) (actual time=0.143..0.799 rows=9000.00 loops=1)
  Filter: (category = 'rare'::text)
  Rows Removed by Filter: 1000
  Buffers: shared hit=107
Planning:
  Buffers: shared hit=11
Planning Time: 0.106 ms
Execution Time: 1.066 ms
```

| 状態 | 推定rows | 実際のrows | 方法 |
| --- | ---: | ---: | --- |
| 更新前 | 1,000 | 1,000 | Index Scan |
| UPDATE後・ANALYZE前 | 1,672 | 9,000 | Index Scan |
| ANALYZE後 | 9,000 | 9,000 | Seq Scan |

更新前の統計には`rare`の割合が0.1と残っています。ただし、ANALYZE前の推定も1,000のままではなく1,672でした。推定は値の割合だけで決まらず、[現在のテーブルの大きさに合わせた補正](https://www.postgresql.org/docs/18/planner-stats.html)も使うためです。見るべき点は、実際には9,000件になったことを古い分布が十分に表せていないことです。

ANALYZE後は推定が9,000件になり、選ばれる方法も変わりました。この小さなテーブルでは実行時間が必ず短くなるとは限りません。統計を更新した効果は、まず推定と実測のずれで確かめます。最後のROLLBACKで、実験用テーブルと更新をまとめて取り消しています。

未コミットのテーブルは、ほかのプロセスであるautovacuum（VACUUMやANALYZEを自動で実行する仕組み。第11章で扱います）から見えないので、実験中に統計が勝手に更新されません。通常のテーブルでは自動の更新が途中で入ることがあります。推定が変わった理由を後で区別できるよう、`ANALYZE`の有無と時刻を記録しておきます。

## 第9章の736,097個は、なぜ7万個台と見積もられたのか

第9章で本ごとに読了記録を数えたとき、`HashAggregate`の見積もりは`rows=78881`でした。実際のグループは736,097個です。先ほどの`stats_demo`と同じように、統計情報の中身を確かめます。

```sql
SELECT count(DISTINCT book_id) AS actual_books FROM reading_records;
SELECT n_distinct FROM pg_stats
WHERE tablename = 'reading_records' AND attname = 'book_id';
```

2026年9月28日、PostgreSQL 18.6で、第12章まで進めた実験用DBでの実行結果です。

```sql:実行結果
 actual_books
--------------
       736097
(1 row)

 n_distinct
------------
      75797
(1 row)
```

記録のある本は736,097冊ですが、統計情報の`n_distinct`（値の種類数の見積もり）は75,797でした。1桁少ない値です。`GROUP BY book_id`の見積もりは、この値から作られます。第9章の`rows=78881`はその日の統計から作られた値で、`ANALYZE`のたびに少し変わります（第3章）。

少なくなった理由は、統計の作り方にあります。`ANALYZE`は、既定では200万件すべてを調べず、3万件を抜き出して調べます[^sample-rows]。この本の読了記録は、よく読まれる本ほど記録が多くなるように作ってあり、記録が1件か2件しかない本が大半です。そうした本の記録は、抜き出した3万件にほとんど入りません。抜き出した中に現れた本の数と、その現れ方から全体の種類数を推測するので、めったに現れない本が多いデータでは、種類数を少なく見積もりやすくなります。

[^sample-rows]: 抜き出すレコード数は、統計の目標値（`default_statistics_target`、既定は100）の300倍です。[ソースコードのこの行](https://github.com/postgres/postgres/blob/REL_18_STABLE/src/backend/commands/analyze.c#L1940)で決めています。目標値を上げると、`ANALYZE`にかかる時間と統計を置く領域も増えることが、[公式ドキュメントのANALYZEの説明](https://www.postgresql.org/docs/18/sql-analyze.html)に書かれています。

統計の目標値を上げると、抜き出すレコードが増えます。`book_id`の列だけ目標値を10,000に上げ、`ANALYZE`し直してから、同じ集約を実行します。統計の変更は実験の間だけにして、最後の`ROLLBACK`で元に戻します。

```sql
BEGIN;
ALTER TABLE reading_records ALTER COLUMN book_id SET STATISTICS 10000;
ANALYZE reading_records;
SELECT n_distinct FROM pg_stats
WHERE tablename = 'reading_records' AND attname = 'book_id';
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, count(*) AS read_count
FROM reading_records GROUP BY book_id;
ROLLBACK;
```

実行結果です。

```sql:実行結果
 n_distinct
------------
 -0.3680485
(1 row)

HashAggregate  (cost=143311.00..166296.97 rows=736097 width=16) (actual time=533.319..744.839 rows=736097.00 loops=1)
  Group Key: book_id
  Planned Partitions: 8  Batches: 9  Memory Usage: 8281kB  Disk Usage: 31440kB
  Buffers: shared hit=9252 read=1559, temp read=3239 written=6740
  ->  Seq Scan on reading_records  (cost=0.00..30811.00 rows=2000000 width=8) (actual time=0.131..130.200 rows=2000000.00 loops=1)
        Buffers: shared hit=9252 read=1559
Planning:
  Buffers: shared hit=29
Planning Time: 0.126 ms
Execution Time: 774.853 ms
```

目標値が10,000なら抜き出すのは300万件なので、200万件のテーブルは全件を調べます。`n_distinct`の-0.3680485は負の値なので、先ほどの表のとおりレコード数に対する割合です。200万件×0.3680485で736,097となり、実際の種類数と一致しました。見積もりも`rows=736097`になっています。

見積もりが変わると、実行のしかたも変わりました。既定の統計のままの集約と交互に2回ずつ実行して比べます（同じ日、同じ接続）。

| 比べるもの | 既定の統計（75,797） | 目標値10,000（736,097） |
| --- | --- | --- |
| 見積もりの`rows` | 75,797 | 736,097 |
| `Planned Partitions` | 表示なし | 8 |
| `Batches` | 21 | 9 |
| `Disk Usage` | 27752kB | 31440kB |
| Execution Time（2回） | 827.775 / 837.268 ms | 760.998 / 791.414 ms |

見積もりが実際に近づくと、PostgreSQLは、グループが作業用メモリに収まらないことを実行の前に見込み、最初から8つに分けて数える計画を立てました。`Batches`は21から9に減っています。ただし、この集約では一時ファイルの量は減らず、時間の差も1割に届きませんでした。見積もりのずれが、いつも大きな遅さにつながるわけではありません。影響が大きくなるのは、ずれが方法の選び方そのものを変える場面です。次の節で、その例を見ます。

種類数がよく分かっている列なら、`ALTER TABLE ... ALTER COLUMN ... SET (n_distinct = ...)`で値を直接指定する方法もあります[^n-distinct]。どちらも、見積もりのずれを実行計画で見つけてから使う手段です。

[^n-distinct]: [公式ドキュメントのALTER TABLEの説明](https://www.postgresql.org/docs/18/sql-altertable.html)にあります。2026年9月28日に同じ実験用DBで`n_distinct = 736097`を指定し、`ANALYZE`の後に見積もりが`rows=736097`になることを確かめました（ROLLBACKで元に戻しています）。

## 小さな見積もりの違いが、後ろへ届く

入力を1件と見積もった処理に、実際には10万件が渡ると、後続の処理量も見積もりを上回ることがあります。

第9章の計画に当てはめてみます。Nested Loopの計画では、外側が`rows=20`と見積もられ、実際にも20件でした。もし推定が20件のままで、実際には約50万件が届いたとしたら、内側で本を1冊ずつ探す操作も約50万回に増えます。1週間分の結合では、外側の推定が`rows=488229`で、実際の499,998件に近い値でした。

![上段は第9章のNested LoopとHash Joinで推定と実際がほぼ一致し、下段は推定20のまま実際が約50万件なら内側の実行回数が20から約50万に増える](/images/postgresql-query-journey/10-estimate-propagation.png)
*上の実測は推定と実際が近く、下は推定20のまま実際が約50万件になった場合の例で、内側の実行回数が増えます。*

すべての遅いSQLがこの形とは限りません。推定が近くても、そもそもの処理量が多い場合もあります。

計画を読むときは、最後に出る`Execution Time`だけでなく、下の方から「予想と実際が大きく離れた場所」を探します。`loops`が複数なら、`actual rows`は1回当たりの平均です。推定の`rows`も1回当たりの値なので、`loops`を掛けずにそのまま比べます。`loops`を掛けるのは、合計のレコード数や時間を知りたいときです。

## costは秒数の予言ではない

第1章の`cost`は、候補を同じ基準で比較するための値でした。ページを読む回数や、レコードの条件を比較する回数に、処理ごとの重みを付けて見積もります。

二つの数字のうち、前は最初のレコードを返すまでの見積もり、後ろは全部返すまでの見積もりです。`LIMIT`で上位の少数だけを返す場合は、全部を返し終えるまでの見積もりだけでなく、最初のレコードをどれだけ早く返せるかも計画選びに関わります。第9章の計画では、`Index Only Scan`の`cost=0.43..60768.43`に対して、上の`Limit`は`0.43..1.04`でした。20件で止まるので、最初のレコードまでの見積もりが小さい方法が選ばれやすくなります。

`cost=100`を100ミリ秒とは読めません。costの値と実際の時間を比べてずれの大きさを測ろうとするより、まず推定レコード数（`rows`）と実際のレコード数（`actual rows`）を比べます。

## 列どうしの関係と、繰り返しの再利用

「都道府県が東京都」と「市区町村が新宿区」は、互いに関係する条件です（新宿区なら必ず東京都です）。このような列どうしの関係があると、一つずつの統計だけでは見積もりが難しくなります。複数列の関係を扱う拡張統計は、本書では扱いません。[CREATE STATISTICSの公式説明](https://www.postgresql.org/docs/18/sql-createstatistics.html)が次の入口です。

また、再利用や分担を加えた計画もあります。一つは、同じ値を何度も探すNested Loopの内側に加わることがある`Memoize`のように、繰り返しの結果を再利用する処理です。もう一つは、複数のプロセスで仕事を分担する並列計画です。知らない計画に出会ったら、ここまでの基本形に再利用や分担が加わった形として読み始めます。

## Indexを無理に使わせる前に確かめる四つのこと

「Indexを使わないから、設定で無理に使わせよう」という案を受け取ったら、何を先に確認しますか。

:::details 考え方
次の四つを比べます。計画の名前だけで優劣を決めません。

- 実際に必要なレコード数
- 推定とのずれ
- 選ばれた方法の処理量
- 別の方法の実測
:::

`UPDATE`で8,000件の値を変えた後、`ANALYZE`で統計情報を作り直しました。統計情報はテーブルの特徴をまとめたメモなので、作り直せば新しい分布を材料に見積もれます。では、`UPDATE`されたテーブルのレコードそのものは、どうなっているのでしょうか。書き換えている途中に、別の接続が同じレコードを読んだら、古い値と新しい値のどちらが見えるのでしょうか。次章では、第6章の補足と同じようにpsqlを二つ開いて確かめます。
