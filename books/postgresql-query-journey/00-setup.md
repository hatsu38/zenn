---
title: "準備：実験環境を作る"
---

この本のSQLは、実験用リポジトリ [`postgresql-structures-lab`](https://github.com/hatsu38/postgresql-structures-lab) で起動するPostgreSQL 18で動かします。Dockerでの起動、データの作成、psqlの設定、中断した実験を再開する手順は、リポジトリの [README](https://github.com/hatsu38/postgresql-structures-lab#readme) にまとめました。本文には読むのに必要な実行結果を載せているので、手元で試さずに読み進めることもできます。

## 実験に使うデータ

本の一覧`books`と、読了記録`reading_records`の二つのテーブルを使います。

```sql
CREATE TABLE books (
  id bigint PRIMARY KEY,
  title text NOT NULL
);
CREATE TABLE reading_records (
  book_id bigint NOT NULL,
  finished_at timestamp NOT NULL
);
```

`books`には「実験用の本 1」から「実験用の本 1000000」まで、100万冊を入れます。`id`は本の番号で、`PRIMARY KEY`（主キー）は同じ番号の本を重複させない約束です。主キーには、番号から本を探すためのIndexが自動で作られます。`reading_records`には、誰かが本を読み終えた記録を200万件入れます。`book_id`が`books`の`id`に対応し、`finished_at`が読み終えた日時です。日時は2026年8月24日からの4週間に散らばります。

読了記録は、よく読まれる本ほど件数が多くなるように割り振っています。一番読まれた本は4週間で約2万件あり、記録が1〜2件の本が約62万冊、一度も読まれていない本も約26万冊あります。この偏りは、第10章で見積もりがずれる原因として出てきます。乱数は使っていないので、何度作っても同じデータになります。

## 測定の共通設定

psqlで接続したら、実行計画を観察する前に次の設定をします。**接続し直したら、毎回この設定を入力します。**

```sql
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
```

一つ目は、複数のプロセスで処理を分担する並列実行を止めます。二つ目は、実行時に処理の一部を機械語へ変換するJITを止めます。どちらも、一つのプロセスの仕事を1件ずつ追えるようにするためです。三つ目の`work_mem`は、並べ替えなどで使う作業用メモリの設定で、第7章で詳しく扱います。自分の結果に`Gather`や`JIT:`という行が出たら、この設定をし忘れていないかを確かめてください。

本に載せた実行結果は、本文が読む行だけを抜き出しています。省いた行は`…`で示しました。全体を見比べたいときは、リポジトリの [results/book](https://github.com/hatsu38/postgresql-structures-lab/blob/main/results/book/README.md) に章ごとの全文があります。時間と`Buffers`の数は、環境や直前の処理で変わるので、ミリ秒の一致ではなく、処理の方法とレコード数を比べてください。
