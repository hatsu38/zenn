---
title: "第7話 選ばれなかった入札者 ─ Hash Join と Merge Join"
---

:::message
この物語はフィクションですが、登場する SQL と EXPLAIN の出力はすべて実測値です（数値の一部は環境により変動するため `...` 表記）。技術書版[「PostgreSQL の EXPLAIN と内部のしくみ」](https://zenn.dev/hatsu38/books/postgres-explain-internals)第 7 章と同じサンプル DB で再現できます。
:::

## 1

午前4時38分。

「Nested Loop が苦しい場面を、もう一度言ってみろ」

「外側が大きい。内側にインデックスが無い。……両方だと最悪」

「そうだ。ではその最悪の領域を得意にする奴を呼ぶ。WHERE なしの全件 JOIN──articles 10 万行と authors 2,000 行を、全部結合しろ」

```sql
EXPLAIN ANALYZE
SELECT a.title, au.name
FROM articles a
JOIN authors au ON a.author_id = au.id;
```

```
 Hash Join  (cost=... rows=100000 width=...) (actual time=... rows=100000 loops=1)
   Hash Cond: (a.author_id = au.id)
   ->  Seq Scan on articles a  (cost=0.00..12181.00 rows=100000 width=...) (actual ... loops=1)
   ->  Hash  (cost=... rows=2000 width=...) (actual ... rows=2000 loops=1)
         Buckets: ...  Batches: 1  Memory Usage: ...kB
         ->  Seq Scan on authors au  (cost=... rows=2000 width=...) (actual ... rows=2000 loops=1)
```

「**Hash Join**……と、その下に `Hash` っていうノードもいますね」

「動きは 2 幕構成だ。第 1 幕、**Build**──小さいほう（authors 2,000 行）を全部読んで、結合キーで引ける**ハッシュ表**をメモリに作る。author_id を言えば即座に著者が出てくる名簿だ。第 2 幕、**Probe**──大きいほう（articles 10 万行）を 1 行ずつ流しながら、名簿を引いて結合する」

![Hash Join の Build → Probe の 2 段階。小さい側でハッシュテーブルを作り、大きい側を 1 行ずつ照合](/images/postgres-explain-internals/ch07/01-hash-join-build-probe.png)
*捜査資料: 本来の落札者の仕事ぶり。第 1 幕で名簿を作り、第 2 幕で照合するだけ──両テーブルとも 1 回しか読まない*

「Nested Loop と決定的に違うのは……内側を 249 回とか呼ばない、ってところですか」

「そこだ。**両方のテーブルを、それぞれ 1 回しか読まない**。10 万行 + 2,000 行 = 10 万 2 千行を読んで終わり。Nested Loop なら外側 10 万行 × 内側 10 万回の呼び出しになる領域を、Hash Join は 2 パスで片づける。『両方大きい』が主戦場だと言った理由がこれだ」

「じゃあ全部 Hash Join でいいじゃないですか」

「甘い。名簿は**メモリに置く**んだ。何のメモリ上限だと思う」

「……あ。work_mem」

「第 5 話の顔がここでも出る。出力の `Batches: 1` を見ろ。**1 ならハッシュ表が work_mem に収まってる**──健全だ。収まらないと PostgreSQL はハッシュ表を N 分割して、1 束ずつメモリに載せてはディスクに書き出しながら何周も回す。`Batches: 2, 4, 8...` と増えるほど、一時ファイルと再スキャンで遅くなる。試したければ work_mem を絞ってみろ」

```sql
SET work_mem = '64kB';   -- 極端に絞る
EXPLAIN ANALYZE SELECT a.title, au.name FROM articles a JOIN authors au ON a.author_id = au.id;
RESET work_mem;
```

「Batches が跳ね上がるはずだ。Hash Join の強さは『名簿がメモリに収まる』という前提の上に建ってる」

## 2

「3 人目も紹介だけしておく。**Merge Join**。こいつは『**両方の入力がソート済み**』を前提に、2 本のソート済みの列を上から並走して読み、一致をすくい上げる」

「ソート済み前提……第 5 話の、B-tree はソート済みっていう話と繋がるんですか」

「繋がる。両方の結合キーに B-tree インデックスがあれば、ソートはタダ同然で手に入る。あるいは片方を Sort してでも、ハッシュ表がメモリに収まらないほど巨大な JOIN なら Merge が勝つことがある。ORDER BY 付きのクエリなら、Merge Join の出力が**最初からソート済み**なのも強い──Sort ノードを 1 個消せるからな」

僕はノートに 3 人の人相書きをまとめた。

| 結合方式 | 強い場面 | 弱い場面 |
|---|---|---|
| Nested Loop | 外側が小さい × 内側にインデックス | 外側が大きい / 内側にインデックス無し |
| Hash Join | 両方大きくても 2 パスで終わる | ハッシュ表が work_mem を大きく超える |
| Merge Join | 両方がキーでソート済み（インデックスあり） | 事前ソートのコストが乗る場合 |

「プランナは毎回、**3 人全員に入札させて最安を選んでる**。第 3 話のスキャン入札と同じ構造が、JOIN の階でも回ってるだけだ」

## 3

「ここで面白いスイッチを見せる。入札者を**指名停止**にできる」

```sql
SET enable_hashjoin = off;
EXPLAIN ANALYZE SELECT a.title, au.name FROM articles a JOIN authors au ON a.author_id = au.id;

SET enable_mergejoin = off;
EXPLAIN ANALYZE SELECT a.title, au.name FROM articles a JOIN authors au ON a.author_id = au.id;

RESET enable_hashjoin;
RESET enable_mergejoin;
```

「`enable_hashjoin = off` は『Hash Join のコストに巨大なペナルティを乗せて、入札で絶対勝てなくする』というスイッチだ。禁止すると次点の入札者が繰り上がる。プラン名とコストがどう変わるか、見比べてみろ」

「……これ、逆もできますよね。今夜の本番クエリで、**Nested Loop を指名停止**にしたら」

通話の向こうで、桐生さんが笑った。今度は、気のせいじゃなかった。

「気づいたか。やってみろ。レプリカでな」

僕はレプリカに繋ぎ直し、セッションで `SET enable_nestloop = off;` を打ってから、12 秒のクエリに EXPLAIN ANALYZE を付けて流した。

──返ってきた。**一瞬で**。

プランの真ん中には Hash Join。Batches: 1。Sort は top-N heapsort に変わり、Execution Time は……12 秒じゃない。**1 秒を切っていた**。

「か、桐生さん。0.4 秒です。プランを変えただけで、12 秒が 0.4 秒に……！ じゃあ本番にこの SET を入れれば」

「**待て**」

二度目の、低い声だった。

「enable_nestloop = off は指名停止だぞ。そのセッションの**全クエリ**から Nested Loop を奪う。第 6 話でやったろう──外側が小さいとき、Nested Loop は*最強*なんだ。お前のサービスの他の 999 本のクエリには、Nested Loop が正解のものが山ほどある。事件を 1 件解決するために、市内の全交通を止めるのか」

「……そう、ですね。すみません、また推測で触るところでした」

「だが収穫は大きい。**正しいプランが存在して、それなら 0.4 秒で終わる**──これが証明された。DB は壊れてない。ハードも足りてる。**プランナの選択だけが狂ってる**。つまり犯人は、選択の材料──見積もりを狂わせた何かだ」

「黒幕の統計情報、ですね。次はそこですか」

「その前に、ひとつ潰しておく。お前、さっきから引っかかってないか。**同じクエリなのに、走らせるたびに時間が違う**ことに。1 回目 12 秒、2 回目 8 秒──この揺らぎを説明できないうちは、対策の効果測定もできない。時間の行き先を、1 ページ単位で数える道具がある。**BUFFERS**だ。血痕を数えに行くぞ」

午前4時54分。窓の外、空の底がわずかに白み始めていた。

（第8話「血痕を数える ─ BUFFERS とキャッシュ」につづく）

---

## 今夜の捜査メモ

- **Hash Join は 2 幕構成**: Build（小さい側を 1 回読んでメモリにハッシュ表＝名簿を作る）→ Probe（大きい側を 1 行ずつ流して名簿を引く）。**両テーブルとも 1 回しか読まない**
- `Batches: 1` はハッシュ表が **work_mem に収まっている**健全な状態。2 以上は分割＝一時ファイル＋再スキャンで劣化
- **Merge Join** は両入力がソート済み前提の並走マージ。両キーに B-tree があると強く、出力もソート済みなので ORDER BY と相性がいい
- 使い分け: 外側が小さい×内側にインデックス→ **Nested Loop** / 両方大きい→ **Hash Join** / 両方ソート済み→ **Merge Join**。プランナは 3 方式全部にコストを見積もらせて最安を選ぶ
- `SET enable_hashjoin = off` 等のスイッチは「そのプランに巨大ペナルティを乗せて入札で勝てなくする」仕組み。**検証には最強、本番常用は劇薬**（セッションの全クエリに効くため）
- 誤ったプランで 12 秒のクエリが、正しいプラン（Hash Join）なら 0.4 秒──**「正しいプランの存在証明」**は、犯人がプランナの入力（統計）側にいることの証拠になる

:::message
Build/Probe の図解、work_mem を絞って Batches が増える実験、enable スイッチ 3 連の比較は技術書版の[第 7 章](https://zenn.dev/hatsu38/books/postgres-explain-internals)にあります。
:::
