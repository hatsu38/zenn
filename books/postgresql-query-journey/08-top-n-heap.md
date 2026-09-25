---
title: "第8章：上位20件だけを選ぶには"
---

## この章で分かること

上位20件だけが必要なとき、すべての順位を確定する必要はあるのでしょうか。少数の候補を保つヒープを具体例で追い、top-N heapsortの出力と対応させます。さらに、Indexの順序を利用する取得方法と比較します。調べる件数、候補として保持する件数、返す件数を分け、LIMITが減らす処理を説明できるようになります。

:::message
日時Indexがない状態から始め、章の途中で作成します。読み直しでは第1章末の再開手順を使い、作成前と作成後を区別します。
:::

## 20件しか表示しないのに

最近の記録の画面に入るのは20件だけです。第7章のSortは対象週の499,998件をすべて並べていましたが、画面に出ないレコードの順位まで決める必要があるでしょうか。

![並びがばらばらの約50万件から、画面に最新20件を出す。読む件数と持つ件数は「？」、返すのは20件](/images/postgresql-query-journey/08-twenty-window.png)
*読む・持つ・返すの三つのうち、LIMIT 20で減るのはどれかを考えてください（説明のための場面）。*

この章で選ぶのは日時順の記録です。本ごとの読了数を比べる人気ランキングとは、並べる基準が違います。

まず、前章と同じ週の検索に`LIMIT 20`を付けます。読了記録は200万件で、日時用のIndexはまだありません。読むレコード数、候補として持つレコード数、返すレコード数のどれが減るか、予想してから実行してください。

```sql
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, finished_at
FROM reading_records
WHERE finished_at >= timestamp '2026-09-14'
  AND finished_at < timestamp '2026-09-21'
ORDER BY finished_at DESC, book_id ASC
LIMIT 20;
```

予想と出力を比べる前に、小さなカードの例で候補の残し方を考えます。

## 上位3枚を残すゲーム

説明用に、数字が大きい上位3枚を選びます。届くカードは8、3、5、9、2の順です。

最初の8、3、5を候補にします。次のカードを入れるか決めるには、候補の中で最小の値が分かれば十分です。新しい値がそれより大きければ、最小の候補を外して入れ替えられます。

この最小値を取り出しやすくするために使うのが、**ヒープ**という木構造です[^heap-name]。ここでは、親の値が子の値以下になるように配置します。すると、一番上の「根」に最小値が来ます。この形を最小ヒープと呼びます。

[^heap-name]: PostgreSQLでは、テーブルの格納先も「ヒープ」と呼びます。同じ名前ですが、この章の優先順位を扱う木構造とは別の用語です。

図の1コマ目では根が3、その子が8と5です。9が届いた後、根の値がどう変わるかを追ってください。

![届く順8・3・5・9・2のうち、9が根の3より大きいので3を外して9を根へ入れ、小さい子の5と交換して根を5にする。次の2は根の5より小さいので候補に入れない](/images/postgresql-query-journey/top-three-heap.png)
*各コマの上の▼が、いま届いたカードです。根の最小値と比べて、入れ替えるかを決めます（説明するための図。カードはレコードに対応します）。*

1コマ目の9は、候補で最小の3より大きいので残します。2コマ目で3を外し、9を根へ入れました。ただし、このままでは親9が子8と子5より大きく、ヒープの条件を満たしていません。

そこで、小さいほうの子5と9を交換します。3コマ目では根が5、その子が8と9になり、親の値が子以下という条件が戻りました。候補の中で最小の値を、再び根から確かめられます。

4コマ目の2は、根の5より小さいので候補に入れません。入力をすべて確かめた後、残った候補を必要な出力順に整えます。今回は大きい順に9、8、5です。

1コマ目の子は左が8、右が5で、小さい順には並んでいません。それでも根は最小です。ヒープは、すべての値の順位を確定せずに、候補の最小値を管理できる構造です。

## 候補が3枚なら、見るカードも減る？

ここまでの5枚の後に100が来るかもしれません。だから、順序が分からない入力では、候補を3枚だけ持つとしても、届くカードは最後まで確かめます。

`n`は全入力、`k`は残したい件数です。1枚を入れ替えるたびに、最大で木の高さの分だけ値を交換します。木の高さは候補数`k`に対して`log k`程度なので、`n`枚を確かめる比較の回数はおよそ`n log k`になります。これを`O(n log k)`と書きます。入力の件数`n`は減らせず、残す件数`k`が小さいほど1回の入れ替えが軽くなります。

実行計画に`top-N heapsort`が出ていたら、PostgreSQLは上の3枚のゲームと同じく、上位`k`件の候補だけをヒープに保ちながら並べています。小さいメモリ表示でも、子のScanが多くのレコードを返していないか確認してください。

2026年9月25日、PostgreSQL 18.6での実行結果です。本100万冊・読了記録200万件、並列実行とJITは無効です。 `work_mem`は4MBです。

```sql
Limit  (cost=54092.78..54092.83 rows=20 width=16) (actual time=125.644..125.648 rows=20.00 loops=1)
  Buffers: shared hit=9545 read=1266
  ->  Sort  (cost=54092.78..55340.61 rows=499134 width=16) (actual time=125.639..125.641 rows=20.00 loops=1)
        Sort Key: finished_at DESC, book_id
        Sort Method: top-N heapsort  Memory: 26kB
        Buffers: shared hit=9545 read=1266
        ->  Seq Scan on reading_records  (cost=0.00..40811.00 rows=499134 width=16) (actual time=0.026..92.883 rows=499998.00 loops=1)
              Filter: ((finished_at >= '2026-09-14 00:00:00'::timestamp without time zone) AND (finished_at < '2026-09-21 00:00:00'::timestamp without time zone))
              Rows Removed by Filter: 1500002
              Buffers: shared hit=9545 read=1266
Planning Time: 0.111 ms
Execution Time: 125.690 ms
```

Seq Scanは、返した499,998件と除外した1,500,002件を合わせて200万件を調べました。そのうちソートへ入ったのは499,998件、上で返すのは20件でした。26kBは、20件の候補を保つのに見合う小ささです。調べたレコード数は499,998件のままなので、この値だけを見て「20件しか調べなかった」とは読めません。

図で、第7章の`ORDER BY`だけの実行とこの章の実行を、三つの数で比べてください。

![ORDER BYだけとLIMIT 20の比較。Sortに入る499,998件は同じで、持つ量は27,913kBと26kB、返すレコードは499,998件と20件に変わる](/images/postgresql-query-journey/08-sort-vs-topn.png)
*Sortに入るレコードは同じで、持つ量と返すレコードだけが減ります（左は第7章、右はこの章の実測。work_memの設定は64MBと4MBで違います）。*

## 最初から順序が分かるなら？

日時順のIndexがあるなら、新しい日時のレコードから読む方法を選べます。必要な20件がそろえば、その先を調べずに終われる場合があります。

```sql
CREATE INDEX reading_records_order_idx
ON reading_records (finished_at DESC, book_id ASC);
ANALYZE reading_records;
```

Indexを作る前と同じSQLを、もう一度測ってください。

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, finished_at
FROM reading_records
WHERE finished_at >= timestamp '2026-09-14'
  AND finished_at < timestamp '2026-09-21'
ORDER BY finished_at DESC, book_id ASC
LIMIT 20;
```

同日のIndex作成後の実行結果です。

```sql
Limit  (cost=0.43..2.87 rows=20 width=16) (actual time=0.010..0.055 rows=20.00 loops=1)
  Buffers: shared hit=21 read=2
  ->  Index Only Scan using reading_records_order_idx on reading_records  (cost=0.43..60903.81 rows=498993 width=16) (actual time=0.009..0.052 rows=20.00 loops=1)
        Index Cond: ((finished_at >= '2026-09-14 00:00:00'::timestamp without time zone) AND (finished_at < '2026-09-21 00:00:00'::timestamp without time zone))
        Heap Fetches: 20
        Index Searches: 1
        Buffers: shared hit=21 read=2
Planning:
  Buffers: shared hit=11 read=4
Planning Time: 0.128 ms
Execution Time: 0.083 ms
```

Sortが消え、`reading_records_order_idx`の`Index Only Scan`が20件を返して止まっています。`cost`側の`rows=498993`は最後まで読んだ場合の見積もりで、今回読み出したレコード数ではありません。実際のレコード数は`actual`側の`rows=20`です。

ここでは`Heap Fetches: 20`もあります。20件を返すためにテーブルのレコードも確認しました。Index Only Scanでもテーブルへの確認がありうる理由は、第11章で確かめます。

上位3件を選ぶ小さな例で、入力の順序が分からない場合と、大きい順に取り出せる場合を並べてみます。保持する候補の数だけでなく、何件を確認するかに注目してください。

![順序が分からない入力では5件をすべて読み、候補3件を持って9・8・5を返す。大きい順のIndexなら3件を読んだところで止まり、候補を持たずに9・8・5を返す](/images/postgresql-query-journey/08-top-n-vs-index.png)
*同じ3件を返すのに、上は5件を読んで3件を持ち、下は3件を読んで止まります（上位3件を求める小さな例。本文の実験は日時順20件）。*

ここで用意したのは、WHEREの日時条件にも、ORDER BYの並び順にも合うIndexです。Indexの並びとは関係のない条件で多数のレコードが除かれるなら、20件を得るためにもっと多くのレコードを読むこともあります。

`Index Only Scan`という名前が出ても、「絶対にテーブルを読まない」という意味にはしないでください。テーブルへの確認が必要かは第11章で扱います。

## たくさん欲しくなったら、もう一度比べる

`LIMIT 20`を外すと、対象週のすべてのレコードが必要になり、Indexを途中で読み終えられません。Indexを順に読む処理や、必要ならテーブルのレコードを取り出す処理が増えるので、選ばれる方法も変わりえます。

`LIMIT 20`だけを外して測ります。

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT book_id, finished_at
FROM reading_records
WHERE finished_at >= timestamp '2026-09-14'
  AND finished_at < timestamp '2026-09-21'
ORDER BY finished_at DESC, book_id ASC;
```

:::details LIMITを外した実行結果
```sql
Index Only Scan using reading_records_order_idx on reading_records  (cost=0.43..60903.81 rows=498993 width=16) (actual time=0.006..391.229 rows=499998.00 loops=1)
  Index Cond: ((finished_at >= '2026-09-14 00:00:00'::timestamp without time zone) AND (finished_at < '2026-09-21 00:00:00'::timestamp without time zone))
  Heap Fetches: 499998
  Index Searches: 1
  Buffers: shared hit=499275 read=2641 written=1750
Planning:
  Buffers: shared hit=4
Planning Time: 0.023 ms
Execution Time: 406.659 ms
```
:::

同じIndex Only Scanでも、今度は499,998件を返し、`Heap Fetches`も499,998です。前の20件で終われた計画との違いを、時間だけでなくレコード数で確認できます。

課題です。「最近の20件」に効いた日時のIndexで、「今週よく読まれた20冊」もすぐ決まるでしょうか。

:::details 考え方
日時順のIndexには、本ごとの読了数は保存されていません。読了数順のランキングを作るには、本ごとの記録を数える処理が必要です。順序を何によって決めるかを確認します。
:::

Indexを作った後の計画でSortが消えていれば、最新20件はIndexの順に取り出せています。ただし、この20件には本の番号しかなく、画面に題名を出せません。「今週よく読まれた20冊」を作るには、記録に題名を付ける処理と、同じ本の記録を数える処理も必要です。次章では、まずこの最新20件に題名を付け、続いて本ごとに数えます。今回のIndexは残して進みます。
