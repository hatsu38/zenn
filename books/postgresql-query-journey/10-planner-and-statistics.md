---
title: "第10章：PostgreSQLは、なぜその計画を選んだのか"
---

## この章で分かること

PostgreSQLは実行前にレコード数や処理量を見積もり、処理方法を選びます。条件の広さやデータの偏りを変え、統計情報、推定レコード数、実際の計画を対応させます。costを実時間と区別し、推定のずれが後続の処理へ及ぼす影響を考えます。期待と違う計画を見たとき、何を確かめてから改善を試すかを組み立てます。

:::message
再接続したら、「準備」の章の共通設定を入力してください。途中の章から始めるときの準備は、[実験用リポジトリのREADME](https://github.com/hatsu38/postgresql-structures-lab#readme)にあります。
:::

## 20件と50万件で、方法が変わったのはなぜ？

第9章では、同じ二つのテーブルを結合するSQLで、外側が20件ならNested Loop、1週間分の約50万件ならHash Joinが選ばれました。計画は実行する前に作られます。つまりPostgreSQLは、記録を実際に取り出す前から、件数の違いを見込んでいたことになります。

同じことは第3章でも起きていました。番号のIndexがあっても、11冊を探すときは`Index Scan`、90万冊を探すときは`Seq Scan`が選ばれています。どちらの章でも、方法を分けたのは必要なレコード数の見込みでした。

![計画を作る段階では、まだ0件しか読んでいない](/images/postgresql-query-journey/10-planner-choice.png)
*「①計画を作る」の時点に注目してください（説明するための図）。*

絵の人物は、方法を選ぶPostgreSQLのたとえです。実際には、実行計画を立てる部分であるプランナ（第6章）が、テーブルについて集めた情報（統計情報。この後で見ます）とコストに基づいて計画を選びます。コストは、第1章で見た`cost`のことで、候補を同じ基準で比較するための値です。

すべての候補を実行して比較すると、結果を得るまでに余計な時間がかかります。そこでプランナは、実行前にレコード数や処理量を見積もって候補を比較します。

では、その予想（推定レコード数）は何を材料に作られるのでしょうか。結合の計画には材料が多く出てくるので、まずは偏りのある小さなテーブルで、推定レコード数と実際のレコード数を比べます。第9章の1週間分の見積もりには、「1週間分の約50万件は、どう見積もられたのか」の節で戻ります。

## 同じ「1種類」でも、件数は違う

偏りのある小さな実験用テーブルを作ります。ランキング用のテーブルとは別です。`BEGIN`でトランザクションを始め、「古いメモで計画を立てたら」の節の`ROLLBACK`まで同じ接続で進めて、最後にテーブルごと取り消します。

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
  …
  Buffers: shared hit=64
  …
```

続いて`rare`の計画です。

```sql:実行結果
Index Scan using stats_demo_category_idx on stats_demo  (cost=0.29..35.78 rows=1000 width=11) (actual time=0.023..0.106 rows=1000.00 loops=1)
  …
```

`popular`は推定も実際も9,000件でSeq Scan、`rare`は推定も実際も1,000件でIndex Scanでした。Seq Scanの`shared hit=64`は、このテーブルが64ページあることを示しています。「どちらも1種類を探す」ことと、「同じレコード数を探す」ことは違います。

対象になる割合を**選択率**と呼びます。この例なら90%と10%です。

プランナは、この割合をテーブルの件数に掛けて、推定の`rows`を作ります。図で、割合から計画の`rows`ができるまでをたどってください。

![1万件のテーブルのうち、popularの9,000件とrareの1,000件を、ANALYZEが割合0.9と0.1としてメモし、10,000×0.1＝1,000がrareを探す計画のrows=1000になる](/images/postgresql-query-journey/10-stats-to-rows.png)
*テーブルの1万件にメモの割合0.1を掛けた1,000が、計画のrowsになります（説明するための図。自分の出力の値と比べてください）。*

図の割合は、`ANALYZE`が作るメモに入っています。次に、そのメモの実物を見ます。

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

`category`の列では、`most_common_vals`に`popular`と`rare`、`most_common_freqs`にそれぞれの割合0.9と0.1が入っています。図で掛けた割合は、このメモから来ています。

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
  …
```

続いて、ANALYZE後の実行結果です。

```sql:実行結果
Seq Scan on stats_demo  (cost=0.00..232.00 rows=9000 width=9) (actual time=0.143..0.799 rows=9000.00 loops=1)
  …
  Buffers: shared hit=107
  …
```

| 状態 | 推定rows | 実際のrows | 方法 |
| --- | ---: | ---: | --- |
| 更新前 | 1,000 | 1,000 | Index Scan |
| UPDATE後・ANALYZE前 | 1,672 | 9,000 | Index Scan |
| ANALYZE後 | 9,000 | 9,000 | Seq Scan |

更新前の統計には`rare`の割合が0.1と残っています。ただし、ANALYZE前の推定も1,000のままではなく1,672でした。推定は値の割合だけで決まらず、[現在のテーブルの大きさに合わせた補正](https://www.postgresql.org/docs/18/planner-stats.html)も使うためです。

補正の中身は、ページ数の比です。統計を作ったとき、テーブルは64ページでした。UPDATEで8,000件の新しい版が書き足され、107ページに増えています（ANALYZE後のSeq Scanの`shared hit=107`）。プランナは、1ページ当たりのレコード数が統計を作ったときと同じだと見て、全体を10,000×107÷64で約16,700件と見込みます。その0.1が1,672件です。

見るべき点は、割合0.1という古い分布のままでは、実際の9,000件を表せないことです。

ANALYZE後は推定が9,000件になり、選ばれる方法も変わりました。この小さなテーブルでは実行時間が必ず短くなるとは限りません。統計を更新した効果は、まず推定と実測のずれで確かめます。最後のROLLBACKで、実験用テーブルと更新をまとめて取り消しています。

未コミットのテーブルは、ほかのプロセスであるautovacuum（VACUUMやANALYZEを自動で実行する仕組み。第11章で扱います）から見えないので、実験中に統計が勝手に更新されません。通常のテーブルでは自動の更新が途中で入ることがあります。推定が変わった理由を後で区別できるよう、`ANALYZE`の有無と時刻を記録しておきます。最後に統計を作った時刻は、`pg_stat_user_tables`の`last_analyze`（手動の`ANALYZE`）と`last_autoanalyze`（autovacuumによるもの）で確かめられます。

## 1週間分の約50万件は、どう見積もられたのか

`stats_demo`の`category`は値が2種類しかなく、どちらも`most_common_vals`に載ったので、`histogram_bounds`は空でした。日時や番号のように値の種類が多い列では、ここに境目が入ります。

`ANALYZE`は、抜き出したレコードのうち、よく出る値の表に載らなかった値を小さい順に並べ、同じ件数ずつの区間に区切ります。その区切りの値が`histogram_bounds`です。既定では100区間に分けるので、境目は101個になります。どの区間にも、残りのレコードのおよそ100分の1ずつが入っている、というメモです。

範囲の条件では、条件の範囲がこの区間のうちどれだけにかかるかを数え、その割合を選択率にします。10区間のうち3区間にかかれば選択率は0.3で、テーブルの件数に0.3を掛けたものが推定の`rows`になります。等号の条件と同じ「割合×件数」です。範囲が区間の途中で切れるときは、その区間の一部だけを数えます。細かい計算は、先ほどの[レコード数見積もりの公式例](https://www.postgresql.org/docs/18/row-estimation-examples.html)に載っています。

これで、章の最初の問いに答えられます。第9章の1週間分の記録では、`finished_at`の100区間のうち約24区間に範囲がかかると見て、200万件×約0.244から`rows=488229`と見積もられました[^range-check]。実際は499,998件なので、近い値です。一方、20件のNested Loopの計画では、`LIMIT 20`があるので、外側から20件より多くは届かないと見込めます。実行する前から、20件と約50万件の違いは分かっていたことになります。第3章で`id BETWEEN 1 AND 900000`が`rows=901290`と見積もられたのも、本の番号の区間のうち約9割に範囲がかかると見た結果です。

[^range-check]: 2026年9月28日に実験用DBで確かめると、読了記録の`finished_at`には`most_common_vals`がなく、101個の境目のうち25個が1週間の範囲に入り、そのときの見積もりは`rows=498088`でした。本の`id`も、101個の境目のうち90個が`1`〜`900000`に入り、見積もりは`rows=898829`でした。境目は`ANALYZE`のたびに少し変わるので、第3章・第9章の値とは一致しません。

## 第9章の736,097個は、なぜ7万個台と見積もられたのか

第9章で本ごとに読了記録を数えたとき、`HashAggregate`の見積もりは`rows=78881`でした。実際のグループは736,097個です。先ほどの`stats_demo`と同じように、統計情報の中身を確かめます。

```sql
SELECT count(DISTINCT book_id) AS actual_books FROM reading_records;
SELECT n_distinct FROM pg_stats
WHERE tablename = 'reading_records' AND attname = 'book_id';
```

2026年9月28日、PostgreSQL 18.6で、第12章まで進めた実験用DBでの実行結果です。第11章と第12章では読了記録を増やしも消しもしないので、記録のある本の数は、この章の時点で数えても同じです。

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

少なくなった理由は、統計の作り方にあります。`ANALYZE`は、既定では200万件すべてを調べず、3万件を抜き出して調べます[^sample-rows]。この本の読了記録は、よく読まれる本ほど記録が多くなるように作ってあり、記録が1件か2件しかない本が大半です。そうした本の記録は、抜き出した3万件にほとんど入りません。

[^sample-rows]: 抜き出すレコード数は、統計の目標値（`default_statistics_target`、既定は100）の300倍です。[ソースコードのこの行](https://github.com/postgres/postgres/blob/REL_18_STABLE/src/backend/commands/analyze.c#L1940)で決めています。目標値を上げると、`ANALYZE`にかかる時間と統計を置く領域も増えることが、[公式ドキュメントのANALYZEの説明](https://www.postgresql.org/docs/18/sql-analyze.html)に書かれています。

全体の種類数を推し量るときの手掛かりは、抜き出した中に現れた本の数と、そのうち1回だけ現れた本の数です[^distinct-estimator]。1回だけの本が多いほど、抜き出しに入らなかった本もまだ多いと見て、種類数を大きくします。ただ、3万件に一度も現れなかった本が実際にどれだけあるかは、抜き出した記録からは分かりません。めったに現れない本が多いデータでは、その分を埋めきれず、種類数を少なく見積もりやすくなります。

[^distinct-estimator]: [ANALYZEのソース](https://github.com/postgres/postgres/blob/REL_18_STABLE/src/backend/commands/analyze.c)で、HaasとStokesの推定式を使い、標本の件数、標本に現れた値の数、1回だけ現れた値の数から種類数を計算していることを確かめました。

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
  …
  Planned Partitions: 8  Batches: 9  Memory Usage: 8281kB  Disk Usage: 31440kB
  …
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

見積もりが実際に近づくと、PostgreSQLは、グループが作業用メモリに収まらないことを実行の前に見込み、メモリがいっぱいになったら8つの組に分けて書き出すと、先に決めておきました（第9章の「HashAggregateの場合」）。`Batches`は21から9に減っています。9は、最初にメモリで数えた1回と、8つの組を合わせた数と読めます。ただし、この集約では一時ファイルの量は減らず、時間の差も1割に届きませんでした。見積もりのずれが、いつも大きな遅さにつながるわけではありません。影響が大きくなるのは、ずれが方法の選び方そのものを変える場面です。次の節で、その例を見ます。

種類数がよく分かっている列なら、`ALTER TABLE ... ALTER COLUMN ... SET (n_distinct = ...)`で値を直接指定する方法もあります[^n-distinct]。どちらも、見積もりのずれを実行計画で見つけてから使う手段です。

[^n-distinct]: [公式ドキュメントのALTER TABLEの説明](https://www.postgresql.org/docs/18/sql-altertable.html)にあります。2026年9月28日に同じ実験用DBで`n_distinct = 736097`を指定し、`ANALYZE`の後に見積もりが`rows=736097`になることを確かめました（ROLLBACKで元に戻しています）。

## 小さな見積もりの違いが、後ろへ届く

入力を1件と見積もった処理に、実際には10万件が渡ると、後続の処理量も見積もりを上回ることがあります。

第9章の計画に当てはめてみます。Nested Loopの計画では、外側が`rows=20`と見積もられ、実際にも20件でした。もし推定が20件のままで、実際には約50万件が届いたとしたら、内側で本を1冊ずつ探す操作も約50万回に増えます。1週間分の結合では、範囲の見積もりで見たとおり、外側の推定`rows=488229`は実際の499,998件に近い値でした。

![上段は第9章のNested LoopとHash Joinで推定と実際がほぼ一致し、下段は推定20のまま実際が約50万件なら内側の実行回数が20から約50万に増える](/images/postgresql-query-journey/10-estimate-propagation.png)
*上の実測は推定と実際が近く、下は推定20のまま実際が約50万件になった場合の例で、内側の実行回数が増えます。*

すべての遅いSQLがこの形とは限りません。推定が近くても、そもそもの処理量が多い場合もあります。

計画を読むときは、最後に出る`Execution Time`だけでなく、下の方から「予想と実際が大きく離れた場所」を探します。`loops`が複数なら、`actual rows`は1回当たりの平均です。推定の`rows`も1回当たりの値なので、`loops`を掛けずにそのまま比べます。`loops`を掛けるのは、合計のレコード数や時間を知りたいときです。

## costは秒数の予言ではない

第1章の`cost`は、候補を同じ基準で比較するための値でした。ページを読む回数や、レコードの条件を比較する回数に、処理ごとの重みを付けて見積もります。既定では、ページを1枚順番に読む手間を1として、ほかの重みをそれに合わせて決めています（[プランナのコストの設定](https://www.postgresql.org/docs/18/runtime-config-query.html#RUNTIME-CONFIG-QUERY-CONSTANTS)の`seq_page_cost`）。

二つの数字のうち、前は最初のレコードを返すまでの見積もり、後ろは全部返すまでの見積もりです。`LIMIT`で上位の少数だけを返す場合は、全部を返し終えるまでの見積もりだけでなく、最初のレコードをどれだけ早く返せるかも計画選びに関わります。第9章の計画では、`Index Only Scan`の`cost=0.43..60768.43`に対して、上の`Limit`は`0.43..1.04`でした。20件で止まるので、最初のレコードまでの見積もりが小さい方法が選ばれやすくなります。

`cost=100`を100ミリ秒とは読めません。costの値と実際の時間を比べてずれの大きさを測ろうとするより、まず推定レコード数（`rows`）と実際のレコード数（`actual rows`）を比べます。

:::details 補足
「都道府県が東京都」と「市区町村が新宿区」は、互いに関係する条件です（新宿区なら必ず東京都です）。このような列どうしの関係があると、一つずつの統計だけでは見積もりが難しくなります。複数列の関係を扱う拡張統計は、本書では扱いません。[CREATE STATISTICSの公式説明](https://www.postgresql.org/docs/18/sql-createstatistics.html)が次の入口です。

また、再利用や分担を加えた計画もあります。一つは、同じ値を何度も探すNested Loopの内側に加わることがある`Memoize`のように、繰り返しの結果を再利用する処理です。もう一つは、複数のプロセスで仕事を分担する並列計画です。知らない計画に出会ったら、ここまでの基本形に再利用や分担が加わった形として読み始めます。
:::

## Indexを無理に使わせる前に確かめる四つのこと

「Indexを使わないから、設定で無理に使わせよう」という案を受け取ったら、何を先に確認しますか。

:::details 考え方
次の四つを比べます。計画の名前だけで優劣を決めません。

- 実際に必要なレコード数
- 推定とのずれ
- 選ばれた方法の処理量
- 別の方法の実測
:::

## まとめ

- 計画は、実行前の見積もりで選ばれる。推定の`rows`は、統計にある割合（よく出る値の割合や、範囲がかかる区間の割合）にテーブルの件数を掛けて作られる。推定の`rows`と`actual`の`rows`が大きく違う段を探す。
- 統計情報は標本から作る。値の偏りや種類の多さは、標本で表しきれないことがある。
- Indexを無理に使わせる前に、実際に必要なレコード数、推定とのずれ、選ばれた方法の処理量、別の方法の実測を確かめる。

`UPDATE`で8,000件の値を変えた後、`ANALYZE`で統計情報を作り直しました。統計情報はテーブルの特徴をまとめたメモなので、作り直せば新しい分布を材料に見積もれます。では、`UPDATE`されたテーブルのレコードそのものは、どうなっているのでしょうか。書き換えている途中に、別の接続が同じレコードを読んだら、古い値と新しい値のどちらが見えるのでしょうか。次章では、第6章の補足と同じようにpsqlを二つ開いて確かめます。
