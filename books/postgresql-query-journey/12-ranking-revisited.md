---
title: "第12章：ランキングを読み解き、改善を選ぶ"
---

## この章で分かること

序章のランキングを、ここまで学んだ観察方法、アルゴリズム、内部構造から読み解きます。Indexの追加、集計と結合の順序の変更、事前集計について、減る処理と残る処理を予想して比較します。結果が同じか、必要な鮮度を満たすか、更新の負担は何かも確かめます。AIや検索で得た案を、自分の条件と根拠で判断するところまでを本の到達点にします。

## 最初の問いに戻る

「20冊のランキングなのに、なぜ待たされる？」

序章では、返す冊数しか手掛かりがありませんでした。今なら、ランキングの処理を次の四つに分けられます。

1. 表を読む。
2. 記録と本を対応させる。
3. 本ごとに数える。
4. 上位を選ぶ。

さらに、これらの処理はページを読み、メモリを使います。どの方法で行うかは統計をもとに選ばれ、表の更新状態にも影響されます。この章では、ページは`BUFFERS`（第3章と第5章）、メモリは`Sort Method`と`Batches`（第7章と第9章）、統計は`rows`と`actual rows`（第10章）、更新状態は`Heap Fetches`（第11章）として、一つの計画の中で読みます。

この章の基準は、手元の本100万冊と読了記録200万件です。序章の2,000万件や約4.6秒とは条件が違うので、改善前後はここで測り直します。

序章では、Indexの追加、読了記録をあらかじめ数えておく方法、表示を10冊に減らす案の三つを挙げました。この章では、Indexを案1、第9章で出てきた「数えてから題名を付ける」を案2、前もって数える事前集計を案3として比べ、10冊に減らす案は第8章の結果から考えます。

![今度は、根拠を持って選べる](/images/postgresql-query-journey/12-decision-notebook.png)
*学ぶきっかけを描く、説明用の場面。*

## 基準となるSQLを残す

psqlを再接続した場合も、同じ設定から始めます。

```sql
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
SELECT count(*) FROM books;
SELECT count(*) FROM reading_records;
```

比較では同じSQLを何度も使うので、その接続の中だけで使えるビューを作ります。ビューは検索に付けた名前で（第6章）、結果そのものは保存しません。接続を閉じると消えるので、再開時は作り直します。

```sql
CREATE TEMP VIEW ranking_before AS
SELECT b.id, b.title, count(*) AS read_count
FROM books AS b
JOIN reading_records AS r ON r.book_id = b.id
WHERE r.finished_at >= timestamp '2026-09-14'
  AND r.finished_at < timestamp '2026-09-21'
GROUP BY b.id, b.title
ORDER BY read_count DESC, b.id ASC
LIMIT 20;

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM ranking_before;
```

この章の実行計画は本書に載せていません。自分の環境で同じ検索を3回測り、行数、方式、時間、BUFFERSを残してください。値がばらつくなら、それも結果です。必要なページがすでに共有バッファにあるかどうかでも時間は変わるので、1回だけの小さな差で勝ち負けを決めません。

## 案1：Indexで減る処理を確かめる

第8章で日時順のIndexを作りました。いまの計画は、それを使っているでしょうか。使っていても、その後の結合や集約に渡す行が多ければ、そこには処理が残ります。

比較の手掛かりとして、実験の間だけIndexを使わないようにした計画も見ます。

```sql
BEGIN;
SET LOCAL enable_indexscan = off;
SET LOCAL enable_indexonlyscan = off;
SET LOCAL enable_bitmapscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM ranking_before;
ROLLBACK;
```

これはIndexを物理的に削除した測定ではなく、候補を制限する診断実験です。設定の違いを記録し、元の計画と比べます。計画を比べるときは、アクセス方法だけでなく、後続の処理へ渡す行数も確認します。

## 行の数が、どこで変わる？

次の案を考える前に、6件の読了記録から上位2冊を返す模型で、行数の変わり方を見ます。題名を付ける段階では何行あるかを見てください。図は処理を整理した例で、実行計画のノードが必ずこの順に並ぶわけではありません。

![題名を付けてから、上位を選ぶ](/images/postgresql-query-journey/12-ranking-before.png)
*6記録と3冊から上位2冊の模型。本文では上位20冊です。*

行が20行まで減るのが最後の段なら、それより前の段では多くの行を扱うことになります。推定行数と実測行数も比べましょう。見積もりが外れている問題と、見積もりが合っていても処理が多い問題は分けます。

時間の読み方は第7章と第9章のとおりで、親の時間は子を含み、`loops`が複数なら1回当たりの平均です。時間の数字を「クエリ開始から何秒後」として引き算しないでください。まず行数と方式から、減らせそうな処理を探します。

## 案2：数えてから、題名を付ける

第9章の問いを試します。まず本の番号だけで数え、上位20冊を選んでから、本の題名を付けます。

```sql
CREATE TEMP VIEW ranking_after AS
SELECT b.id, b.title, top_books.read_count
FROM (
  SELECT book_id, count(*) AS read_count
  FROM reading_records
  WHERE finished_at >= timestamp '2026-09-14'
    AND finished_at < timestamp '2026-09-21'
  GROUP BY book_id
  ORDER BY read_count DESC, book_id ASC
  LIMIT 20
) AS top_books
JOIN books AS b ON b.id = top_books.book_id
ORDER BY top_books.read_count DESC, b.id ASC;

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM ranking_after;
```

同じ6件の模型で、先に数えて上位2冊を選びます。前の図と並べて、題名を付ける対象が何行になるかを見てください。

![上位を選んでから題名を付ける](/images/postgresql-query-journey/12-ranking-after.png)
*6記録と3冊から上位2冊の模型。本文では上位20冊です。*

どこへ渡す行が少なくなるか予想してから、実際の計画を読みましょう。

## 速くても、答えが変わったら困る

今回の書き換えが同じ結果を返すには、次の三つが前提です。

- 本の番号が一意である。
- 各記録に対応する本が存在する。
- 題名による絞り込みがない。

今回は外部キー制約（記録の本番号が本の表に必ずあることを保証する約束）を付けていません。そこで、本の表に番号が見つからない記録が0件かどうかを確かめます。

```sql
SELECT count(*) AS records_without_book
FROM reading_records AS r
WHERE NOT EXISTS (SELECT 1 FROM books AS b WHERE b.id = r.book_id);
```

この原稿の確認時には0件でした。0でなければ、先に上位を決める方法で結果が変わる可能性があります。

両方の結果に差がないかも調べます。

```sql
SELECT count(*) AS differing_rows FROM (
  (SELECT * FROM ranking_before EXCEPT ALL SELECT * FROM ranking_after)
  UNION ALL
  (SELECT * FROM ranking_after EXCEPT ALL SELECT * FROM ranking_before)
) AS differences;
```

確認時には、この差も0件でした。0なら、このデータで行の内容と個数に差がありません。ただし、この比較は表示順までは確かめていません。表示順は、両方の結果に`ORDER BY read_count DESC, id ASC`を付けて見比べます。

一つのデータで一致したことだけで、あらゆる場合の証明になるわけではありません。なぜ同じ結果になるかという前提と、実際の確認の両方が必要です。

## 案3：表示する前に数えておく

今度は、集計結果を本当に表へ保存します。ビューと違って、値を持つ表です。

```sql
\timing on
CREATE TABLE weekly_read_counts AS
SELECT book_id, count(*) AS read_count
FROM reading_records
WHERE finished_at >= timestamp '2026-09-14'
  AND finished_at < timestamp '2026-09-21'
GROUP BY book_id;
CREATE INDEX weekly_read_counts_order_idx
ON weekly_read_counts (read_count DESC, book_id ASC);
ANALYZE weekly_read_counts;

EXPLAIN (ANALYZE, BUFFERS)
SELECT b.id, b.title, w.read_count
FROM weekly_read_counts AS w JOIN books AS b ON b.id = w.book_id
ORDER BY w.read_count DESC, w.book_id ASC LIMIT 20;
```

集計表の作成、Indexの作成、読み出しの三つの時間を分けて記録します。表を作るのは最初の1回ですが、中身は記録が増えたり週が替わったりするたびに作り直すか更新します。

事前集計を使うと、表示時に読了記録を数える必要がなくなります。その代わり、集計表の作成や更新時に記録を数えます。比較では、読み出しと集計表の更新を分けて測ります。

![表示は軽くなる。集計の更新は必要。](/images/postgresql-query-journey/12-preaggregation.png)
*事前集計の模型。訂正や削除への対応も必要です。*

では、更新前に新しい記録が届いたらどうでしょう。表示は最新より少し古くなります。削除や訂正、週の切り替わりも反映する必要があります。

## 10冊に減らせば、速くなる？

序章の三つめの案は、表示を20冊から10冊に減らすことでした。第8章のtop-N heapsortを思い出してください。上位を選ぶには、順序が分からない入力を最後まで確かめる必要がありました。減るのは候補として保つ件数だけです。

ランキングでも同じです。10冊に減らしても、対象週の記録を読み、本ごとに数える処理は変わりません。減るのは、数え終えた後に上位を選ぶときの候補の数だけです。第8章では、`LIMIT 20`でもSortへの入力は499,998行でした。この案で待ち時間が大きく変わるとは考えにくく、確かめるなら`LIMIT 10`にした計画で、上位を選ぶ段より前の行数が変わっていないことを見ます。

## このサービスで、何を選ぶ？

自分の結果を使い、比較表を埋めてください。比較表には読み出し時間だけでなく、更新の間隔と、そのあいだ表示が古くなることも書き込みます。

| 案 | 減るはずの処理（見る値） | 残る・増える処理 | 自分の実測 |
| --- | --- | --- | --- |
| Indexを利用 | 期間内の記録を探すために読む範囲（BUFFERS、Rows Removed） | 集計と結合、Indexの維持 | |
| 先に集計して結合 | 題名を付ける対象の行数（結合に渡るrows） | 期間内の記録を数える | |
| 事前集計 | 表示時の集計（Aggregateの有無） | 集計の更新、鮮度の管理 | |

「最新の記録をすぐ反映したい」と「5分前までの集計でよい」では、判断が変わりえます。たとえば、この架空のサービスで5分の遅れを許せるなら、事前集計（案3）も候補に入ります。更新の負担が少ない案2を先に確かめ、足りなければ案3へ進む、という順も取れます。どちらの鮮度がこのサービスに必要かを、自分で決めて理由を書きましょう。

## 最後の課題：AIの案を検証する

AIから「`work_mem`を増やすと改善します」と提案されたとします。すぐに採用する前に、次の短い調査メモを書いてください。

1. このSQLで減るはずの処理は何か。
2. データ量、Index、設定、更新状態をどうそろえるか。
3. どの計画、行数、ページアクセスを見るか。
4. 結果が同じことをどう確認するか。
5. 時間と運用上の負担から、何を採用するか。
6. まだ分からず、追加で調べたいことは何か。

対象期間を1日、1週間、全期間に変えた場合も、同じ結論でしょうか。一度の成功から適用範囲を考えることが、学んだ仕組みを使う練習になります。

## 20冊のために、何を調べていたのか

20冊を返すまでに、PostgreSQLは対象週の記録（手元のデータでは約50万件、序章の条件では約500万件）を読み、題名と対応させ、本ごとに数えてから上位を選んでいました。返す20冊より前の段で、この途中の行数を扱っていました。待ち時間を減らす手掛かりは、この行数にあります。三つの案は、この途中の行数をどこで減らすか、あるいは表示の前に済ませておくかの違いです。

SQLを受け取るプロセス、データを格納するページ、ソートや集計に使うメモリは、それぞれ実行計画の処理と対応しています。仕組みから処理を予想し、EXPLAINの出力や実測値と比べることで、改善案を検討できます。

知らないノードに出会っても、最初から全名称を覚え直す必要はありません。「何を受け取り、どんな状態を持ち、何を返す処理か」と問い、観察するところから始められます。

序章で書いた予想を読み返してください。選ぶ案が同じでも、理由や確かめ方が増えていれば、第12章までの観察が役に立っています。
