---
title: "第11章：更新された行と、読み手から見える行"
---

## この章で分かること

更新中の表を複数の接続から読むと、同じ行でも見える値が異なることがあります。スナップショットと行のバージョンを観察し、不要な領域の回収、可視性マップ、Index Only Scanを結び付けます。最後にWALとデータページの書き出しを整理します。読み取り性能を、更新・後片付け・耐久性まで含めて考えるための章です。

## はじめに：書き換えている途中で読まれたら

一人が題名を直している間に、別の人が同じ本を読もうとしたら、何が見えるでしょうか。

同じ本を二人が同時に扱う場面です。読み手から見える内容を、操作の順番に沿って追ってみましょう。

![題名を直している間に、読まれたら？](/images/postgresql-structures-explain/11-editing-scene.png)
*学ぶきっかけを描く、説明用の場面。*

答えはトランザクションの状態や分離レベルにも関わります。この後は条件を指定して実験します。

ここでは、本番のデータではなく第1章からの実験用DBを使います。第2章と同じ方法でpsqlを二つ開き、AとBと呼びます。

**トランザクション**は、複数の操作をひとまとまりとして扱う単位です。`BEGIN`で始め、`COMMIT`で確定、`ROLLBACK`で取り消します。

## 同じ読み手の見え方を固定する

まず接続Aで、次を実行します。

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT title FROM books WHERE id = 42;
```

`Repeatable Read`は、今回の読み取りで使う「見える時点」を保つための指定です。読み取りの基準になる状態を**スナップショット**と呼びます。表を丸ごと別の場所へコピーする、という意味ではありません。

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

Aのトランザクション中の検索と、その後の検索で違いが見えるでしょうか。今回の順序なら、Aは途中の検索で元の題名を見て、COMMIT後の新しい検索で改訂版を見ます。

![読む時点によって、見える版が変わる](/images/postgresql-structures-explain/11-snapshots.png)
*本文の実験順序 ／ Repeatable Readを明示して実行。*

最初から最新だけを残して上書きしていたら、古い題名を読み続けられません。ここで行のバージョンという考え方が必要になります。

標準的な`Read Committed`では、各文の開始時点で見える状態が変わります。分離レベルを指定せずに同じ実験をしたら違う結果になりうるため、今回の指定は重要です。[分離レベルの公式説明](https://www.postgresql.org/docs/18/transaction-iso.html)も参照できます。

## 同じ本でも、行の版がある

PostgreSQLでは、更新によって新しい行バージョンが作られます。複数の版を使って読み手ごとの見え方を管理する仕組みが**MVCC**です。

先ほどの3コマでは、同じ本42についてAから見える版を描きました。実際のページ配置や索引の更新をすべて描いたものではありません。

第3章の`ctid`は行バージョンの場所でした。更新後に変わりうるので、主キーの代わりに使えないという話がここにつながります。

実験後、どちらかの接続で題名を戻します。

```sql
UPDATE books SET title = '実験用の本 42' WHERE id = 42;
```

## いつ古い版を片付けられる？

古い版を必要とする読み手がいれば、まだ捨てられません。古い版を参照する可能性のあるトランザクションがなくなると、その領域を回収できます。不要になった行バージョンの領域を再利用可能にする処理がVACUUMです。

「再利用可能」と「ファイルがその分小さくなる」は別です。普通のVACUUMは、空いた場所を次の行に使えるようにすることが中心です。

一方、`ANALYZE`は統計情報を更新する処理です。VACUUMによる領域の回収とは目的が異なります。autovacuumは、こうした保守を自動で進める仕組みです。長いトランザクションが古い状態を必要とし続けると、片付けを妨げることがあります。

## 索引だけで返せると思ったのに

第8章で、日時と本番号の両方を持つ索引を作りました。検索する列が索引にあるなら、表を読まなくてもよさそうです。

しかし、「値があるか」と「この読み手に見えてよい行か」は別の確認です。

PostgreSQLは、表のページごとの可視性を補助情報に持ちます。これが**可視性マップ**です。Index Only Scanでは、必要な可視性情報が確認できないページについて、表の行へ見に行く場合があります。

![索引だけで返せるかは、可視性にもよる](/images/postgresql-structures-explain/11-visibility-map.png)
*Index Only Scanの模型 ／ ページごとに判断。*

AとBのトランザクションをすべて終了してから、試します。VACUUMはBEGINの中では実行しません。

```sql
CREATE INDEX reading_records_visibility_idx
ON reading_records (book_id, finished_at);
VACUUM (ANALYZE) reading_records;
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, finished_at FROM reading_records
WHERE book_id = 42
ORDER BY finished_at DESC, book_id ASC;
```

Index Only Scanの`Heap Fetches`が、表へ確認しに行った回数の手掛かりです。次は小さな変更を加え、同じ検索を比べます。ここでは本42の行を探しやすくする実験用の索引も一つ追加しています。

```sql
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

値を同じにしてもUPDATEは行バージョンを作ります。ただし、変更したページを実際の検索が読むか、別の計画になるか、自動保守が動いたかで結果は変わります。Heap Fetchesが必ず決まった数増える、とは予告しません。正式な条件は[Index Only Scanの解説](https://www.postgresql.org/docs/18/indexes-index-only-scans.html)にあります。

今回の確認では、同じ本42の2行を返す検索で、次の違いが出ました。

| 状態 | 選ばれた方法 | Heap Fetches |
| --- | --- | ---: |
| VACUUM後 | Index Only Scan Backward | 0 |
| UPDATE後 | Index Only Scan Backward | 4 |
| 再びVACUUM後 | Index Only Scan Backward | 0 |

これは2026年9月22日のPostgreSQL 18.6での実測です。返す行は2行でも、表への確認回数は2とは限りません。古い版も関わるため、結果件数と確認の仕事を分けて読みます。時間も測っていますが、この小さな実験では速さの順位ではなく、表への確認の変化に注目します。

## 電源が切れたら、メモリの変更はどうなる？

メモリ上の内容は電源断で失われるため、変更を確定するにはストレージへの保存が必要です。そこで、変更を再現するための記録を先に保存する仕組みを使います。これが**WAL、先行書き込みログ**です。

![ログの保存と、ページの書き出し](/images/postgresql-structures-explain/11-wal-and-pages.png)
*役割と順序の制約を示す模型 ／ 実際の処理は並行する。*

この図は標準的な耐久性設定での役割の模型です。データページの書き出しには、その変更に必要なWALが先に永続化されているという約束があります。

WAL writerはWALの書き出しに関わり、checkpointerはチェックポイント時のページ書き出しなどを進めます。background writerも変更済みページを書き出します。コミットを行うバックエンドもWALの書き出しを担いうるため、WAL writerだけが書くとは考えません。

COMMITのたびに全データページを保存し直すわけではありません。読み手に何が見えるかというMVCCの役割と、障害後も変更を残すWALの役割を分けましょう。

## 次は、全部を使って判断する

索引、メモリ、統計だけでなく、更新された状態や保守も読み込みに関わります。事前集計を使う場合も、新しい記録や訂正を集計結果へ反映する必要があります。

次章では最初のランキングへ戻り、「読むのが速い」だけでなく、どんな負担と引き換えなのかまで比べます。
