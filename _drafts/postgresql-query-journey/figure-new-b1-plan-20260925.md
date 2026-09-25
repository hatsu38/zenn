# 高優先度の新規図 3枚 実装計画（横展開の段階B-1）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 設計書8章で「新規・高」とした7枚のうち、ユーザーの判断を待たずに描ける3枚（`06-tree-levels`・`07-sort-bands`・`08-sort-vs-topn`）を描き、本文の指定した位置へ入れる。

**Architecture:** 段階Aと同じく、1枚1タスクで SVG 原本・PNG・本文（図の直前の1文、図、キャプション、代替テキスト）・catalog.json の自分の項目を作ってコミットする。README・index.html・book-flow.html・執筆方針の枚数は最後のタスクでまとめて合わせる。検査は段階Aで強めた `check-figures.cjs`（描画して測る検査を含む）を使う。

**Tech Stack:** SVG、Node.js、Playwright 1.62.1（Chromium）、Zenn の Markdown。

## この段階で描かない4枚

`09-loops`・`10-stats-to-rows`・`11-heap-fetches`・`12-plan-overview` は、本の範囲に関わる判断（章の技術の図の枚数、本文が「結果は載せていない」とする箇所に実測の図を置くか）をユーザーに確かめてから、段階B-2で描く。下調べの記録は `.superpowers/sdd/b-research.md`（作業用、git の管理外）。

## Global Constraints

段階Aの計画（`_drafts/postgresql-query-journey/figure-fix-plan-20260925.md`）の Global Constraints をそのまま守る。要点：

- SVG は幅640、`viewBox="0 0 640 H"`、H は832以下。`<defs>` と `<style>` は今の部品見本 `images/postgresql-query-journey/parts/figure-parts.svg` からそのまま写す（段階Aで `.work`・`.val`・`.buffer` が加わった）。
- 背景は `#f5f7f9`（問いの型は `#fffdf7`。この段階の3枚はどれも問いの型ではない）。見出しは `<text x="24" y="48" class="h">`。札は右上、右端 x=616、見出しとの間12以上。「模型」の札は幅68（x=548）。
- `<title>`＝見出し＝catalog.json の `title`。文字は22以上。
- 画像の中の文字は、見出し・札・部品の名前・焦点のラベル・矢印の動詞・出力の項目名と値だけ。副題・断り書き・他の章への参照・「。」で終わる文は置かない。
- 橙の太枠（`.hot`）は1枚に1か所。矢印は `.flow`（行・データ）、`.req`（要求）、`.ref`（参照・対応）、`.step`（処理の段階・時間の順）。茶色の文字は `.req` の矢印のラベルにだけ使う。
- 計画の木は「子が下、親が上、行は下から上へ」（設計書4.2）。
- 出力の項目名とノード名は等幅（`.mono`）。
- 「索引」は使わず「Index」。第3章の図と本文では「模型」を使わず、札も付けない（キャプションに「説明するための図」と書く）。第3章の比喩は、内部ノードが「案内板」、葉が「箱」。
- 線や矢印は重なる図形より後に描く。矢じりの近くのラベルは線の太さ×10だけ離す。
- 原本では `transform` を使わない（描画の検査が位置を測れないため）。矢じり以外の線と文字の交わりは検査しないので、PNG で目で確かめる。
- ページ枠は番号を枠の中の上に書く（共有バッファの中のように小さく並べるときだけタブ）。値カードは `.val`、作業用メモリは `.work`（設計書4.1と部品見本）。
- 本文で直してよいのは、各タスクに書いた「図の直前の1文・図・キャプション・代替テキスト」の挿入だけ。
- 数値は各タスクに書いた出典の値だけを使う。
- git worktree の中では `NODE_PATH=/Users/hatsu/development/github.com/hatsu38/zenn/scripts/book-figures/node_modules` を付ける。
- コミットは日本語の Conventional Commits。`Co-Authored-By` は付けない。署名は自動。`git add` はパスを明示し、`.claude/worktrees/` は入れない。

## 図のタスクに共通する手順（Task 1〜3）

1. 読む：各タスクの「本文」に書いた位置の前後40行、部品見本の SVG と PNG、参考にする承認済みの図（各タスクに書く）。
2. SVG を新しく書く：`images/postgresql-query-journey/sources/<名前>.svg`。先頭は段階Aと同じ形（`<title>`、部品見本の `<defs>`・`<style>`、背景、見出し）。
3. 書き出す：`node images/postgresql-query-journey/export.cjs <名前>`（worktree では NODE_PATH を付ける）。
4. 本文に入れる：各タスクの Python を、リポジトリ（worktree）の直下で実行する。
5. catalog.json に自分の項目を足す：各タスクに書いた項目を、同じ章の最後の項目の直後に入れる（`name`・`chapter`・`title`・`description` の4つ。並べ替えは Task 4 で行う）。README・index.html・book-flow.html は触らない。
6. 確かめる：`node scripts/book-figures/check-figures.cjs <名前>` が ✓。
7. 見る：PNG を原寸と `magick <png> -resize 686x /tmp/<名前>-phone.png` で開き、焦点・文字・矢印を確かめる。
8. コミットする：SVG・PNG・章のファイル・catalog.json を明示して `git add` し、各タスクのメッセージでコミットする。
9. 報告する：コミット、SVG の高さ、足したクラス、見たこと。

---

### Task 1: 第3章 新規 `06-tree-levels`（仕組み・説明するための図）

**問い:** 冊数が100倍になっても、たどる枚数はなぜ1枚しか増えないのか。

**数値と出典:** 本文 `books/postgresql-query-journey/03-btree-index.md` の35〜37行目（仮に一枚の案内板に100個の行き先が書けるなら、1段で100個、2段で100×100＝1万個の箱。箱に100冊ずつなら、案内板2段と葉の箱の3段で100万冊。案内板を1段増やすと範囲は100倍）。図で新しく出す数は、この仮定からの計算の「全部なら1＋100＋10,000＝10,101枚」と「1億冊なら4段で4枚」だけ。

**描く:**
- 見出し：`100万冊でも、読むのは3枚`
- 札は付けない（第3章）。
- 左に3段の木。案内板も箱も Index のページなので、どちらも部品見本の Index のページの枠（`.ipage`）で描く（計画のノードの `.node` は使わない）。1段目は案内板1枚（ラベル「案内板 1枚」）。2段目は案内板を5枚ほどと「…」（ラベル「案内板 100枚」）。3段目は箱を8個ほどと「…」（ラベル「箱 1万個（1箱に100冊）」）。3段目の下に「100万冊」。
- たどる道：各段で1枚ずつ（1段目の1枚、2段目の1枚、3段目の1個）を、枠を紺の太さ3にして見分ける（部品見本のクラスで足りなければ1つだけ足して報告する）。上から下へ細い灰色の矢印（`.ref`）でつなぐ。ラベルは1か所だけ「たどる」。
- 木の右（または下）に数の比較を2行：「読むのは 1＋1＋1＝3枚」と「全部なら 1＋100＋10,000＝10,101枚」。前者を焦点の枠（`.hot`）にする。
- いちばん下に、3段目の下へ破線（`.ghost`）の4段目を薄く描き、「1億冊なら、段が1つ増えて4枚」。

**焦点:** 「読むのは 1＋1＋1＝3枚」。

**描かない:** 実際の題名の Index の段数（第4章で確かめる）、ページの中身、「模型」の語。

**参考にする図:** `images/postgresql-query-journey/sources/06-btree-path.svg`（第3章の案内板と箱の言葉）、`01-index-to-row.svg`（`.ref` の「たどる」矢印）。

**本文:** 37行目の段落と39行目の段落の間に、図の直前の1文・図・キャプションを入れる。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/03-btree-index.md')
text = path.read_text(encoding='utf-8')
anchor = '`log`を初めて見ても、まずは'
block = ('図で、各段で読む1枚と、全部を読んだときの枚数を比べてください。\n\n'
         '![案内板1枚、案内板100枚、箱1万個の3段から、各段1枚ずつ合わせて3枚だけをたどる。全部なら10,101枚で、1億冊でも4段で4枚になる](/images/postgresql-query-journey/06-tree-levels.png)\n'
         '*各段で1枚ずつ、合わせて3枚だけを読みます。全部を読むと10,101枚です（説明するための図。1枚の案内板に100個の行き先が書けると仮に置いています）。*\n\n')
assert text.count(anchor) == 1
text = text.replace(anchor, block + anchor)
path.write_text(text, encoding='utf-8')
```

**catalog.json（第3章の最後の項目 `06-catalog-question` の直後）:** `{"name": "06-tree-levels", "chapter": 3, "title": "100万冊でも、読むのは3枚", "description": "仕組み：分岐100の3段の木で、各段1枚だけ読む（説明するための図）"}`

**コミット:** `docs(query-journey): 第3章に、木の段ごとに1枚だけ読む図を足す`（本文：`案内板の段数と読む枚数の関係を、文章だけで説明していた。分岐100の3段の木で、各段1枚ずつの3枚と、全部読んだときの10,101枚を並べ、1億冊でも4枚になることを示す。`）

---

### Task 2: 第7章 新規 `07-sort-bands`（観察）

**問い:** 200万行のうち、何行を並べ替え、どれだけのメモリを使ったか。

**数値と出典:** 本文 `books/postgresql-query-journey/07-sort.md` の88〜97行目の出力と113〜125行目の説明。`Seq Scan` の `rows=499998.00`、`Rows Removed by Filter: 1500002`、`loops=1`、`Buffers: shared hit=10811`。足すと2,000,000行（115行目）。`Sort Method: quicksort  Memory: 27913kB`、設定は `work_mem = '64MB'`（65行目、123行目）。

**描く（計画の木の向きどおり、親の Sort が上、子の Seq Scan が下、行は下から上へ）:**
- 見出し：`200万行を調べ、4分の1を並べた`
- 右上に札「実測」（`.real`）。
- 下段：計画のノード `Seq Scan on reading_records`（部品見本の「計画のノード」）。その下に、長い帯（部品見本の「量の帯」、全体を灰色）「表の200万行」。帯のそばに「× 除外 1,500,002行」と等幅の `Rows Removed by Filter: 1500002`。ノードの横に等幅の `Buffers: shared hit=10811`。
- 中段：帯から取り出した短い帯（長さは200万行の帯の4分の1＝499,998行に比例）に「○ 499,998行」と等幅の `rows=499998`。この短い帯を焦点の枠（`.hot`）にする。上の帯の中での位置は描かない（期間に合う行が表のどこにあるかは、この出力では分からない）。
- 短い帯から上段の Sort へ、実線の青緑（`.flow`）の矢印、ラベル「行を渡す」。
- 上段：計画のノード `Sort`。横に等幅の `Sort Method: quicksort  Memory: 27913kB`。その下に作業領域の破線の枠（部品見本の `.work`）を幅いっぱいに置き、`work_mem 64MB` と書く。枠の中に、27,913kB に比例した長さ（枠の約43%）の塗りを描き、「27,913kB（収まった）」。

**焦点:** Sort へ渡った499,998行の短い帯。

**描かない:** 実行時間（本文の数値と元のログで食い違いがあるため、この図では扱わない）、Sort の Buffers（子の分を含む値で、次の節で説明する）、期間の条件の全文。

**参考にする図:** `images/postgresql-query-journey/sources/01-scan-and-filter.svg`（観察の型の帯と取り出した1行のカード）、`05-limit-bands.svg`、`04-memory-regions.svg`（作業領域の枠）。

**本文:** 125行目の段落と「### 223.929msは、ソートだけの時間ではない」の見出しの間に入れる。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/07-sort.md')
text = path.read_text(encoding='utf-8')
anchor = '\n### 223.929msは、ソートだけの時間ではない\n'
block = ('図で、200万行のうちSortへ渡った行の割合と、Sortが使ったメモリを確かめてください。\n\n'
         '![200万行の帯のうち4分の1の499,998行がSortへ渡り、残りの1,500,002行は除外された。Sortはquicksortで27,913kBを使い、work_memの64MBに収まった](/images/postgresql-query-journey/07-sort-bands.png)\n'
         '*帯の長さで、除外した1,500,002行とSortへ渡した499,998行の差を見てください（件数とメモリは実測）。*\n')
assert text.count(anchor) == 1
text = text.replace(anchor, '\n' + block + anchor)
path.write_text(text, encoding='utf-8')
```

**catalog.json（第7章の最後の項目 `07-recent-records` の直後）:** `{"name": "07-sort-bands", "chapter": 7, "title": "200万行を調べ、4分の1を並べた", "description": "観察：Seq ScanからSortへ渡る行数と、Sortのメモリ（実測）"}`

**コミット:** `docs(query-journey): 第7章に、Sortへ渡る行数とメモリの帯の図を足す`（本文：`200万行を調べて499,998行を並べたことと、27,913kBが work_mem の64MBに収まったことを、行数に比例した帯とメモリの枠で見せる。計画の木の向きに合わせ、Sort を上、Seq Scan を下に描いた。`）

---

### Task 3: 第8章 新規 `08-sort-vs-topn`（比較・実測）

**問い:** `LIMIT 20` を付けると、調べる行・並べる行・持つ量・返す行のどれが変わるか。

**数値と出典:** 左の列は第7章（`books/postgresql-query-journey/07-sort.md` の88〜97行目・115行目：調べた2,000,000行、Sort に入った499,998行、`quicksort  Memory: 27913kB`、返した499,998行、`work_mem` 64MB）。右の列は第8章（`books/postgresql-query-journey/08-top-n-heap.md` の66〜72行目：対象週499,998行が Sort に入る、`top-N heapsort  Memory: 26kB`、返すのは20行、`work_mem` 4MB）。右の列の「調べる2,000,000行」は、同じ表と同じ期間の条件の Seq Scan であることから（第8章18行目「読了記録は200万件」、66行目）。

**描く（比較の型。2列を同じ配置にする）:**
- 見出し：`LIMITで減るのは、持つ量と返す行`
- 右上に札「実測」（`.real`）。
- 列の見出し：左は等幅の `ORDER BY` と「だけ」、その下に小さく `work_mem 64MB`。右は等幅の `ORDER BY … LIMIT 20`、その下に `work_mem 4MB`。
- 行の名前を左端に4つ：「調べる」「Sortに入る」「持つ」「返す」。
- 各行に、左右の列で同じ尺度の帯（どれも部品見本の量の帯 `.band`）を描き、数を添える。
  - 調べる：2,000,000行｜2,000,000行（同じ長さ。どちらも灰色の `.band`）。
  - Sortに入る：499,998行｜499,998行（同じ長さ）。
  - 持つ：左は等幅の `quicksort` と「27,913kB」、右は `top-N heapsort` と「26kB」。同じ尺度なので右はほぼ0の長さになる（見えるように最小2の幅で描く）。
  - 返す：499,998行｜20行（右はほぼ0）。
- 同じだった上の2行は、行の名前の横に「＝同じ」を添え、帯は灰色のまま。変わった下の2行の右の数（26kB と 20行）のうち、「26kB」を焦点の枠（`.hot`）にする。

**焦点:** 右の列の「26kB」。

**描かない:** 計画の木のノード、実行時間、第7章・第8章という章の名前（キャプションで書く）。

**参考にする図:** `images/postgresql-query-journey/sources/05-limit-bands.svg`（同じ尺度の帯を並べる比較）、`01-scan-and-filter.svg`。

**本文:** 72行目の段落と「## 最初から順序が分かるなら？」の見出しの間に入れる。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/08-top-n-heap.md')
text = path.read_text(encoding='utf-8')
anchor = '\n## 最初から順序が分かるなら？\n'
block = ('図で、第7章の`ORDER BY`だけの実行と、四つの数を並べて比べてください。\n\n'
         '![ORDER BYだけとLIMIT 20の比較。調べる200万行とSortに入る499,998行は同じで、持つ量は27,913kBと26kB、返す行は499,998行と20行に変わる](/images/postgresql-query-journey/08-sort-vs-topn.png)\n'
         '*調べる行とSortに入る行は同じで、持つ量と返す行だけが減ります（左は第7章、右はこの章の実測。work_memの設定は64MBと4MBで違います）。*\n')
assert text.count(anchor) == 1
text = text.replace(anchor, '\n' + block + anchor)
path.write_text(text, encoding='utf-8')
```

**catalog.json（第8章の最後の項目 `08-twenty-window` の直後）:** `{"name": "08-sort-vs-topn", "chapter": 8, "title": "LIMITで減るのは、持つ量と返す行", "description": "比較：ORDER BYだけとLIMIT 20の四つの数（実測）"}`

**コミット:** `docs(query-journey): 第8章に、ORDER BYだけとLIMIT 20を並べて比べる図を足す`（本文：`調べる行とSortに入る行は同じで、持つ量（27,913kBと26kB）と返す行（499,998行と20行）だけが変わることを、同じ尺度の帯で見せる。`）

---

### Task 4: 一覧を合わせ、全体を確かめて ship する

- [ ] **Step 1: Task 1〜3 のコミットを作業ブランチへ cherry-pick する**（コントローラー）

- [ ] **Step 2: catalog.json の第3・7・8章の項目を本文の順に並べ直し、README の一覧・執筆方針と README の枚数を合わせる**

catalog.json の第3章は `06-catalog-question`・`06-btree-path`・`06-tree-levels`・`06-range-scan`、第7章は `07-recent-records`・`07-merge-cards`・`07-sort-bands`・`07-external-sort`、第8章は `08-twenty-window`・`top-three-heap`・`08-sort-vs-topn`・`08-top-n-vs-index` の順にする。README の一覧の表は catalog.json と同じ順・同じ見出しにし、新しい3行を足す。`images/postgresql-query-journey/README.md` 5行目と `books/postgresql-query-journey/AGENTS.md` の「計48枚」を「計51枚」にする。

- [ ] **Step 3: book-flow.html の第3・7・8章の図の一覧に、新しい3枚を本文の順で足し、図の一覧を作り直す**（`node scripts/book-figures/build-index.cjs` → `index.html を更新しました（51枚）`）

- [ ] **Step 4: 全体を確かめる**（`check-figures.cjs` で3枚と段階Aまでの16枚が ✓、`npm test` が12件、章の画像参照が51件すべて実在）

- [ ] **Step 5: コミットし、ブランチ全体をレビューしてから ship する**
