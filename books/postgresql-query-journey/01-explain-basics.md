---
title: "第1章：SQLの動きを観察する道具を手に入れる"
---

## この章で分かること

最初の観察は、題名で1冊の本を探す小さなSQLから始めます。EXPLAINで予定を、EXPLAIN ANALYZEで実際の処理を読みます。返したレコードと、条件で除外したレコードを区別し、番号で探した場合と比べます。以降の実験で使う観察の道具をそろえる章です。

## まずは1冊を探そう

いきなり大きなランキングを調べると、探す、数える、並べる処理が一度に出てきます。そこで、最初は「題名で1冊の本を探す」だけにします。

検索画面では、見つかった本しか見えません。

![検索画面には1冊だけが出ている。その裏のデータベースには本が100万冊あり、1冊を返すまでに何冊を調べたかを問う絵](/images/postgresql-query-journey/01-search-window.png)
*画面に出るのは1冊。その裏に、100万冊の一覧があります。*

画面に出た件数と、探すために調べた件数を分けて観察していきます。

これから動かすのは、次のSQLです。

```sql
SELECT id, title FROM books WHERE title = '実験用の本 42';
```

「本の一覧から、題名が一致する本の番号と題名を取り出して」という意味です。このSQLの`books`はテーブルの名前です。テーブルは、データを一覧として保存するものです。本書では、本1冊分のようなデータ1件を「レコード」と呼びます。番号や題名など、レコードに含まれる各項目が「列」です。SQLではレコードをrow（行）と呼ぶため、実行結果には`rows`と表示されます。`SELECT`は取り出す列、`FROM`は読むテーブル、`WHERE`は残すレコードの条件です。

手元で試す場合は、[「準備」の章](00-setup)でデータを用意したうえで、実験用リポジトリのディレクトリから、**ターミナルで**psqlに接続します。準備から続けて同じpsqlで入力しているなら、接続し直す必要はありません。

```bash
docker compose exec db psql -X -U postgres -d reading_map
```

接続し直したときは、「準備」の章で行った設定をもう一度入力します。

```sql
\set ON_ERROR_STOP on
\pset pager off
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
```


## 1冊の題名検索で、何件を調べるか予想する

最初の題名検索を実行してみましょう。

```sql
SELECT id, title FROM books WHERE title = '実験用の本 42';
```

実行結果です。

```sql
 id |     title
----+---------------
 42 | 実験用の本 42
(1 row)
```

結果は1件です。では、何件調べたのでしょうか。

- 目的の1件だけ。
- 見つかったところまで。
- 100万件すべて。

## EXPLAINは、実行する前の予定を見せる

さっきのSELECTで分かったのは、「実験用の本 42」が見つかったことです。どんな探し方をしたかは、結果の表には出ていません。

**EXPLAIN**（エクスプレイン）を使うと、PostgreSQLがSQLをどんな手順で処理する予定なのかを表示できます。この手順を**実行計画**と呼びます。

たとえば同じ1冊を探すにも、テーブルを順に調べる方法や、本の番号から場所を引く目録を使って探す方法があります。どの方法を使う予定か、何件返りそうか、といった情報をEXPLAINで確認できます。

使い方は、調べたいSQLの先頭に`EXPLAIN`を付けるだけです。まずは予定だけを見てみましょう。

```sql
EXPLAIN
SELECT id, title FROM books WHERE title = '実験用の本 42';
```

実行結果です。

```sql
Seq Scan on books  (cost=0.00..19853.00 rows=1 width=30)
  Filter: (title = '実験用の本 42'::text)
```

psqlの画面では、この上に`QUERY PLAN`という見出しと罫線、下に`(2 rows)`という行数も表示されます。本書では、実行計画の出力からこの見出しと行数を省いて載せます。

今度は、本の番号と題名ではなく、処理方法が返ってきました。これが実行計画です。

**EXPLAINだけでは、このSELECTによる検索は実行されません。** 表示されるレコード数やコストは実行前の見積もりなので、「実際に何件調べたか」「何秒かかったか」を知るには、もう一段階必要です。

出力に`Seq Scan on books`があれば、「booksを順に読んで調べる計画」です。テーブルを先頭から順に読んでいく処理を**逐次走査**（Seq Scan）と呼びます。`Filter`は、読んだレコードに当てる条件です。

`cost`の二つの値は、前が最初のレコードを返すまで、後ろがすべてのレコードを返すまでの処理量の見積もりです。ミリ秒ではなく、候補の計画を比べるための値です。

| 表示 | まず読む意味 |
| --- | --- |
| `Seq Scan` | テーブルを順に調べる方法 |
| `rows` | この処理が返すと予想したレコード数 |
| `cost` | 方法を比較するための見積もり値。秒ではない |
| `width` | 返す1件のおおよその大きさ |

`rows=1`は、条件に合うレコードを1件返すという見積もりです。その1件を見つけるまでに何件調べるかは、この値だけでは分かりません。

## 予定だけでなく、実際のレコード数と時間を見る

予定が分かったので、次は実際に動かした結果と比べます。`EXPLAIN`に`ANALYZE`を付けると、SQLを実行し、実際のレコード数や時間も計画に追加して表示できます。

| 入力するもの | SELECTによる検索を実行するか | 表示されるもの |
| --- | --- | --- |
| `SELECT ...` | する | 見つかった本など、検索結果のレコード |
| `EXPLAIN SELECT ...` | しない | 処理方法と実行前の見積もり |
| `EXPLAIN ANALYZE SELECT ...` | する | 実行計画に、実際のレコード数や時間を加えたもの |

三つの入力が、どの段階まで進むかを線で比べてください。

![SELECTは計画から、レコードを画面へ出すところまで進む。EXPLAINは計画を立てたところで止まり、EXPLAIN ANALYZEは実行まで進んで、結果のレコードは画面へ出さない](/images/postgresql-query-journey/01-explain-stages.png)
*実線の段階まで進み、破線の段階は行いません。*

`EXPLAIN ANALYZE`では、先ほどの「42、実験用の本 42」という検索結果の表は表示されません。検索は実行しますが、表示するのはその処理を観察するための情報です。

今回は`BUFFERS`も付けて、データをまとめて保存する単位である**ページ**（第4章で扱います）へのアクセス情報を一緒に記録します。丸括弧の中に、使いたいオプションをカンマで区切って書けます。いまはレコード数と処理方法に注目してください。BUFFERSの読み方は第5章で扱います。

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books WHERE title = '実験用の本 42';
```

実験用リポジトリの環境で、次の結果が出ました。2026年9月23日、PostgreSQL 18.6、本100万冊での1回の実測です。「準備」の章のデータ準備と件数確認、先ほどのSELECTに続けて実行しています。初回のディスク読み込み速度を測ったものではありません。

```sql
Seq Scan on books  (cost=0.00..19853.00 rows=1 width=30) (actual time=0.036..35.994 rows=1.00 loops=1)
  Filter: (title = '実験用の本 42'::text)
  Rows Removed by Filter: 999999
  Buffers: shared hit=5112 read=2241
Planning Time: 0.008 ms
Execution Time: 36.037 ms
```

`Buffers`の数と時間は、直前に実行した処理やマシンによって変わります。あなたの結果と一致しなくてもかまいません。`Seq Scan`、`rows`、`Rows Removed by Filter`の値が同じなら、同じ探し方で同じレコード数を調べています。

### 1件を返すまでに、残り999,999件も調べていた

最初は、次の三つを出力の中で探してください。`actual`は「実際の」という意味です。

| 出力のどこを見る？ | 今回の値 | そこから分かること |
| --- | --- | --- |
| `actual ... rows` | 1.00 | 条件に合う1件を返した |
| `Rows Removed by Filter` | 999,999 | 条件に合わない999,999件を除外した |
| `loops` | 1 | この走査を1回実行した |

今回は1回の走査なので、返した1件と除外した999,999件を足すと、100万件になります。**検索結果に出てこなかった本も、題名を比べる対象になっていた**と分かります。

帯の長さで、除外したレコードと返した1件の差を見てください。

![100万件の帯を先頭から最後まで比べ、999,999件を除外して1件だけを返す](/images/postgresql-query-journey/01-scan-and-filter.png)
*件数は2026年9月23日の実測。帯の長さはレコード数に比例させ、1件のカードだけを拡大しています。*

1件見つけても走査が止まらないのは、このSQLが条件に合うレコードをすべて求めているからです。Seq Scanには、条件に合うレコードがテーブルのどこにあるかを前もって知る手がかりがありません。そのため、残りのレコードも読み続け、100万件すべての題名を比べます。

表のとおり`loops`は実行回数です。複数回のときは平均値の読み方が加わるため、第9章で改めて扱います。

`Execution Time`は実行にかかった時間です。計画を作る`Planning Time`と分けて見ます。時間は毎回少し変わるので、同じミリ秒数が出ることを目標にしないでください。出力の正式な意味は[PostgreSQLのEXPLAIN解説](https://www.postgresql.org/docs/18/using-explain.html)でも確認できます。

:::message
`EXPLAIN ANALYZE`は実際にSQLを動かします。`UPDATE`などに付ければ変更も行われます。ここではまず、データを変更しない`SELECT`で観察します。
:::

## 番号なら、別の探し方ができる

同じ本を番号で探してみます。

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books WHERE id = 42;
```

今回の出力です。

```sql
Index Scan using books_pkey on books  (cost=0.42..8.44 rows=1 width=30) (actual time=0.017..0.017 rows=1.00 loops=1)
  Index Cond: (id = 42)
  Index Searches: 1
  Buffers: shared hit=7
Planning:
  Buffers: shared hit=5
Planning Time: 0.068 ms
Execution Time: 0.026 ms
```

今度は`Rows Removed by Filter`がありません。条件に合わないレコードを読んで除外する代わりに、`Index Cond`の条件でレコードの場所を探しています。題名検索と並べると、次のように違います。

| 比較するもの | 題名で探す | 番号で探す |
| --- | --- | --- |
| 探す方法 | Seq Scan | Index Scan |
| 返したレコード | 1件 | 1件 |
| Rows Removed by Filter | 999,999件 | 表示なし |
| 実行時のBuffers | `hit=5112 read=2241` | `hit=7` |

`Index Scan`は、**Index**（索引）という目録を使ってレコードを探す方法です。「準備」の章で主キーを作ったとき、番号用のIndexも作られています。番号の検索で100万件を調べずに済んだのは、番号を重複させない約束があるからではなく、このIndexを使えたからです[^pk-seqscan]。題名用のIndexはまだありません。

[^pk-seqscan]: 2026年9月25日、PostgreSQL 18.6で、同じ100万冊のテーブルを別に作って確かめました。Indexを使わないようにする設定（第3章で使う`enable_indexscan`など）で`WHERE id = 42`を実行すると、Seq Scanになり、`Rows Removed by Filter: 999999`でした。

Indexを使う場合は、まずレコードの場所を探し、その場所のレコードを読みます。

![Indexの項目42が持つ場所をたどり、テーブルのページから本42のレコードだけを読む](/images/postgresql-query-journey/01-index-to-row.png)
*項目42からレコード42へ伸びる1本の矢印を見てください。Indexの中身は第3章で扱います（説明するための図）。*

そのとき、Index自体もページとして読みます。そのため、結果が1件でもページアクセスは1回とは限りません。

## 自分で確かめる

題名を`'存在しない本'`に変えたら、返すレコードと調べるレコードはどうなるでしょう。まず予想し、同じ観察をしてください。

:::details 実行したSQLと結果
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books WHERE title = '存在しない本';
```

実行結果です。

```sql
Seq Scan on books  (cost=0.00..19853.00 rows=1 width=30) (actual time=40.821..40.821 rows=0.00 loops=1)
  Filter: (title = '存在しない本'::text)
  Rows Removed by Filter: 1000000
  Buffers: shared hit=5206 read=2147 written=78
Planning Time: 0.013 ms
Execution Time: 40.832 ms
```

今回は返したレコードが0件、除外したレコードが100万件でした。見つからなかったときも、本の一覧を最後まで調べています。
:::

## 実行結果を手元に残す

ここまでのSQLは、リポジトリの `sql/01/01-observe.sql` にまとめています。psqlを`\q`で終了し、ターミナルで次のコマンドを実行すると、SQLと出力をファイルへ保存できます。

```bash
docker compose exec -T db psql -X -U postgres -d reading_map \
  -a -f /lab/sql/01/01-observe.sql > results/local-chapter01.txt
```

本に載せた出力の[元ログ](https://github.com/hatsu38/postgresql-structures-lab/blob/main/results/chapter01-million-2026-09-23.txt)と[測定条件](https://github.com/hatsu38/postgresql-structures-lab/blob/main/results/README.md)も公開しています。自分の結果と見比べてみてください。中断と再開の手順は、「準備」の章の最後にまとめています。

## 第2章へ

1冊を返すために、100万件を調べていました。1冊見つかったところで止めれば、調べる量を減らせるでしょうか。次章では同じ100万冊に`LIMIT 1`を試します。
