---
title: "第6章：長い実行計画は、どこから読むのか"
---

## この章で分かること

序章のランキングSQLに`EXPLAIN ANALYZE`を付けると、20行を超える出力が返ります。どこから読めばよいのかを、実行計画の形から確かめます。SQLの文字列が解析・計画・実行と進む流れを図で追い、小さな計画で、上の処理が下の処理にレコードを求める「計画の木」の読み方を確かめます。その読み方で、ランキングの計画をいちばん深いところから読みます。最後に、出力の`Buffers`と`Memory`を手掛かりに、共有するメモリと処理ごとの作業領域を区別します。接続ごとにSQLを処理するプロセスの観察は、章末の補足に置きます。

:::message
第3章の題名Indexが必要です。テーブルやIndexを新しく作る章ではありません。章末の補足では、接続A・Bを同じ実験用DBへつなぎます。
:::

## ランキングの計画が読めない

第5章までで、1冊を探す計画を読めるようになりました。今度は、序章のランキングSQLに`EXPLAIN (ANALYZE, BUFFERS)`を付けて実行します。

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT b.id, b.title, count(*) AS read_count
FROM books AS b
JOIN reading_records AS r ON r.book_id = b.id
WHERE r.finished_at >= timestamp '2026-09-14'
  AND r.finished_at < timestamp '2026-09-21'
GROUP BY b.id, b.title
ORDER BY read_count DESC, b.id ASC
LIMIT 20;
```

2026年9月26日、PostgreSQL 18.6での実行結果です。本100万冊・読了記録200万件で、第3章の題名Indexがあり、読了記録にはまだIndexがありません。並列実行とJITは無効、`work_mem`は4MBです。

```sql
Limit  (cost=153548.50..153548.55 rows=20 width=38) (actual time=627.239..627.244 rows=20.00 loops=1)
  Buffers: shared hit=4288 read=13879, temp read=9046 written=10758
  ->  Sort  (cost=153548.50..154780.84 rows=492937 width=38) (actual time=627.238..627.241 rows=20.00 loops=1)
        Sort Key: (count(*)) DESC, b.id
        Sort Method: top-N heapsort  Memory: 27kB
        Buffers: shared hit=4288 read=13879, temp read=9046 written=10758
        ->  HashAggregate  (cost=128762.88..140431.62 rows=492937 width=38) (actual time=552.463..606.428 rows=255238.00 loops=1)
              Group Key: b.id
              Planned Partitions: 8  Batches: 9  Memory Usage: 8281kB  Disk Usage: 15584kB
              Buffers: shared hit=4285 read=13879, temp read=9046 written=10758
              ->  Hash Join  (cost=36689.00..89481.96 rows=492937 width=30) (actual time=168.642..459.483 rows=499998.00 loops=1)
                    Hash Cond: (r.book_id = b.id)
                    Buffers: shared hit=4285 read=13879, temp read=7278 written=7278
                    ->  Seq Scan on reading_records r  (cost=0.00..40811.00 rows=492937 width=8) (actual time=0.154..101.089 rows=499998.00 loops=1)
                          Filter: ((finished_at >= '2026-09-14 00:00:00'::timestamp without time zone) AND (finished_at < '2026-09-21 00:00:00'::timestamp without time zone))
                          Rows Removed by Filter: 1500002
                          Buffers: shared hit=2048 read=8763
                    ->  Hash  (cost=17353.00..17353.00 rows=1000000 width=30) (actual time=168.081..168.082 rows=1000000.00 loops=1)
                          Buckets: 131072  Batches: 16  Memory Usage: 4883kB
                          Buffers: shared hit=2237 read=5116, temp written=5815
                          ->  Seq Scan on books b  (cost=0.00..17353.00 rows=1000000 width=30) (actual time=0.015..63.978 rows=1000000.00 loops=1)
                                Buffers: shared hit=2237 read=5116
Planning:
  Buffers: shared hit=103 read=6
Planning Time: 0.434 ms
Execution Time: 628.771 ms
```

これまでの1冊を探す計画は、数行でした。今回は20行を超え、`Sort`、`HashAggregate`、`Hash Join`、`Hash`と、まだ説明していない名前が並んでいます。一つずつの名前の意味は、第7〜9章で調べます。この章では、その前に、この出力をどの順で読めばよいかを決めます。

## 文字列が手順になるまで

長い計画を読む前に、PostgreSQLがSQLを受け取ってから結果を返すまでの流れを確かめます。

SQLは、最初は文字の列です。PostgreSQLは、その文字をいきなり実行するのではありません。まず意味を確かめ、結果を作るための手順に組み立てます。

第3章で試した題名検索を例に、SQLを受け取ってから結果を返すまでを並べます。図の矢印は、処理が進む順番です。

![SQLの文字列が解析・書き換え・計画・実行の4段を通って結果のレコードになり、EXPLAINは計画まで、EXPLAIN ANALYZEは実行まで進んでレコードは出さない](/images/postgresql-query-journey/02-query-stages.png)
*右の括弧で、EXPLAINとEXPLAIN ANALYZEがどの段まで進むかを見てください（処理の順番の概略）。*

まず、SQLの文法と、指定されたテーブルや列が存在するかを確認します。続いて、問い合わせ（SQL）をDBに登録された規則に沿って書き換える段階を通ります[^view]。今回のSQLは通常のテーブル`books`を直接指定しているので、書き換えは起きません。

[^view]: たとえば、検索に名前を付けてテーブルのように使うビュー（VIEW）を参照しているなら、この段階でその定義に基づく問い合わせへ置き換えます。

次に、テーブルを順に読むか、Indexを使うかなどを比較して、実行計画を作ります。実行計画を作る部分を**プランナ**と呼びます。出来上がった計画に従ってページを使い、条件を確かめてレコードを返す部分が**エグゼキュータ（実行器）**です。[公式の処理経路の説明](https://www.postgresql.org/docs/18/query-path.html)も、この順序で整理されています。

第1章の表で見た`EXPLAIN`と`EXPLAIN ANALYZE`の違いは、この図の「計画」と「実行」の段に当たります。`EXPLAIN`だけなら計画を作って表示するところまで、`EXPLAIN ANALYZE`なら計画を実行して計測するところまで進みます。

第1章で見た`Planning Time`は計画を作る段階、`Execution Time`は実行する段階にかかった時間です。ただし、この二つを足せば画面の待ち時間を全部説明できるわけではありません。通信や結果の表示にも時間がかかります。

## LimitとIndex Scanのレコードの受け渡し

次のSQLを、まず実行せずに観察します。

```sql
EXPLAIN
SELECT id, title FROM books ORDER BY title LIMIT 3;
```

2026年9月23日、DockerのPostgreSQL 18.6、本100万冊で第3章の題名のIndexがある状態で採取した出力です。

```sql
Limit  (cost=0.42..0.57 rows=3 width=30)
  ->  Index Scan using books_title_idx on books  (cost=0.42..49666.10 rows=1000000 width=30)
```

`Index Scan`がIndexの順にレコードを読み、`Limit`が3件まで受け取る計画です。

`Index Scan`の`rows=1000000`は最後まで実行した場合の見積もりです。上の`Limit`は3件で要求を止める計画なので、100万件すべてを読む予定ではありません。ここでは`EXPLAIN`だけを実行しているため、実際のレコード数や時間は表示されていません。実際のレコード数は`EXPLAIN ANALYZE`で確かめられます。

実際の受け渡しも測ってみます。

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books ORDER BY title LIMIT 3;
```

2026年9月25日、PostgreSQL 18.6で新規DBへ本100万冊を用意し、第3章の題名Indexを作った状態での実行結果です。並列実行とJITは無効です。

```sql
Limit  (cost=0.42..0.57 rows=3 width=30) (actual time=0.015..0.016 rows=3.00 loops=1)
  Buffers: shared hit=2 read=2
  ->  Index Scan using books_title_idx on books  (cost=0.42..49247.50 rows=1000000 width=30) (actual time=0.014..0.015 rows=3.00 loops=1)
        Index Searches: 1
        Buffers: shared hit=2 read=2
Planning Time: 0.022 ms
Execution Time: 0.020 ms
```

Index Scanの推定は最後まで読んだ場合の100万件ですが、実際には3件を返して止まっています。上のLimitの`actual rows=3`と、子の`actual rows=3`が対応しました。

実行計画は、上の処理が下の処理からレコードを受け取る親子の形をしているので、計画の木と呼ばれます。この二つの処理がレコードを受け渡す様子を図にします。左の矢印がレコードを返す向き、右が次のレコードを要求する向きです。

![Limitが次のレコードを3回要求し、Index Scanが題名の順に3件を返す。4回目は要求しない。出力の見積もりはLimitがrows=3、Index Scanがrows=1000000](/images/postgresql-query-journey/02-execution-tree.png)
*①〜③の3往復の後、4回目の要求をしないことを見てください（直前の計画に対応させて説明するための図。rowsは見積もり）。*

実行時は、上の`Limit`が下の`Index Scan`に次の1件を要求します。`Index Scan`は題名のIndexをたどり、テーブルから取り出したレコードを返します。この受け渡しを繰り返し、`Limit`は3件を受け取ったら要求を止める計画です。

今回の計画には、並べ替えを表す`Sort`がありません。題名のIndexから、`ORDER BY title`で求めた順にレコードを取り出せるためです。Indexで順序を得られない場合の並べ替えは、次章で扱います。

## 長い計画を木として読む

小さな計画で確かめた読み方を、ランキングの計画に当てはめます。手掛かりは次の三つです。

- 行頭の`->`と字下げ：字下げが一段深い処理が、すぐ上の処理の子です。子は親にレコードを渡します。
- 同じ深さに並ぶ子：`Hash Join`の下には、`Seq Scan on reading_records r`と`Hash`の二つの子があります。一つの処理が、二つの子からレコードを受け取ることもあります。
- `actual`の`rows`：その処理が親へ渡したレコードの数です。

レコードは下から上へ流れます。そこで、字下げのいちばん深い処理から読み始め、親へ向かって`rows`を追います。

| 読む順 | 処理 | 親へ渡したレコード | していること |
| ---: | --- | ---: | --- |
| 1 | `Seq Scan on reading_records r` | 499,998 | 読了記録200万件を読み、対象週の記録を残す（除外1,500,002件） |
| 2 | `Seq Scan on books b` | 1,000,000 | 本100万冊を読む |
| 3 | `Hash` | 1,000,000 | 本を照合しやすい形にまとめる（第9章） |
| 4 | `Hash Join` | 499,998 | 記録ごとに本を見つけ、題名を付ける（第9章） |
| 5 | `HashAggregate` | 255,238 | 本ごとに記録を数える（第9章） |
| 6 | `Sort` | 20 | 件数の順に並べ、上位を選ぶ（第7・8章） |
| 7 | `Limit` | 20 | 20件で止める |

図で、各段の`rows`がどこで減るかを見てください。

![ランキングの計画を木にすると、Seq Scanの499,998件と本の1,000,000件がHash Joinで499,998件になり、HashAggregateで255,238件、SortとLimitで20件になる](/images/postgresql-query-journey/02-ranking-plan-tree.png)
*枠で囲んだ最後の2段まで、数十万件のレコードを受け渡しています（rowsは実測）。*

20件に減るのは、最後の`Sort`と`Limit`です。それより前の処理は、何十万件ものレコードを受け渡しています。序章の「20冊しか返さないのに」という疑問の答えの一部が、ここに見えています。20件という結果の件数と、途中で扱うレコード数は別のものです。

## 共有する領域と、処理ごとの作業領域

第5章では、ページを置く共有バッファと、並べ替えなどで使う作業用メモリを分けました。ランキングの出力には、その両方が現れています。

| 出力の例 | 表しているもの |
| --- | --- |
| `Buffers: shared hit=2048 read=8763` | 共有バッファのページを使った数（第5章） |
| `Sort Method: top-N heapsort  Memory: 27kB` | 並べ替えに使った作業用メモリ |
| `Memory Usage: 8281kB`（HashAggregate）、`Memory Usage: 4883kB`（Hash） | 数える処理と照合の準備に使った作業用メモリ |
| `temp read=9046 written=10758`、`Batches: 9` | 作業用メモリに収まらず、一時ファイルを使ったこと |

共有バッファは、ほかの接続とも共有するページの置き場所です。作業用メモリは、`Sort`や`HashAggregate`などの処理ごとに用意され、ほかの接続とは共有しません。`work_mem`は4MBなのに`HashAggregate`が8,281kBを使っているのは、ハッシュを使う処理の上限が`work_mem`の2倍になる設定があるためです（第9章）。作業用メモリがどのプロセスに置かれるかは、章末の補足で確かめます。

## 計画の木から、次の章へ

実行計画は、上の処理が下の処理にレコードを求め、下の処理が1件ずつ渡す木の形をしています。長い計画も、字下げで親子を分け、いちばん深いところから`rows`を追えば、どこで何件を扱っているかが分かります。

ランキングの計画では、20件まで減るのは最後の`Sort`と`Limit`でした。その`Sort`は、25万件余りのグループから上位20件を選んでいます。並べ替えは、何件をどうやって並べる処理なのでしょうか。次章では、まず読了記録を日時順に並べる単純な`Sort`から観察します。

## 補足：SQLを受け取るプロセス

この章の本文では、実行計画の中身を読みました。ここでは、SQLを受け取って計画を作り、実行する側を観察します。第11章で二つの接続を使う実験の準備にもなります。読み飛ばしても、次章に進めます。

### SQLは誰に届く？

第5章の図の接続Aと接続Bが、サーバの中で何に当たるのかを確かめます。psqlを二つ開き、接続先で動くプログラムを調べます。

psqlは、入力されたSQLをPostgreSQLのサーバへ送ります。SQLを受け取ってデータを処理するのはサーバ側です。この関係で、要求を送る側を**クライアント**と呼びます。Webサイトでは、サイトのプログラムがDBのクライアントになります。

![二つのターミナルのpsqlからSQLを送ると、サーバで受け取る側がいくつになるかは「？」のまま](/images/postgresql-query-journey/02-client-scene.png)
*二つのpsqlから送ったSQLを、サーバの中で受け取るのは何か。「？」の中身を、この後で確かめます。*

Dockerで動かす今回の実験でも、このクライアントとサーバの関係は同じです。

### 接続ごとに、別のバックエンドプロセスが動く

これまでと同じpsqlで、次を実行してください。

```sql
SELECT pg_backend_pid();
```

2026年9月22日、PostgreSQL 18.6での実行結果です。

```sql
 pg_backend_pid
----------------
            952
(1 row)
```

表示された整数は、この接続を処理している**プロセス**の番号（PID、プロセスID）です。プロセスは、実行中のプログラムをOSが一つずつ管理するときの単位です。同じプログラムから複数のプロセスが動くこともあり、OSはそれぞれを番号で識別します。

この実行例では`952`でした。以降、この接続を「接続A」と呼びます。PIDは接続するたびに変わることがあるので、同じ番号が出なくても問題ありません。

別のターミナルを開き、もう一度接続します。

```bash
docker compose exec db psql -X -U postgres -d reading_map
```

こちらを「接続B」とします。接続Aは開いたままにして、接続Bのpsqlで同じSQLを実行してください。

```sql
SELECT pg_backend_pid();
```

接続Bでの実行結果です。

```sql
 pg_backend_pid
----------------
          22521
(1 row)
```

接続Aは`952`、接続Bは`22521`でした。同じコマンドで同じDBに接続していますが、SQLを処理するプロセスの番号は別になっています。

通常の接続では、接続ごとにSQLを処理するプロセスが作られます。これを**バックエンドプロセス**と呼びます。接続を受け付け、その接続を担当するバックエンドを起動する親のサーバプロセスは、postmasterとも呼ばれます。

![二つのターミナルのpsqlが、それぞれ別のバックエンドプロセス（PID 952と22521）につながり、二つとも同じDBを使う](/images/postgresql-query-journey/02-connections.png)
*接続ごとに別のバックエンドプロセスが動き、DBは一つのままです（PIDは今回の実行例。配置は説明用）。*

二つのバックエンドプロセスが、同じDBに接続しています。接続を増やしても、DBの複製は作られません。[公式のアーキテクチャ解説](https://www.postgresql.org/docs/18/tutorial-arch.html)でも、この接続とプロセスの関係が説明されています。

接続中のバックエンドの状態も確認できます。接続Aでは何も実行せずに待ち、接続Bで次のSQLを実行します。

```sql
SELECT pid, state, query
FROM pg_stat_activity
WHERE datname = current_database();
```

接続Bでの実行結果です。

```sql
  pid  | state  |                query
-------+--------+-------------------------------------
 22521 | active | SELECT pid, state, query           +
       |        | FROM pg_stat_activity              +
       |        | WHERE datname = current_database();
   952 | idle   | SELECT pg_backend_pid();
(2 rows)
```

#### Aは待機中、Bが実行中

`pid`が番号、`state`が状態、`query`が現在または直近のSQLです。さっき確認したPIDを手掛かりにすると、次のように読めます。

| 出力 | 対応する接続 | 分かること |
| --- | --- | --- |
| `22521 / active` | 接続B | いま、この接続一覧を調べるSQLを実行している |
| `952 / idle` | 接続A | 接続を保ったまま、次の命令を待っている |

二つのpsqlは同じDBにつながっていますが、担当するバックエンドは別々です。接続Aが`idle`でも、接続が切れたわけではありません。

接続Aの`query`に`SELECT pg_backend_pid();`が残っているのは、それが最後に実行したSQLだからです。このSQLをずっと実行し続けている、という意味ではありません。接続Bの出力にある`+`は、SQLの文字列が次の行へ続くことを示すpsqlの表示です。

ほかにも接続していれば、表示されるレコードは増えます。このSQLでは表示順を指定していないため、自分の結果ではPIDを見て接続を対応させてください。見える情報は権限によって変わりますが、本の実験用ユーザーでは一覧を観察できます。

### プロセスごとの作業領域と、共有する領域

第5章の図で見た二つの領域を、プロセスと対応させます。共有バッファは複数のバックエンドプロセスから使われ、作業用メモリはそれぞれのプロセスが処理ごとに持ちます。

ただし実際には、複数のプロセスで一つのSQLを分担する計画（第1章で無効にした並列実行）や、プロセスの間で共有する作業領域もあります。そのため、「一つのSQLは、いつも一つのプロセスだけが処理する」とは言い切れません。

ページを書き出したり、データを保守したりする別のプロセスもあります。その役割は第11章で扱います。
