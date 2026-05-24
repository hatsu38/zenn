---
title: "第 9 章 プランナと統計情報"
---

## この章で答える問い

- プランナは「行数」や「選択率」をどこの統計情報から計算しているのか？
- 統計が古いと、2 章で見た `rows` と `actual rows` の乖離はどう生まれるのか？
- 統計はいつ・誰が更新しているのか？（ANALYZE / autoanalyze）

:::message
**この章のゴール**: `pg_statistic` / `pg_stats` の中身を覗いて、`rows` 推定が「ヒストグラム」と「MCV」からどう計算されるかを実機で確かめられるようになる。
:::

## 主役クエリ

```sql
-- ① 統計を覗く
SELECT * FROM pg_stats WHERE tablename = 'articles' AND attname = 'author_id';

-- ② 統計を古くする実験（ロールバックで戻せる）
BEGIN;
EXPLAIN SELECT * FROM articles WHERE author_id = 1;  -- 元のプラン
INSERT INTO articles ... ;                            -- 大量挿入
EXPLAIN SELECT * FROM articles WHERE author_id = 1;  -- ANALYZE 前
ANALYZE articles;
EXPLAIN SELECT * FROM articles WHERE author_id = 1;  -- ANALYZE 後
ROLLBACK;
```

①でプランナが見ている統計の中身を直接覗き、②で「統計を古くすると `rows` 推定がどう外れるか」を実機で再現します。

---

## はじめに

<!--
TODO(human): この章の「つかみ」を 3〜5 行で本人の言葉で書く。
ヒント:
- 2 章で乖離を見たときに「なぜ外れる？」と思った瞬間
- pg_stats を初めて覗いたときの「中身こんな感じか」感
- 読者にどんな状態になってほしいか
-->

---

## 9.1 2 章の乖離はどこから来ているのか

2 章で `rows`（推定）と `actual rows`（実測）が大きくズレるパターンを見ました。あのときは「乖離が起きやすい原因」として 4 つのパターンを並べました。

1. 統計情報が古い
2. 相関のあるカラムの AND
3. LIKE 検索
4. 関数の中身

これら全部の **共通の根っこ** が「プランナが見ている統計情報」です。9 章では、そもそもプランナが何を見て `rows` を見積もっているのか、その情報源を覗きにいきます。

公式ドキュメントの言葉を借りるとこうです。

> 問い合わせプランナは、より良い問い合わせ計画を選択するために問い合わせによって取り出される行数の推定値を必要としています。
> ─ [PostgreSQL 17.x 文書 14.2.1 単一列の統計](https://www.postgresql.jp/document/17/html/planner-stats.html)

`rows` の推定値があるからこそ、3 章で見た Index Scan / Bitmap Heap Scan / Seq Scan の選び分けも、6・7 章で見た JOIN の選び分けも、全部が成立する。プランナの判断はすべて統計情報の上に建っている、というのが本章の出発点です。

---

## 9.2 プランナが見る統計情報の 3 つの場所

PostgreSQL がプランナのために保持している統計情報は、大きく 3 つの場所に分かれています。

| 場所 | 中身 | 保存先 |
|---|---|---|
| `pg_class` | テーブル全体の **行数（reltuples）** と **ページ数（relpages）** | システムカタログ |
| `pg_statistic` | カラムごとの **詳細な統計**（生データ、内部用） | システムカタログ |
| `pg_stats` | `pg_statistic` を読みやすく整形した **ビュー** | ビュー |

実際に使うのはほぼ `pg_class` と `pg_stats` の 2 つです。

### pg_class.reltuples / relpages

これは 1 章で既に覗きました。

```sql
SELECT reltuples::bigint, relpages
FROM pg_class
WHERE relname = 'articles';
-- planner_rows | relpages
--       100000 |     3951
```

`reltuples` は「このテーブルにだいたい何行ある」、`relpages` は「だいたい何ページ占めている」というざっくり統計。1 章で `cost=4951.00` を手計算したときに使ったのもこれです。

### pg_stats でカラムごとの詳細を覗く

`pg_class` よりも 1 段詳しいのが `pg_stats`。**カラムごとに** 値の分布などの統計を持っています。

```sql
SELECT * FROM pg_stats
WHERE tablename = 'articles' AND attname = 'author_id';
```

<!-- TODO(human): 上のクエリの出力を貼る。下の解説と突き合わせる。 -->

主なカラムだけ抜き出すと、こんな感じの構造になっています（実機の値はあとで埋めます）。

| カラム | 意味 |
|---|---|
| `null_frac` | NULL の割合 |
| `avg_width` | 1 行あたりの平均バイト数 |
| `n_distinct` | このカラムに出現する **異なる値の数** |
| `most_common_vals` | **最頻値（MCV）**の配列。「よく出る値トップ N」 |
| `most_common_freqs` | 各 MCV の出現頻度 |
| `histogram_bounds` | **ヒストグラム** の境界値の配列 |
| `correlation` | カラムの値と物理順序の相関係数（-1 から 1） |

これらのうち、選択率の推定に直接効くのが **MCV** と **ヒストグラム** の 2 つです。

---

## 9.3 ヒストグラムと MCV ─ 選択率はどう計算されているか

ヒストグラムと MCV は、プランナが `WHERE author_id = 1` のような WHERE 句から「何行ヒットしそうか」を計算するための材料です。

### 最頻値（Most Common Values, MCV）

`most_common_vals` には「特によく出る値」が配列で入っています。例えば次のような状況：

```text
most_common_vals  = {1, 2, 3, 4, 5}
most_common_freqs = {0.0008, 0.0006, 0.0006, 0.0005, 0.0005}
```

これは「`author_id = 1` の行は全体の 0.08%、`author_id = 2` は 0.06%、...」という意味です。プランナは `WHERE author_id = 1` を見ると、まず MCV に `1` があるかを探して、あれば `most_common_freqs` の対応する値で選択率を計算します。

```text
推定行数 = total_rows × most_common_freqs[i]
       = 100,000 × 0.0008
       = 80 行
```

3 章で `WHERE author_id = 1` の `rows=49` と推定されていたのも、こういう計算の結果です。

### ヒストグラム

`histogram_bounds` には **MCV に入らなかった値の分布** がヒストグラムの形で入っています。配列の各要素が「ここからここまでで全体の N%」を区切る境界値です。

```text
histogram_bounds = {6, 50, 100, 200, ..., 2000}
```

`WHERE author_id BETWEEN 1 AND 100` のように範囲指定すると、プランナはこのヒストグラムを使って「全体の 5% くらい」と見積もります。3 章で `rows=4931` と推定された出力（全体の約 5%）も、ヒストグラムからの計算です。

### つまり

`rows` の推定値は、**MCV の頻度 + ヒストグラムの境界** を組み合わせて計算されている、というのが 9.3 のまとめです。WHERE 句の値が MCV に入るか、ヒストグラムのどの区間に入るかで、選択率が決まります。

![pg_stats: MCV と Histogram で選択率を推定。プランナはこの統計情報から rows 推定を出す](/images/cddb89f9abfaca/11-histogram-mcv-selectivity.png)

---

## 9.4 統計を古くすると乖離が生まれる

ここが 9 章の山場です。「統計が古いと `rows` 推定がどう外れるか」を実機で再現します。

ロールバックで戻せるトランザクションの中で実験するので、サンプルアプリは安全です。

```sql
BEGIN;

-- ① 元のプランを記録
EXPLAIN SELECT * FROM articles WHERE author_id = 1;

-- ② author_id = 1 の行を大量挿入
INSERT INTO articles (author_id, title, body, created_at, updated_at)
SELECT 1, 'spam', 'spam body', NOW(), NOW()
FROM generate_series(1, 50000);

-- ③ 大量挿入したあと ANALYZE する前のプラン
EXPLAIN SELECT * FROM articles WHERE author_id = 1;
-- プランナは古い統計を見ているので、rows がまだ「49 行」のまま

-- ④ ANALYZE で統計を更新する
ANALYZE articles;

-- ⑤ 更新後のプラン
EXPLAIN SELECT * FROM articles WHERE author_id = 1;
-- プランナは新しい統計を見て、rows が「50,049 行」付近に修正される

ROLLBACK;
```

<!-- TODO(human): 上の手順を実機で叩いて、①②③④⑤の各 EXPLAIN 出力（特に rows の数字とプラン名）を貼って、3 段階の変化を見せる。 -->

予想される 3 段階の変化はこうです。

| 段階 | rows 推定 | プラン |
|---|---|---|
| ① 初期 | 49 | Bitmap Heap Scan |
| ③ INSERT 後・ANALYZE 前 | **49 のまま**（古い統計） | Bitmap Heap Scan（実は不適切） |
| ⑤ ANALYZE 後 | **50,049 付近** | Seq Scan に切り替わる可能性大 |

③ では実際に 50,049 行ヒットするのに、プランナは 49 行と思って Bitmap Heap Scan を選びます。**Bitmap Index Scan を 5 万件分やって、5 万ページぶんヒープを訪問する** という重い処理が走り、`actual time` が大きく出るはずです。これが「統計が古いと致命的になる」の正体です。

ANALYZE を打ったあとは、プランナが本来のヒット件数を知って、適切なプラン（Seq Scan）に切り替わります。

---

## 9.5 ANALYZE と autoanalyze

統計はいつ・誰が更新しているか。明示的に走らせる方法と、自動で走る方法の 2 つがあります。

### 手動の ANALYZE

```sql
ANALYZE articles;        -- 特定のテーブル
ANALYZE;                 -- 全テーブル
VACUUM ANALYZE articles; -- VACUUM と同時に
```

`ANALYZE` は **全行を読むわけではなく**、サンプリングして統計を作ります（デフォルトで 30,000 行程度）。10 万行のテーブルでも 1 秒以内で終わるのが普通。

### autoanalyze

通常は自動で走る `autoanalyze` が裏で動いています。これは autovacuum のサブプロセスで、「テーブルの行数の N% が変更されたら自動的に走る」という設定で動いています。

```sql
SHOW autovacuum_analyze_scale_factor;  -- デフォルト 0.1（10%）
SHOW autovacuum_analyze_threshold;     -- デフォルト 50
```

つまり「(0.1 × テーブル行数) + 50 行が変更されたら autoanalyze が走る」。10 万行のテーブルなら 10,050 行の変更で autoanalyze が起動します。

公式ドキュメントの記述もあります。

> これらは`VACUUM`、`ANALYZE`、`CREATE INDEX`などの一部のDDLコマンドによって更新されます。
> ─ [PostgreSQL 17.x 文書 14.2.1 単一列の統計](https://www.postgresql.jp/document/17/html/planner-stats.html)

autoanalyze の動作詳細は 10 章「VACUUM、MVCC、dead tuple」で autovacuum と一緒に扱います。

---

## 9.6 相関カラムと拡張統計

2 章で乖離の原因として「相関のあるカラムの AND」を挙げました。例えば `WHERE country = 'JP' AND lang = 'ja'` のように、強い相関を持つカラム同士を AND で繋いだとき、プランナは独立を仮定して掛け算してしまうため、推定が大きく外れます。

公式の警告も再掲します。

> 問い合わせ句で使われている複数列に相関性があることにより、悪い実行計画を実行する遅いクエリがしばしば観察されます。プランナは通常複数の条件がお互いに独立であるとみなしますが、列の値に相関性がある場合はそれは成り立ちません。
> ─ [PostgreSQL 17.x 文書 14.2.2 拡張統計](https://www.postgresql.jp/document/17/html/planner-stats.html)

この対策が **拡張統計（CREATE STATISTICS）** です。複数カラムの組を一緒に統計対象にして、相関を含む情報を保持できます。

```sql
-- country と lang のセット統計を作る（架空の例）
CREATE STATISTICS country_lang_stats (dependencies, ndistinct)
ON country, lang FROM some_table;

ANALYZE some_table;
```

サンプルアプリで明確な相関カラムの組は少ないですが、`articles.author_id` と `articles.published_at`（特定の著者は特定の時期によく投稿する、など）に擬似的に相関を作って実験するなら、こんな流れになります。

```sql
-- 検証
EXPLAIN ANALYZE SELECT * FROM articles
WHERE author_id = 1 AND published = true;

-- 拡張統計を作って ANALYZE
CREATE STATISTICS articles_author_published ON author_id, published FROM articles;
ANALYZE articles;

EXPLAIN ANALYZE SELECT * FROM articles
WHERE author_id = 1 AND published = true;
```

<!-- TODO(human): 上のクエリを実機で叩いて、拡張統計の前後で rows 推定がどう変わるかを見る。 -->

---

## 章のまとめ

<!--
TODO(human): この章で学んだことを 3 行で、本人の言葉で。
ヒント:
- pg_stats を覗いて MCV とヒストグラムを見つけたときの感想
- 統計を古くすると本当に乖離が出ることを実機で確認したインパクト
- 次章への期待
-->

---

## 次の章へ

第 9 章では、プランナが見ている統計情報の中身と、それを更新する ANALYZE / autoanalyze の挙動を見ました。第 10 章「**VACUUM、MVCC、dead tuple**」では、`autovacuum` がそもそも何のために走っているのか、`UPDATE` / `DELETE` で生まれる **dead tuple** の正体と、`SELECT count(*)` が遅くなる理由を扱います。
