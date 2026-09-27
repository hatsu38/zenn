---
title: "付録：途中から実験を再開する"
---

本文の実験を途中で中断したときや、章を読み直すときの手順です。初めて順番どおりに読むときは使いません。

中断するときは、ターミナルで`docker compose stop`を実行します。再開するときは、実験用リポジトリのディレクトリで、DBを起動してから接続し直します。

```bash
docker compose up -d --wait
```

接続を閉じると、`SET`で指定した値と一時ビューは失われます。未完了のトランザクションも取り消されます。一方、COMMIT済みのテーブルやIndexは残るので、テーブルの作成SQLを再実行する必要はありません。再接続も、実験用リポジトリのディレクトリから行います。

```bash
docker compose exec db psql -X -U postgres -d reading_map
```

再接続後の共通設定です。実験の途中で設定を変えたまま読み直すときも、新しい接続から始めると区別しやすくなります。

```sql
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
\set ON_ERROR_STOP on
\pset pager off
```

章ごとに必要な状態は次のとおりです。テーブルの件数は、基本データの本100万冊・記録200万件を維持します。

| 再開する章 | 開始時に必要な状態 | 章末に残るもの |
| --- | --- | --- |
| 第1〜2章 | 基本データあり、題名Indexなし | 基本データ |
| 第3章 | 題名Indexなし | `books_title_idx` |
| 第4章 | 題名Indexあり。`books_observation`を作る | `books_observation`を第5章へ残す |
| 第5章 | 題名Indexあり、`books_observation`に1,000冊 | `DROP TABLE`で観察用テーブルを削除 |
| 第6章 | 題名Indexあり。章末の補足では、接続A・Bを同じDBへつなぐ | テーブル・Indexの変更なし |
| 第7章 | 日時Indexなし | `work_mem`を4MBへ戻す |
| 第8章 | 日時Indexなし | `reading_records_order_idx` |
| 第9章 | 日時Indexあり | 実験用の設定はROLLBACKで戻す |
| 第10章 | 基本データあり。実験用テーブルは冒頭から同じ接続で作る | ROLLBACKで`stats_demo`は消える |
| 第11章 | 日時Indexあり、A・Bの以前のトランザクションは終了 | 題名を復元し、可視性実験用Indexを削除する |
| 第12章 | 日時Indexあり。一時ビューはその接続で作る | 章末で集計テーブルとそのIndexを削除。一時ビューは切断で消える |

以下は**この本の実験用DBで、章を読み直すときだけ**使う準備です。初回に順番どおり読む場合は不要です。作業中のトランザクションを終えてから実行します。

:::details 初期データを入れた直後の状態に戻す
どの章から戻る場合でも使える、いちばん簡単な方法です。本の中で作ったIndex・テーブル・拡張と、書き換えたデータをまとめて消し、「準備」の章で本100万冊と読了記録200万件を入れた直後の状態に戻します。psqlではなく**ターミナルで**、実験用リポジトリのディレクトリから実行します。

```bash
docker compose exec -T db psql -X -U postgres -d reading_map -f /lab/sql/reset.sql
```

最後に「第1章の初期データを確認しました。」と表示されれば完了です。同じDBにつないでいた他のpsqlは切断されます。開いていたpsqlは接続し直し、再接続後の共通設定を入力してから、第1章の検索の節へ進みます。
:::

:::details 第1〜3章へ戻り、題名Indexなしからやり直す
テーブルのデータは残し、第3章で作ったIndexだけを削除します。

```sql
DROP INDEX IF EXISTS public.books_title_idx;
ANALYZE public.books;
```

「準備」の章のデータ準備は繰り返さず、件数を確認してから第1章の検索の節へ進みます。
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
