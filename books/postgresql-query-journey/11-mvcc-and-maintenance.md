---
title: "第11章：更新された行と、読み手から見える行"
---

## この章で分かること

更新中のテーブルを複数の接続から読むと、同じ行でも見える値が異なることがあります。スナップショットと行のバージョンを観察します。そこから、不要になった領域の回収（VACUUM）、可視性マップ、Index Only Scanの関係をたどります。最後に、更新の実行計画に現れる`WAL`の行を読み、WALとデータページの書き出しを整理します。読み取り性能を、更新、後片付け、耐久性まで含めて考えられるようになります。

:::message
第8章の日時Indexを残し、以前のトランザクションを終了してから始めます。二接続の実験が終わったら両方のトランザクションを終了し、可視性の実験へ進みます。
:::

## 書き換えている途中で読まれたら

第10章では、`UPDATE`で8,000行の値を変えました。そのとき、元の行はどうなったのでしょうか。一人が題名を直している間に、別の人が同じ本を読もうとしたら、何が見えるでしょうか。読み手から見える内容を、操作の順番に沿って追います。

![接続Aと接続Bの画面が、本42の同じ行を指す。Bはまだ確定しておらず、COMMITのボタンが残っている](/images/postgresql-query-journey/11-editing-scene.png)
*二つの接続は同じ行（id 42）を指していますが、Bのボタンはまだ押されていません。*

第4章から使ってきたトランザクションは、複数の操作をひとまとまりとして扱う単位でした。`BEGIN`で始め、`COMMIT`で確定、`ROLLBACK`で取り消します。答えは、トランザクションの状態と、分離レベル（ほかのトランザクションの変更をどこまで見せるかの設定）にも関わります。この後は条件を指定して実験します。

ここでは、本番のデータではなく第1章からの実験用DBを使います。第6章と同じ方法でpsqlを二つ開き、AとBと呼びます。

## 同じ読み手の見え方を固定する

まず接続Aで、次を実行します。

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT title FROM books WHERE id = 42;
```

`Repeatable Read`は、このトランザクションの中のすべての読み取りで、同じ「見える時点」を使い続けるための指定です。読み取りの基準になる状態を**スナップショット**と呼びます。100万冊のテーブルをコピーすれば時間も容量も足りないので、テーブルを丸ごと別の場所へ写すわけではありません。どの時点までに確定した変更を見るか、という基準だけを持ちます。この基準は、次の節の行バージョンと組み合わせて働きます。

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

```sql
実験用の本 42
```

BのCOMMIT後、Aの同じトランザクション内のSELECT：

```sql
実験用の本 42
```

A自身もCOMMITした後のSELECT：

```sql
改訂版の本 42
```

Bが確定しただけではAの見える題名は変わりません。Aのトランザクションが終わり、次のSELECTで新しいスナップショットを使うと題名が変わりました。
:::

`Repeatable Read`の定義どおりなら、Aは途中の検索で元の題名を見て、COMMIT後の新しい検索で改訂版を見ます。もしPostgreSQLが更新のたびに行を上書きし、最新の版だけを残していたら、接続Aは古い題名を読み続けられません。ここで行のバージョンという考え方が必要になります。

![本42の行はBのUPDATEで版1と版2の二つになり、Aは②でも版1を読み、COMMIT後の③で版2を読む](/images/postgresql-query-journey/11-snapshots.png)
*②でも、Aの矢印は版1を指したままです。AがCOMMITした後の③で、初めて版2を見ます（説明するための図）。*

既定の`Read Committed`では、SQL文を実行するたびに、その開始時点の状態を見直します。そのままなら、接続Aの2回目の検索でも、Bが確定した改訂版が見えるはずです。今回はその違いを避けるために`Repeatable Read`を指定しました。[分離レベルの公式説明](https://www.postgresql.org/docs/18/transaction-iso.html)も参照できます。

実験後、どちらかの接続で題名を戻します。

```sql
UPDATE books SET title = '実験用の本 42' WHERE id = 42;
```

## 同じ本でも、行の版がある

PostgreSQLでは、更新によって新しい**行バージョン**が作られます。複数の版を使って読み手ごとの見え方を管理する仕組みが**MVCC**（Multi-Version Concurrency Control）です。

先ほどの3コマでは、同じ本42についてAから見える版を描きました。実際のページ配置やIndexの更新をすべて描いたものではありません。

第4章では、`ctid`は更新後に変わりうるので主キーの代わりには使えない、と説明しました。更新のたびに新しい行バージョンが作られ、その場所が`ctid`だからです。第10章で`UPDATE`した8,000行にも、新しい版が作られました。`ROLLBACK`はその更新を取り消す操作で、元の版が引き続き有効です。取り消された新しい版の領域は、後から回収の対象になります。

## いつ古い版を片付けられる？

古い版を必要とする読み手がいれば、まだ捨てられません。古い版を参照する可能性のあるトランザクションがなくなると、その領域を回収できます。長く終わらないトランザクションがあると、その間は古い版を片付けられないことがあります。

不要になった行バージョンの領域を再利用可能にする処理が**VACUUM**です。「再利用可能」と「ファイルがその分小さくなる」は別です。普通のVACUUMは、空いた場所を次の行に使えるようにすることが中心です。

一方、`ANALYZE`は統計情報を更新する処理です。VACUUMによる領域の回収とは目的が異なります。autovacuumは、この二つの保守を自動で進める仕組みです。

## Indexだけで返せると思ったのに

第8章で、日時と本番号の両方を持つIndexを作りました。第9章の計画にも、このIndexを使う`Index Only Scan`があり、`Heap Fetches: 0`と表示されていました。検索する列がIndexにあるなら、テーブルを読まなくてもよさそうです。

しかし、Indexの項目には値と行の場所しかなく、その行がどのトランザクションから見えるかはテーブルの行にしか書かれていません。「値があるか」と「この読み手に見えてよい行か」は別の確認です。

そこでPostgreSQLは、テーブルのページごとに「このページの行はすべての読み手に見えてよいか」を記録した補助情報を持っています。これが**可視性マップ**です。ページごとに数ビットの印を持ち、テーブルと一緒にファイルとして保存されます。ここで使う「すべて見えてよい」という印を付けるのはVACUUMです。第3章の検索用ビットマップは、一回の検索中に対象のページや行の位置を覚えるものでした。可視性マップは、読み手からの見え方を記録するもので、役割が異なります。Index Only Scanは、可視性マップで「すべて見えてよい」と確かめられないページについては、テーブルの行を見に行きます。

![Index (book_id, finished_at) の二つの項目のうち、可視性マップが✓のページの項目はテーブルを見ずに返し、×のページの項目だけテーブルの行を確かめる](/images/postgresql-query-journey/11-visibility-map.png)
*×のマスと、そこからテーブルへ伸びる矢印を見てください。この矢印の回数がHeap Fetchesです（説明するための図）。*

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

値を同じにしてもUPDATEは行バージョンを作ります。ただし、結果は次の条件で変わります。検索が変更したページを読むかどうか、別の計画が選ばれるかどうか、その間にautovacuumが動いたかどうかです。Heap Fetchesが必ず決まった数増える、とは予告しません。正式な条件は[Index Only Scanの解説](https://www.postgresql.org/docs/18/indexes-index-only-scans.html)にあります。

今回の確認では、同じ本42の2行を返す検索で、次の違いが出ました。

| 状態 | 選ばれた方法 | Heap Fetches |
| --- | --- | ---: |
| VACUUM後 | Index Only Scan Backward | 0 |
| UPDATE後 | Index Only Scan Backward | 4 |
| 再びVACUUM後 | Index Only Scan Backward | 0 |

これは2026年9月22日のPostgreSQL 18.6での実測です。返す行は2行でも、テーブルへの確認回数は2とは限りません。UPDATEで本42の2行に新しい版ができ、Indexには古い版と新しい版の項目が両方残った可能性があります。更新したページは可視性マップの印が消えるので、4つの項目それぞれでテーブルを確かめ、見えない古い版を除いて2行を返したと考えられます。VACUUM後は0に戻りました。古い版の項目が片付き、印が戻ったためと考えられます。結果の件数と、テーブルへ確認する処理は分けて読みます。時間も測っていますが、この小さな実験では速さの順位ではなく、テーブルへの確認の変化に注目します。

:::details VACUUM後にHeap Fetchesが戻らなかった実例
2026年9月25日に同じ手順を実行し直したときは、再びVACUUMした後も`Heap Fetches`が4のままでした。別の接続が前日から`BEGIN`したまま、`COMMIT`も`ROLLBACK`もしていなかったためです。`VACUUM (VERBOSE) reading_records`を実行すると、`2 are dead but not yet removable`と報告されました。古い版が2つあるが、まだ捨てられない、という意味です。「いつ古い版を片付けられる？」で書いた、長く終わらないトランザクションがあると片付けられない状況が、そのまま起きていました。読者の環境で0に戻らないときは、次のSQLで開いたままの接続がないかを確かめてください。

```sql
SELECT pid, state, xact_start FROM pg_stat_activity
WHERE state = 'idle in transaction';
```

`idle in transaction`は、トランザクションを始めたまま何も実行していない接続です。その接続の作業内容を確認し、確定するなら`COMMIT`、取り消すなら`ROLLBACK`で終了します。その後にVACUUMし直すと、古い版を残していた原因の一つを取り除けます。

ただし、長いトランザクションがなくても、1回のVACUUMで`Heap Fetches`が0に戻るとは限りません。既定の`INDEX_CLEANUP AUTO`では、不要な行が少ないとIndexの掃除を省くことがあります。テーブルの行を片付けてもIndexからの参照が残り、ページに「すべて見えてよい」という印を付けられない場合があります。0に戻らないときは、`VACUUM (VERBOSE)`の出力で、まだ捨てられない行があるのか、Indexの掃除が省かれたのかも確認します。[VACUUMの公式説明](https://www.postgresql.org/docs/18/sql-vacuum.html)に、掃除を選ぶ条件が載っています。
:::

## 電源が切れたら、メモリの変更はどうなる？

先ほどの`UPDATE`の実行結果に戻ります。`WAL`オプションを付けたので、`Buffers`の次に`WAL:`の行が出ています。2026年9月25日の実行結果です。この出力は第8章の`reading_records_order_idx`がない状態で採取しました。本の順に進めてそのIndexが残っている場合は、更新するIndexが増えるため、WALやBuffersの数値も変わりえます。

```sql
Update on reading_records  (cost=0.43..12.46 rows=0 width=0) (actual time=0.193..0.193 rows=0.00 loops=1)
  Buffers: shared hit=20 dirtied=3
  WAL: records=6 fpi=2 bytes=16786
  ->  Index Scan using reading_records_visibility_idx on reading_records  (cost=0.43..12.46 rows=2 width=14) (actual time=0.015..0.021 rows=2.00 loops=1)
        Index Cond: (book_id = 42)
        Index Searches: 1
        Buffers: shared hit=5
Planning:
  Buffers: shared hit=3
Planning Time: 0.051 ms
Execution Time: 0.307 ms
```

`Buffers`の`dirtied=3`は、この実行中に、まだ変更済みではなかったページを3枚、新たに変更済みにしたことを示します。すでに変更済みのページをさらに書き換えても、この数には加わりません。また、この数だけではテーブルとIndexのどのページを変更したかまでは分かりません。`written`の表示がないのは、この実行を担当したバックエンドによる計測対象の書き戻しが0だった、という意味です。同時に動く別のプロセスの書き出しまで0だったとは言えません。

`WAL:`の行は、この文が**生成した**記録の数（`records=6`）と大きさ（`bytes=16786`）を示します。ストレージへの保存が完了した量ではありません。`fpi=2`はページ全体のイメージを記録した数です。特に`fpi`は、直前のチェックポイント（後述）からそのページを初めて変更したかどうかで変わります。各項目の定義は[EXPLAINの公式説明](https://www.postgresql.org/docs/18/sql-explain.html)で確認できます。

ここまでのSELECTには`WAL`オプションを付けていないので、その出力からWALの有無は判断できません。SELECTでもWALを生成する場合があります。読み取り中に、行の可視性の判断を助ける印をページに付ける場合があり、データのチェックサムや`wal_log_hints`の設定によっては、その変更でもWALが生成されます。

変更を障害後に再現するための記録が**WAL**（先行書き込みログ）です。メモリ上の内容は電源断で失われるため、変更を確定するにはストレージへの保存が必要です。通常のテーブルでは、変更したデータページを書き出すより先に、その変更に必要なWALを保存します。ページへの反映が途中で止まっても、保存したWALから復旧できます。これはWALの仕組みの説明であり、上の`EXPLAIN`だけで保存の完了や順序を観測できたわけではありません。

![電源が切れてもWALが残っていれば、ページを作り直せる](/images/postgresql-query-journey/11-wal-and-pages.png)
*既定の`fsync=on`、`synchronous_commit=on`を前提に、WALの保存と電源断後の復旧を描いています（説明するための図）。*

この既定の設定では、COMMITは、そのトランザクションを復旧するために必要なWALの保存を待ってから返ります。データページ自体の書き出しは、必要なWALの保存が済んでいれば、COMMITの前にも後にも起こりえます。`synchronous_commit=off`にすると、COMMITがWALの保存を待たずに返るため、直後の障害で確定済みと応答した変更を失う可能性があります。ただし、`fsync=on`で通常のテーブルを扱うとき、データページより先に必要なWALを保存する順序は変わりません。[WALの設定](https://www.postgresql.org/docs/18/runtime-config-wal.html)も参照してください。

第6章で触れた、ページを書き出したりデータを保守したりする別のプロセスのうち、WALを書くものと、変更済みのページを書き出すものが、この役割を分担します[^bg-processes]。コミットした接続のバックエンドプロセス自身がWALを書くこともあるので、WALを書くのは一つのプロセスだけではありません。

[^bg-processes]: WALの書き出しにはWAL writer、チェックポイント（ある時点までの変更をデータページへ反映し終えた印を付ける処理。`fpi`はこの印の後で初めて変更したページで増えます）時のページ書き出しにはcheckpointer、変更済みページの随時の書き出しにはbackground writerが関わります。

COMMITのたびに全データページを保存し直すわけではありません。読み手に何が見えるかというMVCCの役割と、障害後も変更を残すWALの役割を分けましょう。

## ランキングの改善案に、何が加わったか

序章で挙げた改善案の一つは、あらかじめ読了記録を数えておく方法でした。この章で見たように、テーブルの行は更新されるたびに新しい版が作られ、古い版はVACUUMで片付けられます。読み込みの速さは、Index、メモリ、統計だけでなく、この更新と保守の状態にも左右されます。

前もって数えた集計用テーブルを使うなら、新しい記録や訂正、削除があるたびに、そのテーブルも書き直す必要があります。書き直すたびに新しい行の版とWALの記録が作られ、古い版はVACUUMで片付ける対象になります。表示が速くなっても、この書き直しの負担は読み込みの時間には現れません。

次章では序章のランキングに戻り、Index、集計の順序、事前集計の3案を、読む速さと、その代わりに増える負担の両方で比べます。
