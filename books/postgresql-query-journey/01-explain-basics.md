---
title: "第1章：SQLの動きを観察する道具を手に入れる"
---

## この章で分かること

最初の観察は、題名で1冊の本を探す小さなSQLから始めます。実験環境を用意し、EXPLAINで予定を、EXPLAIN ANALYZEで実際の処理を読みます。返したレコードと、条件で除外したレコードを区別し、番号で探した場合と比べます。以降の実験で使う観察の道具をそろえる章です。

## まずは1冊を探そう

いきなり大きなランキングを調べると、探す、数える、並べる処理が一度に出てきます。そこで、最初は「題名で1冊の本を探す」だけにします。

検索画面では、見つかった本しか見えません。

![検索画面には1冊だけが出ている。その裏のデータベースには本が100万冊あり、1冊を返すまでに何冊を調べたかを問う絵](/images/postgresql-query-journey/01-search-window.png)
*画面に出るのは1冊。その裏に、100万冊の一覧があります。*

画面に出た件数と、探すために調べた件数を分けて観察していきます。

次は、これから動かすSQLの例です。まだテーブルを作っていないので、実行は準備の後に行います。

```sql
SELECT id, title FROM books WHERE title = '実験用の本 42';
```

「本の一覧から、題名が一致する本の番号と題名を取り出して」という意味です。このSQLの`books`はテーブルの名前です。テーブルは、データを一覧として保存するものです。本書では、本1冊分のようなデータ1件を「レコード」と呼びます。番号や題名など、レコードに含まれる各項目が「列」です。SQLではレコードをrow（行）と呼ぶため、実行結果には`rows`と表示されます。`SELECT`は取り出す列、`FROM`は読むテーブル、`WHERE`は残すレコードの条件です。

まず、このSQLを試す場所を用意しましょう。

## SQLを入力する場所を作る

実験用リポジトリ [`postgresql-structures-lab`](https://github.com/hatsu38/postgresql-structures-lab) の `compose.yaml` を使います。GitとDocker Desktopなどを用意し、Dockerを起動します。まだ取得していなければ、ターミナルで次を実行してください。

```bash
git clone https://github.com/hatsu38/postgresql-structures-lab.git
cd postgresql-structures-lab
```

以降の`docker compose`コマンドは、このディレクトリで実行します。まずDBを起動します。

```bash
docker compose up -d --wait
```

PostgreSQLが接続を受け付けるまで待ってから、コマンドが終了します。続いて、SQLを入力する道具、`psql`を開きます。

```bash
docker compose exec db psql -X -U postgres -d reading_map
```

ここからは、入力用の`sql`枠をこのpsqlへ入力します。実行結果として示した枠は入力しません。末尾の`;`は「このSQLはここまで」という印です。ターミナルとpsqlのどちらへ入力するかに注意してください。

まず、エラーが起きたら止まる設定と、結果を一度に表示する設定をします。そのうえで、バージョンを確認します。

```sql
\set ON_ERROR_STOP on
\pset pager off
SELECT version();
```

`SELECT version();`の実行結果は次のとおりです。

```sql
                                                         version
--------------------------------------------------------------------------------------------------------------------------
 PostgreSQL 18.6 (Debian 18.6-1.pgdg13+2) on aarch64-unknown-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit
(1 row)
```

先頭の`PostgreSQL 18.6`が、接続先のデータベースサーバのバージョンです。ここではDocker内で動いているPostgreSQLを確認しています。`aarch64`はCPUのアーキテクチャを表し、この実行例はARM64環境です。

自分の結果では、まずPostgreSQLのバージョンを確認してください。CPUやビルド環境の部分は異なることがあります。実行計画を見比べるときの条件として、この出力も残しておきます。

## 本100万冊と読了記録200万件を用意する

次のSQLは最初の1回だけ実行します。実験用DBへ、本100万冊と読了記録200万件を入れます。

同じSQLを、リポジトリの `sql/01/00-setup.sql` にも置いてあります。ファイルから実行した場合は、ここで再び入力する必要はありません。

```sql
BEGIN;
CREATE TABLE books (
  id bigint PRIMARY KEY,
  title text NOT NULL
);
CREATE TABLE reading_records (
  book_id bigint NOT NULL,
  finished_at timestamp NOT NULL
);
INSERT INTO books
SELECT n, '実験用の本 ' || n FROM generate_series(1, 1000000) AS n;
INSERT INTO reading_records
SELECT ((floor(power(1 + u * (power(1000001::float8, 0.2) - 1), 5))::bigint
          * 386413) % 1000000) + 1,
       timestamp '2026-08-24'
         + ((n::bigint * 104729) % 2419200) * interval '1 second'
FROM (SELECT n, n * 0.6180339887498949::float8
                - floor(n * 0.6180339887498949::float8) AS u
      FROM generate_series(1, 2000000) AS n) AS s;
ANALYZE books;
ANALYZE reading_records;
SELECT count(*) FROM books;
SELECT count(*) FROM reading_records;
COMMIT;
```

読了記録は、よく読まれる本とそうでない本の差が出るように割り振っています。一番読まれた本は4週間で約2万件あり、1,000件以上の本は60冊です。一方で、記録が1〜2件の本が約62万冊、一度も読まれていない本も約26万冊あります。乱数は使っていないので、何度実行しても同じデータになります。

準備の実行結果です。二つの`count`が、本の冊数と読了記録の件数に対応します。

```sql
BEGIN
CREATE TABLE
CREATE TABLE
INSERT 0 1000000
INSERT 0 2000000
ANALYZE
ANALYZE
  count
---------
 1000000
(1 row)

  count
---------
 2000000
(1 row)
COMMIT
```

複数の操作をひとまとまりにして、まとめて確定したり取り消したりする単位を**トランザクション**と呼びます。ここでは`BEGIN`で始め、`COMMIT`で準備を確定しています。途中で失敗した場合は、`COMMIT`する前に次を入力すると、今回の準備を取り消せます。

```sql
ROLLBACK;
```

エラーの原因を直してから、準備を`BEGIN`からやり直します。すでに準備が完了したDBには、同じCREATE TABLEを重ねて実行しません。「既に存在する」というエラーなら、まずテーブルの件数を確認します。第3章以降から戻った場合の手順は、章末の「途中から実験を再開する」にまとめています。

`CREATE TABLE`に出てくる語の意味は次のとおりです。

| 書き方 | 意味 |
| --- | --- |
| `bigint` | 整数を入れる型 |
| `text` | 文字列を入れる型 |
| `timestamp` | 日時を入れる型 |
| `PRIMARY KEY` | 同じ番号の本を重複させない約束 |
| `NOT NULL` | 値がないことを表す`NULL`を許さない約束 |

`NULL`と、文字が0文字の空文字列`''`は別です。`NOT NULL`だけでは、空文字列の題名は禁止されません。

`generate_series`は連番を作ります。`||`で文字と番号をつなぐと、「実験用の本 1」「実験用の本 2」といった題名になります。読了記録を作る側の長い式は、本の番号と日時をばらけさせるためのものです。式を覚える必要はありません。

`count(*)`はレコードの数を数えます。結果が1,000,000と2,000,000になれば準備できました。

`ANALYZE books`はテーブルの特徴を調べ、SQLの処理手順（実行計画。この後で説明します）を立てる材料を集める命令です。詳しくは第10章で扱います。

初期データは以降の章でも使います。今回の環境では、booksテーブルと主キーのIndex（索引）で79 MB、読了記録で85 MBでした。作成中のログや、後で追加するIndexにも容量を使います。そのため、空き容量はこの合計より多めに用意してください。準備にかかる時間は環境で変わるので、コマンドが終わるまで待ってください。

観察する計画を読みやすくするため、次の設定も行います。接続し直した場合は再設定してください。

```sql
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
```

実行結果は、三つの設定が完了したことを示します。

```sql
SET
SET
SET
```

並列実行は複数のプロセスで処理を分担する仕組み、JITは実行時に処理の一部を機械語へ変換する仕組みです。最初は一つのプロセスの処理を追うため、どちらも無効にします。`work_mem`は並べ替えなどで使う作業用メモリの設定で、詳しくは後の章で扱います。

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

実験用リポジトリの環境で、次の結果が出ました。2026年9月23日、PostgreSQL 18.6、本100万冊での1回の実測です。データ準備と件数確認、先ほどのSELECTに続けて実行しています。初回のディスク読み込み速度を測ったものではありません。

```sql
Seq Scan on books  (cost=0.00..19853.00 rows=1 width=30) (actual time=0.036..35.994 rows=1.00 loops=1)
  Filter: (title = '実験用の本 42'::text)
  Rows Removed by Filter: 999999
  Buffers: shared hit=5112 read=2241
Planning Time: 0.008 ms
Execution Time: 36.037 ms
```

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

`Index Scan`は、**Index**という目録を使ってレコードを探す方法です。主キーを作ったとき、番号用のIndexも作られています。番号の検索で100万件を調べずに済んだのは、番号を重複させない約束があるからではなく、このIndexを使えたからです[^pk-seqscan]。題名用のIndexはまだありません。

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

本に載せた出力の[元ログ](https://github.com/hatsu38/postgresql-structures-lab/blob/main/results/chapter01-million-2026-09-23.txt)と[測定条件](https://github.com/hatsu38/postgresql-structures-lab/blob/main/results/README.md)も公開しています。自分の結果と見比べてみてください。

中断するときは、ターミナルで`docker compose stop`を実行します。再開するときは、`docker compose up -d --wait`の後、次のコマンドで接続し直します。

```bash
docker compose exec db psql -X -U postgres -d reading_map
```

データは残るので、テーブルの作成SQLを再実行する必要はありません。

## 第2章へ

1冊を返すために、100万件を調べていました。1冊見つかったところで止めれば、調べる量を減らせるでしょうか。次章では同じ100万冊に`LIMIT 1`を試します。

## 途中から実験を再開する

接続を閉じると、`SET`で指定した値と一時ビューは失われます。未完了のトランザクションも取り消されます。一方、COMMIT済みのテーブルやIndexは残ります。再接続は、実験用リポジトリのディレクトリから行います。

```bash
docker compose exec db psql -X -U postgres -d reading_map
```

再接続後の共通設定です。実験の途中で設定を変えたまま読み直すときも、新しい接続から始めると区別しやすくなります。

```sql
\set ON_ERROR_STOP on
\pset pager off
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
```

章ごとに必要な状態は次のとおりです。テーブルの件数は、基本データの本100万冊・記録200万件を維持します。

| 再開する章 | 開始時に必要な状態 | 章末に残るもの |
| --- | --- | --- |
| 第1〜2章 | 基本データあり、題名Indexなし | 基本データ |
| 第3章 | 題名Indexなし | `books_title_idx` |
| 第4章 | 題名Indexあり。`books_observation`を作る | `books_observation`を第5章へ残す |
| 第5章 | 題名Indexあり、`books_observation`に1,000冊 | `DROP TABLE`で観察用テーブルを削除 |
| 第6章 | 題名Indexあり。接続A・Bは同じDBへつなぐ | テーブル・Indexの変更なし |
| 第7章 | 日時Indexなし | `work_mem`を4MBへ戻す |
| 第8章 | 日時Indexなし | `reading_records_order_idx` |
| 第9章 | 日時Indexあり | 実験用の設定はROLLBACKで戻す |
| 第10章 | 基本データあり。実験用テーブルは冒頭から同じ接続で作る | ROLLBACKで`stats_demo`は消える |
| 第11章 | 日時Indexあり、A・Bの以前のトランザクションは終了 | 題名を復元し、可視性実験用Indexを削除する |
| 第12章 | 日時Indexあり。一時ビューはその接続で作る | 章末で集計テーブルとそのIndexを削除。一時ビューは切断で消える |

以下は**この本の実験用DBで、章を読み直すときだけ**使う準備です。初回に順番どおり読む場合は不要です。作業中のトランザクションを終えてから実行します。

:::details 第1〜3章へ戻り、題名Indexなしからやり直す
テーブルのデータは残し、第3章で作ったIndexだけを削除します。

```sql
DROP INDEX IF EXISTS public.books_title_idx;
ANALYZE public.books;
```

第1章のデータ準備は繰り返さず、件数を確認して検索の節から進めます。
:::

:::details 第4〜6章から始めるために題名Indexを用意する
第3章と同じ定義のIndexを用意します。同じ名前のIndexを自分で別の定義へ変更していないことが前提です。

```sql
CREATE INDEX IF NOT EXISTS books_title_idx ON public.books (title);
ANALYZE public.books;
```

第4章から作り直す場合は、この本で作った観察用テーブルだけを削除します。別の用途で同じ名前を使っている場合は実行しないでください。

```sql
DROP TABLE IF EXISTS books_observation, size_short, size_long;
```

第4章の作成SQLから再開します。第5章から再開する場合は削除せず、同章の件数確認から進めます。削除済みなら、同章の補足に準備SQLがあります。
:::

:::details 第7〜8章へ戻り、日時Indexなしからやり直す
第8章と第11章で作った実験用Indexを削除します。記録のレコードは削除しません。

```sql
DROP INDEX IF EXISTS public.reading_records_order_idx;
DROP INDEX IF EXISTS public.reading_records_visibility_idx;
ANALYZE public.reading_records;
```

第7章のメモリの設定から、または第8章の最初のSQLから再開します。
:::

:::details 第9章以降から始めるために日時Indexを用意する
第8章と同じ定義のIndexを用意します。

```sql
CREATE INDEX IF NOT EXISTS reading_records_order_idx
ON public.reading_records (finished_at DESC, book_id ASC);
ANALYZE public.reading_records;
```

第11章を途中からやり直す場合は、A・Bのトランザクションを終了し、残った可視性実験用Indexを削除してから章の冒頭へ戻ります。

```sql
DROP INDEX IF EXISTS public.reading_records_visibility_idx;
```
:::

:::details 第12章をやり直す
新しい接続を開くと、一時ビューを作り直せます。事前集計テーブルだけは残るので、この本で作ったテーブルを削除してから始めます。テーブルに付いたIndexも一緒に削除されます。

```sql
DROP TABLE IF EXISTS public.weekly_read_counts;
```

これまでの観察でキャッシュ、統計、可視性マップなどの状態は変わっています。これらの準備で、初回と同じ時間まで再現されるわけではありません。比較する実験どうしで条件をそろえ、方法・レコード数・アクセス量を確かめます。
:::
