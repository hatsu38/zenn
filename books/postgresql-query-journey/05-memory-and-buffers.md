---
title: "第5章：同じページを、毎回ストレージから読むのか"
---

## この章で分かること

一度使ったページは、次の検索で再利用できるのでしょうか。ページを保存するストレージと、実行中に使うメモリの関係を図で確認し、`BUFFERS`の`hit`と`read`を読みます。同じ検索を3回実行した結果から、ページの再利用と、行の条件を調べる処理を区別します。

## 同じ検索を、もう一度

前の章で、表はページというまとまりで扱われると分かりました。では、同じ本をもう一度探したら、同じページを最初から取り寄せるのでしょうか。

繰り返した検索で、変わった値と変わらなかった値を、観察ノートに並べるつもりで比べてみます。

![同じ検索を、もう一度](/images/postgresql-query-journey/04-repeat-observation.png)
*学ぶきっかけを描く、説明用の場面。*

## ページを保存する場所と、検索で使う場所

前章で調べた表のファイルは、SSDなどのストレージに保存されています。検索するときは、必要なページを**メモリ（RAM）**へ読み込みます。メモリは、プログラムが動いている間にデータを置いて使う場所です。

PostgreSQLは、読み込んだ表や索引のページをメモリ内に保持します。この領域は、このサーバへの複数の接続から共通に使う場所で、**共有バッファ**と呼びます。次の検索でも必要なページが残っていれば、ファイルから読み込み直さずに使えます。

図の上側がメモリ、下側がストレージです。同じページが、ファイルからメモリへ読み込まれ、その後も使われる様子を見てください。

![メモリの中の共有バッファとOSキャッシュ、ストレージの中の表ファイルの関係](/images/postgresql-query-journey/shared-buffer-reuse.png)
*読み込み経路の模型。ページ7は説明用の番号です。メモリに残っている間は、別の接続からも使えます。*

`EXPLAIN (ANALYZE, BUFFERS)`は、ページを使ったときの状況を次の二つに分けて表示します。

| 表示 | ページを使うときの状況 |
| --- | --- |
| `shared hit` | 共有バッファに既にあり、そのページを使った |
| `shared read` | 共有バッファになく、ファイルから読み込んだ |

図には**OSキャッシュ**という領域もあります。PostgreSQLとは別に、OSもファイルの内容をメモリに残すことがあるためです。`read`と表示されたページも、実際はOSキャッシュから読まれていることがあります。そのため、`read`の回数をそのままSSDを読んだ回数とは考えられません。

共有バッファに残るのは、検索結果の1行ではなく、表や索引のページです。では、ページを再利用できたら、その中から条件に合う行を探す処理も省けるでしょうか。次の実験で確かめます。

## この章だけの小さな表を用意する

第4章と同じ手順で、1,000冊の観察用の表をもう一度作ります。第4章末の`ROLLBACK`で取り消したためです。通常の表なので、そのページはこの章で見る共有バッファに置かれます。同じ名前のスキーマが既にある場合は、削除せずに別の名前へ書き換えてから実行してください。

```sql
BEGIN;
CREATE SCHEMA book_observation;
CREATE TABLE book_observation.books
  (LIKE public.books INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
ALTER TABLE book_observation.books ADD PRIMARY KEY (id);
INSERT INTO book_observation.books
SELECT id, title FROM public.books WHERE id BETWEEN 1 AND 1000;
SET LOCAL search_path = book_observation, public;
ANALYZE books;
SELECT count(*) FROM books;
```

:::details 準備SQLの実行結果
2026年9月24日に共有された出力から、入力SQLとpsqlのプロンプトを除いて掲載しています。

```sql
BEGIN
CREATE SCHEMA
CREATE TABLE
ALTER TABLE
INSERT 0 1000
SET
ANALYZE
 count
-------
  1000
(1 row)
```

`INSERT 0 1000`と最後の`count`から、観察用の表に1,000行あると確認できます。
:::

このトランザクションは開いたまま観察を続け、観察が終わったところで`ROLLBACK`して片付けます。

## 同じ検索を3回実行する

次のSQLを3回実行してください。実行する前に、2回目と3回目で`shared hit`、`shared read`、`Rows Removed by Filter`のそれぞれがどう変わるかを予想してください。

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books WHERE title = '実験用の本 42';
```

2026年9月24日に共有された、本1,000冊での1回目の実行結果です。「1回目」はこの比較の最初であり、DBを起動してから最初の検索という意味ではありません。表の作成、データの挿入、件数確認を行った後の観察です。

```sql
Seq Scan on books  (cost=0.00..20.50 rows=1 width=27) (actual time=0.018..0.079 rows=1.00 loops=1)
  Filter: (title = '実験用の本 42'::text)
  Rows Removed by Filter: 999
  Buffers: shared hit=8
Planning:
  Buffers: shared hit=3
Planning Time: 0.123 ms
Execution Time: 0.104 ms
```

:::details 2回目と3回目の実行結果
2回目です。

```sql
Seq Scan on books  (cost=0.00..20.50 rows=1 width=27) (actual time=0.051..0.154 rows=1.00 loops=1)
  Filter: (title = '実験用の本 42'::text)
  Rows Removed by Filter: 999
  Buffers: shared hit=8
Planning Time: 0.167 ms
Execution Time: 0.190 ms
```

3回目です。

```sql
Seq Scan on books  (cost=0.00..20.50 rows=1 width=27) (actual time=0.036..0.093 rows=1.00 loops=1)
  Filter: (title = '実験用の本 42'::text)
  Rows Removed by Filter: 999
  Buffers: shared hit=8
Planning Time: 0.105 ms
Execution Time: 0.117 ms
```
:::

3回分を表にまとめます。

| 実行 | 探す方法 | 調べた行 | shared hit | Execution Time |
| --- | --- | ---: | ---: | ---: |
| 1回目 | Seq Scan | 1,000 | 8 | 0.104 ms |
| 2回目 | Seq Scan | 1,000 | 8 | 0.190 ms |
| 3回目 | Seq Scan | 1,000 | 8 | 0.117 ms |

### 3回とも、ページを再利用して1,000行を調べている

3回とも、検索の実行中の表示は`shared hit=8`でした。共有バッファにあるページを8回使っていて、`shared read`は表示されていません。表の作成、行の挿入、件数確認でページを使った後なので、この比較は最初からページがメモリにある状態で始まっています。

それでも、`Rows Removed by Filter`は毎回999です。返した1行と合わせて、**3回とも1,000行の題名を比べています**。ページの読み込みを省けることと、行を調べなくて済むことは別だと分かります。

この短い実験は、キャッシュによる大きな速度差を示す例ではありません。どの回もページを再利用しており、処理方法と調べた行数も同じです。時間はわずかに上下していますが、この出力だけでは原因を特定できません。

キャッシュによる速度差を調べるなら、ページが共有バッファにない状態と、ある状態を用意して比べる必要があります。ここでの「1回目」は、ページが共有バッファになかった状態の測定とは見なせません。

この区別で、これまでの出力も振り返れます。第1章の題名検索は`shared hit=5112 read=2241`、第2章の同じ検索は`hit=5537 read=1816`、第3章で索引を作る前の検索は`hit=7353`で`read`がありませんでした。同じ表を読み返すうちに`read`が`hit`へ置き換わったと読める可能性がありますが、この間には別のSQLも実行しているので、同じ条件の比較ではありません。

:::details Planningの値は別に読む
`Planning Time`は計画を作る時間、`Execution Time`は実行の時間です。1回目の`Planning`の下の`shared hit=3`も計画作成時のアクセスなので、検索の実行時の8回には足しません。
:::

## メモリの領域を用途で分ける

ここまでの共有バッファは、ページを使うための場所です。一方、行を並べ替えたり、途中の集計値を保持したりする作業領域も必要です。

ページを共有する領域と、それぞれの処理が使う作業領域を見比べてください。

![ページの保存場所と、計算の作業場所](/images/postgresql-query-journey/04-memory-regions.png)
*基本の配置の模型。並列処理などは省略しています。*

並べ替えは**ソート**とも呼びます。ソートの途中の値は処理ごとの作業領域へ、再利用する表や索引のページは共有バッファへ置きます。まず、この二つに関わる設定を見ます。

| 設定名 | 決めるもの |
| --- | --- |
| `shared_buffers` | 表や索引のページを保持する共有バッファの大きさ |
| `work_mem` | ソートなど、一つの処理が作業に使うメモリ量の基準 |

値は`SHOW`で確認できます。今回の実験環境では、次の値になっていました。

```sql
SHOW shared_buffers;
```

```sql
 shared_buffers
----------------
 128MB
(1 row)
```

```sql
SHOW work_mem;
```

```sql
 work_mem
----------
 4MB
(1 row)
```

この出力は設定値であり、いま各処理が実際に使っているメモリ量ではありません。たとえば`work_mem`の`4MB`を見ても、「この検索で4MB使った」とは読めません。

いまは値を変更しません。自分の環境の設定を記録し、どの用途に関わる値なのかを上の表と対応させてみてください。

`work_mem`は、一つの接続が使うメモリ全体の上限ではありません。一つのSQLに並べ替えなどの処理が複数あれば、処理ごとに`work_mem`を目安にメモリを使うことがあります。ハッシュを使う処理では、`hash_mem_multiplier`という倍率の設定も関わります。第7章と第9章で具体例を見ます。[設定の公式説明](https://www.postgresql.org/docs/18/runtime-config-resource.html)にも対象が分けて書かれています。

:::details ほかの用途のメモリ設定と「一時」の意味
一時テーブルは、接続内で一時的に使うために作る表です。そのページには`temp_buffers`が関わります。索引作成や、不要な領域を回収するVACUUMの作業には、`maintenance_work_mem`が関わります。今回の環境での設定値は次のとおりです。

```sql
SHOW temp_buffers;
```

```sql
 temp_buffers
--------------
 8MB
(1 row)
```

```sql
SHOW maintenance_work_mem;
```

```sql
 maintenance_work_mem
----------------------
 64MB
(1 row)
```

一時テーブルのページは、BUFFERSの`local`に現れます。一方、並べ替えの途中結果がメモリに収まらずに書き出される**一時ファイル**は、`temp read`や`temp written`に関係します。第7章でこの一時ファイルを観察します。この章の観察用の表は`CREATE TABLE`で作った通常の表なので、`local`ではなく`shared`に現れます。
:::

## 観察用の表を片付ける

この章の観察が終わったら、同じpsqlで次を実行します。観察用スキーマの準備からここまでを、一つのトランザクションとして扱ってきました。

```sql
ROLLBACK;
```

観察用スキーマと表が取り消され、`books`という名前が指す表も元の`public.books`に戻ります。100万冊の`public.books`と題名索引は変更していません。

## ページを再利用しても、調べる行数は減らない

調べる範囲を減らす変更（第3章の索引）と、ページをメモリから再利用することは別の効果です。この二つを、出力で分けて読めるようになりました。

改善の前後を比べるときも、時間だけでなく、計画、行数、`hit`と`read`を一緒に記録します。同じデータと設定で複数回測り、ページを再利用できていたかも確認してください。

共有バッファは、複数の接続から利用できる場所でした。では、接続した先では何がSQLを実行しているのでしょうか。次章ではpsqlを二つ開き、接続ごとに動くプログラムと、共有するメモリの関係を確かめます。
