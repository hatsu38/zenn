---
title: "準備：実験環境を作る"
---

## この章ですること

この本では、手元のPostgreSQLで同じSQLを動かし、本に載せた実行結果と見比べながら進みます。この章では、実験用のPostgreSQLをDockerで起動し、本100万冊と読了記録200万件を用意します。あわせて、実行計画を読みやすくする設定をします。中断した実験を再開する手順は、巻末の付録にまとめています。第1章以降のSQLは、すべてこの章で用意するデータを使います。

本文には実行結果も載せているので、手元で試さずに読み進めることもできます。その場合は、この章を飛ばして第1章へ進んでください。後から試したくなったときに、この章へ戻ってきても構いません。

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

まず、エラーが起きたら止まる設定と、結果を一度に表示する設定をします。

```sql
\set ON_ERROR_STOP on
\pset pager off
```

実行結果です。`\set`は何も表示しません。

```sql:実行結果
Pager usage is off.
```

`\`で始まる行は、SQLではなくpsqlへの命令です。複数行をまとめて貼り付けると、`\`で始まる行の後ろに続くSQLが、その命令の続きとして扱われて実行されないことがあります。そのため本書では、`\`で始まる行の後ろにSQLを続けません。

続けて、バージョンを確認します。

```sql
SELECT version();
```

`SELECT version();`の実行結果は次のとおりです。

```sql:実行結果
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

```sql:実行結果
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

エラーの原因を直してから、準備を`BEGIN`からやり直します。すでに準備が完了したDBには、同じCREATE TABLEを重ねて実行しません。「既に存在する」というエラーなら、まずテーブルの件数を確認します。第3章以降から戻った場合の手順は、巻末の付録「途中から実験を再開する」にまとめています。

`CREATE TABLE`に出てくる語の意味は次のとおりです。

| 書き方 | 意味 |
| --- | --- |
| `bigint` | 整数を入れる型 |
| `text` | 文字列を入れる型 |
| `timestamp` | 日時を入れる型 |
| `PRIMARY KEY` | 同じ番号の本を重複させない約束 |
| `NOT NULL` | 値がないことを表す`NULL`を許さない約束 |

`NULL`と、文字が0文字の空文字列`''`は別です。`NOT NULL`だけでは、空文字列の題名は禁止されません。

`generate_series`は連番を作ります。`||`で文字と番号をつなぐと、「実験用の本 1」「実験用の本 2」といった題名になります。読了記録を作る側の長い式は、本の番号に人気の偏りを付け、日時をばらけさせるためのものです。式を覚える必要はありません。

`count(*)`はレコードの数を数えます。結果が1,000,000と2,000,000になれば準備できました。

`ANALYZE books`はテーブルの特徴を調べ、SQLの処理手順（実行計画。第1章で説明します）を立てる材料を集める命令です。詳しくは第10章で扱います。

初期データは以降の章でも使います。今回の環境では、booksテーブルと主キーのIndex（索引）で79 MB、読了記録で85 MBでした。作成中のログや、後で追加するIndexにも容量を使います。そのため、空き容量はこの合計より多めに用意してください。準備にかかる時間は環境で変わるので、コマンドが終わるまで待ってください。

観察する計画を読みやすくするため、次の設定も行います。接続し直した場合は再設定してください。

```sql
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
```

実行結果は、三つの設定が完了したことを示します。

```sql:実行結果
SET
SET
SET
```

並列実行は複数のプロセスで処理を分担する仕組み、JITは実行時に処理の一部を機械語へ変換する仕組みです。最初は一つのプロセスの処理を追うため、どちらも無効にします。`work_mem`は並べ替えなどで使う作業用メモリの設定で、詳しくは後の章で扱います。

:::details 本書で止めている並列実行とJIT
二つの設定をしないまま実験すると、この本とは違う形の計画が出ることがあります。2026年9月26日、PostgreSQL 18.6の既定の設定（`max_parallel_workers_per_gather = 2`、`jit = on`）で、第1章で行う題名検索を実行した結果です。

```sql:実行結果
Gather  (cost=1000.00..13561.43 rows=1 width=30) (actual time=0.415..39.677 rows=1.00 loops=1)
  Workers Planned: 2
  Workers Launched: 2
  Buffers: shared hit=1498 read=5855 dirtied=5882 written=5855
  ->  Parallel Seq Scan on books  (cost=0.00..12561.33 rows=1 width=30) (actual time=23.375..35.797 rows=0.33 loops=3)
        Filter: (title = '実験用の本 42'::text)
        Rows Removed by Filter: 333333
        Buffers: shared hit=1498 read=5855 dirtied=5882 written=5855
Planning:
  Buffers: shared hit=62 read=1 written=1
Planning Time: 0.486 ms
Execution Time: 39.765 ms
```

`Workers Launched: 2`は、手伝いのプロセスが2つ動いたことを示します。`Parallel Seq Scan`は、SQLを受け取ったプロセスと手伝いの2つ、合わせて3つでテーブルを分けて読みました。`loops=3`はその3つを表し、`rows=0.33`や`Rows Removed by Filter: 333333`は、1つのプロセス当たりの平均です。全体の件数を知るには3倍します。`Gather`は、3つのプロセスが見つけたレコードを集める処理です。

序章のランキングのように見積もり（`cost`）の大きいSQLでは、出力の最後に`JIT:`の行も出ます。見積もりが既定で100000を超えると、処理の一部を機械語へ変換してから実行するためです。

```sql:実行結果
JIT:
  Functions: 37
  Options: Inlining false, Optimization false, Expressions true, Deforming true
  Timing: Generation 1.441 ms (Deform 0.399 ms), Inlining 0.000 ms, Optimization 0.706 ms, Emission 12.385 ms, Total 14.533 ms
```

`Timing`の`Total`が、変換にかかった時間です。この時間も`Execution Time`に含まれます。

本書でこの二つを止めるのは、一つのプロセスの仕事を1件ずつ追えるようにするためと、変換の時間を実行時間に混ぜないためです。自分の結果に`Gather`や`JIT:`が出たら、上の設定をし忘れていないかを確かめてください。
:::

## 第1章へ

これで実験の準備ができました。第1章では、このデータで題名から1冊を探すSQLを動かし、EXPLAINでその中身を見ます。

途中で中断したときや、章を読み直すときの手順は、巻末の付録「途中から実験を再開する」にまとめています。
