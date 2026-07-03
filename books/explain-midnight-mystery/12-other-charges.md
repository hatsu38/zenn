---
title: "第12話 余罪の捜査 ─ アンチパターン人相書き"
---

:::message
この物語はフィクションですが、登場する SQL と EXPLAIN の出力はすべて実測値です（数値の一部は環境により変動するため `...` 表記）。技術書版[「PostgreSQL の EXPLAIN と内部のしくみ」](https://zenn.dev/hatsu38/books/cddb89f9abfaca)第 12 章と同じサンプル DB で再現できます。
:::

## 1

翌日、午前11時。

ポストモーテムは淡々と終わった。時系列、根本原因、再発防止策──バッチ後の `ANALYZE` 追加、autovacuum のワーカー数とコスト制限の見直し、大量更新の分割実行。誰も責められなかった。「全員が仕様どおりに動いて、組み合わせだけが壊れた」という桐生さんの一文が、そのまま結論になった。

会議室に残った僕らの前に、桐生さんはノート PC を開いた。

「さて、余罪の捜査だ。一昨日の事件は氷山の一角──コードベースには、まだ発火してないだけの同類が眠ってる。**遅いクエリには典型的な顔つき**がある。人相書きを 8 枚作るぞ。順に検挙していく」

## 2

**【人相書き 1 号: 関数の覆面】**

リポジトリを `lower(` で grep したら、ログイン処理で一発ヒットした。

```sql
EXPLAIN ANALYZE
SELECT * FROM authors WHERE lower(email) = 'user1@example.com';
```

```
 Seq Scan on authors  (cost=0.00..... rows=10 ...) (actual ... rows=1 loops=1)
   Filter: (lower((email)::text) = 'user1@example.com'::text)
```

「email にはユニークインデックスがあるのに、Seq Scan……」

「インデックスは *email の値そのもの*で並んでる。`lower(email)` は**別の値**だ。覆面をかぶった顔は、索引では引けない。──直し方は 2 つ。関数の結果そのものに索引を張る**式インデックス** `CREATE INDEX ... ON authors (lower(email))`。もっと素直なのは、**保存時に小文字へ正規化**して、検索で関数を使わないことだ」

**【人相書き 2 号: 中間一致の亡霊】**

```sql
EXPLAIN ANALYZE SELECT * FROM articles WHERE title LIKE '%Article 1%';
```

「`%` が先頭にある中間一致は、B-tree では引けない。B-tree は*先頭から*並んでる辞書だからな。前方一致 `LIKE 'Article 1%'` なら使える余地がある。中間一致がビジネス要件なら、**pg_trgm 拡張 + GIN インデックス**が定番だ──文字列を 3 文字ずつの破片にして索引化する」

**【人相書き 3 号: 大食いのアスタリスク】**

「`SELECT *` は全カラムを返す。つまり**必ずヒープを読む**──第 4 話の Index Only Scan の出番を、書き方ひとつで潰してる。必要なカラムだけに絞れば `Heap Fetches: 0` の道が開ける。width も細くなって、第 1 話でやったとおり I/O コストまで下がる。ORM の既定値に任せきりのところ、全部見直せ」

**【人相書き 4 号: 索引なき整列】**

```sql
EXPLAIN ANALYZE SELECT * FROM articles ORDER BY title LIMIT 20;  -- Sort が出る
EXPLAIN ANALYZE SELECT id  FROM articles ORDER BY id    LIMIT 20;  -- Sort が消える
```

「第 5 話の鉄則だ。ORDER BY のカラムに索引が無ければ Sort、あれば『上から N 件』。10 万行の top-N heapsort は我慢できても、1,000 万行では死ぬ。ソートが要件なら `CREATE INDEX ... ON articles (title)` を張って、**Sort ノードごと消す**」

**【人相書き 5 号: 数え屋】**

「ダッシュボードの count(\*) 連打、昨日見つけたな。第 10 話のとおり count(\*) は全件読みだ。直し方は 3 段構え──①`count(id)` + VACUUM 維持で Index Only Scan 化。②桁感で足りる表示なら `SELECT reltuples::bigint FROM pg_class WHERE relname = 'articles'` で**ミリ秒未満**。③どうしても正確な数が高頻度で要るなら、それは設計の問題だ。集計テーブルを検討しろ」

**【人相書き 6 号: OR の行列】**

```sql
-- 行列       WHERE author_id = 1 OR author_id = 2 OR ... OR author_id = 5
-- まとめる   WHERE author_id IN (1, 2, 3, 4, 5)
-- 連続範囲   WHERE author_id BETWEEN 1 AND 5
```

「OR の連打はプランナに BitmapOr の組み立てを強いて、推定も荒れやすい。**IN にまとめる**、連続範囲なら **BETWEEN**。意味は同じでもプランナへの読ませ方が違う。迷ったら 3 種類とも EXPLAIN して比べろ──もうお前はそれができる」

**【人相書き 7 号: 化けの皮キャスト】**

```sql
EXPLAIN ANALYZE SELECT * FROM authors WHERE id = '1';   -- 文字列で比較
```

「bigint のカラムに文字列 '1' をぶつけると、暗黙のキャストが挟まる。状況次第でインデックスが使えず Seq Scan に落ちる。アプリのパラメータの**型が合ってるか**は、EXPLAIN の `Filter:` 行にキャストが見えるかで分かる。──これが怖いのは、コードレビューでまず気づけないことだ。ORM の中で型がすり替わる。**Filter 行のキャストを見たら疑え**」

**【人相書き 8 号: 千本ノック】**

「最後は、EXPLAIN 1 枚には映らない犯人だ。アプリの N+1──**同じ形のクエリが 1 万回飛んでくる**やつ。1 本 1 本は 0.1 ms の優等生だから、スロークエリログにも出ない。見つけるには `pg_stat_statements` 拡張で集計する」

```sql
SELECT query, calls, total_exec_time, mean_exec_time
FROM pg_stat_statements
ORDER BY calls DESC
LIMIT 20;
```

「`calls` が異常に多いクエリが人相書きだ。`SELECT * FROM authors WHERE id = $1` が 1 万 calls──見えたら、アプリ側で IN か JOIN に束ねる。第 6 話でやった Nested Loop の暴走を、**アプリが手動でやってる**構図だからな」

## 3

昼過ぎには、ボードに 8 枚の人相書きと、検挙リスト（Issue 番号つき）が並んでいた。

「最後に、パターン暗記より大事なものを渡す。**3 つの目**だ。初見の EXPLAIN ANALYZE で、どこを見れば人相書きに辿り着けるか」

1. **`Filter:` 行に関数や型キャストが見える** → 1 号・7 号を疑え
2. **Sort ノードがいる / 意外な Seq Scan がいる** → 2 号・3 号・4 号を疑え
3. **`Buffers` の read が異常に大きい / `pg_stat_statements` の calls が大きい** → 5 号・8 号を疑え

「一昨日の夜のお前は、この 3 つのどれも見えてなかった。今は全部見える。──それが、あの 3 時間 18 分でお前が得たものだ」

僕は 8 枚の人相書きを見渡した。どの顔も、二日前なら素通りしていた顔だった。

「桐生さん。これ、チームの全員が読めたほうがよくないですか。俺だけ読めても、明日また誰かが 1 号を書きます」

桐生さんは、初めてはっきりと笑った。

「いい答えだ。なら、まとめろ。**お前の言葉で、1 枚に**。今夜の事件簿の、最終ページだ」

（最終話「捜査手帳 ─ 1 枚のチートシート」につづく）

---

## 今夜の捜査メモ ─ 人相書き 8 枚

| # | 人相書き | 症状（EXPLAIN での見え方） | 直し方 |
|---|---|---|---|
| 1 | 関数の覆面 | `Filter: (lower(col) = ...)` で Seq Scan | 式インデックス / 保存時に正規化 |
| 2 | 中間一致の亡霊 | `LIKE '%x%'` で Seq Scan | pg_trgm + GIN（前方一致なら B-tree の余地） |
| 3 | 大食いのアスタリスク | `SELECT *` で Index Only Scan 不発・width 肥大 | 必要カラムだけ SELECT |
| 4 | 索引なき整列 | ORDER BY で Sort ノード | ソート列にインデックス（Sort ごと消す） |
| 5 | 数え屋 | `count(*)` の全件 Seq Scan | count(id) + VACUUM / 概算なら reltuples |
| 6 | OR の行列 | OR 連打で BitmapOr が乱立・推定が荒れる | IN / BETWEEN にまとめる |
| 7 | 化けの皮キャスト | `Filter:` に暗黙キャスト、索引不発 | パラメータの型を揃える |
| 8 | 千本ノック（N+1） | 1 本は速いが `pg_stat_statements` の calls が異常 | アプリ側で IN / JOIN に束ねる |

**3 つの目**: ① Filter 行の関数・キャスト ② Sort と意外な Seq Scan ③ Buffers の read と calls の異常値

:::message
各パターンの実機出力と直し方の詳細（式インデックスの作成、pg_trgm、pg_stat_statements の設定）は技術書版の[第 12 章](https://zenn.dev/hatsu38/books/cddb89f9abfaca)にあります。
:::
