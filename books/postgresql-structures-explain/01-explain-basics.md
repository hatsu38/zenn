---
title: "第1章：SQLの動きを観察する道具を手に入れる"
---

## この章で分かること

最初の観察は、題名で1冊の本を探す小さなSQLから始めます。実験環境を用意し、EXPLAINで予定を、EXPLAIN ANALYZEで実際の処理を読みます。返した行と条件から除外した行を区別し、番号で探した場合との違いを観察します。結果件数とSQLの仕事量は同じではないと理解し、以降の実験で使う道具を手に入れる章です。

## はじめに：まずは1冊を探そう

いきなり大きなランキングを調べると、探す、数える、並べる処理が一度に出てきます。そこで、最初は「題名で1冊の本を探す」だけにします。

検索画面では、見つかった本しか見えません。まずは、この小さな検索の内側を調べます。

![まずは、1冊だけ探してみる](/images/postgresql-structures-explain/01-search-window.png)
*学ぶきっかけを描く、説明用の場面。*

画面に出た件数と、探すために調べた件数を分けて観察していきます。

表とは、行と列を持った一覧です。本1冊が1行、番号や題名が列になります。`SELECT`は取り出す列、`FROM`は読む表、`WHERE`は残す行の条件です。

次は、これから動かすSQLの例です。まだ表を作っていないので、実行は準備の後に行います。

```sql
SELECT id, title FROM books WHERE title = '実験用の本 42';
```

「本の一覧から、題名が一致する本の番号と題名を取り出して」という意味です。まず、このSQLを試す場所を用意しましょう。

## SQLを入力する場所を作る

実験用リポジトリ `postgresql-structures-lab` の `compose.yaml` を使います。Docker Desktopなどを起動し、リポジトリのディレクトリで次のコマンドを実行してください。

```bash
docker compose up -d --wait
```

PostgreSQLが接続を受け付けるまで待ってから、コマンドが終了します。続いて、SQLを入力する道具、`psql`を開きます。

```bash
docker compose exec db psql -X -U postgres -d reading_map
```

ここからの`sql`と書かれた枠は、このpsqlへ入力します。末尾の`;`は「このSQLはここまで」という印です。ターミナルとpsqlのどちらへ入力するかに注意してください。

まずバージョンと、エラー時に止まる設定を確認します。

```sql
\set ON_ERROR_STOP on
\pset pager off
SELECT version();
```

## 小さな本の一覧を作る

次のSQLは最初の1回だけ実行します。実験用DBへ、本1,000冊と読了記録2万件を入れます。

同じSQLを、リポジトリの `sql/01/00-setup.sql` にも置いてあります。ファイルから実行した場合は、ここで再び入力する必要はありません。

```sql
CREATE TABLE books (
  id bigint PRIMARY KEY,
  title text NOT NULL
);
CREATE TABLE reading_records (
  book_id bigint NOT NULL,
  finished_at timestamp NOT NULL
);
INSERT INTO books
SELECT n, '実験用の本 ' || n FROM generate_series(1, 1000) AS n;
INSERT INTO reading_records
SELECT ((n::bigint * 7919) % 1000) + 1,
       timestamp '2026-08-24'
         + ((n::bigint * 104729) % 2419200) * interval '1 second'
FROM generate_series(1, 20000) AS n;
ANALYZE books;
ANALYZE reading_records;
SELECT count(*) FROM books;
SELECT count(*) FROM reading_records;
```

`bigint`は整数、`text`は文字列、`timestamp`は日時を入れる型です。`PRIMARY KEY`は同じ番号の本を重複させない約束、`NOT NULL`は空欄を許さない約束です。

`generate_series`は連番を作ります。`||`で文字と番号をつなぐと、「実験用の本 1」「実験用の本 2」といった題名になります。記録の長い式は、番号と日時をばらけさせるためのものです。式を覚える必要はありません。

`count(*)`は行の数を数えます。結果が1,000と20,000になれば準備できました。`ANALYZE books`は表の特徴を調べ、計画を立てる材料を集める命令です。詳しくは第10章で扱います。

## 1冊返るなら、調べるのも1冊？

最初の題名検索を実行してみましょう。

```sql
SELECT id, title FROM books WHERE title = '実験用の本 42';
```

```text
 id |     title
----+---------------
 42 | 実験用の本 42
(1 row)
```

結果は1行です。では、何行調べたのでしょうか。

- 目的の1行だけ。
- 見つかったところまで。
- 1,000行すべて。

## EXPLAINとは？

さっきのSELECTで分かったのは、「実験用の本 42」が見つかったことです。どんな探し方をしたかは、結果の表には出ていません。

**EXPLAIN（エクスプレイン）は、PostgreSQLがSQLをどのような手順で処理する予定なのかを表示する命令です。** この処理の手順を「実行計画」と呼びます。

たとえば同じ1冊を探すにも、表を順に調べる方法や、番号の索引を使って探す方法があります。どの方法を使う予定か、何行返りそうか、といった情報をEXPLAINで確認できます。

使い方は、調べたいSQLの先頭に`EXPLAIN`を付けるだけです。先ほどの予想と比べてみましょう。

```sql
EXPLAIN
SELECT id, title FROM books WHERE title = '実験用の本 42';
```

```text
Seq Scan on books  (cost=0.00..20.50 rows=1 width=27)
  Filter: (title = '実験用の本 42'::text)
```

今度は、本の番号と題名ではなく、処理方法が返ってきました。これが実行計画です。

**EXPLAINだけでは、このSELECTによる検索は実行されません。** 表示される行数やコストは実行前の見積もりなので、「実際に何行調べたか」「何秒かかったか」を知るには、もう一段階必要です。

出力に`Seq Scan on books`があれば、「booksを順に読んで調べる計画」です。`Filter`は、読んだ行に当てる条件です。

| 表示 | まず読む意味 |
| --- | --- |
| `Seq Scan` | 表を順に調べる方法 |
| `rows` | この処理が返すと予想した行数 |
| `cost` | 方法を比較するための見積もり値。秒ではない |
| `width` | 返す1行のおおよその大きさ |

`rows=1`は、条件に合う行を1行返すという見積もりです。その1行を見つけるまでに何行調べるかは、この値だけでは分かりません。

## 予定だけでなく、実際に行った仕事を見る

予定が分かったので、次は実際に動かした結果と比べます。`EXPLAIN`に`ANALYZE`を付けると、SQLを実行し、実際の行数や時間も計画に追加して表示できます。

| 入力するもの | SELECTによる検索を実行するか | 表示されるもの |
| --- | --- | --- |
| `SELECT ...` | する | 見つかった本など、検索結果の行 |
| `EXPLAIN SELECT ...` | しない | 処理方法と実行前の見積もり |
| `EXPLAIN ANALYZE SELECT ...` | する | 実行計画に、実際の行数や時間を加えたもの |

`EXPLAIN ANALYZE`では、先ほどの「42、実験用の本 42」という検索結果の表は表示されません。検索は実行しますが、表示するのはその処理を観察するための情報です。

今回は`BUFFERS`も付けて、ページへのアクセス情報を一緒に記録します。丸括弧の中に、使いたいオプションをカンマで区切って書けます。BUFFERSの読み方は第4章で扱うので、いまは行数と処理方法に注目してください。

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books WHERE title = '実験用の本 42';
```

実験用リポジトリの環境で、次の結果が出ました。2026年9月22日、PostgreSQL 18.6、本1,000冊での1回の実測です。データ準備と件数確認、先ほどのSELECTに続けて実行しています。初回のディスク読み込み速度を測ったものではありません。

```text
Seq Scan on books  (cost=0.00..20.50 rows=1 width=27) (actual time=0.006..0.042 rows=1.00 loops=1)
  Filter: (title = '実験用の本 42'::text)
  Rows Removed by Filter: 999
  Buffers: shared hit=8
Planning Time: 0.019 ms
Execution Time: 0.047 ms
```

### 1行を返すまでに、残り999行も調べていた

最初は、次の三つを出力の中で探してください。`actual`は「実際の」という意味です。

| 出力のどこを見る？ | 今回の値 | そこから分かること |
| --- | --- | --- |
| `actual ... rows` | 1.00 | 条件に合う1行を返した |
| `Rows Removed by Filter` | 999 | 条件に合わない999行を除外した |
| `loops` | 1 | この走査を1回実行した |

今回は1回の走査なので、返した1行と除外した999行を足すと、1,000行になります。**検索結果に出てこなかった本も、題名を比べる対象になっていた**と分かります。

次は、この初期データを単純な1回の逐次走査で読んだ場合の**行数の説明図**です。時間の実測結果ではありません。

![結果が1行でも、調べたのは1,000行](/images/postgresql-structures-explain/01-scan-and-filter.png)
*初期データの単純な逐次走査（loops = 1）。帯は行の集まりを表し、本数は省略しています。*

結果は1行ですが、題名の比較は1,000行に対して行っています。題名は重複しないと宣言していないので、1行見つけても「後に同じ題名がない」とは判断できません。

`loops`は同じ処理を何回実行したかです。今回は1回を想定しています。複数回のときは平均値の読み方が加わるため、第9章で改めて扱います。

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

```text
Index Scan using books_pkey on books  (cost=0.28..8.29 rows=1 width=27) (actual time=0.014..0.014 rows=1.00 loops=1)
  Index Cond: (id = 42)
  Index Searches: 1
  Buffers: shared hit=6
Planning:
  Buffers: shared hit=5
Planning Time: 0.030 ms
Execution Time: 0.019 ms
```

`Index Scan`が選ばれたら、索引という目録を使う方法です。主キーを作ったとき、番号用の索引も作られています。題名用の索引はまだありません。

索引を使う場合は、まず行の場所を探し、その場所の行を読みます。

![番号で場所を探し、表から行を取り出す](/images/postgresql-structures-explain/01-index-to-row.png)
*Index Scanの模型 ／ 索引の内部は第6章で扱う。*

索引を使う場合も、索引のページを読んで行の場所を調べます。結果が1行でも、必要なページアクセスは1回とは限りません。索引の構造は第6章で説明します。

## 自分で確かめる

題名を`'存在しない本'`に変えたら、返す行と調べる行はどうなるでしょう。まず予想し、同じ観察をしてください。

:::details 実行したSQLと結果
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books WHERE title = '存在しない本';
```

```text
Seq Scan on books  (cost=0.00..20.50 rows=1 width=27) (actual time=0.041..0.042 rows=0.00 loops=1)
  Filter: (title = '存在しない本'::text)
  Rows Removed by Filter: 1000
  Buffers: shared hit=8
Planning Time: 0.011 ms
Execution Time: 0.044 ms
```

今回は返した行が0行、除外した行が1,000行でした。見つからなかったときも、本の一覧を最後まで調べています。
:::

## 実行結果を手元に残す

ここまでのSQLは、リポジトリの `sql/01/01-observe.sql` にまとめています。psqlを`\q`で終了し、ターミナルで次のコマンドを実行すると、SQLと出力をファイルへ保存できます。

```bash
docker compose exec -T db psql -X -U postgres -d reading_map \
  -a -f /lab/sql/01/01-observe.sql > results/local-chapter01.txt
```

本に載せた出力の元ログは `results/chapter01-2026-09-22.txt`、測定条件は `results/README.md` にあります。自分の結果と見比べてみてください。

中断はターミナルで`docker compose stop`。再開は`docker compose up -d --wait`の後、先ほどのpsql接続コマンドです。データは残るので、表の作成SQLを再実行する必要はありません。

次章では、SQLを受け取って計画を実行するプロセスを調べます。
