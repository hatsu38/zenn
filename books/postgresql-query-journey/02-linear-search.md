---
title: "第2章：見つかったところで止めればよいのでは？"
---

## この章で分かること

同じ100万冊から1冊を探すとき、見つかったところで止めれば仕事を減らせるでしょうか。LIMITの有無と検索する題名を変え、早く見つかる場合・遅く見つかる場合・見つからない場合を比べます。返す行が1行でも、見つかる位置によって調べる行数が変わることを、実行結果で確かめます。

## はじめに：1冊見つけた後も、調べる必要はある？

第1章では、1冊を返すために100万行を調べていました。検索画面で1冊だけ表示したいなら、見つかったところで止めてもよさそうです。

同じ100万冊を使って、返す件数を制限する`LIMIT 1`を試します。早く見つかる本と、なかなか見つからない本では、どんな違いがあるでしょうか。

![100万冊から、1冊見つけたら止める？](/images/postgresql-query-journey/05-growing-library.png)
*学ぶきっかけを描く、説明用の場面。棚の絵は実際の行の配置を表していません。*

まず、次の三つを予想してください。

1. 早く見つかる本なら、何行調べるか。
2. 遅く見つかる本なら、何行調べるか。
3. 存在しない本でも、1行だけで終えられるか。

## 比較する条件をそろえる

第1章の100万冊をそのまま使います。題名用の索引はまだ作りません。psqlで次を設定します。再接続したら設定し直してください。

```sql
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
SET synchronize_seqscans = off;
```

設定の実行結果です。

```sql
SET
SET
SET
SET
```

最初の三つは第1章と同じです。最後の設定は、複数の走査が読み取り位置をそろえる機能を無効にします。この章では表の先頭から読み始めて比較するために使います。設定の意味は[PostgreSQLの公式ドキュメント](https://www.postgresql.org/docs/18/runtime-config-compatible.html#GUC-SYNCHRONIZE-SEQSCANS)でも確認できます。これは実験の条件であり、SQLが返す行の順序を保証する設定ではありません。

冊数を確認します。

```sql
SELECT count(*) FROM books;
```

実行結果です。

```sql
  count
---------
 1000000
(1 row)
```

まず、LIMITを付けない検索を同じ接続で記録します。

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books WHERE title = '実験用の本 42';
```

2026年9月23日、DockerのPostgreSQL 18.6での実行結果です。本100万冊・主キー索引のみの状態で、以下のLIMIT付き検索まで順に実行しました。

```sql
Seq Scan on books  (cost=0.00..19853.00 rows=1 width=30) (actual time=0.009..36.378 rows=1.00 loops=1)
  Filter: (title = '実験用の本 42'::text)
  Rows Removed by Filter: 999999
  Buffers: shared hit=5537 read=1816 written=97
Planning:
  Buffers: shared hit=12
Planning Time: 0.083 ms
Execution Time: 36.396 ms
```

返した1行と除外した999,999行を足すと、100万行です。`loops=1`なので、この走査1回で100万行に条件を当てています。この結果を、同じデータでLIMITを付けた場合と比べます。

## 順番に調べる場合の比較回数

説明用に5冊へ縮めます。本4を探していても、同じ題名が後ろにもあるかもしれないので、条件に合う行を全部求める検索では最後まで調べます。

![見つけても、そこで終わりとは限らない](/images/postgresql-query-journey/05-linear-scan.png)
*5冊へ縮めた模型 ／ 題名に一意性の指定なし。*

5冊なら5冊分、100万冊なら100万冊分の確認が必要です。このような、一つずつたどる探し方を**線形探索**と呼びます。

件数を`n`と置くと、仕事の増え方を`O(n)`と書きます。「オーダー・エヌ」と読みます。難しい計算の式というより、**件数が増えたら、仕事もそれに応じて増える**という増え方の名前です。

ただし、件数が100倍なら秒数も必ず100倍、とは言えません。計測時の状態やほかの処理の負荷も時間に関わるからです。ページの再利用による影響は第5章で調べます。仕事量と時間は、関係しますが同じ値ではありません。

## 見つかったら止まってよいなら？

今度は、同じ題名が複数あっても1行だけでよいとします。

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books
WHERE title = '実験用の本 42'
LIMIT 1;
```

今回の実行結果です。

```sql
Limit  (cost=0.00..19853.00 rows=1 width=30) (actual time=0.008..0.008 rows=1.00 loops=1)
  Buffers: shared hit=2
  ->  Seq Scan on books  (cost=0.00..19853.00 rows=1 width=30) (actual time=0.007..0.007 rows=1.00 loops=1)
        Filter: (title = '実験用の本 42'::text)
        Rows Removed by Filter: 41
        Buffers: shared hit=2
Planning Time: 0.055 ms
Execution Time: 0.019 ms
```

### 探し方は同じでも、途中で止まれた

出力では、`Limit`の下にまだ`Seq Scan`があります。索引を使う検索に変わったわけではありません。

- `Rows Removed by Filter: 41`：一致しなかった41行を除外。
- `actual ... rows=1.00`：一致した1行を返した。
- `loops=1`：この走査を1回実行。

今回は、**41＋1＝42行を確認したところで終了**しています。`LIMIT 1`によって、1行見つかった後は残りを調べずに済みました。「速い探し方に変わる」効果と、「必要な結果がそろったら止まる」効果を分けて考えられます。

ここでの42行は、出力の行数を足して分かった値です。検索条件の本の番号が42だから、必ず42行目で見つかるという意味ではありません。

実行時の`Buffers: shared hit=2`は、`Limit`とその子の`Seq Scan`の両方に出ています。親の値には子の処理が含まれるので、足して4回とは数えません。計画作成時の情報が`Planning`に出ている場合は、検索の実行時と分けて読みます。

実行時間は0.019 msでした。時間はキャッシュなどの状態にも左右されますが、今回、調べた行数が100万行から42行へ減ったことは出力から確認できます。


`LIMIT 1`は「最大1行でよい」という依頼です。目的の行を見つければ、上のLimitがそれ以上要求しなくて済む場合があります。

![LIMIT 1でも、探す量は変わる](/images/postgresql-query-journey/05-limit-search.png)
*読み順を固定した模型 ／ SQLの行順を保証しない。*

これは早く見つかった場合の模型です。目的の行が後ろにあれば、そこまで調べます。存在しなければ、最後まで調べて初めて「ない」と分かります。

## 遅く見つかる本と、存在しない本も探す

次の二つは、結果を予想してから実行してください。初期データを作った後に行の追加・更新をしていない状態で比べます。

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books
WHERE title = '実験用の本 999999'
LIMIT 1;
```

実行結果です。

```sql
Limit  (cost=0.00..19853.00 rows=1 width=30) (actual time=39.306..39.307 rows=1.00 loops=1)
  Buffers: shared hit=5746 read=1607 written=94
  ->  Seq Scan on books  (cost=0.00..19853.00 rows=1 width=30) (actual time=39.305..39.306 rows=1.00 loops=1)
        Filter: (title = '実験用の本 999999'::text)
        Rows Removed by Filter: 999998
        Buffers: shared hit=5746 read=1607 written=94
Planning Time: 0.038 ms
Execution Time: 39.319 ms
```

今回は1行を返すまでに999,998行を除外し、合わせて999,999行を調べました。`LIMIT 1`があっても、目的の行へたどり着くまでの確認は残っています。

続いて、存在しない題名で試します。

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM books
WHERE title = '存在しない本'
LIMIT 1;
```

実行結果です。

```sql
Limit  (cost=0.00..19853.00 rows=1 width=30) (actual time=35.350..35.350 rows=0.00 loops=1)
  Buffers: shared hit=5841 read=1512 written=94
  ->  Seq Scan on books  (cost=0.00..19853.00 rows=1 width=30) (actual time=35.348..35.348 rows=0.00 loops=1)
        Filter: (title = '存在しない本'::text)
        Rows Removed by Filter: 1000000
        Buffers: shared hit=5841 read=1512 written=94
Planning Time: 0.067 ms
Execution Time: 35.368 ms
```

返した行は0行、除外した行は100万行です。1行も見つからないので、表を最後まで調べています。

| 今回の検索 | 返した行 | 除外した行 | 調べた行の合計 |
| --- | ---: | ---: | ---: |
| 本42・LIMITなし | 1 | 999,999 | 1,000,000 |
| 本42・LIMIT 1 | 1 | 41 | 42 |
| 本999999・LIMIT 1 | 1 | 999,998 | 999,999 |
| 存在しない本・LIMIT 1 | 0 | 1,000,000 | 1,000,000 |

この表は、今回の単純なSeq Scan・`loops=1`での観察です。SQLに`ORDER BY`がなければ行の順序は保証されません。主キーの番号が、そのまま見つかる順番を保証するわけではないので、自分の出力でも行数を確かめてください。

## 行の数だけでなく、ページを見る

たくさんの行を比べるには、その行を含むページにも触れます。一つのページを読み、その中の行を比較し、次のページへ進みます。

出力には`BUFFERS`もありますが、ここではまず調べた行数を比べます。「ページ」と「hit/read」の読み方は第4・5章で確かめます。100万行の検索がメモリ内で済んでも、100万行の条件を比べる仕事まで消えるわけではありません。

同じ本を`WHERE id = 42`でも探し、索引を使う計画と比べましょう。比べる軸は「速かった」だけでなく、どの方法で、どれだけの範囲に触れたかです。

## 結果件数と、調べる行数の違い

上位20冊を返すランキングも、結果が20だから仕事が20件分とは限りません。必要な答えを確定するまでに、どこまで調べるかが重要です。

「LIMITを付けたので、大きな表でも大丈夫」という提案には、**見つからない場合と、遅く見つかる場合も確かめよう**と返せます。

次章では、途中を一つずつ確認せず、探す範囲を狭める索引の仕組みを見ます。

この章だけの設定を戻します。

```sql
RESET synchronize_seqscans;
```

実行結果です。

```sql
RESET
```

実験用リポジトリの`sql/02/01-observe.sql`に、この章の比較SQLをまとめています。掲載出力の元ログは`results/chapter02-million-2026-09-23.txt`です。
