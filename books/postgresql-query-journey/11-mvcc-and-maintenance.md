---
title: "第11章：MVCCでは、更新中のレコードは読み手にどう見えるのか"
---

## この章で分かること

更新中のテーブルを複数の接続から読むと、同じレコードでも見える値が異なることがあります。スナップショットとレコードのバージョンを観察します。そこから、不要になった領域の回収（VACUUM）、可視性マップ、Index Only Scanの関係をたどります。最後に、更新の実行計画に現れる`WAL`の行を読み、WALとデータページの書き出しを整理します。読み取り性能を、更新、後片付け、耐久性まで含めて考えられるようになります。

:::message
再接続したら、「準備」の章の共通設定を入力してください。途中の章から始めるときの準備は、[実験用リポジトリのREADME](https://github.com/hatsu38/postgresql-structures-lab#readme)にあります。
:::

## 書き換えている途中で読まれたら

第10章では、`UPDATE`で8,000件の値を変えました。そのとき、元のレコードはどうなったのでしょうか。一人が題名を直している間に、別の人が同じ本を読もうとしたら、何が見えるでしょうか。読み手から見える内容を、操作の順番に沿って追います。

![接続Aと接続Bの画面が、本42の同じレコードを指す。Bはまだ確定しておらず、COMMITのボタンが残っている](/images/postgresql-query-journey/11-editing-scene.png)
*二つの接続は同じレコード（id 42）を指していますが、Bのボタンはまだ押されていません。*

答えには、第9章で見たトランザクション（`BEGIN`で始め、`COMMIT`で確定し、`ROLLBACK`で取り消す、ひとまとまりの操作）が関わります。何が見えるかは、トランザクションの状態と、分離レベル（ほかのトランザクションの変更をどこまで見せるかの設定）で変わります。この後は分離レベルを指定して実験します。

ここでは、本番のデータではなく実験用DBを使います。これまで使ってきたpsqlを接続Aとします。第6章の補足と同じように、別のターミナルを開いて次のコマンドでもう一つ接続し、こちらを接続Bとします。

```bash
docker compose exec db psql -X -U postgres -d reading_map
```

## 同じ読み手の見え方を固定する

まず接続Aで、次を実行します。

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT title FROM books WHERE id = 42;
```

`Repeatable Read`は、このトランザクションの中のすべての読み取りで、同じ「見える時点」を使い続けるための指定です。読み取りの基準になる状態を**スナップショット**と呼びます。`Repeatable Read`のスナップショットは、`BEGIN`の時点ではなく、トランザクションの中で最初のSQL（ここではSELECT）を実行した時点で取られます（[分離レベルの公式説明](https://www.postgresql.org/docs/18/transaction-iso.html)）。100万冊のテーブルをコピーすれば時間も容量も足りないので、テーブルを丸ごと別の場所へ写すわけではありません。スナップショットが持つのは、その時点でどのトランザクションが確定していたか、という記録だけです。

続いて接続Bで変更します。

```sql
BEGIN;
UPDATE books SET title = '改訂版の本 42' WHERE id = 42;
COMMIT;
```

接続Aに戻り、同じ検索をもう一度実行します。

```sql
SELECT title FROM books WHERE id = 42;
COMMIT;
SELECT title FROM books WHERE id = 42;
```

Aのトランザクション中の検索と、その後の検索で違いが見えるでしょうか。予想してから実行し、次の結果と見比べてください。

:::details 二つの接続で確かめた結果
2026年9月25日、PostgreSQL 18.6で確認しました。各SELECTの出力から、題名の値だけを抜粋します。Aが最初のSELECTを終えてから、Bで更新・COMMITしました。

Aの最初のSELECT：

```sql:実行結果
実験用の本 42
```

BのCOMMIT後、Aの同じトランザクション内のSELECT：

```sql:実行結果
実験用の本 42
```

A自身もCOMMITした後のSELECT：

```sql:実行結果
改訂版の本 42
```

Bが確定しただけではAの見える題名は変わりません。Aのトランザクションが終わり、次のSELECTで新しいスナップショットを使うと題名が変わりました。
:::

`Repeatable Read`の定義どおりなら、Aは途中の検索で元の題名を見て、COMMIT後の新しい検索で改訂版を見ます。既定の`Read Committed`では、SQL文を実行するたびに、その開始時点の状態を見直します。そのままなら、接続Aの2回目の検索でも、Bが確定した改訂版が見えるはずです。今回はその違いを避けるために`Repeatable Read`を指定しました。

実験後、どちらかの接続で題名を戻します。

```sql
UPDATE books SET title = '実験用の本 42' WHERE id = 42;
```

## 同じ本でも、レコードの版がある

もしPostgreSQLが更新のたびにレコードを上書きし、最新の内容だけを残していたら、接続Aは古い題名を読み続けられません。実際のPostgreSQLは、更新のとき元のレコードを残したまま、新しい**レコードバージョン**（版）を作ります。複数の版を使って読み手ごとの見え方を管理する仕組みが**MVCC**（Multi-Version Concurrency Control）です。

どの版を誰に見せるかを決めるために、各版には二つの番号が付いています。`xmin`はその版を作ったトランザクションの番号、`xmax`はその版を消した（新しい版に置き換えた）トランザクションの番号です。作られたばかりの版の`xmax`は0です[^xmin-xmax]。

[^xmin-xmax]: `xmin`と`xmax`は、第4章の`ctid`と同じくシステム列です。[公式ドキュメントのシステム列の説明](https://www.postgresql.org/docs/18/ddl-system-columns.html)にあります。

読み手は、スナップショットの記録とこの二つの番号を比べて、見せる版を選びます。

1. `xmin`のトランザクションが、スナップショットの時点で確定していたかを見ます。確定していなければ、その版はまだ作られていないものとして扱い、見せません。
2. 確定していたら、次に`xmax`を見ます。`xmax`が0か、そのトランザクションがスナップショットの時点で確定していなければ、その版はまだ消されていないので見せます。確定していれば、消された版として見せません。

「確定していない」には、まだ実行中のもの、スナップショットを取った後に始まったもの、取り消されたものが入ります。ただし、自分のトランザクションが作った版は、確定する前でも自分には見えます[^mvcc-rule]。

[^mvcc-rule]: この規則は、PostgreSQL 18のソースの[`HeapTupleSatisfiesMVCC`](https://github.com/postgres/postgres/blob/REL_18_STABLE/src/backend/access/heap/heapam_visibility.c)で確かめました。自分のトランザクションの中でSQLを実行した順番の扱いや、判定の結果をページに書き込んでおく仕組みなどの細部は省いています。

先ほどの実験に当てはめます。BのUPDATEで、本42には元の題名の版1と、改訂版の版2ができました。版2の`xmin`と版1の`xmax`は、どちらもBのトランザクションの番号です。Aのスナップショットは、Bが始まる前に取ったものなので、Bは「確定していない」側に入ります。そのため、Aには版2が見えず、版1はまだ消されていない版として見えます。AがCOMMITした後の検索は新しいスナップショットを使い、そこではBが確定済みです。今度は版2が見え、版1は消された版として見えなくなります。

![番号999のBが本42の版2を作り、998まで確定済みのスナップショットを持つAには③で版1だけが見え、COMMIT後に999まで確定済みになった④では版2だけが見える](/images/postgresql-query-journey/11-snapshots.png)
*③と④で、番号の下の「確定」「未確定」を見てください。規則の1で`xmin`を、2で`xmax`を、Aのスナップショットと比べています（説明するための図。番号は次の節の実行結果に近い値にしていますが、次の節の999は接続Aが自分で`UPDATE`したトランザクションで、図のBとは別の実験です）。*

### 版を、実物で見る

本42の版を、実際に表示してみます。`ctid`に加えて、隠れた列の`xmin`と`xmax`も表示します。AとBのトランザクションをすべて終了してから、接続Aで実行します。最後の`ROLLBACK`で更新を取り消すので、本のデータは元に戻ります。

```sql
BEGIN;
SELECT ctid, xmin, xmax, title FROM books WHERE id = 42;
UPDATE books SET title = '改訂版の本 42' WHERE id = 42;
SELECT ctid, xmin, xmax, title FROM books WHERE id = 42;
ROLLBACK;
SELECT ctid, xmin, xmax, title FROM books WHERE id = 42;
```

2026年9月28日、PostgreSQL 18.6での実行結果です。3つのSELECTの結果だけを載せます。番号と場所は、それまでの操作によって変わります。

```sql:実行結果
    ctid    | xmin | xmax |     title
------------+------+------+---------------
 (7352,130) |  948 |    0 | 実験用の本 42
(1 row)

    ctid    | xmin | xmax |     title
------------+------+------+---------------
 (7352,131) |  999 |    0 | 改訂版の本 42
(1 row)

    ctid    | xmin | xmax |     title
------------+------+------+---------------
 (7352,130) |  948 |  999 | 実験用の本 42
(1 row)
```

`UPDATE`の後は、`ctid`が(7352,130)から(7352,131)に変わり、`xmin`も999になりました。同じ本42でも、別の場所に新しい版が書かれ、それをトランザクション999が作ったことが分かります。まだ確定していない版ですが、作った本人のトランザクションの中なので見えています。第4章で、`ctid`は更新後に変わりうるので主キーの代わりには使えない、と説明したのは、このためです。第10章で`UPDATE`した8,000件にも、同じように新しい版が作られました[^stats-demo]。

[^stats-demo]: 第10章の`stats_demo`は、同じトランザクションの中で作ったテーブルなので、最後の`ROLLBACK`でテーブルごと取り消されました。

`ROLLBACK`の後は、元の(7352,130)の版がまた見えます。その`xmax`には999が残っています。999は取り消されたので、先ほどの規則の2で「確定していない」側に入り、この版はまだ消されていない版として見えます。999が作った(7352,131)の版は、同じ理由で誰にも見えません。この取り消された版の領域は、後から回収の対象になります。

:::details ページの中の古い版を直接見る
同じトランザクションの中では、置き換えられた古い版はSELECTでは見えません。第4章の補足で使った`pageinspect`で、ページの中身を直接読みます。`\gset`は、SELECTの結果をpsqlの変数に入れる命令です。`:old_page`のように書くと、その値が入ります。`\gset`の後ろにSQLを続けると貼り付けたときに実行されないので、三つの枠に分けています。

```sql
CREATE EXTENSION IF NOT EXISTS pageinspect;
BEGIN;
SELECT (ctid::text::point)[0]::int AS old_page FROM books WHERE id = 42 \gset
```

```sql
UPDATE books SET title = '改訂版の本 42' WHERE id = 42;
SELECT (ctid::text::point)[0]::int AS new_page FROM books WHERE id = 42 \gset
```

```sql
SELECT lp, t_xmin, t_xmax, t_ctid
FROM heap_page_items(get_raw_page('books', :old_page))
WHERE t_xmax = pg_current_xact_id()::xid
UNION ALL
SELECT lp, t_xmin, t_xmax, t_ctid
FROM heap_page_items(get_raw_page('books', :new_page))
WHERE t_xmin = pg_current_xact_id()::xid;
ROLLBACK;
```

三つ目の枠の実行結果です（同じ日に続けて実行しました）。

```sql:実行結果
 lp  | t_xmin | t_xmax |   t_ctid
-----+--------+--------+------------
 130 |    948 |   1001 | (7352,132)
 132 |   1001 |      0 | (7352,132)
(2 rows)
```

`lp`はページの中の項目の番号で、`ctid`の右側の数に当たります。130番の古い版は、`t_xmax`にこのトランザクションの番号1001が入り、`t_ctid`が新しい版の場所(7352,132)を指しています。132番の新しい版は、`t_xmin`が1001です。古い版は消されずにページに残り、新しい版への道しるべを持っています。131番は、本文の実験で取り消した更新が作った版で、まだ回収されずに残っています。
:::

## いつ古い版を片付けられる？

規則の2から、古い版が見えるのは、その版を消したトランザクションがまだ確定していなかったときにスナップショットを取った読み手です。そういう読み手が残っている間は、古い版を捨てられません。そのスナップショットを使うトランザクションがすべて終わると、その領域を回収できます。長く終わらないトランザクションがあると、その間は古い版を片付けられないことがあります。

不要になったレコードバージョンの領域を再利用可能にする処理が**VACUUM**です。VACUUMは、テーブルの古い版を片付けるとき、Indexの中でその版を指している項目も、通常は一緒に片付けます（[日常的なVACUUMの公式説明](https://www.postgresql.org/docs/18/routine-vacuuming.html)）。「再利用可能」と「ファイルがその分小さくなる」は別です。普通のVACUUMは、空いた場所を次のレコードに使えるようにすることが中心です。

ただし、テーブルの末尾のページがまるごと空いたときは、その分だけファイルを切り詰めます。使い捨てのテーブル（10万件、1,728ページ）で確かめると、前半の5万件を消してVACUUMしても1,728ページのままでした。さらに末尾の2万5千件を消してVACUUMすると、1,294ページに縮みました。空いた場所を詰めてテーブルを作り直す`VACUUM FULL`では、432ページになりました（2026年9月28日）。`VACUUM FULL`は、実行している間、そのテーブルの読み書きを止めます。

一方、`ANALYZE`は統計情報を更新する処理です。VACUUMによる領域の回収とは目的が異なります。autovacuumは、この二つの保守を自動で進める仕組みです。

## Indexだけで返せると思ったのに

第8章で、日時と本番号の両方を持つIndexを作りました。第9章の計画にも、このIndexを使う`Index Only Scan`があり、`Heap Fetches: 0`と表示されていました。検索する列がIndexにあるなら、テーブルを読まなくてもよさそうです。

しかし、Indexの項目には値とレコードの場所しかなく、そのレコードがどのトランザクションから見えるかはテーブルのレコードにしか書かれていません。「値があるか」と「この読み手に見えてよいレコードか」は別の確認です。

そこでPostgreSQLは、テーブルのページごとに「このページのレコードはすべての読み手に見えてよいか」を記録した補助情報を持っています。これが**可視性マップ**です。ページごとに数ビットの印を持ち、テーブルと一緒にファイルとして保存されます[^vm-bitmap]。

[^vm-bitmap]: 第5章の検索用ビットマップは、一回の検索中に対象のページやレコードの位置を覚えるものでした。可視性マップは、読み手からの見え方をページごとに記録し続けるもので、役割が異なります。

この「すべて見えてよい」という印を付けるのはVACUUMです。ページのレコードを更新や削除で変えると、そのページの印は消えます。

Index Only Scanは、Indexの項目が指すページの印を確かめます。印があれば、テーブルを読まずにIndexの値を返します。印がないページについては、テーブルのレコードを見に行き、この読み手に見える版かを確かめます。

AとBのトランザクションをすべて終了してから、試します。第8章のIndexは日時が先頭なので、本42だけを探すには向きません。本の番号から探せる実験用のIndexを一つ作ってから、VACUUMして検索します。VACUUMはBEGINで始めたトランザクションの中では実行できないので、BEGINは付けません。

```sql
CREATE INDEX reading_records_visibility_idx
ON reading_records (book_id, finished_at);
VACUUM (ANALYZE) reading_records;
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, finished_at FROM reading_records
WHERE book_id = 42
ORDER BY finished_at DESC, book_id ASC;
```

Index Only Scanの`Heap Fetches`が、テーブルへ確認しに行った回数の手掛かりです。次は小さな変更を加え、同じ検索を比べます。`UPDATE`にも`EXPLAIN`を付けています。`ANALYZE`を付けた`EXPLAIN`は実際に実行するので、更新はそのまま行われます。`WAL`オプションで増える行は、この章の最後の節で読みます。

```sql
EXPLAIN (ANALYZE, BUFFERS, WAL)
UPDATE reading_records SET finished_at = finished_at WHERE book_id = 42;
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, finished_at FROM reading_records
WHERE book_id = 42
ORDER BY finished_at DESC, book_id ASC;
VACUUM (ANALYZE) reading_records;
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, finished_at FROM reading_records
WHERE book_id = 42
ORDER BY finished_at DESC, book_id ASC;
DROP INDEX reading_records_visibility_idx;
```

今回の確認では、本42の1件を返す検索で、次の違いが出ました。どの状態でも、Indexを後ろから逆向きに読む`Index Only Scan Backward`が選ばれています。`ORDER BY finished_at DESC`の新しい順に返すためです。

| 状態 | 選ばれた方法 | Heap Fetches |
| --- | --- | ---: |
| VACUUM後 | Index Only Scan Backward | 0 |
| UPDATE後 | Index Only Scan Backward | 2 |
| 再びVACUUM後 | Index Only Scan Backward | 0 |

これは2026年9月26日のPostgreSQL 18.6での実測です。返すレコードは1件でも、テーブルへの確認回数は1とは限りません。

UPDATE後の2は、次のように読めます。値を同じにしてもUPDATEはレコードバージョンを作るので、本42の1件に新しい版ができます。この実行では新しい版が別のページに置かれ、Indexには古い版を指す項目と新しい版を指す項目が並びました（新しい版を同じページに置けたときの違いは、下の囲みで見ます）。更新したページは可視性マップの印が消えるので、2つの項目それぞれでテーブルを確かめ、見えない古い版を除いて1件を返します。これがHeap Fetchesの2です。

再びVACUUMした後に0へ戻ったのは、VACUUMが古い版と、それを指すIndexの項目を片付け、ページに「すべて見えてよい」の印を付け直したためです。

![本42の1件は、VACUUM後はIndexの項目が1つで印が✓、UPDATE後は古い版と新しい版を指す項目が2つになって印が×、再びVACUUM後は項目が1つに戻って印が✓になる](/images/postgresql-query-journey/11-visibility-map.png)
*②の2本の矢印が、`Heap Fetches`の2に当たります。①と③は印が✓なので、テーブルを読みません（説明するための図。`Heap Fetches`の値は上の表の実測）。*

ただし、Heap Fetchesがいつも0→2→0と動くとは限りません。検索が変更したページを読むかどうか、別の計画が選ばれるかどうか、その間にautovacuumが動いたかどうかで変わります。正式な条件は[Index Only Scanの解説](https://www.postgresql.org/docs/18/indexes-index-only-scans.html)にあります。

:::message
同じUPDATEでも、Heap Fetchesが1になることがあります。Indexの列の値が変わらず、新しい版を同じページに置けるときは、Indexに項目を足さない**HOT更新**になるからです。Indexの項目は1つのままで、テーブルの中で古い版から新しい版へたどります。9月28日に試すと、本42のページに空きがあったのでHOT更新になり、Heap Fetchesは1でした。日時を1秒ずらす更新ではHOT更新にならず、Indexの項目が2つになって、Heap Fetchesは2でした。この更新の直後のIndexを、この章の前半でも使ったpageinspectの`bt_page_items`（Indexのページの項目を一覧する関数）で調べると、本42を指す項目は2つ並んでいました。どちらになるかは、Indexの列の値が変わるかと、同じページに空きがあるかで決まります。
:::

結果の件数と、テーブルへ確認する処理は分けて読みます。時間も測っていますが、この小さな実験では速さの順位ではなく、テーブルへの確認の変化に注目します。

:::details VACUUM後にHeap Fetchesが戻らなかった実例
2026年9月25日に同じ手順を実行し直したときは、再びVACUUMした後も`Heap Fetches`が4のままでした（当時のデータでは、本42の記録は2件でした）。別の接続が前日から`BEGIN`したまま、`COMMIT`も`ROLLBACK`もしていなかったためです。`VACUUM (VERBOSE) reading_records`を実行すると、`2 are dead but not yet removable`と報告されました。古い版が2つあるが、まだ捨てられない、という意味です。「いつ古い版を片付けられる？」で書いた、長く終わらないトランザクションがあると片付けられない状況が、そのまま起きていました。読者の環境で0に戻らないときは、次のSQLで開いたままの接続がないかを確かめてください。

```sql
SELECT pid, state, xact_start FROM pg_stat_activity
WHERE state = 'idle in transaction';
```

`idle in transaction`は、トランザクションを始めたまま何も実行していない接続です。その接続の作業内容を確認し、確定するなら`COMMIT`、取り消すなら`ROLLBACK`で終了します。その後にVACUUMし直すと、古い版を残していた原因の一つを取り除けます。

ただし、長いトランザクションがなくても、1回のVACUUMで`Heap Fetches`が0に戻るとは限りません。既定の`INDEX_CLEANUP AUTO`では、不要なレコードが少ないとIndexの掃除を省くことがあります。テーブルのレコードを片付けてもIndexからの参照が残り、ページに「すべて見えてよい」という印を付けられない場合があります。0に戻らないときは、`VACUUM (VERBOSE)`の出力で、まだ捨てられないレコードがあるのか、Indexの掃除が省かれたのかも確認します。[VACUUMの公式説明](https://www.postgresql.org/docs/18/sql-vacuum.html)に、掃除を選ぶ条件が載っています。
:::

## 電源が切れたら、メモリの変更はどうなる？

`UPDATE`で書き換えたページは、まず共有バッファの上で変更済みになります。メモリ上の内容は電源断で失われるため、変更を確定するにはストレージへの保存が必要です。ただし、変更したデータページを、そのたびにファイルへ書き出すわけではありません。

代わりに先に保存するのが、変更を障害後に再現するための記録です。これを**WAL**（Write-Ahead Log、先行書き込みログ）と呼びます。通常のテーブルでは、変更したデータページを書き出すより先に、その変更に必要なWALを保存します。ページへの反映が途中で止まっても、保存したWALから復旧できます。

既定の設定（`fsync=on`、`synchronous_commit=on`）では、COMMITは、そのトランザクションを復旧するために必要なWALの保存を待ってから返ります。データページ自体の書き出しは、必要なWALの保存が済んでいれば、COMMITの前にも後にも起こりえます。

変更済みのデータページは、後から書き出されます。ある時点までの変更をデータページへ反映し終え、その印をWALに残す処理を**チェックポイント**と呼びます。電源が切れた後の復旧では、最後のチェックポイントの印から後のWALだけを読み直して、変更を再現します。印より前の変更は、すでにデータページのファイルに書かれているからです（[チェックポイントの公式説明](https://www.postgresql.org/docs/18/wal-configuration.html)）。既定の設定では、変更があれば遅くとも5分ごとにチェックポイントが走ります[^bg-processes]。

![チェックポイントで変更済みのページを書き出してWALに印を残し、本42の変更の記録をCOMMITまでに保存する。電源断の後は、印から後の記録だけを読んで本42のページを作り直す](/images/postgresql-query-journey/11-wal-and-pages.png)
*④で読み直すのは、①の印から後のWAL（本42の記録）だけです。①の前の記録は、ページがすでにファイルへ書き出されているので読みません（既定の`fsync=on`、`synchronous_commit=on`を前提にした、説明するための図）。*

[^bg-processes]: 第6章の補足で触れた、ページを書き出したりデータを保守したりする別のプロセスが、この役割を分担します。WALの書き出しにはWAL writer、チェックポイントのときのページ書き出しにはcheckpointer、変更済みページの随時の書き出しにはbackground writerが関わります。コミットした接続のバックエンドプロセス自身がWALを書くこともあるので、WALを書くのは一つのプロセスだけではありません。

### UPDATEは、どれだけWALを作ったのか

可視性の実験で実行した`UPDATE`には、`WAL`オプションを付けていました。次のSQLです。すでに実行したので、もう一度実行する必要はありません。

```sql
EXPLAIN (ANALYZE, BUFFERS, WAL)
UPDATE reading_records SET finished_at = finished_at WHERE book_id = 42;
```

2026年9月26日の実行結果です。本の順に進め、第8章の`reading_records_order_idx`が残っている状態で採取しました。Indexの数が違うと、更新するIndexの数も変わるため、WALやBuffersの数値も変わりえます。

```sql:実行結果
Update on reading_records  (cost=4.61..97.52 rows=0 width=0) (actual time=0.095..0.096 rows=0.00 loops=1)
  Buffers: shared hit=16 read=2 dirtied=2
  WAL: records=4 bytes=304
  ->  Bitmap Heap Scan on reading_records  (cost=4.61..97.52 rows=24 width=14) (actual time=0.009..0.010 rows=1.00 loops=1)
        …
        ->  Bitmap Index Scan on reading_records_visibility_idx  (cost=0.00..4.61 rows=24 width=0) (actual time=0.003..0.004 rows=1.00 loops=1)
              …
```

WALの行を読む前に、計画の木の形を確かめます。第6章と同じく、字下げのいちばん深い処理から読みます。下の`Bitmap Index Scan`と`Bitmap Heap Scan`は、書き換える記録を探す処理です。本42の記録を1件見つけ、親へ渡しています（`rows=1.00`）。推定の`rows=24`が実際の1件より多いのは、第10章で見た、`book_id`の種類数を少なく見積もるずれと同じ向きです。

いちばん上の`Update on reading_records`が、受け取った記録の新しい版をテーブルに書き込む処理です。SELECTの計画と違い、この処理は親へレコードを渡さないので、`RETURNING`を付けない限り`rows`は0になります。INSERTやDELETEの計画でも一番上に同じ種類の処理が置かれ、`Insert on`や`Delete on`と表示されます[^modifytable]。

[^modifytable]: `EXPLAIN (FORMAT JSON)`で出力すると、この種類は`ModifyTable`と表示されます。[EXPLAINの使い方の公式説明](https://www.postgresql.org/docs/18/using-explain.html)にも、テーブルを変更する作業は一番上の処理が行い、その下の処理は古いレコードを探したり新しい値を計算したりする、と書かれています。

`Buffers`の`dirtied=2`は、この実行中に、まだ変更済みではなかったページを2枚、新たに変更済みにしたことを示します。すでに変更済みのページをさらに書き換えても、この数には加わりません。また、この数だけではテーブルとIndexのどのページを変更したかまでは分かりません。`written`の表示がないのは、この実行を担当したバックエンドによる計測対象の書き戻しが0だった、という意味です。同時に動く別のプロセスの書き出しまで0だったとは言えません。

`WAL:`の行は、この文が**生成した**WALの記録の数（`records=4`）と大きさ（`bytes=304`）です。4件は、テーブルの古い版と新しい版を書き換える記録と、2つのIndexにそれぞれ項目を足す記録です[^wal-records]。ストレージへの保存が完了した量ではありません。保存の完了や、データページより先にWALを保存した順序は、この`EXPLAIN`からは観測できません。

[^wal-records]: この実行はHOT更新ではありませんでした（`Heap Fetches`が2）。Indexの列の値を変えないのにHOT更新にならないのは、新しい版を同じページに置けなかったときです。2026年9月28日に、lab の`BEGIN`〜`ROLLBACK`の中で本42のページを埋めてから同じ`UPDATE`を実行し、`pg_waldump`で記録を一覧すると、`records=4`で、古い版に書き換え中の印を付ける`LOCK`、新しい版を別のページに書く`UPDATE`、Indexの葉に項目を足す`INSERT_LEAF`が2件でした。日時を1秒ずらした更新（Indexの列の値が変わるのでHOT更新にならない）で、新しい版を同じページに置けたときは`LOCK`がなく3件、HOT更新では`UPDATE`に当たる1件だけでした。

この出力には、ページ全体の内容を記録した数を表す`fpi`がありません。0の項目は表示されないためです。PostgreSQLは、チェックポイントの後で初めてページを変更するとき、ページ全体の内容をWALに記録します。ページの書き出しの途中で電源が切れると、ファイルの中のページに古い内容と新しい内容が混ざることがあり、差分の記録だけでは直せないからです（[`full_page_writes`の説明](https://www.postgresql.org/docs/18/runtime-config-wal.html#GUC-FULL-PAGE-WRITES)）。

直前のVACUUMとの間にチェックポイントが挟まると、あなたの結果にも`fpi=3`のように表示され、ページ全体を記録する分だけ`bytes`も数万バイトに増えます。書き出された後のページを変更し直すので、`dirtied`も増えることがあります。各項目の定義は[EXPLAINの公式説明](https://www.postgresql.org/docs/18/sql-explain.html)で確認できます。

COMMITのたびに全データページを保存し直すわけではありません。読み手に何が見えるかというMVCCの役割と、障害後も変更を残すWALの役割を分けましょう。

:::details COMMITがWALの保存を待たない設定
`synchronous_commit=off`にすると、COMMITがWALの保存を待たずに返ります。そのため、直後に障害が起きると、確定済みと応答した変更を失う可能性があります。ただし、`fsync=on`で通常のテーブルを扱うとき、データページより先に必要なWALを保存する順序は変わりません。[WALの設定](https://www.postgresql.org/docs/18/runtime-config-wal.html)も参照してください。
:::

:::details SELECTでもWALが作られる場合
ここまでのSELECTには`WAL`オプションを付けていないので、その出力からWALの有無は判断できません。SELECTでもWALを生成する場合があります。一つは、読み取り中に、レコードの可視性の判断を助ける印をページに付ける場合です。データのチェックサムや`wal_log_hints`の設定によっては、この変更でもWALが生成されます。もう一つは、読み取り中に、もう誰からも見えない古い版をページから片付ける場合で、この片付けもWALに記録されます[^prune-wal]。
:::

[^prune-wal]: 2026年9月28日、PostgreSQL 18.6の使い捨てのDBで、2回更新した150件のテーブルを読むSELECTだけを実行し、そのとき書かれたWALを`pg_waldump`で調べました。印を付けたページの丸写し（`FPI_FOR_HINT`）と、古い版の片付け（`PRUNE_ON_ACCESS`）の両方が記録されていました。実験用DBはデータのチェックサムが有効でした（PostgreSQL 18から、新しく作るDBの既定です）。

## ランキングの改善案に、何が加わったか

序章で挙げた改善案の一つは、あらかじめ読了記録を数えておく方法でした。この章で見たように、テーブルのレコードは更新されるたびに新しい版が作られ、古い版はVACUUMで片付けられます。読み込みの速さは、Index、メモリ、統計だけでなく、この更新と保守の状態にも左右されます。

前もって数えた集計用テーブルを使うなら、新しい記録や訂正、削除があるたびに、そのテーブルも書き直す必要があります。書き直すたびに新しいレコードの版とWALの記録が作られ、古い版はVACUUMで片付ける対象になります。表示が速くなっても、この書き直しの負担は読み込みの時間には現れません。

## まとめ

- 更新は上書きではなく、新しい版を作る。読み手は、版の`xmin`・`xmax`のトランザクションがスナップショットの時点で確定していたかを見て、見せる版を選ぶ。古い版は、それを見る可能性のある読み手がいなくなるまで残る。
- 長く開いたままのトランザクションは、VACUUMによる古い版の片付けを止める。
- Index Only Scanでも、可視性マップで確かめられないページは、テーブルを見に行く（`Heap Fetches`）。

## 第12章へ

次章では序章のランキングに戻り、Index、集計の順序、事前集計の3案を、読む速さと、その代わりに増える負担の両方で比べます。
