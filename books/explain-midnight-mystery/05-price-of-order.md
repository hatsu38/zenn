---
title: "第5話 並べ替えの代償 ─ Sort と work_mem"
---

:::message
この物語はフィクションですが、登場する SQL と EXPLAIN の出力はすべて実測値です（数値の一部は環境により変動するため `...` 表記）。技術書版[「PostgreSQL の EXPLAIN と内部のしくみ」](https://zenn.dev/hatsu38/books/postgres-explain-internals)第 5 章と同じサンプル DB で再現できます。
:::

## 1

午前4時5分。

「本番プランの真ん中に鎮座してる Sort を読む前に、単体で観察する。articles を title で並べろ。title にインデックスは無い」

```sql
EXPLAIN ANALYZE SELECT * FROM articles ORDER BY title;
```

```
 Sort  (cost=... rows=100000 width=269) (actual time=... rows=100000 loops=1)
   Sort Key: title
   Sort Method: external merge  Disk: ...kB
   ->  Seq Scan on articles  (cost=0.00..12181.00 rows=100000 width=269) (actual time=...)
```

「2 段になってますね。下の Seq Scan が全行読んで、上の Sort が並べ替える。行は下から上に流れる……」

「そうだ。そして Sort の actual time の A を見ろ。第 2 話で予告した『A ≒ B 型』の実物だ。Sort は**全行揃うまで 1 行も返せない**。最後の 1 行が届くまで、最小値すら確定しないからな。スタートアップが重い──これが並べ替えの第一の代償だ」

「第一の、ってことは第二もあるんですか」

「`Sort Method` の行を見ろ。**external merge、Disk**。並べ替えがメモリに収まらず、**ディスクに一時ファイルを書きながら**マージしてる。Sort に許されたメモリの上限が `work_mem` だ」

```sql
SHOW work_mem;   -- 4MB
```

「デフォルト 4MB。今回の Sort は 10 万行、width 269──ざっと 26MB ぶんある。4MB の机で 26MB の書類は並べられない。だから床（ディスク）に広げた。メモリ内ソートより当然遅い。これが第二の代償だ」

![work_mem 内に収まる quicksort と、溢れて一時ファイルに書く external merge の対比](/images/postgres-explain-internals/ch05/01-sort-memory-vs-disk.png)
*捜査資料: 机（work_mem）に収まれば quicksort、溢れれば床（ディスクの一時ファイル）で external merge*

「コスト式はどうなってるんですか。Seq Scan みたいに手計算できます？」

「骨格だけ覚えろ。ソースの `cost_sort` を読むと、比較回数の項が `2 × cpu_operator_cost × N × log2(N)`。**N log N** だ。行数が 10 倍になれば、コストは 10 倍じゃなく約 12 倍になる。**Sort は、食わせる行数に対して線形より悪く膨らむ**──ここは今夜の事件の急所だから、覚えておけ」

## 2

「次。同じクエリに LIMIT 20 を付けろ。本番のページネーションと同じ形だ」

```sql
EXPLAIN ANALYZE SELECT * FROM articles ORDER BY title LIMIT 20;
```

```
 Limit  (cost=... rows=20 width=269) (actual time=... rows=20 loops=1)
   ->  Sort  (cost=... rows=100000 width=269) (actual time=... rows=20 loops=1)
         Sort Key: title
         Sort Method: top-N heapsort  Memory: ...kB
         ->  Seq Scan on articles  (cost=0.00..12181.00 rows=100000 width=269) (actual time=...)
```

「Sort Method が変わった。**top-N heapsort**……Disk が消えて、Memory が数十 kB になってる。さっき 26MB あったのに」

「PostgreSQL が『LIMIT 20 なら、全部並べる必要はない』と気づいて、アルゴリズムごと切り替えた。動きはこうだ──**上位 20 件だけを入れる小さな器**を持って、全行を流し読みする。新しい行が来るたび、器の中の最下位と比べる。勝てば入れ替え、負ければ捨てる。読み終わったとき、器に残った 20 件が答えだ」

「トーナメントの上位だけ控えておく方式……メモリには常に 20 件しかいないから、数十 kB で済むのか」

「そうだ。全行は読む。だが**全行は並べない**。──もうひとつ、work_mem を上げる手も見せておく」

```sql
SET work_mem = '64MB';
EXPLAIN ANALYZE SELECT * FROM articles ORDER BY title;  -- LIMIT なし
RESET work_mem;
```

「LIMIT なしでも、64MB あれば `Sort Method: quicksort` に変わって Disk が消える。ただし警告だ。**work_mem はクエリ全体の上限じゃない。Sort や Hash のノード 1 個ごとの上限**だ。複雑なクエリなら 1 本で何個も並ぶし、同時接続が 100 本あれば 100 倍化ける。深夜のテンションで本番の work_mem を跳ね上げて、朝メモリ枯渇で二度目のアラートを浴びた奴を知ってる」

「……知ってる、って誰ですか」

「さあな。次だ」

## 3

「最後に、いちばん上等な手を見せる。**Sort を出さない**という手だ。ORDER BY を title じゃなく id に変えて、SELECT も id だけにしろ」

```sql
EXPLAIN SELECT id FROM articles ORDER BY id LIMIT 20;
```

```
 Limit  (cost=0.42..... rows=20 width=16)
   ->  Index Only Scan using articles_pkey on articles  (cost=0.42..... rows=100000 width=16)
```

「……Sort ノードが、無い」

「B-tree インデックスは、キーを**最初からソート済みの順序**で持ってる。id 順が欲しいなら、articles_pkey を上から 20 件読んで止まればいい。並べ替えという仕事そのものが消える。N log N が丸ごとゼロだ。しかも第 4 話の Index Only Scan だから、ヒープにも触らない」

「ORDER BY するカラムにインデックスがあるかどうかで、Sort の要不要が決まる……」

「チューニングの鉄則だ。**その ORDER BY、インデックスで済まないか？** と最初に疑え。──さて、道具は揃った。本番だ」

## 4

僕は 30 行のプランを開き直した。真ん中の Sort。今度は、読めた。

「……Sort Method、**external merge**。Disk に、百 MB 単位で書いてます。work_mem を溢れて床に書類をぶちまけてる」

「続けろ」

「でも変です。本番のクエリには LIMIT 20 が付いてる。さっきの実験なら **top-N heapsort に切り替わって、メモリ数十 kB で済むはず**なのに……あ」

見えた。Sort ノードの下。並べ替えの材料を運び込んでくる、入力側の行数。

「Sort が食わされてる行数が、桁違いなんだ。第 2 話で見つけた**推定 4 桁ズレの Nested Loop**、あれの真上にこの Sort がいる。JOIN が想定の 1 万倍の行を吐いて、Sort はそれを全部受け止めてる。N log N で膨らんで、work_mem を溢れて、ディスクに──」

「構図が見えたな」

桐生さんの声に、初めてはっきりした熱が乗った。

「Sort は**共犯**だが、主犯じゃない。奴は運ばされただけだ。想定の 1 万倍の荷物をな。12 秒の内訳のかなりの部分がこの Sort のディスク書きだが、**元栓は下流の JOIN が吐いてる行数**だ。そこを直さない限り、work_mem をいくら積んでも焼け石に水」

「じゃあ、次はいよいよ……」

「ああ。**実行犯**に会いに行く。Nested Loop──第 2 話でお前が『loops がすごい数』と言った、あの現場だ。なぜプランナは Nested Loop を選んだのか。なぜ暴走したのか。JOIN の 3 兄弟の性格から教える」

午前4時19分。事件の構図が、半分まで見えた。

（第6話「実行犯 ─ Nested Loop の暴走」につづく）

---

## 今夜の捜査メモ

- `ORDER BY`（インデックスなし）は **Sort ノード**を生む。Sort は**全行揃うまで 1 行も返せない** A ≒ B 型 → LIMIT の早期打ち切りが効かない
- Sort のコストは **N log₂ N** で膨らむ（`cost_sort`: `2 × cpu_operator_cost × N × log2(N)` + 溢れたら一時ファイル I/O）。食わせる行数が桁で増えると、線形より悪く遅くなる
- Sort のメモリ上限は **`work_mem`**（デフォルト 4MB）。収まれば `quicksort`（メモリ内）、溢れると **`external merge Disk: ...kB`**（ディスクの一時ファイル）
- `ORDER BY ... LIMIT N` は **`top-N heapsort`** に切り替わる: 上位 N 件だけの器を持って全行を流し読み。全行読むが全行並べない。メモリは数十 kB
- `work_mem` は**クエリ単位ではなく Sort / Hash ノード 1 個ごと**の上限。同時接続数×ノード数で化けるので、安易に上げない
- **Sort を消す**のが上等: B-tree はソート済みなので、ORDER BY のカラムにインデックスがあれば「上から N 件」で Sort ノード自体が消える
- 本番の構図: LIMIT 付きなのに external merge が出るのは、**下流の JOIN が想定外の行数を Sort に食わせている**サイン。主犯は Sort ではなく元栓

:::message
top-N heapsort の動作フロー図、work_mem 超過の対比図、実機での Sort Method 切り替え実験は技術書版の[第 5 章](https://zenn.dev/hatsu38/books/postgres-explain-internals)にあります。
:::
