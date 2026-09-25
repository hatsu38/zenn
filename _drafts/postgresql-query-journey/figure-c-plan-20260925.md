# 序章・第3〜4章の10枚 実装計画（横展開の段階C）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 設計書8章で序章・第3章・第4章の「手直し」「描き直し」とした10枚を、試作と段階A・Bで決めた型で直す。新規の図はない。

**Architecture:** 段階Aと同じく、1枚1タスクで SVG 原本を丸ごと書き直し、PNG・本文（キャプション・代替テキスト、タスクに書いたときだけ図の直前の1文）・catalog.json の自分の項目を直してコミットする。README・index.html・book-flow.html・設計書・執筆方針は最後のタスクでまとめて合わせる。検査は `check-figures.cjs`（描画して測る検査を含む）を使う。

**Tech Stack:** SVG、Node.js、Playwright 1.62.1（Chromium）、Zenn の Markdown。

## 下調べ

対象10枚の今の位置・前後の文・設計書のセル・今の SVG の問題・検査の結果は、作業用の下調べ `.superpowers/sdd/c-research.md`（git の管理外）にまとめた。計画に効く点：

- 序章には読了記録の数が2つ出てくる。85行目の2,000万件は Homebrew の PostgreSQL 18.3 と一時テーブルで測った過去の実測で、143行目の200万件（本100万冊）が第1章で用意する主実験のデータ。図に使うのは200万件（執筆方針「序章の過去実測と条件を混同しない」）。
- 第3章158行目の範囲の検索の「7回のアクセス」（`shared hit=7`）は、新しい接続の1回目だけの値で、システムカタログの読み取りを含む（設計書9章の要確認4）。第3・4章の図では使わない。題名の検索の `shared hit=1 read=3`（4回）と `shared hit=7353` は、本文と2つの検証ログで同じ値になる。
- `00-book-sketch` と `00-reading-service` は人物と本のアイコンを `transform` で置いている。描き直しで座標を直接書き、人物は描かない（問いの型の試作 `01-search-window`・`05-growing-library` と同じ）。
- `06-btree-path` の開かない箱は、破線に×を重ねる（段階Bの `06-tree-levels` で破線だけを「増える段」に使ったため。設計書8章に記録済み）。

## Global Constraints

段階Aの計画（`_drafts/postgresql-query-journey/figure-fix-plan-20260925.md`）と段階Bの計画の Global Constraints をそのまま守る。要点：

- SVG は幅640、`viewBox="0 0 640 H"`、H は832以下。`<defs>` と `<style>` は今の部品見本 `images/postgresql-query-journey/parts/figure-parts.svg` からそのまま写す（段階Bで `.route`（たどって読むページの紺の太枠）と `.leader`（矢じりのない引き出し線）が加わった）。
- 背景は `#f5f7f9`。問いの型（`00-reading-service`・`00-ranking-question`・`06-catalog-question`・`03-storage-question`）は `#fffdf7`。見出しは `<text x="24" y="48" class="h">`。札は右上、右端 x=616、見出しとの間12以上。「模型」の札は幅68（x=548）。
- `<title>`＝見出し＝catalog.json の `title`。文字は22以上。
- 画像の中の文字は、見出し・札・部品の名前・焦点のラベル・矢印の動詞・出力の項目名と値だけ。副題・断り書き・他の章への参照・「。」で終わる文は置かない。
- 橙の太枠（`.hot`）は1枚に1か所。矢印は `.flow`（行・データ）、`.req`（要求）、`.ref`（参照・対応）、`.step`（処理の段階・時間の順）。茶色の文字は `.req` の矢印のラベルにだけ使う。ラベルの中で「→」を「だから」の意味に使わない（「なので」と書く）。
- 問いの型の問いの箱は、承認済みの `09-title-lookup` と同じ書き方（`fill="#fff0d3" stroke="#243b50" stroke-width="2.5"` の角丸の箱に、太字の問い1文）。人物は描かない。
- 出力の項目名・ノード名・SQLの句・表と列の名前は等幅（`.mono`）。
- 「索引」は使わず「Index」。第3章の図と本文では「模型」を使わず、札も付けない（キャプションに「説明するための図」と書く）。第3章の比喩は、内部ノードが「案内板」、葉が「箱」。
- 読まない・開かないものは、灰色の破線（`.ghost`）に×を重ねる。たどって読むページは `.route`。
- 線や矢印は重なる図形より後に描く。矢じりの近くのラベルは線の太さ×10だけ離す。
- 原本では `transform` を使わない（描画の検査が位置を測れないため）。矢じり以外の線と文字の交わりは検査しないので、PNG で目で確かめる。
- 本文で直してよいのは、各タスクに書いたキャプション・代替テキスト（Task 10 だけ図の直前の1文も）。ほかの文は変えない。
- 数値は各タスクに書いた出典の値だけを使う。
- git worktree の中では `NODE_PATH=/Users/hatsu/development/github.com/hatsu38/zenn/scripts/book-figures/node_modules` を付ける。
- コミットは日本語の Conventional Commits。`Co-Authored-By` は付けない。署名は自動（`--no-gpg-sign`・`--no-verify` は使わない）。`git add` はパスを明示し、`.claude/worktrees/` は入れない。

## 実行の段取り

- 作業ブランチ `book-query-journey-figure-c` を、段階Bの最後のコミットから切る。計画をコミットしてから、各タスクの worktree `.claude/worktrees/figc-task-N` を作る。
- 2回に分けて並行に進める。1回目は Task 1・2・3・5・6、2回目は Task 4・7・8・9・10。Task 7 は Task 6 の木を写すので、Task 6 を作業ブランチへ取り込んだ後のコミットから worktree を作る。
- 各タスクは実装 → 1枚ずつのレビュー（段階Bのレビュー手順 `.superpowers/sdd/b-figure-review-instructions.md` を使う）→ 指摘の直し。承認されたら作業ブランチへ cherry-pick する。
- 最後に Task 11 で一覧と記録を合わせ、ブランチ全体をレビューしてから ship する。PR は、段階Bの PR がマージ済みなら main へ、未マージなら段階Bのブランチへ向ける。

## 図のタスクに共通する手順（Task 1〜10）

1. 読む：各タスクの「本文」に書いた行の前後40行、今の SVG と PNG、部品見本（`images/postgresql-query-journey/parts/figure-parts.svg` と `.png`）、参考にする承認済みの図（各タスクに書く）。
2. SVG を丸ごと書き直す：`images/postgresql-query-journey/sources/<名前>.svg`。先頭は段階Aと同じ形（`<title>`、部品見本の `<defs>`・`<style>`、背景、見出し）。
3. 書き出す：`node images/postgresql-query-journey/export.cjs <名前>`（worktree では NODE_PATH を付ける）。
4. 本文を直す：各タスクの Python を、リポジトリ（worktree）の直下で実行する（置き換え元がちょうど1回あることを確かめてから置き換える）。
5. catalog.json の自分の項目の `title` と `description` を、各タスクの値にする。ほかの項目と README・index.html・book-flow.html は触らない。
6. 確かめる：`node scripts/book-figures/check-figures.cjs <名前>` が ✓。✗ なら直して 3 からやり直す。
7. 見る：PNG を原寸と `magick images/postgresql-query-journey/<名前>.png -resize 686x /tmp/<名前>-phone.png` で開き、焦点・文字・矢印を確かめる。
8. コミットする：SVG・PNG・章のファイル・catalog.json を明示して `git add` し、各タスクのメッセージでコミットする。
9. 報告する：コミット、SVG の高さ、足したクラス（あれば）、手順7で見たこと。

---

### Task 1: 序章 `00-book-sketch`（仕組み・全体像・手直し）

**今の問題:** 高さ1060（縦横比1.66）。人物と本のアイコンを `transform` で置いている。副題「いつものSQLから、仕組みが見えてくる」と「。」で終わる文が6つ、文字18〜21。章番号と EXPLAIN が描かれておらず、「並べる」の絵が棒グラフで、行数の帯と紛らわしい。

**問い:** この本は、どの章で何を確かめ、どこへ戻ってくるのか。

**数値と出典:** `books/postgresql-query-journey/00-prologue.md` の本書の構成の表（200〜207行目：第1章 実験環境とEXPLAINの基本、第2〜3章 全件探索・LIMIT・B-tree Index、第4〜6章 ページ・メモリ・接続とプロセス、第7〜9章 並べ替え・上位N件の選択・結合と集計、第10〜11章 実行計画の選択・統計情報・更新と保守、第12章 ランキングの再調査）。動詞は46行目「探す、並べる、組み合わせる」。EXPLAIN は18行目「SQLの実行手順を表示する`EXPLAIN`を手がかりに」。数字カード「3 1 2 → 1 2 3」は設計書の指定の、並べ替えを表す説明用の並び。

**描く（上から下へ。段と段は太い白抜きの矢印 `.step` でつなぐ）:**
- 見出し：`この本で、一緒に調べること`（今のまま）。札は付けない。背景は `#f5f7f9`。
- どの箱も、1行目に章番号を灰色（`.m`）で、2行目に中身を太字で書く。
- 1段目：箱（問いの箱と同じ `#fff0d3` の塗り）「序章」「20冊のランキングが、なかなか出てこない」。
- 2段目：箱「第1章」「`EXPLAIN` で、SQLの中を見る」（`EXPLAIN` は等幅）。この箱を焦点の枠（`.hot`）にし、箱の右下に虫眼鏡（円と柄。紺の線）を描いて、レンズの一部を3段目の枠の上辺に重ねる。
- 3段目：枠「SQLの中の仕組み」の中に、同じ大きさのカードを3枚横に並べる。
  - 「第2〜3章」「探す」：木の絵（丸3つと線2本。根が上）。
  - 「第7〜8章」「並べる」：数字カード6枚「3」「1」「2」→「1」「2」「3」（「→」は文字でよい）。
  - 「第9章」「組み合わせる」：2本の線が1本にまとまる絵（今の図の結合の絵を座標で描き直す）。
- 4段目：3段目の枠のすぐ下に、横いっぱいの箱「第4〜6章」「支える：ページ・メモリ・プロセス」（土台に見えるよう、3段目との間に矢印は置かない）。
- 5段目：箱「第10〜11章」「計画の選び方・更新と保守」。
- 6段目：箱（1段目と同じ塗り）「第12章」「もう一度、ランキングへ」。
- 高さが832を超えそうなら、箱の高さと段の間を詰める（章番号と中身を同じ行に並べてもよい）。

**焦点:** 2段目の「`EXPLAIN` で、SQLの中を見る」。

**描かない:** 人物、本のアイコン、副題、「予想 → 観察 → 検証」の文、各章の実測値、1段目から6段目へ戻る矢印。

**参考にする図:** `images/postgresql-query-journey/sources/02-query-stages.svg`（太い白抜きの矢印で段を進める）、今の `00-book-sketch.svg`（木と結合の絵）。

**本文:** `books/postgresql-query-journey/00-prologue.md` の7〜8行目。前後の文は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/00-prologue.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![ランキングの疑問から、小さなSQLでの実験、探索、並べ替え、結合の理解を経て、改善の判断へ戻る](/images/postgresql-query-journey/00-book-sketch.png)',
     '![序章のランキングの疑問から、第1章のEXPLAINを道具に、探す・並べる・組み合わせる仕組み、それを支えるページ・メモリ・プロセス、計画の選び方と更新・保守を章ごとに学び、第12章でランキングへ戻る](/images/postgresql-query-journey/00-book-sketch.png)'),
    ('*本全体の道のり。各章で、この中の仕組みを一つずつ確かめます。*',
     '*箱ごとの章番号で、どの章で何を確かめるかを見てください。どの仕組みも、第1章のEXPLAINを使って調べます。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `この本で、一緒に調べること`、`description` は `仕組み：本全体の道のりと章番号、観察の道具のEXPLAIN`。

**コミット:** `docs(query-journey): 序章の道のりの図に章番号とEXPLAINを入れ、縦の長さを収める`（本文：`高さ1060で人物と本を transform で置き、章番号と EXPLAIN がなかった。箱ごとに章番号を書き、EXPLAIN の箱を焦点にして虫眼鏡を仕組みの枠に重ね、並べ替えを数字カードで描いた。人物と文は外した。`）

---

### Task 2: 序章 `00-reading-service`（問い・手直し）

**今の問題:** 高さ995（縦横比1.55）。人物と本のアイコンを `transform` で置いている。断り書き2つ（「※ 同じ本の再読も…」「架空の画面イメージ…」）と「。」で終わる文、文字16〜21。「読了を記録 → 記録が増える → 本ごとに数えて上位20冊」の流れになっておらず、20冊のうち3冊しか見えない。

**問い:** 読了の記録は増え続けても、ランキングに出すのは20冊。その20冊を出すために、何件の記録を数えるのか。

**数値と出典:** `books/postgresql-query-journey/00-prologue.md` の37〜39行目（読了した本と日付を記録し、記録をもとに今週よく読まれた本を表示する。対象の週の読了記録が多い本から順に20冊）。記録のカードの値は、同じ序章の56〜67行目の表（本1 星の図鑑、本2 海の図鑑、記録は本1 9月14日・本2 9月15日・本1 9月16日）。ランキングの書名と件数（星の図鑑12件・海の図鑑9件・森の図鑑7件）は今の図と同じ説明用の値で、キャプションで説明用と書く。

**描く（問いの型。背景 `#fffdf7`。上から下へ3つの段を、太い白抜きの矢印 `.step` でつなぐ）:**
- 見出し：`記録は増えても、表示は20冊`。札は付けない。
- ① 画面の枠（`09-title-lookup` の画面の書き方）「読了を記録」。中に1行「星の図鑑　9月16日　読了 ✓」。
- 矢印のラベル「記録が1件増える」。
- ② 表の枠（`.panel`）「読了記録 `reading_records`」（表の名前は等幅）。行カード（`.row`）を上から「本1・9月14日」「本2・9月15日」「本1・9月16日」と並べ、最後の「本1・9月16日」を焦点の枠（`.hot`）にして、右に「＋1件」。上に「⋮」を置き、前にも記録が続くことを示す。
- 矢印のラベル「本ごとに数える」。
- ③ 画面の枠「今週よく読まれた本」。行を「1　星の図鑑　12件」「2　海の図鑑　9件」「3　森の図鑑　7件」「⋮」、最後に灰色（`.m`）で「20位まで」。
- 最下：問いの箱「20冊を出すために、何件の記録を数える？」。

**焦点:** ②の「本1・9月16日」と「＋1件」。

**描かない:** 人物、本のアイコン、背表紙の色、再読の注意書き、画面の注意書き、数える件数（答え）。

**参考にする図:** `images/postgresql-query-journey/sources/09-title-lookup.svg`（問いの型の画面の枠・行カード・問いの箱）、`01-search-window.svg`。

**本文:** `books/postgresql-query-journey/00-prologue.md` の41〜42行目。前後の文は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/00-prologue.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![本の読了を記録し、今週よく読まれた本をランキングで見る読書記録サービス](/images/postgresql-query-journey/00-reading-service.png)',
     '![読了を記録するたびに読了記録が1件増え、本ごとに数えた上位20冊をランキングに出す](/images/postgresql-query-journey/00-reading-service.png)'),
    ('*架空の画面イメージ。図の書名と件数は説明用で、後のSQL実行結果とは異なります。*',
     '*読了を記録するたびに、記録が1件ずつ増えていきます。ランキングに出すのは20冊です（架空の画面。書名と件数は説明用で、後のSQLの実行結果とは異なります）。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `記録は増えても、表示は20冊`、`description` は `問い：読了の記録から上位20冊を出すまで`。

**コミット:** `docs(query-journey): 序章のサービスの絵を、記録が増えて20冊を出す流れの問いにする`（本文：`画面の絵で3冊だけを見せ、人物と本を transform で置き、断り書きと文が画像の中にあった。読了を記録すると記録が1件増え、本ごとに数えて20冊を出す流れを3段で描き、問いの箱を1文にした。`）

---

### Task 3: 序章 `00-books-and-records`（仕組み・手直し）

**今の問題:** 副題「サンプルの2冊・3件で考える」と「。」で終わる文が3つ。代替テキストが見出しと同じ。列名がなく、後のランキングのSQL（`JOIN` と `count(*)`）とつながらない。

**問い:** 本の一覧と読了記録は、どの列で対応し、本ごとに何件と数えるのか。

**数値と出典:** `books/postgresql-query-journey/00-prologue.md` の56〜67行目の二つの表（本1 星の図鑑・本2 海の図鑑、記録は本1 9月14日・本2 9月15日・本1 9月16日）、69行目（星の図鑑は2件、海の図鑑は1件）、76行目（`books`・`reading_records`・`book_id`・`id`）、ランキングのSQL（112〜119行目：`count(*)`、`JOIN reading_records AS r ON r.book_id = b.id`、`r.finished_at`）。列名 `finished_at` は図の後の112〜116行目で初めて出るが、図の前の表の「読み終えた日」と同じ列なので、列名として先に見せる（設計書の指定）。

**描く:**
- 見出し：`本ごとに、記録の件数を数える`。札「模型」（幅68、x=548。サンプルの2冊と3件なので、段階Aの `09-hash-join` と同じ扱い）。
- 上段左：表の枠 `books`（等幅）。ヘッダー行「`id`」「`title`」（等幅）。行カード（`.row`、区切りの縦線で2つの欄に分ける）「1｜星の図鑑」「2｜海の図鑑」。
- 上段右：表の枠 `reading_records`（等幅）。ヘッダー行「`book_id`」「`finished_at`」（等幅）。行カードを「1｜9月14日」「1｜9月16日」「2｜9月15日」の順に並べる（同じ本の記録を隣にして、対応の線が交わらないようにする）。
- 対応の線：記録の `book_id` の欄から本の `id` の欄へ、細い灰色の矢印（`.ref`）を3本。ラベルは1か所だけ「`JOIN`　`book_id = id`」（等幅）。
- 上段から下段へ、実線の青緑の矢印（`.flow`）を1本。ラベル「本ごとに数える」と、等幅の「`count(*)`」。
- 下段：枠「本ごとの件数」の中に「星の図鑑　2件」「海の図鑑　1件」。「星の図鑑　2件」を焦点の枠（`.hot`）にする。

**焦点:** 下段の「星の図鑑　2件」。

**描かない:** 外部キー制約、読んだ人数、対象週の条件（`WHERE`）、100万冊・200万件などの実際の件数、「。」で終わる文。

**参考にする図:** `images/postgresql-query-journey/sources/09-hash-join.svg`（サンプルの表と模型の札）、`09-title-lookup.svg`（区切りの縦線のある行カード）。

**本文:** `books/postgresql-query-journey/00-prologue.md` の73〜74行目。前後の文は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/00-prologue.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![本の冊数と、読了記録の件数](/images/postgresql-query-journey/00-books-and-records.png)',
     '![booksの2冊とreading_recordsの3件をbook_idとidで対応させ、本ごとに数えると星の図鑑が2件、海の図鑑が1件になる](/images/postgresql-query-journey/00-books-and-records.png)'),
    ('*サンプルの2冊と3件で考える。*',
     '*星の図鑑には2件の記録がつながり、本ごとに数えると2件になります（サンプルの2冊と3件の模型。列名は後のSQLと同じ）。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `本ごとに、記録の件数を数える`、`description` は `仕組み：booksとreading_recordsの対応と、本ごとの件数（模型）`。

**コミット:** `docs(query-journey): 序章の本と記録の図に列名を入れ、JOINとcount(*)につなぐ`（本文：`本と記録をカードで並べていたが、列名がなく、後のランキングのSQLとつながらなかった。books と reading_records を列名付きの表にし、book_id と id の対応に JOIN、本ごとの件数に count(*) のラベルを付けた。`）

---

### Task 4: 序章 `00-ranking-question`（問い・描き直し）

**今の問題:** 高さ930（縦横比1.45）。副題が断り書き（「処理量を調べる前の見取り図 ／ 行数の縮尺ではない」）で、代替テキストが見出しと同じ。入力の件数がなく、中の処理が文章で書かれ、途中の行数の「？」がない。

**問い:** 結果は20行。読了記録200万件と本100万冊から、途中で何行を扱っているのか。

**数値と出典:** `books/postgresql-query-journey/00-prologue.md` の143行目（第1章で用意する本100万冊と読了記録200万件、2026年9月23日、PostgreSQL 18.6）、168行目の `(20 rows)`、ランキングのSQL（111〜119行目）の句と、122〜127行目の言い換え（対象の週にする、同じ本の記録を数えて題名と返す、件数の多い順に並べる、上位20冊）。**85行目の2,000万件（過去の実測）は使わない。**

**描く（問いの型。背景 `#fffdf7`。上から下へ）:**
- 見出し：`200万件から、20行を返す`。札は付けない。
- 上：入力の枠（`.panel`）を2つ横に並べる。左「読了記録　200万件」と等幅の `reading_records`、右「本　100万冊」と等幅の `books`。
- 中：破線の枠（`01-search-window` の「データベースの中」と同じ書き方）「SQLの中（結果からは見えない）」。中に上から4つの句を置き、各句は小さな角丸の箱（`.panel`。計画のノード `.node` は EXPLAIN の1行を表す部品なので使わない）に等幅の句と、右に動詞のラベル：
  - `WHERE`「対象の週に絞る」
  - `JOIN`「題名を付ける」
  - `GROUP BY`「本ごとに数える」
  - `ORDER BY` / `LIMIT`「多い順に20冊」
- 句と句の間を実線の青緑の矢印（`.flow`、下向き）でつなぎ、矢印の横に行数「？行」（`WHERE` の後）、「？行」（`JOIN` の後）、「？冊」（`GROUP BY` の後）を書く。左の入力（読了記録）から `WHERE` へ、右の入力（本）から `JOIN` の横へ、それぞれ `.flow` の矢印を引く。
- `WHERE` の後の「？行」を焦点の枠（`.hot`）にする。
- 下：結果の枠「結果　20行」（`ORDER BY` / `LIMIT` から `.flow` の矢印）。
- 最下：問いの箱「途中で、何行を扱っている？」。

**焦点:** `WHERE` の後の「？行」。

**描かない:** 途中の行数（答え）、実行計画のノード名、時間、2,000万件と約4.6秒、行数に比例した帯。

**参考にする図:** `images/postgresql-query-journey/sources/01-search-window.svg`（破線の枠「データベースの中」）、`09-title-lookup.svg`（問いの箱）、`05-limit-search.svg`（行の矢印の書き方）。

**本文:** `books/postgresql-query-journey/00-prologue.md` の191〜192行目。前後の文は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/00-prologue.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![20冊を返すまでに、何をしている？](/images/postgresql-query-journey/00-ranking-question.png)',
     '![読了記録200万件と本100万冊から、WHERE・JOIN・GROUP BY・ORDER BYとLIMITを経て20行を返すが、途中の行数は分からない](/images/postgresql-query-journey/00-ranking-question.png)'),
    ('*処理量を調べる前の見取り図。行数の縮尺ではありません。*',
     '*入口の200万件と出口の20行の間で、何行を扱うかは「？」のままです。SQLが求める処理を並べた図で、実行の順番や行数の縮尺ではありません（件数は第1章で用意するデータ）。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `200万件から、20行を返す`、`description` は `問い：ランキングのSQLの途中で扱う行数`。

**コミット:** `docs(query-journey): 序章のランキングの問いを、入口の件数とSQLの句と「？」で描き直す`（本文：`入力の件数がなく、中の処理を文章で書いていた。第1章のデータの200万件と100万冊から、WHERE・JOIN・GROUP BY・ORDER BY と LIMIT の句を経て20行になる流れを描き、途中の行数を「？」にした。85行目の2,000万件（過去の実測）は使っていない。`）

---

### Task 5: 第3章 `06-catalog-question`（問い・手直し）

**今の問題:** 副題「表のほかに、Indexにも保存場所が必要。」と断り書き、文字14〜21、代替テキストが見出しと同じ。目録が3項目しかなく、「目録も100万件」が見えない。

**問い:** 目録（Index）にも100万冊分の情報がある。全部読まずに、目的の場所へ行けるのか。

**数値と出典:** `books/postgresql-query-journey/03-btree-index.md` の11〜13行目（100万冊から1冊を探してきた、番号検索はIndexという目録を使えた、Indexにも100万冊分の情報がある、先頭から全部読んだら助けにならない）。

**描く（問いの型。背景 `#fffdf7`。第3章なので札と「模型」の語は使わない）:**
- 見出し：`目録も、本と同じ100万件`。
- 上：中略した長い棚（`01-search-window`・`05-growing-library` の棚の書き方）。ラベル「表 `books`　100万冊」。
- 下：棚と同じ長さ・同じ厚さの目録の帯。目録のカード（小さな縦長の札。部品見本の Index の項目の色）を棚の本と同じ間隔で並べ、真ん中を「…」で中略する。ラベル「Index（目録）　100万件」。
- 目録の帯を焦点の枠（`.hot`）で囲む。
- 最下：問いの箱「目録を全部読まずに、目的の場所へ行ける？」。

**焦点:** 下の目録の帯。

**描かない:** 案内板と箱（次の節の答え）、目録の中の値、題名の目録（題名の Index はこの章の後半で作る）、虫眼鏡、断り書き。

**参考にする図:** `images/postgresql-query-journey/sources/01-search-window.svg`・`05-growing-library.svg`（中略した棚と問いの箱）。

**本文:** `books/postgresql-query-journey/03-btree-index.md` の15〜16行目。前後の文は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/03-btree-index.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![目録も大きい。それでも速い？](/images/postgresql-query-journey/06-catalog-question.png)',
     '![本100万冊の棚と同じ長さで、Indexの目録にも100万件が並ぶ](/images/postgresql-query-journey/06-catalog-question.png)'),
    ('*学ぶきっかけを描く、説明用の場面。目録そのものも100万冊分あります。*',
     '*本の棚と同じ長さで並ぶ、目録の100万件を見てください（説明するための図）。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `目録も、本と同じ100万件`、`description` は `問い：Indexにも100万冊分の情報がある`。

**コミット:** `docs(query-journey): 第3章の入口の絵で、目録も100万件あることを棚と同じ長さで見せる`（本文：`目録を3項目だけ描いていて、目録も100万件あることが見えなかった。本の棚と同じ長さ・厚さの目録の帯を並べ、副題と断り書きを外した。`）

---

### Task 6: 第3章 `06-btree-path`（仕組み・手直し）

**今の問題:** 副題が断り書き（「番号1〜9で説明する図 ／ 矢印は探索で進む向き」）、「。」で終わる文が2つ、文字21。案内板と三つの箱が別々のパネルで1本の木になっておらず、開かない箱も実線。ラベル「8は「7以上」 → 右の箱へ」の「→」が「だから」の意味。

**問い:** 案内板の境目を見ると、どの箱を開けばよいか。

**数値と出典:** `books/postgresql-query-journey/03-btree-index.md` の20〜22行目（番号1〜9を三つの箱に、左1・2・3、真ん中4・5・6、右7・8・9。案内板に境目の4と7）、27行目（8は7以上なので右の箱へ進み、その中で8を見つける。左と真ん中の箱は開かない）。

**描く（第3章：札なし、「模型」の語なし。案内板と箱は Index のページの枠 `.ipage`、たどって読むページは `.route`）:**
- 見出し：`境目を見て、開く箱を選ぶ`。
- 上の中央：案内板（`.route`）。中に「案内板」と「境目　4｜7」。
- 下：三つの箱を横に並べる。各箱の上に範囲のラベル「4未満」「4以上7未満」「7以上」、中に番号「1 2 3」「4 5 6」「7 8 9」。
- 木の枝と探す道：案内板の下辺から左と真ん中の箱の上辺へは、矢じりのない細い灰色の線（`fill="none" stroke="#b5c2cc" stroke-width="2"`。木の形を示すだけで、部品見本に同じ線のクラスはないので属性で書く）。右の箱へは細い灰色の矢印（`.ref`）で、枝と探す道を兼ねる。ラベル「① 7以上なので右へ」。
- 左と真ん中の箱：灰色の破線（`.ghost`）にし、箱の右上に×（灰色の線2本）、箱の下に「開かない」。
- 右の箱：`.route`。中の「8」を焦点の枠（`.hot`）で囲み、箱の下に「② 箱の中で8を見つける」。

**焦点:** 右の箱の「8」。

**描かない:** 表の行の場所（第4章で扱う）、ページの中身、「模型」の語、段の数（次の節で扱う）。

**参考にする図:** `images/postgresql-query-journey/sources/06-tree-levels.svg`（第3章の `.ipage`・`.route`・`.ref` の「たどる」矢印）、`01-index-to-row.svg`。

**本文:** `books/postgresql-query-journey/03-btree-index.md` の24〜25行目。前後の文は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/03-btree-index.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![8は7以上なので右の箱へ進み、その箱の中で8を見つける](/images/postgresql-query-journey/06-btree-path.png)',
     '![案内板の境目4と7を見て、8は7以上なので右の箱だけを開き、その中で8を見つける。左と真ん中の箱は開かない](/images/postgresql-query-journey/06-btree-path.png)'),
    ('*番号1〜9で説明するための図です。矢印は探索で進む向きです。*',
     '*開くのは右の箱だけで、×を付けた二つの箱は開きません（番号1〜9で説明するための図）。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `境目を見て、開く箱を選ぶ`、`description` は `仕組み：案内板の境目で開く箱を選び、箱の中で8を見つける（説明するための図）`。

**コミット:** `docs(query-journey): 第3章の探し方の図を1本の木にし、開かない箱を破線と×で示す`（本文：`案内板と三つの箱が別々の枠で、開かない箱も実線だった。案内板から三つの箱へ枝を伸ばした1本の木にし、開く右の箱を紺の太枠、開かない二つの箱を破線と×にした。「→」を「だから」の意味で使っていたラベルは「7以上なので右へ」にした。`）

---

### Task 7: 第3章 `06-range-scan`（仕組み・描き直し。Task 6 の後）

**今の問題:** 副題が断り書き（「Indexの葉をたどる図 ／ 表への参照は省略」）、「。」で終わる文、代替テキストが見出しと同じ。前の図と違う形で描いていて、表から取り出す行と、探す・開く・取り出すの数がない。

**問い:** 4以上8以下を取り出すとき、探すのは何回で、箱をいくつ開き、表から何行を取り出すか。

**数値と出典:** `books/postgresql-query-journey/03-btree-index.md` の127行目（4以上8以下）、132行目（まず4がある場所を探し、4・5・6・7・8と順に取り出す。箱の終わりに来たら隣の箱へ。範囲に入る冊数が増えるほど取り出す行も増える）、20〜22行目の箱分け（真ん中4・5・6、右7・8・9）。図で新しく出す数は、この箱分けから数えた「探す 1回」「開く箱 2個」「取り出す行 5行」だけ（実測ではない）。**158行目の「7回のアクセス」（`shared hit=7`）は使わない**（新しい接続の1回目の値で、カタログの読み取りを含むため。設計書9章の要確認4）。

**描く（Task 6 で承認された `06-btree-path.svg` の木を写す。案内板 x=230 y=80 幅180 高さ88、三つの箱 y=340 幅176 高さ120（左 x=24、真ん中 x=232、右 x=440）、枝と矢印の起点 y=169.5 は同じにする。座標は目安で、検査と目で調整してよいが、案内板と三つの箱の位置と大きさは変えない。第3章の約束は同じ）:**
- 見出し：`4以上8以下なら、隣の箱も開く`。
- 案内板（`.route`、「案内板」「境目　4｜7」）。
- 枝と探す道：案内板から左の箱と右の箱へは、Task 6 と同じ座標の矢じりのない灰色の線（`fill="none" stroke="#b5c2cc" stroke-width="2"`）。真ん中の箱へは `.ref` の矢印（探す道）。
- ① のラベル「① 4の箱へ」（幅約110）：真ん中の矢印の左、左の枝との間に右寄せで置く（目安 `x="308" text-anchor="end"`、ベースライン y≈290。左の枝から10以上、矢じりから20以上離す）。Task 6 のレビューで、「① 4がある箱へ」（幅約154）は枝の間に入らないと分かったため短くした。
- 左の箱：Task 6 と同じ（`.ghost`、中身は `.m`、右上に×、下に「開かない」）。
- 真ん中の箱（`.route`）：「4以上7未満」（`.s`）、4・5・6（`.h`）。
- 右の箱（`.route`）：「7以上」（`.s`）、7・8・9（`.h`）。
- ② 隣の箱へ：真ん中と右の箱のすき間（x=408〜440）に、y=400 前後で左から右へ短い `.ref` の矢印。ラベル「② 隣の箱へ」（幅約117）はすき間に入らないので、箱の上の、真ん中の矢印と右の枝の間に置く（目安 x=340〜457、ベースライン y≈322。真ん中の矢じりから20以上、右の枝から10以上）。ラベルの下から矢印の手前まで、引き出し線（`.leader`、x=424 前後の縦の線）でつなぐ。
- ✓と×の行：箱の下（Task 6 の「開かない」と同じ y=492 前後）に、4・5・6・7・8 の真下に ✓（`.teal`）、9 の真下に ×（左の箱の×と同じ灰色の線）。
- 9 のラベル：右の箱の下、✓と×の行の下に2行「9は範囲外」「ここで止まる」（中央 x=528）。
- 行を取り出す：真ん中と右の箱のすき間の下（x=424 前後）、✓と×の行より下から、下の表の枠へ `.ref` の矢印。ラベル「行を取り出す」は矢印の左に右寄せで置く。番号は付けない（2026-09-25 のレビュー：「③」にすると「箱をたどり終えてから表の5行をまとめて読む」と読め、本文132行目の「取り出す途中で隣の箱へ進む」と、Index Scan が1行ずつ受け渡すこと（第6章）と食い違う）。
- 表の枠「表 `books`」（`.panel`）：行カード（`.row`）を横に5枚「本4」「本5」「本6」「本7」「本8」。
- 数のまとめ：表の枠の下に、同じ大きさの枠を3つ横に並べる「探す 1回」「開く箱 2個」「取り出す行 5行」。「取り出す行 5行」を焦点の枠（`.hot`）にし、ほかの2つは `.panel`。
- 高さは832以下。

**焦点:** 「取り出す行 5行」。

**描かない:** 実際の番号（400000〜400010）と Buffers の値、表のページの区切り（ページは第4章で扱う）、「模型」の語。

**参考にする図:** Task 6 の `images/postgresql-query-journey/sources/06-btree-path.svg`（木をそのまま写す）、`06-tree-levels.svg`。

**本文:** `books/postgresql-query-journey/03-btree-index.md` の129〜130行目。前後の文は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/03-btree-index.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![4以上8以下なら、隣の葉も読む](/images/postgresql-query-journey/06-range-scan.png)',
     '![案内板から4のある真ん中の箱へ進み、4・5・6を取り出してから隣の右の箱で7と8を取り出し、範囲外の9で止まる。表から取り出す行は5行](/images/postgresql-query-journey/06-range-scan.png)'),
    ('*Indexの葉をたどる様子を単純にした図です。表への参照は省略しています。*',
     '*探すのは1回で、開く箱は2個、表から取り出す行は5行です。範囲が広がると、取り出す行が増えます（番号1〜9で説明するための図）。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `4以上8以下なら、隣の箱も開く`、`description` は `仕組み：範囲の検索で隣の箱へ進み、表から5行を取り出す（説明するための図）`。

**コミット:** `docs(query-journey): 第3章の範囲の検索の図を、前の図と同じ木と取り出す行で描き直す`（本文：`前の図と違う形で葉だけを描き、表から取り出す行と数がなかった。06-btree-path と同じ木で4〜8に ✓、9に × を付け、表の5行と「探す1回・開く箱2個・取り出す行5行」を描いた。158行目の7回（接続1回目の値）は使っていない。`）

---

### Task 8: 第4章 `03-storage-question`（問い・手直し）

**今の問題:** 副題「画面の1行と、保存先の単位を考える。」と断り書き、文字14〜21、代替テキストが見出しと同じ。章の問い（7,353回は何を数えたか）の数字がなく、ファイルの数の問いになっている。

**問い:** 100万行を調べたのに、アクセスは7,353回。1回で何を読んだのか。

**数値と出典:** `books/postgresql-query-journey/04-pages-and-storage.md` の11〜13行目（Indexを作る前の検索は100万行に条件を当てた、アクセスは7,353回、1行につき1回なら100万回近くになる）。元の出力は `books/postgresql-query-journey/03-btree-index.md` の58〜61行目（`Rows Removed by Filter: 999999`、`Buffers: shared hit=7353`）。

**描く（問いの型。背景 `#fffdf7`）:**
- 見出し：`100万行なのに、7,353回`。札は付けない。
- 同じ大きさの枠（`.panel`）を左右に2つ。
  - 左「調べた行」：行カードを重ねた小さな絵と「100万行」（太字）。
  - 右「アクセス」：「7,353回」（太字）。この枠を焦点の枠（`.hot`）にする。
- 最下：問いの箱「1回で、何を読んだ？」。

**焦点:** 右の「アクセス　7,353回」の枠。

**描かない:** ページ（答え）、ファイル、共有バッファ、Indexを作った後の4回、「1行1回なら100万回」の計算（本文にある）。

**参考にする図:** `images/postgresql-query-journey/sources/01-search-window.svg`・`09-title-lookup.svg`（問いの型）。

**本文:** `books/postgresql-query-journey/04-pages-and-storage.md` の17〜18行目。前後の文は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/04-pages-and-storage.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![本の一覧は、どこに保存される？](/images/postgresql-query-journey/03-storage-question.png)\n*学ぶきっかけを描く、説明用の場面。*',
     '![Indexを作る前の題名検索は100万行を調べたが、アクセスは7,353回だった](/images/postgresql-query-journey/03-storage-question.png)\n*調べた行の100万と、アクセスの7,353回を見比べてください（どちらも第3章の実測）。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `100万行なのに、7,353回`、`description` は `問い：100万行を調べたアクセスが7,353回だった`。

**コミット:** `docs(query-journey): 第4章の入口の絵を、100万行と7,353回を並べる問いにする`（本文：`本1冊につきファイルが1個かを問う絵で、章の問いの数字がなかった。調べた100万行とアクセスの7,353回を並べ、「1回で、何を読んだ？」と問う。副題と断り書きは外した。`）

---

### Task 9: 第4章 `03-ctid-location`（仕組み・手直し）

**今の問題:** 副題、断り書き（「行の配置・空き領域は省略した模型。」）、「。」で終わる文が3つ、文字21。出力の形（`|` 区切り）と違う書き方で、0と1がどの数かが括弧線で示されていない。

**問い:** ctid の (0,1) の二つの数は、それぞれ何を選ぶのか。

**数値と出典:** `books/postgresql-query-journey/04-pages-and-storage.md` の148〜167行目の出力（`SELECT id, ctid, title FROM books ORDER BY id LIMIT 8;` の1行目 `  1 | (0,1) | 実験用の本 1`、8行目まで ctid の左は0）、171行目（左がページ番号、右がそのページ内で行を指す項目の番号。ページ番号は0から、項目番号は1から）、176行目（`LIMIT 8` で止めたので、ページ0の行が8行だけとは限らない）。

**描く:**
- 見出し：`ctid = (0,1) が指す場所`（今のまま）。札「模型」（幅68、x=548）。
- 上：出力の2行を等幅で、出力と同じ字面にする：` id | ctid  |    title` と `  1 | (0,1) | 実験用の本 1`。
- (0,1) の「0」の下と「1」の下に、それぞれ短い括弧線（`.leader`）と、ラベル「ページ番号」「項目番号」。
- 下：ページの枠（`.page`、番号を枠の中の上に「ページ0」）。枠の中の上に項目の並び（小さな枠「1」「2」「3」「4」と「…」）、その下に行カード（`.row`）「実験用の本 1」「実験用の本 2」「実験用の本 3」「実験用の本 4」と「⋮」。
- 出力の「0」からページの枠へ、細い灰色の矢印（`.ref`）。ラベル「① ページを選ぶ」。
- 項目「1」〜「4」から行カードへ `.ref` の矢印を4本。ラベルは項目1の矢印だけ「② 項目が行を指す」。
- 行カード「実験用の本 1」を焦点の枠（`.hot`）にする。

**焦点:** ページ0の中の「実験用の本 1」。

**描かない:** 空き領域、ページの中の実際の並び（項目は前から、行は後ろから詰める）、ページの大きさ、ページ0の行数。

**参考にする図:** `images/postgresql-query-journey/sources/03-pages-and-rows.svg`（第4章のページの枠と行カード）、`09-loops.svg`（`.leader` の使い方）、`01-index-to-row.svg`（`.ref` の矢印）。

**本文:** `books/postgresql-query-journey/04-pages-and-storage.md` の173〜174行目。前後の文は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/04-pages-and-storage.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![ctidの左の0でページを選び、右の1でページ内の項目を選ぶ](/images/postgresql-query-journey/03-ctid-location.png)',
     '![出力の1行目のctid (0,1)の0でページ0を選び、1の項目をたどって、実験用の本 1の行に届く](/images/postgresql-query-journey/03-ctid-location.png)'),
    ('*掲載出力の対応を示す模型。行の物理的な並びや空き領域の配置は再現していません。*',
     '*(0,1)の0がページを、1がページの中の項目を選ぶことを見てください。掲載した出力に合わせた模型で、ページの中の並びや空き領域は再現していません。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `ctid = (0,1) が指す場所`、`description` は `仕組み：ctidのページ番号と項目番号で行を指す（模型）`。

**コミット:** `docs(query-journey): 第4章のctidの図を、出力と同じ字面と括弧線で描き直す`（本文：`「id = 1 ctid = (0, 1)」のように出力と違う書き方で、0と1の意味を文で書いていた。出力と同じ字面の2行に括弧線で「ページ番号」「項目番号」を付け、「① ページを選ぶ」「② 項目が行を指す」の2本の矢印にした。`）

---

### Task 10: 第4章 `03-index-reference`（比較・描き直し）

**今の問題:** Index Scan の経路だけで、Seq Scan と比べていない。「100万行・7,353ページ・57 MB」の関係がない。副題が断り書き、「。」で終わる文が2つ、文字21。

**問い:** Seq Scan と Index Scan は、それぞれ何ページを読んだか。

**数値と出典:** `books/postgresql-query-journey/03-btree-index.md` の58〜61行目（`Seq Scan on books`、`Rows Removed by Filter: 999999`、`Buffers: shared hit=7353`）と92〜95行目（`Index Scan using books_title_idx on books`、`Buffers: shared hit=1 read=3`）、`books/postgresql-query-journey/04-pages-and-storage.md` の194〜198行目（`57 MB`、`7353` ページ）、202〜206行目（7,353は表のページ数、4回にはIndexと表の両方が入る）、225〜232行目（`bt_metap` の `level` が2で、根・途中の案内板・葉の3段）。**第3章158行目の範囲の検索の「7回」は使わない。**

**描く（比較の型。上下の2段を同じ配置にする）:**
- 見出し：`7,353ページか、4ページか`。札「ページ数は実測」（`.real`、見出しと同じ行の右上、右端616）。
- 上段：左にラベル `Seq Scan`（等幅）、右に `shared hit=7353`（等幅）。表の帯「表 `books`　100万行・57 MB・7,353ページ」：小さなページのアイコン（`.page`）を横に並べ、真ん中を「…」で中略する。読んだページはすべて紺の太枠（`.route`）。帯の下に「読むページ 7,353」。
- 下段：左にラベル `Index Scan`（等幅）、右に `shared hit=1 read=3`（等幅）。
  - Index の3段：上から「根」1枚、「途中」数枚と「…」、「葉」数枚と「…」（Index のページの枠 `.ipage`。段の名前は左に書く）。各段で1枚を `.route` にし、上から細い灰色の矢印（`.ref`）でつなぐ（ラベルは1か所「たどる」）。ほかのページは `.ipage` のまま。段と段を結ぶ木の枝は描かない（`06-tree-levels` と同じ）。
  - その下に、上段と同じ表の帯（同じアイコン・同じ並び）。1枚だけを `.route` にし、葉の1枚から `.ref` の矢印でつなぐ（ラベル「表のページへ」）。ほかのページは `.page` のまま。
  - 帯の下に「読むページ 3＋1＝4」を焦点の枠（`.hot`）にする。
- 上段の「読むページ 7,353」と下段の「読むページ 3＋1＝4」は、同じ位置・同じ書き方にする。

**焦点:** 下段の「読むページ 3＋1＝4」。

**描かない:** どのページが hit でどのページが read か（`Buffers` に内訳は出ない）、途中と葉の段のページ数（測っていない）、`Planning` の Buffers、範囲の検索の7回、ページの中身。

**参考にする図:** `images/postgresql-query-journey/sources/06-tree-levels.svg`（`.route` でたどる木）、`03-row-width.svg`（第4章のページのアイコンの並び）、`05-limit-bands.svg`（同じ配置の比較）。

**本文:** `books/postgresql-query-journey/04-pages-and-storage.md` の208〜211行目。図の直前の1文を、比べる相手が分かる文にする。213行目以降は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/04-pages-and-storage.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('根から葉までIndexのページをたどり、最後に表のページから目的の行を取り出す経路を、図で見てみましょう。',
     '表のページをすべて読むSeq Scanと、根から葉までIndexのページをたどってから表のページを読むIndex Scanを、図で比べてみましょう。'),
    ('![Indexの根、途中の案内板、葉をたどり、表のページから行を取り出す](/images/postgresql-query-journey/03-index-reference.png)',
     '![Seq Scanは表の7,353ページをすべて読み、Index Scanは根・途中・葉のIndexの3ページと表の1ページの合わせて4ページを読む](/images/postgresql-query-journey/03-index-reference.png)'),
    ('*3段のIndexと表1ページを使う経路の模型。実行ログから各アクセス先を特定した図ではありません。*',
     '*読むページの数（7,353と4）は実測です。下の4ページの内訳（Indexの3ページと表の1ページ）はIndexの段数から考えた模型で、実行ログで各アクセス先を確かめたものではありません。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `7,353ページか、4ページか`、`description` は `比較：Seq Scanの7,353ページとIndex Scanの4ページ（ページ数は実測）`。

**コミット:** `docs(query-journey): 第4章のIndexの経路の図を、Seq Scanと読むページ数で比べる図にする`（本文：`Index Scan の経路だけを描き、Seq Scan と比べていなかった。同じ表の帯で、Seq Scan が7,353ページすべて、Index Scan が Index の3ページと表の1ページの4ページを読むことを並べ、100万行・57 MB・7,353ページの関係を入れた。図の直前の1文を、比べる2つが分かる文にした。`）

---

### Task 11: 一覧を合わせ、記録を更新して ship する（Task 1〜10 の後）

**Files:**
- Modify: `images/postgresql-query-journey/catalog.json`（第5・11・12章の並び）、`images/postgresql-query-journey/README.md`、`images/postgresql-query-journey/index.html`、`books/postgresql-query-journey/book-flow.html`、`books/postgresql-query-journey/FIGURE-PLAN.md`、`books/postgresql-query-journey/AGENTS.md`

- [ ] **Step 1: Task 1〜10 のコミットを作業ブランチへ cherry-pick する**（コントローラー。1回目の5枚は承認の順に、Task 7 は Task 6 の後）

- [ ] **Step 2: catalog.json の第5・11・12章を本文の順にし、README の一覧を catalog から作り直す**（段階Bの全体レビューの直しで、第5・11・12章の並びが本文の順でないと報告があった。並びは各章の画像の行の順）。README の表は catalog と同じ順・同じ見出しにする。

- [ ] **Step 3: book-flow.html の10枚のラベルを新しい見出しにし、図の一覧を作り直す**（`node scripts/book-figures/build-index.cjs` → `index.html を更新しました（52枚）`。book-flow.html の章データは1行なので、10枚の `["見出し", "/images/postgresql-query-journey/<名前>.png"]` だけを置き換える）

- [ ] **Step 4: 設計書の記録を更新する**
  - 8章の序章・第3章・第4章の表で、10枚の判定の欄に「（2026-09-25 直した）」を付ける。直し方の欄と違えて描いたところ（`06-btree-path` の「① 7以上なので右へ」、`06-range-scan` の表の行カード、`03-storage-question` の問いの箱）は、実装で直した点に書く。
  - 9章の要確認2・3に、PR #19 で直したこと（第11章は `synchronous_commit` に絞って書いたこと）を書き足す。要確認4の「第3章153行目」を今の行番号にし、第3・4章の図では範囲の検索の7を使っていないことを書き足す。

- [ ] **Step 4b: 部品見本に「開かない箱」の見本を足す**（`.ghost` の枠と灰色 `#7d93a3` の×。段階Cの `06-btree-path` と `06-range-scan` で初めて使った描き方。設計書4.3の「灰色の破線＋×」の行に、×の色を書き足す）

- [ ] **Step 5: 執筆方針の図の行を更新する**（`books/postgresql-query-journey/AGENTS.md` の図の枚数の行の括弧に、「序章・第3〜4章の10枚を直した」を足す。枚数は52枚のまま）

- [ ] **Step 6: 全体を確かめる**
  - `node scripts/book-figures/check-figures.cjs` に、段階Bまでの21枚と段階Cの10枚（`00-book-sketch 00-reading-service 00-books-and-records 00-ranking-question 06-catalog-question 06-btree-path 06-range-scan 03-storage-question 03-ctid-location 03-index-reference`）を渡して、`31枚中 31枚が約束を満たしています`。
  - `cd scripts/book-figures && npm test` で `ℹ pass 12`。
  - 章の画像参照52件がすべて実在する。
  - `git grep -n "索引" -- images/postgresql-query-journey/sources/ books/postgresql-query-journey/0[3-9]-*.md books/postgresql-query-journey/1[0-2]-*.md` が出力なし。
  - `git grep -n "模型" -- images/postgresql-query-journey/sources/06-*.svg books/postgresql-query-journey/03-btree-index.md` が出力なし。
  - `git grep -n "transform" -- images/postgresql-query-journey/sources/0[0-6]-*.svg` で、段階Cの10枚に出てこない。

- [ ] **Step 7: コミットし、ブランチ全体をレビューしてから ship する**（`docs(query-journey): 直した10枚の見出しを一覧に合わせ、設計書の記録を更新する`。PR の向け先は「実行の段取り」のとおり）
