---
退避元: books/postgres-explain-internals/03-scan-selection.md の旧 3.5 節
退避日: 2026-05-31
退避理由:
  3 章のクライマックスを「LIMIT のクロスオーバー = STD_FUZZ_FACTOR = 1.01」に
  差し替えるため、random_page_cost 実験の節をカット。
  将来「実務で使うコスト調整」「11 章 プランナの挙動を制御する」周辺で再利用可。
---

## 3.5 random_page_cost を動かすと何が起きるか

ここが第 3 章の山場です。

1 章の details で「SSD/NVMe 時代には `random_page_cost = 1.1〜2.0` に下げると Index Scan が選ばれやすくなる」と予告しました。実際に手元で動かしてみます。動かす方向は 2 つ。下げる方向と、上げる方向です。

### 実験 1: random_page_cost を下げる

3.4 で Bitmap Heap Scan が選ばれた「`WHERE author_id BETWEEN 1 AND 100`」（5% ヒット）を素材にして、`random_page_cost` をデフォルトの `4.0` から `1.1` に下げてみます。

```sql
SHOW random_page_cost;   -- 4.0（デフォルト）
EXPLAIN SELECT * FROM articles WHERE author_id BETWEEN 1 AND 100;

SET random_page_cost = 1.1;
EXPLAIN SELECT * FROM articles WHERE author_id BETWEEN 1 AND 100;
```

出力の要点だけ並べると:

| `random_page_cost` | プラン | スタートアップ | トータル |
|---|---|---|---|
| 4.0 | Bitmap Heap Scan | 78.84 | **4,312.86** |
| 1.1 | Bitmap Heap Scan | 58.54 | **3,206.94** |

**プラン名は変わりませんでした**。「`random_page_cost` を下げると Index Scan に切り替わる」と思い込んでいたら、現実はもっと地味で、Bitmap のままコストだけが約 26% 減っています。Bitmap Heap Scan はヒープアクセスもインデックス側もランダム I/O が含まれるので、`random_page_cost` を下げると一律で安くなる、という効き方です。

Index Scan に切り替わらなかった理由を逆算してみると、もし Index Scan で 4,931 行を引いたら最低でも `random_page_cost × 4,931 = 1.1 × 4,931 = 5,424` くらいかかる見込み。これは Bitmap の `3,206.94` よりまだ高いので、Bitmap が勝ち続けます。サンプルアプリの 5% ヒットでは、`random_page_cost` を下げてもプランの切り替えは起きない、ということが見えました。

### 実験 2: random_page_cost を上げる

同じクエリで、今度は `random_page_cost` を **上げて** みます。

```sql
SET random_page_cost = 10;
EXPLAIN SELECT * FROM articles WHERE author_id BETWEEN 1 AND 100;

SET random_page_cost = 100;
EXPLAIN SELECT * FROM articles WHERE author_id BETWEEN 1 AND 100;

RESET random_page_cost;
```

出力:

```sql
 Seq Scan on articles  (cost=0.00..5451.00 rows=4931 width=269)
   Filter: ((author_id >= 1) AND (author_id <= 100))
```

`random_page_cost = 10` でも `= 100` でも、出力は **完全に同じ Seq Scan のコスト 5,451.00**。Bitmap → Seq Scan に切り替わりました。

ここでひとつ考えたいのは、なぜ `random_page_cost = 10` と `= 100` で Seq Scan のコストが同じ `5,451.00` なのか、という点です。出てきたプランは Seq Scan ですが、Seq Scan は **連続 I/O** で読む読み方なので、`random_page_cost` はそもそも使われません。だから `random_page_cost` をいくら上げても、Seq Scan のコスト自体は動かないわけです。

これが大事な気付きです。**`random_page_cost` を変えると、Bitmap や Index Scan のコストは動く。でも Seq Scan のコストは動かない**。プランナはこの相対バランスを見て選び直しているので、`random_page_cost` を上げると「ランダム I/O が必要なノードが相対的に不利になる → Seq Scan が勝つ」という形で切り替わります。

### おまけ: 5,451.00 を手計算で再現する

ここで出てきた Seq Scan のコスト `5,451.00`、1 章で見た WHERE なしの Seq Scan のコスト `4,951.00` と微妙に違います。差は **500**。これは何のコストか、手計算で詰められます。

出力の `Filter: ((author_id >= 1) AND (author_id <= 100))` に注目すると、WHERE 条件を行ごとに評価する CPU コストが乗っているはずです。

```sql
cpu_operator_cost × オペレータ数 × 行数
= 0.0025 × 2 (>= と <=) × 100,000
= 500.00
```

Seq Scan の全体コストを、1 章のコスト式に WHERE 句評価ぶんを足して書くと:

```sql
seq_page_cost × ページ数 + cpu_tuple_cost × 行数 + cpu_operator_cost × オペレータ数 × 行数
= 1.0 × 3,951 + 0.01 × 100,000 + 0.0025 × 2 × 100,000
= 3,951 + 1,000 + 500
= 5,451.00
```

実値の `5,451.00` とぴったり一致しました。1 章のコスト式に **WHERE 句評価のコスト** が乗っただけ、というのが見えます。コスト式がそのまま素直に拡張できる、ということでもあります。

### SSD/NVMe 時代のチューニングの話

実機の I/O 性能と `random_page_cost` がズレていると、プランナは「ランダム I/O を避ける」方向に偏ったプランを選びます。SSD/NVMe 上の本番 DB で Seq Scan ばかり選ばれるなら、`random_page_cost` を下げてみると、Bitmap や Index Scan のコストが下がってプランが切り替わる可能性があります。

ただ、今回の実験で見たように、選択率や元のプランによっては、`random_page_cost` を動かしてもプラン名は変わらず、コストだけが地味に動くだけ、ということもあります。「下げれば必ず Index Scan が選ばれる」みたいな単純な話ではなく、コストの相対バランスがどう変わるかを実機で確かめるのが現実的そうです。

なお、`enable_bitmapscan = off` のような **プランナのスイッチ系パラメータ** を使うと、コストとは別の軸で「このプランを選ばせない」と指示できます。これは 11 章「プランナの挙動を制御する」で改めて扱います。
