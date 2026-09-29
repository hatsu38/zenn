---
title: "第6章：長い実行計画は、どこから読むのか"
---

## この章で分かること

序章のランキングSQLに`EXPLAIN ANALYZE`を付けると、20行を超える出力が返ります。どこから読めばよいのかを、実行計画の形から確かめます。SQLの文字列が解析・計画・実行と進む流れを図で追い、小さな計画で、上の処理が下の処理にレコードを求める「計画の木」の読み方を確かめ、子が二つある小さな計画で、親がどちらの子から動かすかを見ます。その読み方で、ランキングの計画をいちばん深いところから読みます。親の`Buffers`に子の分が含まれることも確かめます。接続ごとにSQLを処理するプロセスの観察は、章末の補足に置きます。

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

実行すると、20行を超える出力が返ります。これまでの1冊を探す計画は数行でしたが、今回は`Sort`、`HashAggregate`、`Hash Join`、`Hash`と、まだ説明していない名前が並びます。一つずつの名前の意味は、第7〜9章で調べます。この章では、その前に、この出力をどの順で読めばよいかを決めます。出力の全体は、読み方を確かめた後、この章の後半で読みます。

## 文字列が手順になるまで

長い計画を読む前に、PostgreSQLがSQLを受け取ってから結果を返すまでの流れを確かめます。

SQLは、最初は文字の列です。PostgreSQLは、その文字をいきなり実行するのではありません。まず意味を確かめ、結果を作るための手順に組み立てます。

第3章で試した題名検索を例に、SQLを受け取ってから結果を返すまでを図6.1に並べます。矢印は、処理が進む順番です。

![SQLの文字列が解析・書き換え・計画・実行の4段を通って結果のレコードになり、EXPLAINは計画まで、EXPLAIN ANALYZEは実行まで進んでレコードは出さない](/images/postgresql-query-journey/02-query-stages.png)
*図6.1　右の括弧で、EXPLAINとEXPLAIN ANALYZEがどの段まで進むかを見てください（処理の順番の概略）。*

まず、SQLの文法と、指定されたテーブルや列が存在するかを確認します。続いて、問い合わせ（SQL）をDBに登録された規則に沿って書き換える段階を通ります[^view]。今回のSQLは通常のテーブル`books`を直接指定しているので、書き換えは起きません。

[^view]: たとえば、検索に名前を付けてテーブルのように使うビュー（VIEW）を参照しているなら、この段階でその定義に基づく問い合わせへ置き換えます。

次に、テーブルを順に読むか、Indexを使うかなどを比較して、実行計画を作ります。実行計画を作る部分を**プランナ**と呼びます。出来上がった計画に従ってページを使い、条件を確かめてレコードを返す部分が**エグゼキュータ（実行器）**&#8203;です。[公式の処理経路の説明](https://www.postgresql.org/docs/18/query-path.html)も、この順序で整理されています。

第1章の表1.2で見た`EXPLAIN`と`EXPLAIN ANALYZE`の違いは、図6.1の「計画」と「実行」の段に当たります。`EXPLAIN`だけなら計画を作って表示するところまで、`EXPLAIN ANALYZE`なら計画を実行して計測するところまで進みます。

第1章で見た`Planning Time`は計画を作る段階、`Execution Time`は実行する段階にかかった時間です。ただし、この二つを足せば画面の待ち時間を全部説明できるわけではありません。通信や結果の表示にも時間がかかります。

## LimitとIndex Scanのレコードの受け渡し

次のSQLを、まず実行せずに観察します。

```sql
EXPLAIN
SELECT id, title FROM books ORDER BY title LIMIT 3;
```

2026年9月23日、DockerのPostgreSQL 18.6、本100万冊で第3章の題名のIndexがある状態で採取した出力です。

```sql:実行結果
Limit  (cost=0.42..0.57 rows=3 width=30)
  ->  Index Scan using books_title_idx on books  (cost=0.42..49666.10 rows=1000000 width=30)
```

`Index Scan`がIndexの順にレコードを読み、`Limit`が3件まで受け取る計画です。

`Index Scan`の`rows=1000000`は最後まで実行した場合の見積もりです。上の`Limit`は3件で求めるのをやめる計画なので、100万件すべてを読む予定ではありません。ここでは`EXPLAIN`だけを実行しているため、実際のレコード数や時間は表示されていません。実際のレコード数は`EXPLAIN ANALYZE`で確かめられます。

実際の受け渡しも測ってみます。

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books ORDER BY title LIMIT 3;
```

2026年9月25日、PostgreSQL 18.6で新規DBへ本100万冊を用意し、第3章の題名Indexを作った状態での実行結果です。並列実行とJITは無効です。

```sql:実行結果
Limit  (cost=0.42..0.57 rows=3 width=30) (actual time=0.015..0.016 rows=3.00 loops=1)
  …
  ->  Index Scan using books_title_idx on books  (cost=0.42..49247.50 rows=1000000 width=30) (actual time=0.014..0.015 rows=3.00 loops=1)
…
```

Index Scanの推定は最後まで読んだ場合の100万件ですが、実際には3件を返して止まっています。上のLimitの`actual rows=3`と、子の`actual rows=3`が対応しました。

実行計画は、上の処理が下の処理からレコードを受け取る親子の形をしているので、計画の木と呼ばれます。この二つの処理がレコードを受け渡す様子を図6.2に描きます。左の矢印がレコードを返す向き、右が次のレコードを求める向きです。

![Limitが次の1件を3回求め、Index Scanが題名の順に3件を返す。4回目は求めない。出力の見積もりはLimitがrows=3、Index Scanがrows=1000000](/images/postgresql-query-journey/02-execution-tree.png)
*図6.2　①〜③の3往復の後、4回目は求めないことを見てください（本文の`Limit`と`Index Scan`の計画に対応させて説明するための図。rowsは見積もり）。*

実行時は、上の`Limit`が下の`Index Scan`に次の1件を求めます。`Index Scan`は題名のIndexをたどり、テーブルから取り出したレコードを返します。この受け渡しを繰り返し、`Limit`は3件を受け取ったら求めるのをやめる計画です。

今回の計画には、並べ替えを表す`Sort`がありません。題名のIndexから、`ORDER BY title`で求めた順にレコードを取り出せるためです。Indexで順序を得られない場合の並べ替えは、次章で扱います。

## 子が二つある計画

ランキングの計画に出てくる`Hash Join`は、子を二つ持つ処理です。子が二つあると、親はどちらの子から、どの順にレコードを求めるのでしょうか。ランキングに進む前に、同じ形の小さな計画で確かめます。本42と本43の読了記録を、題名を付けて取り出します。

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT b.title, r.finished_at
FROM books AS b
JOIN reading_records AS r ON r.book_id = b.id
WHERE b.id IN (42, 43);
```

2026年9月28日、PostgreSQL 18.6での実行結果です。本100万冊・読了記録200万件で、読了記録にはまだIndexがありません。

```sql:実行結果
Hash Join  (cost=12.91..36073.93 rows=4 width=30) (actual time=73.019..262.468 rows=3.00 loops=1)
  Hash Cond: (r.book_id = b.id)
  …
  ->  Seq Scan on reading_records r  (cost=0.00..30811.00 rows=2000000 width=16) (actual time=0.015..138.384 rows=2000000.00 loops=1)
        …
  ->  Hash  (cost=12.88..12.88 rows=2 width=30) (actual time=0.006..0.007 rows=2.00 loops=1)
        …
        ->  Index Scan using books_pkey on books b  (cost=0.42..12.88 rows=2 width=30) (actual time=0.004..0.005 rows=2.00 loops=1)
              Index Cond: (id = ANY ('{42,43}'::bigint[]))
              …
…
Execution Time: 262.495 ms
```

`Hash Join`の下に、`Seq Scan on reading_records r`と`Hash`の二つの子が、同じ深さで並んでいます。`Hash`の下には、さらに`Index Scan using books_pkey on books b`があります。

`Hash Join`は、二つの子に同じように1件ずつ求めるわけではありません。読了記録の照合を始める前に、`Hash`の側を最後まで動かします。`Hash`は、下の`Index Scan`から本42と本43の2件（`rows=2.00`）を受け取り、**ハッシュ表**にまとめます。ハッシュ表は、値から計算で置き場所を決める表で、第9章で扱います。`Hash`は、このハッシュ表を1件ずつではなく、まとめて親に渡します。`Hash`の`rows`は、ハッシュ表に入れたレコードの数です。

ハッシュ表ができてから、`Hash Join`はもう一方の子の`Seq Scan`に、読了記録を1件ずつ求めます。受け取った記録の`book_id`（`Hash Cond`の条件）でハッシュ表を引き、本42か本43の記録なら題名を付けて親へ返します。`Seq Scan`が渡した200万件（`rows=2000000.00`）のうち、ハッシュ表で見つかった3件が、`Hash Join`の`rows=3.00`です。

この受け渡しを、図6.3で順に追ってみます。

![Hash JoinがまずHashの側を動かして本42と本43のハッシュ表を作らせ、その後でSeq Scanから読了記録を1件ずつ受け取って表を引き、3件を返す](/images/postgresql-query-journey/02-hash-join-steps.png)
*図6.3　①で`Hash`の側が動き終えてから、②で`Seq Scan`が動き始めます（受け渡しを説明するための図。rowsは実測）。*

出力では`Hash`が下に書かれていますが、先に動き終えるのは`Hash`の側です。子が並ぶ順番は、動く順番とは限りません。どの子をいつ動かすかは、親の処理が決めます。

どちらの子の側でハッシュ表を作るかも、計画ごとに決まります。この小さな計画では件数の少ない本2冊の側で作りましたが、次のランキングの計画では、件数の多い本100万冊の側で作っています。どちらの側で作ったかの読み方は、第9章で確かめます。

## 長い計画を木として読む

二つの小さな計画で確かめた読み方を、ランキングの計画に当てはめます。章の最初に実行したランキングSQLの実行結果です。2026年9月26日、PostgreSQL 18.6で、本100万冊・読了記録200万件、第3章の題名Indexがあり、読了記録にはまだIndexがない状態で測りました。並列実行とJITは無効、`work_mem`は4MBです。

```sql:実行結果
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

手掛かりは次の三つです。

- 行頭の`->`と字下げ：字下げが一段深い処理が、すぐ上の処理の子です。子は親にレコードを渡します。
- 同じ深さに並ぶ子：一つの処理が、二つの子を持つことがあります。前の節の計画と同じく、`Hash Join`の下には`Seq Scan on reading_records r`と`Hash`の二つの子があります。
- `actual`の`rows`：その処理が親へ渡したレコードの数です。`Hash`の`rows`は、ハッシュ表に入れたレコードの数です。

レコードは下から上へ流れます。そこで、字下げのいちばん深い処理から読み始め、親へ向かって`rows`を追います。この計画でいちばん深いのは、`Hash`の下の`Seq Scan on books b`です。

表6.1　ランキングの計画を読む順
| 読む順 | 処理 | 親へ渡したレコード | していること |
| ---: | --- | ---: | --- |
| 1 | `Seq Scan on books b` | 1,000,000 | 本100万冊を読む |
| 2 | `Hash` | 1,000,000 | 本を照合しやすい形にまとめる（第9章） |
| 3 | `Seq Scan on reading_records r` | 499,998 | 読了記録200万件を読み、対象週の記録を残す（除外1,500,002件） |
| 4 | `Hash Join` | 499,998 | 記録ごとに本を見つけ、題名を付ける（第9章） |
| 5 | `HashAggregate` | 255,238 | 本ごとに記録を数える（第9章） |
| 6 | `Sort` | 20 | 件数の順に並べ、上位を選ぶ（第7・8章） |
| 7 | `Limit` | 20 | 20件で止める |

前の節の小さな計画と同じく、`Hash Join`は、本のハッシュ表を作り終えてから、読了記録を1件ずつ照合します。今回は、出力の時間にもこの順が表れています。第1章で見たとおり、`actual time`の前の数は最初の1件を返すまで、後ろの数はすべて返し終えるまでにかかった時間です。`Hash Join`が最初の1件を返すまでの168.642ミリ秒には、`Hash`が本をまとめ終えるまでの168.082ミリ秒がほぼそのまま含まれています。ハッシュ表を作り終えてから、照合を始めたということです。

図6.4で、各段の`rows`がどこで減るかを見てください。

![ランキングの計画を木にすると、Hashが本の1,000,000件を表にして先に渡し、その後にSeq Scanの499,998件をHash Joinが照合して499,998件になり、HashAggregateで255,238件、SortとLimitで20件になる](/images/postgresql-query-journey/02-ranking-plan-tree.png)
*図6.4　矢印の①〜③は`Hash Join`が子を動かす順で、枠で囲んだ最後の2段まで数十万件のレコードを受け渡しています（rowsは実測）。*

20件に減るのは、最後の`Sort`と`Limit`です。それより前の処理は、何十万件ものレコードを受け渡しています。序章の「20冊しか返さないのに」という疑問の答えの一部が、ここに見えています。20件という結果の件数と、途中で扱うレコード数は別のものです。

出力の`Buffers`も、木の形に沿って読みます。親の`Buffers`には、子の分も含まれます。たとえば`Hash Join`の`shared hit=4285`は、二つの子の2,048と2,237を足した数で、`read=13879`も8,763と5,116の合計です。

出力には、`Sort`の`Memory`、`Hash`や`HashAggregate`の`Memory Usage`、`temp`や`Batches`のように、メモリの使い方を表す値も並んでいます。これは共有バッファではなく、処理ごとに使うメモリの値です。次章の最初で、この二つのメモリを分けて読みます。

## まとめ

- 長い計画は、字下げのいちばん深い処理から読み、親へ向かって`rows`を追う。
- 子が二つあるとき、どの子をいつ動かすかは親が決める。`Hash Join`は、先に`Hash`の側でハッシュ表を作り終えてから、もう一方の子のレコードを1件ずつ照合する。
- どの段でレコード数が大きく減るかを見る。結果が20件でも、途中の段で数十万件を受け渡していることがある。
- 親の`Buffers`には子の分も含まれる。

## 第7章へ

ランキングの計画では、20件まで減るのは最後の`Sort`と`Limit`でした。その`Sort`は、25万件余りのグループから上位20件を選んでいます。並べ替えは、何件をどうやって並べる処理なのでしょうか。次章では、まず計画に並んでいたメモリの値を読み分け、そのうえで読了記録を日時順に並べる単純な`Sort`を観察します。

## 補足：SQLを受け取るプロセス

この章の本文では、実行計画の中身を読みました。ここでは、SQLを受け取って計画を作り、実行する側を観察します。第11章で二つの接続を使う実験の準備にもなります。読み飛ばしても、次章に進めます。

### SQLは誰に届く？

第5章では、共有バッファを複数の接続から共通に使うと書きました。その接続が、サーバの中で何に当たるのかを確かめます。psqlを二つ開き、接続先で動くプログラムを調べます。

psqlは、入力されたSQLをPostgreSQLのサーバへ送ります。SQLを受け取ってデータを処理するのはサーバ側です。この関係で、要求を送る側を**クライアント**と呼びます。Webサイトでは、サイトのプログラムがDBのクライアントになります。

![二つのターミナルのpsqlからSQLを送ると、サーバで受け取る側がいくつになるかは「？」のまま](/images/postgresql-query-journey/02-client-scene.png)
*図6.5　二つのpsqlから送ったSQLを、サーバの中で受け取るのは何か。「？」の中身を、この後で確かめます。*

Dockerで動かす今回の実験でも、このクライアントとサーバの関係は同じです。

### 接続ごとに、別のバックエンドプロセスが動く

これまでと同じpsqlで、次を実行してください。

```sql
SELECT pg_backend_pid();
```

2026年9月22日、PostgreSQL 18.6での実行結果です。

```sql:実行結果
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

```sql:実行結果
 pg_backend_pid
----------------
          22521
(1 row)
```

接続Aは`952`、接続Bは`22521`でした。同じコマンドで同じDBに接続していますが、SQLを処理するプロセスの番号は別になっています。

通常の接続では、接続ごとにSQLを処理するプロセスが作られます。これを**バックエンドプロセス**と呼びます。接続を受け付け、その接続を担当するバックエンドを起動する親のサーバプロセスは、postmasterとも呼ばれます。

![二つのターミナルのpsqlが、それぞれ別のバックエンドプロセス（PID 952と22521）につながり、二つとも同じDBを使う](/images/postgresql-query-journey/02-connections.png)
*図6.6　接続ごとに別のバックエンドプロセスが動き、DBは一つのままです（PIDは今回の実行例。配置は説明用）。*

二つのバックエンドプロセスが、同じDBに接続しています。接続を増やしても、DBの複製は作られません。[公式のアーキテクチャ解説](https://www.postgresql.org/docs/18/tutorial-arch.html)でも、この接続とプロセスの関係が説明されています。

接続中のバックエンドの状態も確認できます。接続Aでは何も実行せずに待ち、接続Bで次のSQLを実行します。

```sql
SELECT pid, state, query
FROM pg_stat_activity
WHERE datname = current_database();
```

接続Bでの実行結果です。

```sql:実行結果
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

表6.2　接続一覧の読み方
| 出力 | 対応する接続 | 分かること |
| --- | --- | --- |
| `22521 / active` | 接続B | いま、この接続一覧を調べるSQLを実行している |
| `952 / idle` | 接続A | 接続を保ったまま、次の命令を待っている |

二つのpsqlは同じDBにつながっていますが、担当するバックエンドは別々です。接続Aが`idle`でも、接続が切れたわけではありません。

接続Aの`query`に`SELECT pg_backend_pid();`が残っているのは、それが最後に実行したSQLだからです。このSQLをずっと実行し続けている、という意味ではありません。接続Bの出力にある`+`は、SQLの文字列が次の行へ続くことを示すpsqlの表示です。

ほかにも接続していれば、表示されるレコードは増えます。このSQLでは表示順を指定していないため、自分の結果ではPIDを見て接続を対応させてください。見える情報は権限によって変わりますが、実験用リポジトリのREADMEの手順で接続する`postgres`ユーザーなら、一覧を観察できます。

### プロセスごとの作業領域と、共有する領域

メモリの領域を、プロセスと対応させます。共有バッファ（第5章）は複数のバックエンドプロセスから使われます。一方、並べ替えなどの途中の値を置く作業用メモリは、それぞれのプロセスが処理ごとに持ちます。作業用メモリは、次章の最初で説明します。

ただし実際には、複数のプロセスで一つのSQLを分担する計画（「準備」の章で無効にした並列実行）や、プロセスの間で共有する作業領域もあります。そのため、「一つのSQLは、いつも一つのプロセスだけが処理する」とは言い切れません。

ページを書き出したり、データを保守したりする別のプロセスもあります。その役割は第11章で扱います。
