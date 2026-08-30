---
title: "コストが安いプランが選ばれるとは限らない。PostgreSQL プランナの 1% ルールを実測する"
emoji: "⚖️"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["postgresql", "database", "sql", "explain"]
published: false
---

こんにちは、hatsu です。

EXPLAIN の解説では「プランナは推定コストが最小のプランを選ぶ」と説明されます。
私もずっとそう理解していました。
ところが LIMIT の値を 1 ずつ変えながら EXPLAIN を眺めていたとき、コスト計算上は負けているはずのプランが選ばれ続ける区間に出会いました。
計算を間違えたのかと思ったのですが、コストの値そのものは式と小数第二位まで一致します。
プランナは、コスト最小のプランを選んでいませんでした。

この記事では、その現象を実測で再現し、原因を PostgreSQL のソースコードまで追いかけます。

## TL;DR

- LIMIT 付きのクエリでは、Limit ノードが下のプランのコストを「先頭 N 行ぶん」に按分する。そのため LIMIT の値によって Index Scan と Bitmap Heap Scan の損得が入れ替わる
- 実測すると、2 つのプランのコストの交点は LIMIT ≈ 15。ところが実際にプランが切り替わるのは LIMIT 18 だった
- ズレの正体はプランナの比較ルール。コスト差が 1% 以内のプランは「同等」とみなされ、startup コストの安い方が生き残る。ソースコードの `STD_FUZZ_FACTOR = 1.01` がこの閾値
- 「コスト最小のプランを選ぶ」は、正確には「1% を超えてはっきり安いプランを選ぶ」だった

## 検証環境

- PostgreSQL 17.10（Docker、設定はデフォルト）
- `articles` テーブル: 100,000 行、`author_id` に btree インデックス
- 対象クエリ: `WHERE author_id = 1`（プランナの推定 80 行、実際は 65 行）

同じ構成（行数とインデックス）を用意すれば、切り替えが起きる LIMIT 値は多少ずれても、この記事と同じ現象を観察できます。

<!-- TODO: sandbox リポジトリ (zenn-explain-analyze-sample) を public に push したら、ここに再現用リンクと seed 決定化の説明を追加する -->

## LIMIT を付けただけでプランが変わる

まず LIMIT なしで EXPLAIN を取ります。

```sql
EXPLAIN SELECT * FROM articles WHERE author_id = 1;
```

```
 Bitmap Heap Scan on articles  (cost=4.91..305.64 rows=80 width=853)
   Recheck Cond: (author_id = 1)
   ->  Bitmap Index Scan on index_articles_on_author_id  (cost=0.00..4.89 rows=80 width=0)
         Index Cond: (author_id = 1)
```

選ばれたのは Bitmap Heap Scan です。
インデックスから該当行の位置を集めてビットマップを作り、ヒープ（テーブル本体）をページ順にまとめて読む方式で、トータルコストは `305.64` でした。

同じクエリに `LIMIT 5` を付けます。

```sql
EXPLAIN SELECT * FROM articles WHERE author_id = 1 LIMIT 5;
```

```
 Limit  (cost=0.29..20.63 rows=5 width=853)
   ->  Index Scan using index_articles_on_author_id on articles  (cost=0.29..325.68 rows=80 width=853)
         Index Cond: (author_id = 1)
```

プランが Index Scan に切り替わりました。
Index Scan はインデックスを 1 件引くたびにヒープへ飛ぶ方式なので、80 行全部を取るならランダムアクセスがかさんで Bitmap より高くつきます（トータル `325.68` > `305.64`）。
そのかわり、**最初の 5 行が取れた時点で途中でやめられます**。
Bitmap Heap Scan は先にビットマップを作り切る前処理が必要なので、LIMIT があっても前処理のぶんは省けません。
プランナはこの差を見て、LIMIT が小さいときは Index Scan を選んでいます。

## Limit ノードはコストを按分している

Limit ノードのコスト `20.63` は、下の Index Scan のコストから手計算で出せます。
「全体の推定 80 行のうち 5 行だけ取るなら、コストも 5/80 だけかかる」という按分です。

```
Limit の total = 0.29 + (325.68 - 0.29) × 5/80
              = 0.29 + 20.34
              = 20.63
```

startup（最初の 1 行を返すまでのコスト）はそのまま残し、残りを行数比で縮める、という素直な式です。
分母の 80 が実際の行数（65）ではなく推定 rows であることは、あとで効いてくるので覚えておいてください。

## 切り替わる境界を探す

LIMIT が小さければ Index Scan、LIMIT なしなら Bitmap Heap Scan。
では、どこかに切り替わる境界があるはずです。
LIMIT の値を振って、選ばれたプランと Limit ノードのトータルコストを一覧にします。

| LIMIT | 選ばれたプラン | Limit の total cost |
| ---: | --- | ---: |
| 1 | Index Scan | 4.36 |
| 5 | Index Scan | 20.63 |
| 14 | Index Scan | 57.24 |
| 15 | Index Scan | 61.30 |
| 16 | Index Scan | 65.37 |
| 17 | Index Scan | 69.44 |
| **18** | **Bitmap Heap Scan** | **72.58** |
| 19 | Bitmap Heap Scan | 76.34 |
| 80 | Bitmap Heap Scan | 305.64 |

切り替えは LIMIT 17 と 18 のあいだで起きました。

## コストの交点は LIMIT 15 のはず

境界を式からも出してみます。
LIMIT L のときの両プランの按分コストは次のとおりです。

```
Index Scan:        0.29 + (325.68 - 0.29) × L/80
Bitmap Heap Scan:  4.91 + (305.64 - 4.91) × L/80
```

両者が等しくなる L を解くと、L ≈ 15.0 になります。
式の上では、LIMIT 16 からは Bitmap Heap Scan の方が安いはずです。

式だけだと不安なので、負けた側のプランのコストも実測しました。
`enable_bitmapscan = off` で Index Scan を、`enable_indexscan = off` で Bitmap Heap Scan を強制すると、プランナが比較していた両方の値がそのまま見えます。

| LIMIT | Index Scan | Bitmap Heap Scan | 差の割合 |
| ---: | ---: | ---: | ---: |
| 15 | 61.30 | 61.30 | 0.00% |
| 16 | 65.37 | 65.06 | 0.48% |
| 17 | 69.44 | 68.82 | 0.90% |
| 18 | 73.50 | 72.58 | 1.27% |

交点は LIMIT 15 でした（EXPLAIN の表示上は両者 `61.30` で一致します。丸めを外した真値の交点は L ≈ 15.0 です）。
そして LIMIT 16 と 17 では、たしかに Bitmap Heap Scan の方が安いのに、選ばれているのは Index Scan です。
コスト計算は合っている。
なのにコスト最小のプランが選ばれていない。
ここがこの記事の出発点になった現象です。

## プランナは 1% 未満の差を「差」と見なさない

答えは PostgreSQL のソースコード、プラン候補の比較をしている `src/backend/optimizer/util/pathnode.c` にあります。

https://github.com/postgres/postgres/blob/REL_17_STABLE/src/backend/optimizer/util/pathnode.c

```c
/*
 * STD_FUZZ_FACTOR is the normal fuzz factor for compare_path_costs_fuzzily.
 * XXX is it worth making this user-controllable?  It provides a tradeoff
 * between planner runtime and the accuracy of path cost comparisons.
 */
#define STD_FUZZ_FACTOR 1.01
```

プラン候補同士の優劣は `compare_path_costs_fuzzily()` という関数が判定していて、名前のとおり「fuzzily（あいまいに）」比較します。
関数コメントにルールが書いてあります。

> The fuzz_factor argument must be 1.0 plus delta, where delta is the fraction of the smaller cost that is considered to be a significant difference.  For example, fuzz_factor = 1.01 makes the fuzziness limit be 1% of the smaller cost.

つまり `fuzz_factor = 1.01` のとき、**コスト差が安い方の 1% 以内なら「意味のある差ではない」とみなされます**。
判定の実装はこうなっています。

```c
	if (path1->total_cost > path2->total_cost * fuzz_factor)
	{
		/* path1 fuzzily worse on total cost */
		...
	}
	if (path2->total_cost > path1->total_cost * fuzz_factor)
	{
		/* path2 fuzzily worse on total cost */
		...
	}
	/* fuzzily the same on total cost ... */
	if (path1->startup_cost > path2->startup_cost * fuzz_factor)
	{
		/* ... but path1 fuzzily worse on startup, so path2 wins */
```

トータルコストの差が 1% 以内なら「同等」に進み、今度は startup コストで決着をつけます。
今回の 2 つのプランの startup は、Index Scan が `0.29`、Bitmap Heap Scan が `4.91`。
トータルが同等扱いのあいだは、startup の安い Index Scan が勝ち続けるわけです。

このルールを先ほどの実測表に当てはめると、切り替え点がそのまま説明できます。

| LIMIT | 差の割合 | 判定 |
| ---: | ---: | --- |
| 16 | 0.48% | 1% 以内なので同等。startup の安い Index Scan が残る |
| 17 | 0.90% | 同上（ぎりぎり 1% 以内） |
| 18 | 1.27% | 1% を超えた。Bitmap Heap Scan がはっきり安い |

コストの交点（15）と実際の切り替え点（18）のあいだのズレは、この 1% ルールで埋まりました[^add-path]。

[^add-path]: 厳密には、この比較はプラン候補を残すか捨てるかを決める `add_path()` の中で行われます。LIMIT 18 のように「トータルは 1% 超で負けるが startup では勝つ」候補は両方生き残り、最後にトータルの安い方が採用されます。興味があれば `pathnode.c` の `add_path()` と `compare_path_costs_fuzzily()` を読んでみてください。

ちなみにソースコメントには「XXX これをユーザーが調整できるようにする価値はあるか？」という開発者のぼやきも残っています。
プランナの実行時間とコスト比較の正確さのトレードオフだ、と。
1% ルールは手抜きではなく、この 2 つを天秤にかけた設計です。
誤差程度のコスト差でプランが揺れない、という安定性への効果は、コメントには書かれていませんが、この設計から自然についてくる性質です。

## 実務での含意

この現象から持ち帰れることを 3 つ挙げます。

- **LIMIT の値でプランは変わる**：ページネーションや「先頭 N 件取得」のクエリで「LIMIT 10 は速いのに 20 にすると遅い」といった段差に出会ったら、境界を疑って LIMIT の値を振りながら EXPLAIN を取ると、切り替え点が特定できます
- **按分の分母は推定 rows**：今回の分母 80 は実際の行数 65 ではなく統計情報からの推定値でした。統計が古くなって推定がずれると、切り替え境界ごと動きます。プランの段差が急に現れたら、ANALYZE の実行時期も確認する価値があります
- **EXPLAIN のコストを比べるときは 1% を思い出す**：2 つの書き方のコストを比較して「こちらの方が 0.5% 安いのに選ばれない」と悩んだら、それはバグではなくプランナの仕様です。プランナにとって 1% 未満は誤差です

## まとめ

- Limit ノードはソースプランのコストを `startup + (total - startup) × L/推定rows` で按分する
- 按分コストの交点は LIMIT 15 だったが、プランの切り替えは LIMIT 18 で起きた
- プランナはコスト差 1% 以内を「同等」とみなし、startup コストでタイブレークする（`STD_FUZZ_FACTOR = 1.01`）
- 「プランナはコスト最小のプランを選ぶ」の正確な形は「1% を超えてはっきり安いプランを選ぶ」

EXPLAIN の出力に出てくる数字は、ここまで追いかけて説明がつくようにできています。

<!-- TODO: 執筆中の書籍『PostgreSQL 実行計画の教科書 ─ EXPLAIN でのぞく内部構造』の公開後、ここに告知リンクを追加する -->
