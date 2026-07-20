---
title: "第6話 実行犯 ─ Nested Loop の暴走"
---

:::message
この物語はフィクションですが、登場する SQL と EXPLAIN の出力はすべて実測値です。技術書版[「PostgreSQL の EXPLAIN と内部のしくみ」](https://zenn.dev/hatsu38/books/postgres-explain-internals)第 6 章と同じサンプル DB で再現できます。
:::

## 1

午前4時21分。

「実行犯に会う前に、現場をもう一度踏む。第 2 話で撃ったこのクエリ、覚えてるな」

```sql
EXPLAIN ANALYZE
SELECT a.title, c.body
FROM articles a
JOIN comments c ON c.article_id = a.id
WHERE a.author_id BETWEEN 1 AND 5;
```

```
 Nested Loop  (cost=7.11..11296.29 rows=2330 width=62) (actual time=0.625..29.985 rows=2469 loops=1)
   ->  Bitmap Heap Scan on articles a  (cost=6.68..754.94 rows=233 width=36) (actual ... rows=249 loops=1)
         Recheck Cond: ((author_id >= 1) AND (author_id <= 5))
   ->  Index Scan using index_comments_on_article_id on comments c  (cost=0.42..45.13 rows=11 width=58)
         (actual time=0.020..0.104 rows=10 loops=249)
         Index Cond: (article_id = a.id)
```

「あのときは loops の掛け算を覚えて終わった。今夜は**構造**を読む。Nested Loop をプログラムに直すと、こうなる」

```text
for each row a in 外側:                  # Bitmap Heap Scan on articles → 249 行
    for each row c in 内側:              # Index Scan on comments WHERE article_id = a.id
        return (a, c)
```

「二重ループ……そのままの名前なんですね。外側が 1 行進むたびに、内側のループが丸ごと 1 回呼ばれる。だから内側の `loops=249` は、**外側の行数そのもの**なんだ」

![Nested Loop の動き。loops は外側の行数、actual rows は内側の 1 回あたり平均](/images/postgres-explain-internals/ch06/01-nested-loop-timeline.png)
*捜査資料: 実行犯の犯行手口。外側 249 行 × 内側 1 回ずつの反復訪問──回数が桁で狂えばこのまま凶器になる*

「そうだ。SQL の結合方式の中で、いちばん素朴な奴だ。素朴だから、輝く場面と暴走する場面がはっきり分かれる。──まず、なぜ今回プランナはこいつに落札させたのか。入札額を検算しろ。内側 1 回のコストは？」

「`cost=0.42..45.13`。それが 249 回呼ばれる見込みだから……`45.13 × 249 ≒ 11,238`。あ、Nested Loop 全体のトータル `11,296.29` とほぼ一致します」

「それが Nested Loop の値札の付き方だ。**外側 1 回 + 内側 × 外側の行数**。今回は外側が 249 行と小さく、内側は article_id のインデックスで 1 発 0.1 ms で引ける。だから安い。『**外側が小さくて、内側をインデックスで引ける**』──この条件が揃ったとき、Nested Loop は最強の結合だ」

「じゃあ、条件が揃わなかったら……」

「それが今夜の 12 秒だ」

## 2

「思考実験をやる。もし `index_comments_on_article_id` が**存在しなかったら**、内側はどうなる」

「インデックスが無いなら……第 3 話の入札で、comments 100 万行の Seq Scan。1 回あたり数百 ms」

「それが 249 回呼ばれる」

「数百 ms × 249……**分単位**じゃないですか。たった 2,469 行の結果を出すのに」

「アプリ側で言う **N+1 問題**の、DB 内部での正体がこれだ。ループの中でクエリを 1 本ずつ投げるあの悪夢を、プランナが実行計画の中で自前でやってしまう。──もうひとつの暴走パターンが、**外側が想定より大きい**場合。内側 1 回がインデックスで 0.1 ms と安くても、外側が 100 万行なら 0.1 ms × 100 万 = 100 秒だ。単価が安くても、回数が桁で狂えば破産する」

「回数が桁で狂う……rows の推定ミス、ですね。ずっとその話に戻ってくる」

「そうだ。Nested Loop は『外側は小さいはず』という**見積もりを信じて**選ばれる結合だ。信じた見積もりが 4 桁外れたとき、こいつは事故を起こす。──ひとつ、救済措置も見せておく。PostgreSQL 14 から入った **Memoize** だ」

```sql
EXPLAIN ANALYZE
SELECT a.title, c.body
FROM comments c
JOIN articles a ON a.id = c.article_id
WHERE c.author_id BETWEEN 1 AND 5;
```

「さっきと逆向き──comments を外側にした結合だ。外側の comments には**同じ article_id が何度も出てくる**。同じキーで内側を 2 回引くのは無駄だろう？ そこで Nested Loop の内側に Memoize というキャッシュ係が挟まる」

```text
 Nested Loop
   ->  外側ノード
   ->  Memoize
         Cache Key: c.article_id
         (actual 側に Cache Hits: N  Cache Misses: M ...)
         ->  内側 Index Scan
```

「初めて見るキーなら内側を呼んで結果を覚える──Cache Miss。二度目以降はキャッシュから返す──Cache Hit。**Hits が多いほど、内側の呼び出しが実際に減ってる**。読むときは Hits と Misses の比を見ろ。──ただし Memoize は万能薬じゃない。外側に重複キーが多いとプランナが*見積もった*ときにしか選ばれない。ここでも結局、統計の見立てが土台だ」

## 3

「──さて。道具は全部渡した。実行犯の現場を、自分の言葉で再構成してみろ」

僕は本番のプランを開いた。4 度目ともなると、もう暗号には見えない。深呼吸をひとつ。

「……再構成します。まず、プランナは Nested Loop の外側になるサブクエリの結果を **rows=131** と見積もった。131 行なら、内側を comments のインデックスで 131 回引くのが最安──入札は Nested Loop が落札。ここまでは、見積もりが正しければ完璧な判断です」

「続けろ」

「でも実際に蓋を開けたら、外側から **4 桁多い行**が出てきた。内側は 131 回のつもりが**十数万 loops**。1 回は軽い Index Scan でも、掛け算で数秒級に化けた。さらにその大量の結合結果が、第 5 話の Sort にそのまま流れ込んで──work_mem を溢れて external merge、ディスク書き。**Nested Loop の暴走と Sort のディスク行きの合わせ技**で、12 秒」

「実行犯の特定、完了だ」

桐生さんの声には、しかしまだ続きがあった。

「だが湊、実行犯は*駒*だ。考えてみろ。もし推定が正しく『十数万行返る』と出ていたら、プランナは Nested Loop を選んだか？」

「……選ばない、ですよね。内側を十数万回引くコストが正しく積み上がるから、入札で負ける。じゃあ、正しい推定なら何が落札してたんですか？ 外側も内側も大きい JOIN を得意にする奴なんて、いるんですか」

「いる。**Hash Join** と **Merge Join**──今夜まだ顔を見せていない、結合の残り 2 兄弟だ。特に Hash Join は『両方大きい』が主戦場でな。本来なら今夜の事件、あいつが落札して**コンマ数秒で終わってたはず**なんだ」

「本来の落札者……」

「次はそいつらの仕事ぶりを見る。**選ばれなかった入札者**を知らないと、『どのプランに戻すべきか』が語れないからな」

午前4時36分。実行犯は挙がった。残るは、実行犯に仕事をさせた**黒幕**──狂った見積書の出どころだ。

（第7話「選ばれなかった入札者 ─ Hash Join と Merge Join」につづく）

---

## 今夜の捜査メモ

- **Nested Loop = 二重 for ループ**。外側 1 行ごとに内側ノードが丸ごと 1 回呼ばれる。内側の `loops` = 外側の行数
- 値札は「外側 1 回 + **内側 × 外側の行数**」。実測でも `45.13 × 249 ≒ 11,238 ≈ トータル 11,296` と検算できる
- 輝く条件は「**外側が小さい × 内側をインデックスで引ける**」。この 2 条件が Nested Loop の存在理由
- 暴走パターン: ①外側の rows 推定が過小（回数が桁で狂う）②内側にインデックスが無い（Seq Scan × loops = **N+1 問題の DB 内部版**）
- **Memoize**（PG14+）は内側の結果をキーごとにキャッシュする救済措置。`Cache Hits / Misses` の比で効きを読む。ただし選ばれるかどうかは、これも統計の見立て次第
- 兆候を見る 3 つの目: **外側の actual rows** / **内側の actual time(B) × loops が全体に占める割合** / **rows と actual rows の乖離**
- 「rows=131 のつもりが 4 桁多かった」とき、Nested Loop の選択自体は*見積もり上は*正しい。**責めるべきはプラン選択ではなく、狂った推定の出どころ**

:::message
Nested Loop のタイムライン図、Memoize の判定フロー、実機での Memoize 観察は技術書版の[第 6 章](https://zenn.dev/hatsu38/books/postgres-explain-internals)にあります。
:::
