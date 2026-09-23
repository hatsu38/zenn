---
title: "第12章：ランキングを読み解き、改善を選ぶ"
---

## この章で分かること

序章のランキングを、ここまで学んだ観察方法・アルゴリズム・内部構造から読み解きます。索引の追加、集計と結合の順序の変更、事前集計について、減る仕事と残る仕事を予想して比較します。結果が同じか、必要な鮮度を満たすか、更新の負担は何かも確かめます。AIや検索で得た案を、自分の条件と根拠で判断するところまでを本の到達点にします。

## はじめに：最初の問いに戻る

「20冊のランキングなのに、なぜ待たされる？」

序章では、返す冊数しか手掛かりがありませんでした。今なら、表を読む、記録と本を対応させる、本ごとに数える、上位を選ぶ、という仕事に分けられます。

さらに、その仕事がページを読み、メモリを使い、統計によって選ばれ、更新状態にも影響されることを学びました。これらを一緒に使います。

この章の基準は、手元の**100万冊・200万件の読了記録**です。序章の2,000万件や約4.6秒とは条件が違うので、改善前後はここで測り直します。

ランキング画面を改善する案を、調査メモにまとめます。最初に思いついた案を、今の知識で確かめ直します。

![今度は、根拠を持って選べる](/images/postgresql-query-journey/12-decision-notebook.png)
*学ぶきっかけを描く、説明用の場面。*

画面は説明用です。実際の順位と性能は、同じ条件でSQLを実行して比較します。

## 基準となるSQLを残す

psqlを再接続した場合も、同じ設定から始めます。

```sql
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET work_mem = '4MB';
SELECT count(*) FROM books;
SELECT count(*) FROM reading_records;
```

比較で何度も同じSQLを書くため、接続内だけで使うビューを作ります。**ビューはSQLに付けた名前**で、ここでは結果を事前保存しません。接続を閉じると消えるので、再開時は作り直します。

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

同じ検索を3回測り、行数、方式、時間、BUFFERSを残します。値がばらつくなら、それも結果です。使えるページがすでにメモリにあるかも関わるので、単発の小さな差だけで勝敗を決めません。

## 行の数が、どこで変わる？

まず、6件の読了記録から上位2冊を返す模型で考えます。題名を付ける段階では何行あるかを見てください。図は処理を整理した例で、実行計画のノードが必ずこの順に並ぶわけではありません。自分の計画では各段に何行あるかも確認しましょう。

![題名を付けてから、上位を選ぶ](/images/postgresql-query-journey/12-ranking-before.png)
*6記録・3冊から上位2冊の模型 ／ 本文では上位20冊。*

20行になるのが最後なら、それより前の仕事は多く残ります。推定行数と実測行数も比べましょう。見積もりが外れている問題と、見積もりが合っていても仕事が多い問題は分けます。

時間の数字を「クエリ開始から何秒後」として引き算しないでください。ノードの実行時間はその処理の計測であり、子の仕事や繰り返しも関わります。まず行数と方式から、減らせそうな仕事を探します。

## 案1：索引で減る仕事を確かめる

第8章で日時順の索引を作りました。いまの計画は、それを使っているでしょうか。使っていても、その後の結合や集約に渡す行が多ければ、そこには仕事が残ります。

比較の手掛かりとして、実験の間だけ索引の利用を抑えた候補も見ます。

```sql
BEGIN;
SET LOCAL enable_indexscan = off;
SET LOCAL enable_indexonlyscan = off;
SET LOCAL enable_bitmapscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM ranking_before;
ROLLBACK;
```

これは索引を物理的に削除した測定ではなく、候補を制限する診断実験です。設定の違いを記録し、元の計画と比べます。

索引によって読み込む範囲が減っても、取り出した記録の結合や集計は必要です。計画を比べるときは、アクセス方法だけでなく、後続の処理へ渡す行数も確認します。

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

同じ6件の模型で、先に数えて上位2冊を選びます。今度は、題名を付ける対象が何行になるでしょうか。

![上位を選んでから題名を付ける](/images/postgresql-query-journey/12-ranking-after.png)
*6記録・3冊から上位2冊の模型 ／ 本文では上位20冊。*

前の図と比べて、どこへ渡す行が少なくなるか予想してから、実際の計画を読みましょう。必ず何倍速くなる、という結論は置きません。

## 速くても、答えが変わったら困る

今回の書き換えが同じ結果を返すには、本の番号が一意で、各記録に対応する本が存在し、題名による絞り込みがないことが前提になります。

今回、外部キー制約は付けていないため、対応する本がない記録がないか確認します。

```sql
SELECT count(*) AS records_without_book
FROM reading_records AS r
WHERE NOT EXISTS (SELECT 1 FROM books AS b WHERE b.id = r.book_id);
```

サンプルデータでは0件を想定しています。0でなければ、先に上位を決める方法で結果が変わる可能性があります。

両方の結果に差がないかも調べます。

```sql
SELECT count(*) AS differing_rows FROM (
  (SELECT * FROM ranking_before EXCEPT ALL SELECT * FROM ranking_after)
  UNION ALL
  (SELECT * FROM ranking_after EXCEPT ALL SELECT * FROM ranking_before)
) AS differences;
```

この原稿の確認時には、対応する本のない記録も、書き換え前後の差も0件でした。

0なら、このデータで行の内容と個数に差がありません。表示順は`ORDER BY read_count DESC, id ASC`を両方の結果に明示して見比べます。

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

作成と索引作成の時間、読み出しの時間を分けて記録します。`CREATE TABLE`は最初の1回だけです。

事前集計を使うと、表示時に読了記録を数える必要がなくなります。その代わり、集計表の作成や更新時に記録を数えます。比較では、読み出しと集計表の更新を分けて測ります。

![表示は軽くなる。集計の更新は必要。](/images/postgresql-query-journey/12-preaggregation.png)
*事前集計の模型 ／ 訂正・削除への対応も必要。*

では、更新前に新しい記録が届いたらどうでしょう。表示は最新より少し古くなります。削除や訂正、週の切り替わりも反映する必要があります。読み出し時間だけを比較表に載せず、この責任も書き込みます。

## このサービスで、何を選ぶ？

自分の結果を使い、比較表を埋めてください。

| 案 | 減った仕事 | 残る・増える仕事 | 自分の実測 |
| --- | --- | --- | --- |
| 索引を利用 | 対象へ到達する経路 | 集計・結合、索引の維持 | |
| 先に集計して結合 | 題名を付ける対象 | 期間内の記録を数える | |
| 事前集計 | 表示時の集計 | 集計の更新、鮮度の管理 | |

「最新の記録をすぐ反映したい」と「5分前までの集計でよい」では、判断が変わりえます。どちらがこの架空のサービスに必要かを、自分で決めて理由を書きましょう。

## 最後の課題：AIの案を検証する

AIから「日時に索引を追加すると改善します」と提案されたとします。すぐに採用する前に、次の短い調査メモを書いてください。

1. このSQLで減るはずの仕事は何か。
2. データ量、索引、設定、更新状態をどうそろえるか。
3. どの計画・行数・ページアクセスを見るか。
4. 結果が同じことをどう確認するか。
5. 時間と運用上の負担から、何を採用するか。
6. まだ分からず、追加で調べたいことは何か。

対象期間を1日、1週間、全期間に変えた場合も、同じ結論でしょうか。一度の成功から適用範囲を考えることが、学んだ仕組みを使う練習になります。

## 処理の予想と実測を比べる

SQLを受け取るプロセス、データを格納するページ、ソートや集計に使うメモリは、それぞれ実行計画の処理と関係しています。仕組みから処理を予想し、EXPLAINの出力や実測値と比べることで、改善案を検討できます。

知らないノードに出会っても、最初から全名称を覚え直す必要はありません。「何を受け取り、どんな状態を持ち、何を返す仕事か」と問い、観察するところから始められます。

序章で書いた予想を読み返してください。選ぶ案が同じでも、理由や確かめ方が増えていれば、それがこの本で得た力です。
