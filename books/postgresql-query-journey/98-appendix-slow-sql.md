---
title: "付録：自分の遅いSQLを調べる"
---

本文では、ランキングという一つのSQLを最後まで追いました。この付録では、同じ読み方を自分の仕事のSQLに当てはめるための手順と、よく出会う遅い書き方をまとめます。

後半のパターンの実行結果は、この本の実験用DB（第12章まで進めた状態）で、2026年9月28日にPostgreSQL 18.6で測ったものです。並列実行とJITは無効、`work_mem`は4MBです。Indexを作る実験は`BEGIN`と`ROLLBACK`の間で行い、元に戻しています。

## 手順1：遅いSQLを見つける

調べる前に、どのSQLが遅いのかを見つけます。PostgreSQLには、そのための仕組みがいくつかあります。

- **pg_stat_statements**：SQLの形ごとに、実行回数（`calls`）、合計時間（`total_exec_time`）、平均時間（`mean_exec_time`）を記録する拡張機能です。使うには、設定の`shared_preload_libraries`に加えてサーバを再起動し、`CREATE EXTENSION`します[^pgss]。この本の実験環境では有効にしていません。
- **log_min_duration_statement**：指定した時間より長くかかったSQLを、サーバのログに書き出す設定です[^log-min]。
- **auto_explain**：遅かったSQLの実行計画を、自動でログに書き出す拡張機能です[^auto-explain]。本番で`EXPLAIN ANALYZE`を手で実行しなくても、そのときの計画が残ります。

[^pgss]: [公式ドキュメントのpg_stat_statementsの説明](https://www.postgresql.org/docs/18/pgstatstatements.html)にあります。

[^log-min]: [公式ドキュメントのログの設定の説明](https://www.postgresql.org/docs/18/runtime-config-logging.html)にあります。

[^auto-explain]: [公式ドキュメントのauto_explainの説明](https://www.postgresql.org/docs/18/auto-explain.html)にあります。

1回ずつは速くても、何千回も実行されて合計が大きくなっているSQLもあります。`pg_stat_statements`で`calls`の多いSQLを見ると、後で扱う「同じSQLを何度も送る」書き方が見つかります。

## 手順2：アプリケーションのSQLを取り出す

ORM（オブジェクトからSQLを組み立ててくれるライブラリ）を使っていると、実際に送られるSQLが見えません。主なフレームワークには、組み立てたSQLを表示する機能があります。

| フレームワーク | SQLを見る | 実行計画を見る |
| --- | --- | --- |
| Ruby on Rails | `relation.to_sql` | `relation.explain`（`explain(:analyze)`のように指定もできる） |
| Django | 設定の`DEBUG`を有効にして`connection.queries` | `queryset.explain(analyze=True)` |
| Laravel | `->dumpRawSql()`、`->ddRawSql()` | 取り出したSQLをpsqlで`EXPLAIN`する |

それぞれの説明は、[RailsのAPIドキュメント](https://api.rubyonrails.org/classes/ActiveRecord/Relation.html)、[DjangoのQuerySetの説明](https://docs.djangoproject.com/en/5.2/ref/models/querysets/)と[FAQ](https://docs.djangoproject.com/en/5.2/faq/models/)、[Laravelのクエリビルダの説明](https://laravel.com/docs/12.x/queries)にあります。取り出したSQLは、値が埋め込まれた形でpsqlに貼り、この本と同じように`EXPLAIN`で調べられます。

## 手順3：安全に測る

`EXPLAIN ANALYZE`は、SQLを実際に実行します（第1章）。本番のDBや共有の検証環境で調べるときは、次の順で進めます。

1. まず`ANALYZE`を付けない`EXPLAIN`で、実行せずに計画の形を見ます。
2. `UPDATE`や`DELETE`を`EXPLAIN ANALYZE`で調べるときは、`BEGIN`の後に実行し、`ROLLBACK`で取り消します。第10章と第11章の実験と同じ形です。
3. 時間がかかりそうなSQLには、`SET LOCAL statement_timeout = '5s';`のように上限を付けます。上限を超えたSQLは途中で止まります[^timeout]。
4. できれば本番と同じくらいのデータを持つ検証用のDBで測ります。レコード数が違うと、選ばれる計画も変わります（第3章、第10章）。

[^timeout]: [公式ドキュメントのstatement_timeoutの説明](https://www.postgresql.org/docs/18/runtime-config-client.html)にあります。

この本では並列実行とJITを止めて測りました（「準備」の章）。本番の計画には、並列実行を表す`Gather`が現れることがあります。その下に並ぶ処理は、この本と同じく、字下げのいちばん深いところから読みます。

## 手順4：出力のどこを見るか

計画を下から読み（第6章）、気になる表示があったら、次の表で疑うことと戻る章を引きます。表示そのものの意味は、付録「実行計画の読み方の早見表」にまとめました。第12章の最後の表は仕組みから引く表でしたが、こちらは出力の表示から引く表です。

| 出力に見えること | 疑うこと | 試すこと | 戻る章 |
| --- | --- | --- | --- |
| Seq Scanの`Rows Removed by Filter`が大きく、返すレコードは少ない | 条件の列にIndexがない、またはIndexを使えない書き方 | 条件の列にIndexを作る。列を関数で包まない（パターン1〜3） | 第1〜3章 |
| `rows`と`actual rows`が桁違い | 統計が古い、値の偏りを標本が表せていない | `ANALYZE`、統計の目標値を上げる | 第10章 |
| `Nested Loop`の内側の`loops`が大きい | 外側のレコード数の見積もりのずれ | 見積もりのずれた段を探す | 第9・10章 |
| `Sort Method: external merge`、`Batches`が2以上、`temp` | 作業用メモリに収まらない | 扱うレコード数を減らす。`work_mem`を変えても速くなるとは限らない | 第7・9・12章 |
| `LIMIT`なのに子の`actual rows`が大きい | 大きな`OFFSET`、順序を使えない並べ替え | 順序に合うIndex、`OFFSET`を減らす（パターン4） | 第8章 |
| Index Only Scanなのに`Heap Fetches`が多い | VACUUMの前、長く開いたままのトランザクション | VACUUM、`idle in transaction`の確認 | 第8・11章 |
| 最後の段で急にレコード数が減る | 減らせる処理を後回しにしている | 集計や上位の選択を先にできるか考える | 第12章 |
| `shared read`が多い、時間が回ごとに揺れる | キャッシュの状態 | 何回か測る。レコード数とページ数で比べる | 第5章 |

## よくある遅い書き方

ここからは、同じ結果を返すのに仕事量が大きく変わる書き方を、この本のデータで比べます。どれも、実行計画のレコード数とページへのアクセスで違いを確かめられます。

### パターン1：条件の列を関数で包む

9月14日に読み終えた記録を数えます。`date(finished_at)`と書くと分かりやすいのですが、計画を比べると違いがあります。

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM reading_records
WHERE date(finished_at) = date '2026-09-14';
```

実行結果です。

```sql:実行結果
Aggregate  (cost=40836.00..40836.01 rows=1 width=8) (actual time=142.223..142.224 rows=1.00 loops=1)
  Buffers: shared read=10811
  ->  Seq Scan on reading_records  (cost=0.00..40811.00 rows=10000 width=0) (actual time=0.156..138.612 rows=71430.00 loops=1)
        Filter: (date(finished_at) = '2026-09-14'::date)
        Rows Removed by Filter: 1928570
        Buffers: shared read=10811
Planning:
  Buffers: shared hit=33 read=3
Planning Time: 0.441 ms
Execution Time: 142.243 ms
```

同じ日を、範囲の条件で書きます。

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM reading_records
WHERE finished_at >= timestamp '2026-09-14'
  AND finished_at < timestamp '2026-09-15';
```

実行結果です。

```sql:実行結果
Aggregate  (cost=2790.24..2790.25 rows=1 width=8) (actual time=14.761..14.761 rows=1.00 loops=1)
  Buffers: shared read=278
  ->  Index Only Scan using reading_records_order_idx on reading_records  (cost=0.43..2606.93 rows=73325 width=0) (actual time=1.418..11.407 rows=71430.00 loops=1)
        Index Cond: ((finished_at >= '2026-09-14 00:00:00'::timestamp without time zone) AND (finished_at < '2026-09-15 00:00:00'::timestamp without time zone))
        Heap Fetches: 7
        Index Searches: 1
        Buffers: shared read=278
Planning:
  Buffers: shared hit=6 read=1
Planning Time: 0.127 ms
Execution Time: 14.784 ms
```

どちらも71,430件を数えています。`date(finished_at)`の書き方では、第8章の日時のIndexを使えず、200万件の記録を順に読んで1,928,570件を除外しました。Indexに並んでいるのは`finished_at`の値そのもので、`date(finished_at)`の値ではないからです。範囲で書くと、Indexから9月14日の部分だけを読み、ページへのアクセスも10,811回から278回に減りました。

関数で包んだ条件を使い続けたいときは、その式そのもので作るIndex（式のIndex）もあります。パターン3でその例を使います。

### パターン2：前方一致のLIKEと照合順序

題名が「実験用の本 4200」で始まる本を探します。第3章で題名のIndexを作ったので、使われそうに見えます。

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books WHERE title LIKE '実験用の本 4200%';
```

実行結果です。

```sql:実行結果
Seq Scan on books  (cost=0.00..19853.00 rows=100 width=30) (actual time=1.151..73.120 rows=111.00 loops=1)
  Filter: (title ~~ '実験用の本 4200%'::text)
  Rows Removed by Filter: 999889
  Buffers: shared hit=1 read=7352
Planning:
  Buffers: shared hit=31 read=4
Planning Time: 0.749 ms
Execution Time: 73.143 ms
```

題名のIndexがあるのに、Seq Scanで100万冊を調べました。この本の実験用DBの照合順序は`en_US.utf8`で、題名のIndexもこの並び順で作られています。この並び順では、文字列の前から何文字かが同じものが、必ず隣に並ぶとは限りません。そのため、前方一致の`LIKE`にはこのIndexを使えません。

前方一致に使えるのは、文字を一文字ずつ比べる並び順で作ったIndexです[^pattern-ops]。実験の間だけ作って試します。

[^pattern-ops]: `text_pattern_ops`という演算子クラスを指定します。[公式ドキュメントの演算子クラスの説明](https://www.postgresql.org/docs/18/indexes-opclass.html)にあります。第3章で範囲検索の比較を`COLLATE "C"`にしたときに速くなったのも、同じ「一文字ずつ比べる並び順」を使ったためです。

```sql
BEGIN;
CREATE INDEX books_title_pattern_idx ON books (title text_pattern_ops);
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books WHERE title LIKE '実験用の本 4200%';
ROLLBACK;
```

実行結果です。

```sql:実行結果
Index Scan using books_title_pattern_idx on books  (cost=0.42..8.45 rows=100 width=30) (actual time=0.070..0.154 rows=111.00 loops=1)
  Index Cond: ((title ~>=~ '実験用の本 4200'::text) AND (title ~<~ '実験用の本 4201'::text))
  Filter: (title ~~ '実験用の本 4200%'::text)
  Index Searches: 1
  Buffers: shared hit=18 read=7
Planning:
  Buffers: shared hit=53 read=1
Planning Time: 0.303 ms
Execution Time: 0.172 ms
```

`Index Cond`に、「実験用の本 4200」以上「実験用の本 4201」未満という範囲が現れました。PostgreSQLは前方一致を範囲に置き換え、Indexからその範囲の111冊だけを取り出しています。ページへのアクセスは7,353回から25回になりました。

### パターン3：複合Indexの列の順番

本42の記録を探します。いまある読了記録のIndexは、第8章の`(finished_at DESC, book_id)`です。

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, finished_at FROM reading_records WHERE book_id = 42;
```

実行結果です。

```sql:実行結果
Seq Scan on reading_records  (cost=0.00..35811.00 rows=24 width=16) (actual time=64.554..64.555 rows=1.00 loops=1)
  Filter: (book_id = 42)
  Rows Removed by Filter: 1999999
  Buffers: shared hit=95 read=10716
Planning:
  Buffers: shared hit=8
Planning Time: 0.091 ms
Execution Time: 64.573 ms
```

`book_id`はIndexの2番目の列なので、このIndexは日時の順に並んでいて、本42の記録は全体に散らばっています。PostgreSQLは200万件を順に読むほうを選びました。本番号を先頭にしたIndexを、実験の間だけ作って比べます。

```sql
BEGIN;
CREATE INDEX reading_records_book_first_idx ON reading_records (book_id, finished_at);
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, finished_at FROM reading_records WHERE book_id = 42;
ROLLBACK;
```

実行結果です。

```sql:実行結果
Index Only Scan using reading_records_book_first_idx on reading_records  (cost=0.43..8.85 rows=24 width=16) (actual time=0.061..0.062 rows=1.00 loops=1)
  Index Cond: (book_id = 42)
  Heap Fetches: 0
  Index Searches: 1
  Buffers: shared hit=4 read=3
Planning:
  Buffers: shared hit=7 read=1
Planning Time: 0.151 ms
Execution Time: 0.076 ms
```

同じ2つの列を持つIndexでも、先頭の列で絞れる条件かどうかで、使えるかが変わります。複合Indexは、先頭の列の順に並べた辞書のようなものです。

ただし、PostgreSQL 18では、先頭の列の条件がなくてもIndexを使える**skip scan**という読み方が加わりました。先頭の列の値の種類が少ないときに、その値ごとにIndexを探し直す方法です[^skip-scan]。読了日（4週間分で28種類）を先頭にした式のIndexで試します。

[^skip-scan]: [公式ドキュメントの複合Indexの説明](https://www.postgresql.org/docs/18/indexes-multicolumn.html)に、先頭の列の値の種類が少ないときに選ばれ、多いときは多くの場合Seq Scanが選ばれる、と書かれています。上の`(finished_at DESC, book_id)`でSeq Scanになったのは、`finished_at`の値の種類が多いためです。

```sql
BEGIN;
CREATE INDEX reading_records_day_book_idx ON reading_records ((date(finished_at)), book_id);
ANALYZE reading_records;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM reading_records WHERE book_id = 42;
ROLLBACK;
```

実行結果です。

```sql:実行結果
Aggregate  (cost=132.90..132.91 rows=1 width=8) (actual time=0.781..0.781 rows=1.00 loops=1)
  Buffers: shared hit=35 read=59
  ->  Index Only Scan using reading_records_day_book_idx on reading_records  (cost=0.43..132.84 rows=23 width=0) (actual time=0.174..0.777 rows=1.00 loops=1)
        Index Cond: (book_id = 42)
        Heap Fetches: 0
        Index Searches: 29
        Buffers: shared hit=35 read=59
Planning:
  Buffers: shared hit=19 read=1
Planning Time: 0.200 ms
Execution Time: 0.842 ms
```

`Index Searches: 29`は、Indexを29回探しに行ったことを表します。28日分の読了日ごとに「この日の本42」を探し直しています。Index Searchesの数は、第3章で見たときはいつも1でした。1より大きいときは、Indexを何度も探し直す読み方になっています。

### パターン4：大きなOFFSET

最近の記録の一覧で、5,001ページ目（1ページ20件）を表示するとします。

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, finished_at FROM reading_records
ORDER BY finished_at DESC, book_id ASC
LIMIT 20 OFFSET 100000;
```

実行結果です。

```sql:実行結果
Limit  (cost=3039.23..3039.84 rows=20 width=16) (actual time=18.797..18.802 rows=20.00 loops=1)
  Buffers: shared hit=3 read=385
  ->  Index Only Scan using reading_records_order_idx on reading_records  (cost=0.43..60776.43 rows=2000000 width=16) (actual time=0.867..15.084 rows=100020.00 loops=1)
        Heap Fetches: 9
        Index Searches: 1
        Buffers: shared hit=3 read=385
Planning:
  Buffers: shared hit=31
Planning Time: 0.121 ms
Execution Time: 18.820 ms
```

`Limit`が返したのは20件ですが、子の`Index Only Scan`は100,020件を読んでいます。`OFFSET`で飛ばす10万件も、Indexから読んで捨てているからです。1ページ目（`OFFSET`なし）なら、子が読むのは20件で、0.022 msでした。ページ番号が大きくなるほど、読んで捨てる件数が増えます。前のページの最後の値から続きを探す書き方にすれば、読む件数をページの件数に近づけられる可能性があります（この本では測っていません）。

### パターン5：範囲の条件は、結合の相手に伝わらない

第9章のMerge Joinで見たとおり、`WHERE b.id <= 100`は本の側だけの条件で、読了記録の`r.book_id`には自動では伝わりません。結合の両側で同じ範囲に絞れることが分かっているなら、`AND r.book_id <= 100`のように両側に書くと、結合の前に扱うレコード数を減らせます。

### パターン6：同じSQLを何度も送る

一覧の20冊それぞれについて、アプリケーションが題名を1冊ずつ問い合わせると、SQLが21回送られます。この書き方はN+1と呼ばれます。1回ずつは速いので、一つのSQLの実行計画を見ても気付けません。手順1の`pg_stat_statements`で、同じ形のSQLの`calls`が多いことから見つけます。

第9章の`Nested Loop`（`loops=20`）は、同じ仕事をDBの中で1回のSQLにまとめたものでした。ORMには、関連するレコードをまとめて読む機能があります。Railsの`includes`、Djangoの`select_related`、Laravelの`with`です。

## コラム：PostgreSQL 18で変わった出力

この本の出力は、すべてPostgreSQL 18.6で採りました。古い版のPostgreSQLで同じSQLを実行すると、表示が少し違います。18で変わった主な点は次のとおりです[^release-18]。

- `EXPLAIN ANALYZE`に、`BUFFERS`を書かなくてもバッファの情報が表示されるようになりました（第1章の脚注）。
- `actual`の`rows`が、`rows=1.00`のように小数で表示されるようになりました。`loops`が複数のとき、1回当たりの平均を丸めずに示せます。
- Indexを使う処理に、Indexを探しに行った回数`Index Searches`が表示されるようになりました（パターン3）。
- 複合Indexの先頭の列に条件がなくても、skip scanでIndexを使えることがあります（パターン3）。
- 非同期I/Oが加わり、設定`io_method`で方式を選べるようになりました。この本の実験環境は既定の`worker`のままです。Seq ScanやBitmap Heap Scanなどの読み込みに効くことがあると説明されていますが、この本では違いを測っていません。

[^release-18]: [PostgreSQL 18のリリースノート](https://www.postgresql.org/docs/18/release-18.html)にあります。
