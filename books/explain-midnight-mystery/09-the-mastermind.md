---
title: "第9話 黒幕の名 ─ プランナと統計情報"
---

:::message
この物語はフィクションですが、登場する SQL と EXPLAIN の出力はすべて実測値です（数値の一部は環境により変動するため `...` 表記）。技術書版[「PostgreSQL の EXPLAIN と内部のしくみ」](https://zenn.dev/hatsu38/books/postgres-explain-internals)第 9 章と同じサンプル DB で再現できます。
:::

## 1

午前5時13分。

「プランナは何を見て `rows=131` と言ったのか。答えから言う。**プランナはテーブルを見ていない**。テーブルの*要約*を見ている。置き場所は 3 つだ」

| 場所 | 中身 |
|---|---|
| `pg_class` | テーブル全体の行数（reltuples）とページ数（relpages） |
| `pg_statistic` | カラムごとの詳細統計（内部用の生データ） |
| `pg_stats` | 上を人間向けに整形した**ビュー** |

「pg_class は第 1 話で覗いたな。コスト手計算に使った reltuples と relpages だ。今夜の主役は 3 つ目、**pg_stats**。カラム 1 本ごとの、値の分布の要約が入ってる。覗け」

```sql
SELECT * FROM pg_stats
WHERE tablename = 'articles' AND attname = 'author_id';
```

見慣れない列が並んだ。n_distinct、most_common_vals、histogram_bounds──。

「大事なのは 2 つ。**MCV** と**ヒストグラム**だ。`most_common_vals` は『よく出る値トップ N』のリスト。隣の `most_common_freqs` がその出現率だ。たとえばこんな中身だとする」

```text
most_common_vals  = {1, 2, 3, 4, 5}
most_common_freqs = {0.0008, 0.0006, 0.0006, 0.0005, 0.0005}
```

「プランナが `WHERE author_id = 1` を見たら、まず MCV に 1 があるか探す。あれば頻度を引いて掛け算するだけだ」

```text
推定行数 = 総行数 × 頻度 = 100,000 × 0.0008 = 80 行
```

「第 3 話で `WHERE author_id = 1` が `rows=49` と出てたのは、この計算だったんですね。じゃあ histogram_bounds のほうは」

「MCV に入らなかった*その他大勢*の分布だ。値の範囲を等頻度で区切った境界値のリストで、`BETWEEN 1 AND 100` みたいな範囲条件のとき、『この範囲はヒストグラムの何区間ぶんか』で選択率を出す。第 3 話の `rows=4699`──全体の約 5%──はこっちの計算だ」

![pg_stats の MCV とヒストグラムから選択率を推定するしくみ](/images/postgres-explain-internals/ch09/01-histogram-mcv-selectivity.png)
*捜査資料: 黒幕の手口。プランナが見ているのはこの「要約」だけ──等値条件は MCV、範囲条件はヒストグラムで見積もる*

「……推定って、もっと得体の知れないものかと思ってました。ただの度数分布表と掛け算なんだ」

「そうだ。そして**ただの表だからこそ、現実とズレる**。──ここからが本題だ。犯行を、サンドボックスで再現する」

## 2

「トランザクションで包むから安心して壊せ。手順は 5 つだ」

```sql
BEGIN;

-- ① 現在のプランを記録
EXPLAIN SELECT * FROM articles WHERE author_id = 1;
--> Bitmap Heap Scan ... rows=49

-- ② author_id = 1 の記事を 5 万件、大量挿入する
INSERT INTO articles (author_id, title, body, created_at, updated_at)
SELECT 1, 'spam', 'spam body', NOW(), NOW()
FROM generate_series(1, 50000);

-- ③ 挿入直後、ANALYZE する前のプラン
EXPLAIN SELECT * FROM articles WHERE author_id = 1;
--> Bitmap Heap Scan ... rows=49  ← まだ 49 のまま！

-- ④ 統計を取り直す
ANALYZE articles;

-- ⑤ もう一度
EXPLAIN SELECT * FROM articles WHERE author_id = 1;
--> Seq Scan ... rows=50049 付近  ← 現実に追いついた

ROLLBACK;
```

③ の出力を見た瞬間、僕は声を上げていた。

「rows=49 のまま……！ 実際にはもう 5 万行あるのに、プランナはまだ 49 行だと言い張ってる」

「当然だ。**pg_stats の要約は、書き込みに連動して更新されない**。②の INSERT は現実を変えたが、要約は昨日のままだ。プランナは古い地図で入札を裁く。49 行のつもりで Bitmap Heap Scan を選び──実際は 5 万行を、5 万件ぶんのインデックス引きとヒープ訪問でさばく羽目になる」

「④ の ANALYZE で、やっと現実に追いつく。しかもプランごと Seq Scan に変わった……。これ、**今夜の本番とまったく同じ形**じゃないですか。推定 131、実測 4 桁上。プランナは昨日の地図で Nested Loop に落札させた」

「再現完了だ。あとは本番で*物証*を取る。統計がいつ取られたか、記録が残ってる」

```sql
SELECT relname, last_analyze, last_autoanalyze, n_live_tup, n_mod_since_analyze
FROM pg_stat_user_tables
WHERE relname IN ('articles', 'comments');
```

レプリカに投げた。出力の日時を見て、息が止まった。

「……articles の `last_autoanalyze`、**昨日の 14 時 07 分**です。18 時のバッチより**前**。バッチが全行更新した*あと*、統計は一度も取り直されてない。`n_mod_since_analyze`──統計を取ってからの変更行数が、**ほぼ全行ぶん**積まれてます」

「黒幕、確保だ」

桐生さんは静かに言った。

「事件の全容はこうだ。昨日 18 時、再集計バッチが articles をほぼ全行 UPDATE した。**現実の分布は激変したが、統計は 14 時のまま**。プランナは古い要約から `rows=131` と見積もり、その数字なら最適な Nested Loop に落札させた。現実には 4 桁多い行が流れ、内側の Index Scan が十数万回転し、膨れ上がった結合結果が Sort の work_mem を溢れさせてディスクへ──**12 秒**。プランナは一度も嘘をついていない。**古い真実を読まされ続けただけ**だ」

## 3

「応急処置に入る。湊、本番プライマリで打て」

「ほ、本番に、何をですか」

「`ANALYZE articles;` だ。恐れることはない。ANALYZE は全行を読まない──**3 万行程度をサンプリングして要約を作り直すだけ**だ。テーブルはロックで固まらないし、10 万行なら 1 秒かからん。EXPLAIN の次に安全な部類のコマンドだ」

指が震えたのは、深夜だからではなかったと思う。本番プライマリに繋ぎ、打った。

```sql
ANALYZE articles;
ANALYZE
```

1 秒足らず。あっけなかった。すぐにレプリカで例のクエリの EXPLAIN を取り直す。

──プランが、変わっていた。Nested Loop は消え、真ん中には **Hash Join**。Batches: 1。Sort は top-N heapsort。第 7 話で「本来の落札者」と呼んだ、あのプランだった。

ダッシュボードに切り替える。12 秒で張り付いていたレイテンシのグラフが、崖を**逆向きに**描いて落ちていく。0.4 秒。0.3 秒。エラー率、ゼロ。

「……落ちました。直った。直りました、桐生さん」

「よくやった」

窓の外はもう、群青から薄い橙に変わっていた。午前5時32分。アラートから 3 時間 18 分。

僕がへたり込みかけたところに、桐生さんの声が続いた。まだ、事件簿を閉じる声ではなかった。

「──だが湊、これは*応急処置*だ。疑問が 2 つ残ってる。ひとつ。10 万行のテーブルなら、1 万行も変われば **autoanalyze が自動で走るはず**なんだ。`autovacuum_analyze_scale_factor = 0.1`──10% + 50 行が発火条件。全行更新なら余裕で発火する。**なぜ走らなかった？**」

「たしかに……昨日 18 時から今まで、11 時間もあったのに」

「ふたつ。バッチが全行 UPDATE したということは、第 4 話でやったな──**dead tuple が 10 万行ぶん、まだテーブルに積まれてる**。visibility map も倒れたままだ。Heap Fetches の異常も、テーブルの膨張も、放置すれば次の事件の火種になる。──死体の山の後始末と、来なかった清掃人の話。仕上げに行くぞ」

（第10話「死体の山 ─ VACUUM と autovacuum」につづく）

---

## 今夜の捜査メモ

- プランナはテーブルではなく**要約**を見る: `pg_class`（reltuples / relpages）と `pg_stats`（カラムごとの分布）
- `pg_stats` の主役は **MCV**（最頻値とその頻度: 等値条件用）と**ヒストグラム**（その他の値の等頻度区切り: 範囲条件用）。推定行数は `総行数 × 頻度` のただの掛け算
- **統計は書き込みに連動しない**。大量 INSERT / UPDATE の直後、ANALYZE が走るまでプランナは「昨日の地図」で入札を裁く──これが rows 乖離の最多原因
- 再現手順（安全）: `BEGIN; → EXPLAIN → 大量 INSERT → EXPLAIN（まだ古い）→ ANALYZE → EXPLAIN（追いつく）→ ROLLBACK`
- 物証は **`pg_stat_user_tables`**: `last_analyze` / `last_autoanalyze`（最終の統計取得日時）と `n_mod_since_analyze`（それ以降の変更行数）
- `ANALYZE` は**約 3 万行のサンプリング**で高速・低負荷。大量データ変更を伴うバッチやリリースの直後に手動で打つ価値がある
- autoanalyze の発火条件: `変更行数 > テーブル行数 × 0.1 + 50`（`autovacuum_analyze_scale_factor` / `autovacuum_analyze_threshold`）
- 相関する 2 カラムの AND（例: `country='JP' AND lang='ja'`）はプランナが独立と仮定して過小推定する → **拡張統計 `CREATE STATISTICS`** で組の分布を持たせる

:::message
MCV / ヒストグラムによる選択率計算の図解、拡張統計の実験は技術書版の[第 9 章](https://zenn.dev/hatsu38/books/postgres-explain-internals)にあります。
:::
