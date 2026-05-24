---
title: "第 12 章 EXPLAIN で見つけるアンチパターン集"
---

## この章で答える問い

- EXPLAIN を見て「あ、これはアンチパターンだ」と気付けるパターンにはどんなものがある？
- それぞれのアンチパターンは、生 SQL と EXPLAIN の出力でどう見える？
- どう直せばプランが変わって速くなる？

:::message
**この章のゴール**: 1〜11 章で学んだ EXPLAIN の読み方を実戦に持ち込み、「同じテーブルの同じデータでも、クエリの書き方ひとつでプランが劇的に変わる」を体感する。出くわしたクエリが「直すべきか / 放っておくか」をその場で判断できるようになる。
:::

## 主役クエリ

12 章には「ひとつの主役クエリ」はありません。代わりに **悪い例 → 直し方** を並べた 8 つのアンチパターンを順に見ていきます。

---

## はじめに

<!--
TODO(human): この章の「つかみ」を 3〜5 行で本人の言葉で書く。
ヒント:
- 自分が現場で実際にハマったアンチパターンの話
- EXPLAIN を読めるようになってから気付けるようになったこと
- 読者にどんな状態になってほしいか
-->

---

## 12.1 WHERE で関数を使うとインデックスが効かない

### 悪い例

`authors` テーブルに `email` のユニークインデックスがあります。でも `WHERE lower(email) = '...'` のように **関数で包む** と、インデックスは使えません。

```sql
EXPLAIN ANALYZE
SELECT * FROM authors WHERE lower(email) = 'user1@example.com';
```

出力:

```
 Seq Scan on authors  (cost=0.00..... rows=10 width=...) (actual time=... rows=1 loops=1)
   Filter: (lower((email)::text) = 'user1@example.com'::text)
```

<!-- TODO(human): 実機の出力を貼る。Seq Scan が出ていることを確認。 -->

インデックスは「email の値そのもの」で並んでいます。`lower(email)` という**別の値**で検索すると、PostgreSQL は「インデックスから引いていいか」が判定できず、Seq Scan に逃げてしまう。

### 直し方 A: 式インデックス

PostgreSQL は **式インデックス** で「関数の結果」をインデックス化できます。

```sql
CREATE INDEX index_authors_on_lower_email ON authors (lower(email));

EXPLAIN ANALYZE
SELECT * FROM authors WHERE lower(email) = 'user1@example.com';
```

出力:

```
 Index Scan using index_authors_on_lower_email on authors  (cost=0.28..8.30 rows=1 width=...)
   Index Cond: (lower((email)::text) = 'user1@example.com'::text)
```

Index Scan に切り替わります。

### 直し方 B: そもそも関数を使わない（保存時に正規化）

書き込み時にメールアドレスを小文字で正規化しておけば、検索時に `lower()` を使わずに済みます。これが一番素直。

---

## 12.2 LIKE '%xxx%' は B-tree が効かない（中間一致）

### 悪い例

```sql
EXPLAIN ANALYZE
SELECT * FROM articles WHERE title LIKE '%Article 1%';
```

中間一致（`%` が前にある）だと B-tree インデックスは使えません。Seq Scan で全件を読むことになります。

前方一致なら B-tree が使える場合があります（ただし `text_pattern_ops` のオペレータクラスを指定したインデックスが必要なケースもあります）。

```sql
EXPLAIN ANALYZE
SELECT * FROM articles WHERE title LIKE 'Article 1%';
```

### 直し方: pg_trgm + GIN/GiST

中間一致が必須なら、**pg_trgm 拡張**でトライグラム化して GIN または GiST インデックスを張る、というのが現場の定番です（深くは別書籍に譲ります）。

```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX index_articles_on_title_gin ON articles USING gin (title gin_trgm_ops);

EXPLAIN ANALYZE
SELECT * FROM articles WHERE title LIKE '%Article 1%';
```

これで中間一致でも Index Scan が選ばれる可能性が出ます。

---

## 12.3 SELECT * の濫用

### 悪い例

```sql
EXPLAIN ANALYZE
SELECT * FROM articles WHERE id = (SELECT id FROM articles LIMIT 1);
```

`SELECT *` だと全カラムを返すので、PostgreSQL は必ずヒープを読みに行きます。**Index Only Scan の出番がない**わけです。

### 直し方: 必要なカラムだけにする

```sql
EXPLAIN ANALYZE
SELECT id FROM articles WHERE id = (SELECT id FROM articles LIMIT 1);
```

これで 4 章で見た Index Only Scan が候補に入り、`Heap Fetches: 0` で済む可能性が出ます。

実務でも「`SELECT *` を `SELECT 必要なカラムだけ` に直すだけで Index Only Scan に切り替わって速くなる」という例は珍しくありません。

---

## 12.4 ORDER BY が Index を使えない

### 悪い例

```sql
EXPLAIN ANALYZE SELECT * FROM articles ORDER BY title LIMIT 20;
```

`title` には index がないので、PostgreSQL は全件読んで Sort ノードで並べ替えます。5 章で見た `top-N heapsort` が走ります。10 万行に対しては許容できるかもしれませんが、1,000 万行になると一気に遅くなります。

### 直し方 A: Index がある列でソート

```sql
EXPLAIN ANALYZE SELECT id FROM articles ORDER BY id LIMIT 20;
```

`articles_pkey` を上から 20 件読むだけ。Sort ノードが**消えます**。

### 直し方 B: ソート用の Index を貼る

ビジネス要件上 `title` でソートする必要があれば、`title` に B-tree インデックスを貼ります。

```sql
CREATE INDEX index_articles_on_title ON articles (title);

EXPLAIN ANALYZE SELECT * FROM articles ORDER BY title LIMIT 20;
```

これで Sort ノードが消えて、Index Scan が「上から 20 件」読むだけになります。

---

## 12.5 count(*) の濫用

### 悪い例

```sql
EXPLAIN ANALYZE SELECT count(*) FROM articles;
```

10 章で見た通り、PostgreSQL の `count(*)` は MVCC の事情で **全件を読みに行きます**。10 万行ならまだ我慢できても、本番の数千万行レベルだと数秒〜数十秒かかります。

### 直し方 A: count(id) で Index Only Scan

```sql
VACUUM articles;
EXPLAIN ANALYZE SELECT count(id) FROM articles;
```

VACUUM 後なら Index Only Scan で `articles_pkey` だけを読んで count を出せます。ヒープを読まないぶん、`count(*)` より速い。

### 直し方 B: 概算で良いなら pg_class.reltuples

「正確な数じゃなくて、桁感が分かれば OK」という用途なら、これが一番速いです。

```sql
SELECT reltuples::bigint FROM pg_class WHERE relname = 'articles';
```

ANALYZE 時点の **推定値** ですが、ミリ秒未満で返ります。Web のページネーションでも「だいたい N 万件」みたいな表示で問題ないなら、これで十分です。

---

## 12.6 OR の多用

### 悪い例

```sql
EXPLAIN ANALYZE SELECT * FROM articles
WHERE author_id = 1 OR author_id = 2 OR author_id = 3 OR author_id = 4 OR author_id = 5;
```

OR を多用すると、プランナは「BitmapOr で各 OR 条件を統合する」プランを組むことが多いですが、コストが膨らんでうまく index が効かないことがあります。

### 直し方 A: IN にまとめる

```sql
EXPLAIN ANALYZE SELECT * FROM articles WHERE author_id IN (1, 2, 3, 4, 5);
```

意味は同じですが、プランナにとっては読みやすい形。

### 直し方 B: 連続範囲なら BETWEEN

```sql
EXPLAIN ANALYZE SELECT * FROM articles WHERE author_id BETWEEN 1 AND 5;
```

これも意味は近いですが、ヒストグラムを使った推定がより正確になりやすい。

3 章で実測したとおり、`BETWEEN 1 AND 5` は Bitmap Heap Scan で `cost=6.60..731.29` です。OR と IN と BETWEEN でコストが微妙に変わることがあるので、迷ったら 3 種類とも打って比較するのが筋。

---

## 12.7 暗黙の型キャスト

### 悪い例

`authors.id` は `bigint` ですが、文字列で比較してしまうとどうなるか。

```sql
EXPLAIN ANALYZE SELECT * FROM authors WHERE id = '1';
```

`text` の `'1'` を `bigint` の `id` と比較するには PostgreSQL が暗黙のキャストを挟みます。場合によっては「インデックスが使えないキャスト」が発生して Seq Scan になります（PostgreSQL のバージョンや状況によります）。

### 直し方: 型を合わせる

```sql
EXPLAIN ANALYZE SELECT * FROM authors WHERE id = 1;
```

アプリ層から ID をパラメータ化するときも、型を合わせるのが鉄則です。文字列で渡るか整数で渡るかでキャストの有無が変わり、最悪 Seq Scan に落ちます。本番でこれが起きると気付くのが難しいので、`EXPLAIN` を打って `Filter:` の中にキャストが見えたら疑う癖を付けたいところです。

---

## 12.8 N+1 ─ クライアント側で同じクエリを大量発行

### DB 側の症状

アプリ側の N+1 問題は、DB から見ると「**同じ形の SELECT が大量に飛んでくる**」状態として観測できます。`pg_stat_statements` 拡張があれば、これを集計で見つけられます。

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

設定 `shared_preload_libraries = 'pg_stat_statements'` が必要（Docker のサンプル環境では未設定。本番で使うなら設定してください）。

```sql
SELECT
    query,
    calls,
    total_exec_time,
    mean_exec_time
FROM pg_stat_statements
ORDER BY calls DESC
LIMIT 20;
```

ここで「`SELECT * FROM authors WHERE id = $1` が 1 万回呼ばれている」ような形が見えたら、それが N+1 のシグナルです。

### 直し方: 1 本のクエリにまとめる

クライアント側で「each で 1 件ずつ引く」のをやめて、IN や JOIN で 1 本にまとめます。

```sql
-- 悪い例 (擬似コード): for id in ids: SELECT * FROM authors WHERE id = $id
-- 直し方 A: IN でまとめる
EXPLAIN ANALYZE SELECT * FROM authors WHERE id IN (1, 2, 3, 4, 5);

-- 直し方 B: JOIN にする
EXPLAIN ANALYZE
SELECT a.title, au.name
FROM articles a
JOIN authors au ON au.id = a.author_id
WHERE a.id IN (SELECT id FROM articles LIMIT 10);
```

アプリ層で各 ORM・クエリビルダが提供する「一括ロード」や「JOIN 化」を使うのが基本ですが、本書のスタンスは **DB 側からどう見えるか** に絞ります。DB 側で N+1 を観測する手段が `pg_stat_statements` で、`calls` の大きいクエリを探せばアプリの実装に関係なく N+1 を見つけられます。

---

## 12.9 アンチパターンを見つける「3 つの目」

最後に、本章で扱ったアンチパターンを EXPLAIN ANALYZE 出力から見つけるための着眼点を 3 つにまとめます。

1. **`Filter:` 行に関数や型キャストが見える** → 12.1 / 12.7 を疑う
2. **`Sort` ノードが出ている / `Seq Scan` が選ばれている** → 12.3 / 12.4 / 12.2 を疑う
3. **`Buffers:` の `shared read` が異常に大きい / `pg_stat_statements` の `calls` が大きい** → 12.5 / 12.8 を疑う

EXPLAIN ANALYZE を読む癖を付けていけば、「クエリを書いた瞬間にこのパターンに当てはまっていないか？」を意識できるようになります。

---

## 章のまとめ

<!--
TODO(human): この章で学んだことを 3 行で、本人の言葉で。
ヒント:
- EXPLAIN を読めるようになったからこそ見えるアンチパターン
- 同じ機能でもクエリの書き方ひとつで全然違う
- 次章への期待（チートシート）
-->

---

## 次の章へ

第 12 章では、現場で出くわすアンチパターンを EXPLAIN ANALYZE 出力から見つけるための着眼点を集めました。最終章「**チートシートとふりかえり**」では、12 章ぶんの学びを 1 枚にまとめて、自分の手元で `EXPLAIN ANALYZE` を読むときに即座に参照できるチートシートを作ります。
