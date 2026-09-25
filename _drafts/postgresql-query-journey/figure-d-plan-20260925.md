# 第5〜8章の12枚 実装計画（横展開の段階D）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 設計書8章で第5〜8章の「手直し」「描き直し」とした11枚を直し、新規の `04-two-levels` を1枚描く。先に、部品見本にないストレージとファイル・画面の枠を足す。

**Architecture:** 段階A〜Cと同じく、1枚1タスクで SVG 原本を書き、PNG・本文（キャプション・代替テキスト、新規図だけ図の直前の1文）・catalog.json の自分の項目を直してコミットする。一覧・設計書・執筆方針は最後のタスクでまとめて合わせる。検査は `check-figures.cjs`（描画して測る検査を含む）。

**Tech Stack:** SVG、Node.js、Playwright 1.62.1（Chromium）、Zenn の Markdown。

## 下調べとユーザーの判断

下調べは作業用の `.superpowers/sdd/d-research.md`（git の管理外）。計画に効く点：

- **2026-09-25 のユーザーの判断**：新規 `04-two-levels` は描く（第5章の技術の図は3枚で目安内）。新規 `07-work-mem-total` は見送る（第7章の技術の図が4枚になる。処理ごとの作業用メモリは第5章の `04-memory-regions` で描いた）。
- 第5章の本文は、2026-09-25 にページを追い出してから測り直した結果（1回目 `shared read=8`、2・3回目 `shared hit=8`、`Rows Removed by Filter: 999` が3回とも）。設計書8章の `04-two-levels` のセル（「すべてshared hit」「3回とも同じ」）と `04-repeat-observation` のセルは、測り直す前の本文で書かれている。この計画は今の本文に合わせる。
- 設計書のセルから、本の約束に当てはめて変えた点（Task 14 で設計書8章に記録する）：
  - `02-execution-tree`：出力は `EXPLAIN` だけで実測の行数がない（145行目）ので、「観察」ではなく仕組み（模型）に出力の見積もりを添える。「葉の先頭3枚」「読まない予定」は、Index をページ単位で読むことと食い違うので「先頭の3件」「4件目から先は要求されない」にする。
  - `02-connections`：作業領域と共有バッファは描かない。直後の69行目「同じDB」を図に残し、156行目の節（第5章の図とプロセスの対応）を先取りしないため。
  - `07-recent-records`：「同じ日なら本の番号順」は SQL（`ORDER BY finished_at DESC, book_id ASC`、`finished_at` は日時）と違うので「同じ日時なら」。記録は白い行カードにし、色で見分けさせない（設計書4.1）。
  - `07-merge-cards`：「499,998行なら約19段」は外す（出典がない、実験より前の数、実際の Sort は quicksort で32行目の約束とも食い違う）。
  - `07-external-sort`：external merge・Disk・temp との対応表と出力の項目名は描かない（本文170〜175行目と重なり、166行目で読者が確かめる前に答えを見せる）。「先頭だけ読み戻す」は「少しずつ読み戻す」。
  - `08-twenty-window`：「調べる？件」は「読む？件」（第7章では「調べる」が200万行を指し、段階Bで `08-sort-vs-topn` から外した語。33行目の予想の語は「読む」）。
  - `08-top-n-vs-index`：ノードの列は描かない（101行目で、Indexを作った後の計画を読者が確かめる課題のため）。
  - `top-three-heap`：2枚に分けず、1枚の中で2×2のコマにして縦を収める（ファイル名と本文の「1〜4コマ目」を変えずに済む）。
- 接続1回目の値（`shared hit=7` など）を使う図はない。

## Global Constraints

段階A〜Cの計画の Global Constraints をそのまま守る。要点：

- SVG は幅640、`viewBox="0 0 640 H"`、H は832以下（縦横比1.3以下）。`<defs>` と `<style>` は Task 1 の後の部品見本 `images/postgresql-query-journey/parts/figure-parts.svg` からそのまま写す。
- 背景は `#f5f7f9`。問いの型（`04-repeat-observation`・`02-client-scene`・`07-recent-records`・`08-twenty-window`）は `#fffdf7`。見出しは `<text x="24" y="48" class="h">`。札は右上、右端 x=616、見出しとの間12以上。「模型」「実測」の札は幅68（x=548）。
- `<title>`＝見出し＝catalog.json の `title`。文字は22以上。
- 画像の中の文字は、見出し・札・部品の名前・焦点のラベル・矢印の動詞・出力の項目名と値だけ。副題・断り書き・他の章への参照・「。」で終わる文は置かない。
- 橙の太枠（`.hot`）は1枚に1か所（比べる2枚は2枚。2×2のコマの図は各コマ1か所）。矢印は `.flow`（行・データ）、`.req`（要求）、`.ref`（参照・対応）、`.step`（処理の段階・時間の順）。茶色の文字は `.req` の矢印のラベルにだけ。ラベルの中で「→」を「だから」の意味に使わない。
- ①②③の番号は、実際にその順に起きる手順にだけ付ける。条件で通らない枝は、線の形やラベル（「なければ」）で分ける。
- 問いの型の問いの箱は設計書4.1のとおり（x=24・幅592・高さ60・角丸10、地 `#fff0d3`・紺 `#243b50` の線2.5、太字の問い1文、下の余白20）。問いの箱の地をほかの箱に使わない。人物は描かない。
- 読まない物の描き方は設計書4.3のとおり（多数のページは読む物だけ `.route`、少数の開かない物は破線＋灰色の×、比べて外れた値は紺の文字の×）。要求されない物は `05-limit-search` と同じ破線（`.ghost`、×なし）。
- 計画の木は「子が下、親が上、行は下から上へ」。出力の項目名・ノード名・SQLの句は等幅（`.mono`）。
- 「索引」は使わず「Index」。第5章の図には「バックエンド」の語を出さない（第6章64行目で定義する前）。
- 線や矢印は重なる図形より後に描く。矢じりの近くのラベルは線の太さ×10だけ離す。原本では `transform` を使わない。矢じり以外の線と文字の交わりは検査しないので、PNG を2倍に拡大して目でも確かめる。
- 本文で直してよいのは、各タスクに書いたキャプション・代替テキスト（新規図は図の直前の1文・図・キャプションの挿入）だけ。
- 数値は各タスクに書いた出典の値だけを使う。
- git worktree の中では `NODE_PATH=/Users/hatsu/development/github.com/hatsu38/zenn/scripts/book-figures/node_modules` を付ける。
- コミットは日本語の Conventional Commits。`Co-Authored-By` は付けない。署名は自動（`--no-gpg-sign`・`--no-verify` は使わない）。`git add` はパスを明示し、`.claude/worktrees/` は入れない。

## 実行の段取り

- 作業ブランチ `book-query-journey-figure-d`（main e574b32 から）。計画をコミットしてから Task 1 を始める。
- Task 1（部品見本）を作業ブランチへ取り込んだ後のコミットから、図のタスクの worktree `.claude/worktrees/figd-task-N` を作る。
- 1回目：Task 2・3・4・5・7・8。2回目：Task 9・11・12・13。3回目：Task 6（Task 5 の承認後）と Task 10（Task 9 の承認後）。後の図は先の図の座標を写すので、先の図を作業ブランチへ取り込んだ後のコミットから worktree を作る。
- 各タスクは実装 → 1枚ずつのレビュー（`.superpowers/sdd/c-figure-review-instructions.md` と同じ手順。段階Dの Global Constraints を渡す）→ 指摘の直し → cherry-pick。
- 最後に Task 14 で一覧と記録を合わせ、ブランチ全体をレビューしてから ship する（PR は main 向け）。

## 図のタスクに共通する手順（Task 2〜13）

1. 読む：各タスクの「本文」に書いた行の前後40行、今の SVG と PNG、部品見本の SVG と PNG、参考にする承認済みの図。
2. SVG を書く：`images/postgresql-query-journey/sources/<名前>.svg`（直しは丸ごと書き直す）。先頭は段階Aと同じ形（`<title>`、部品見本の `<defs>`・`<style>`、背景、見出し）。
3. 書き出す：`node images/postgresql-query-journey/export.cjs <名前>`（worktree では NODE_PATH を付ける）。
4. 本文を直す：各タスクの Python を、リポジトリ（worktree）の直下で実行する（置き換え元がちょうど1回あることを確かめてから）。
5. catalog.json：直しは自分の項目の `title` と `description` を各タスクの値に、新規は各タスクに書いた項目を足す。ほかの項目と README・index.html・book-flow.html は触らない。
6. 確かめる：`node scripts/book-figures/check-figures.cjs <名前>` が ✓。
7. 見る：PNG を原寸と `magick images/postgresql-query-journey/<名前>.png -resize 686x /tmp/<名前>-phone.png` で開き、焦点・文字・矢印を確かめる。
8. コミットする：SVG・PNG・章のファイル・catalog.json を明示して `git add` し、各タスクのメッセージでコミットする。
9. 報告する：コミット、SVG の高さ、足したクラス（あれば）、手順7で見たこと、依頼書から外れた点と理由。

---

### Task 1: 部品見本に、ストレージとファイル・画面の枠を足す

**今の問題:** 設計書4.1の「ストレージ（下段の枠。中に表のファイル・WALのファイル・一時ファイル）」に部品見本がない。第5章の2枚・第6章の `02-connections`・第7章の `07-external-sort` が使う。psql のターミナルの画面の枠も見本がない（第6章の2枚が使う。承認済みの `01-search-window`・`09-title-lookup`・`00-reading-service` の画面の枠が手本）。

**描く（部品見本 `images/postgresql-query-journey/parts/figure-parts.svg` の末尾に足す）:**
- 「ストレージ」：下段に置く横長の枠。クラス `.storage` を足す（既存の部品と見分けられる色。共有バッファ `.buffer`・作業用メモリ `.work`・Index のページ `.ipage`・白い `.panel` と紛れないこと）。枠の中の左上に「ストレージ（SSDなど）」。
- 「ファイル」：ストレージの枠の中に置く白い箱。クラス `.file` を足す。見本は「表のファイル」と「一時ファイル」の2つ。
- 「画面の枠」：`00-reading-service` の画面の枠と同じ書き方（白い地・紺 `#243b50` の線2.5・上に題の帯）。見本の題は「ターミナル：psql」。クラスは足さない（問いの箱と同じく属性で書く）。
- 部品見本の高さ・背景の高さを必要なだけ伸ばし、`node images/postgresql-query-journey/export.cjs parts/figure-parts.svg` で PNG も書き出す。

**設計書:** `books/postgresql-query-journey/FIGURE-PLAN.md` 4.1 の「ストレージ」の行の見た目の欄に `.storage` と `.file` を書き、「画面の枠」の行を足す（見た目：白い地・紺の線2.5・題の帯／意味：psql やサービスの画面。問いの型の場面と、接続を描く図で使う）。

**確かめる:** 部品見本の PNG を原寸と686px で見て、ほかの部品と見分けられること。`check-figures.cjs`（31枚）と `npm test` が今のまま通ること。

**コミット:** `docs(query-journey): ストレージとファイル、画面の枠を部品見本と設計書に足す`

---

### Task 2: 第5章 `04-repeat-observation`（問い・手直し）

**今の問題:** 副題「速さだけで、理由を決めない。」と断り書き、文字14〜21、代替テキストが見出しと同じ。問いの箱が実験の前に「時間が変わった」と言っている。観察ノートの地が問いの箱の色（`#fff0d3`）。表のファイルが描かれていない。

**問い:** 同じ検索を2回目に実行するとき、ページをまた表のファイルから取り寄せるのか。

**数値と出典:** `books/postgresql-query-journey/05-memory-and-buffers.md` の7行目（ページを追い出してから同じ検索を3回実行する）、11行目（同じページを最初から取り寄せるのか）、13行目（観察ノートに並べる）、106行目の予想の3項目（`shared hit`・`shared read`・`Rows Removed by Filter`）。値（1回目 `shared read=8` など）は描かない（106行目の予想の答え）。

**描く（問いの型。背景 `#fffdf7`）:**
- 見出し：`同じ検索を、もう一度`（今のまま）。札は付けない。
- 上：画面の枠（部品見本）「題名で1冊を検索」。中に「同じSQLを3回」。
- 下：ストレージの枠（部品見本）の中に「表のファイル」（`.file`）。
- ファイルから画面へ、2本の矢印（`.flow`）。1本目のラベル「1回目：取り寄せる」（追い出した後なので前提）、2本目のラベル「2回目：？」。「2回目：？」を焦点の枠（`.hot`）にする。
- 右（または横）：観察ノート（`.panel`、白い地）「観察ノート」と3項目（等幅の名前）「`shared hit` ？」「`shared read` ？」「`Rows Removed by Filter` ？」。
- 最下：問いの箱「2回目も、ここから取り寄せる？」。

**焦点:** 「2回目：？」。

**描かない:** 値（答え）、メモリと共有バッファ（次の節で説明する）、実行時間、人物、断り書き。

**参考にする図:** `images/postgresql-query-journey/sources/00-reading-service.svg`（問いの型の画面の枠と問いの箱）、`03-storage-question.svg`（第4章の問い）、Task 1 の部品見本。

**本文:** `books/postgresql-query-journey/05-memory-and-buffers.md` の15〜16行目。前後の文は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/05-memory-and-buffers.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![同じ検索を、もう一度](/images/postgresql-query-journey/04-repeat-observation.png)',
     '![同じ検索を3回実行するとき、1回目は表のファイルからページを取り寄せる。2回目も取り寄せるのかを、shared hit・shared read・Rows Removed by Filterの三つで観察する](/images/postgresql-query-journey/04-repeat-observation.png)'),
    ('*学ぶきっかけを描く、説明用の場面。*',
     '*2回目の「？」と、観察ノートの三つの項目を見てください。値は、この後の実行で確かめます。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `同じ検索を、もう一度`、`description` は `問い：2回目も表のファイルからページを取り寄せるか`。

**コミット:** `docs(query-journey): 第5章の入口の絵を、表のファイルと観察ノートの三つの項目で問う形にする`（本文：`問いの箱が実験の前に「時間が変わった」と言い、観察ノートの地が問いの箱の色だった。表のファイルから取り寄せる1回目と「？」の2回目を描き、ノートの項目を106行目の予想の三つにした。副題と断り書きは外した。`）

---

### Task 3: 第5章 `shared-buffer-reuse`（仕組み・手直し）

**今の問題:** 縦横比1.42。副題が断り書き、「。」の文、文字21。OSキャッシュからストレージへの枝が一本道に見える（ストレージへ行くのは OSキャッシュにもないときだけ）。共有バッファの中のページを旧来の緑の行カードで描いている。

**問い:** ページはどこから共有バッファへ来て、次の検索でどう使われるか。

**数値と出典:** `books/postgresql-query-journey/05-memory-and-buffers.md` の20〜24行目（ストレージとメモリ、共有バッファ、図の上側がメモリ・下側がストレージ）、29〜34行目（`shared hit`＝共有バッファにあった、`shared read`＝なくてファイルから読み込んだ）、36行目（OSキャッシュ。`read` でも OSキャッシュから読まれることがある）。ページの番号は説明用の「P7」（今のキャプションの「ページ7」）。

**描く:**
- 見出し：`読み込んだページを、次も使う`。札「模型」（幅68、x=548）。
- 上：メモリ（RAM）の枠の中に、共有バッファ（`.buffer`。ページはタブ付きの `.page`「P7」で、`04-memory-regions` と同じ書き方）と OSキャッシュ（`.panel`）。
- 下：ストレージの枠（部品見本）の中に「表のファイル」（`.file`）と、その中のページ「P7」。
- 番号付きの経路（番号は実際に起きる順。ラベルに「→」を使わない）：
  - ① 検索が共有バッファで探す（`.req`）。
  - ② 共有バッファになければ、OSキャッシュで探す（`.req`）。
  - ③ OSキャッシュにもなければ、ストレージの表のファイルから読む。②で見つかれば③は通らないことを、ラベル「なければ」と枝の形で示す。
  - ④ ページを共有バッファに置く（`.flow`）。ラベル「④ 置く＝`shared read`」。
  - ⑤ 次の検索が、①で共有バッファのページを使う。①〜④とは別の検索として描く（「次の検索」の箱を分ける）。ラベル「⑤ 使う＝`shared hit`」。
- ⑤のラベルを焦点の枠（`.hot`）にする。
- 今の図の説明の行（「実行中にデータを置いて使う場所」「ここにあれば、SSDまで読みに行かずに済む」など）は外し、縦横比を1.3以下にする。

**焦点:** ⑤ `shared hit`。

**描かない:** 「バックエンド」の語、行を比べる仕事（38行目の問い）、実際の回数。

**参考にする図:** `images/postgresql-query-journey/sources/04-memory-regions.svg`（共有バッファとタブ付きのページ）、`05-limit-search.svg`（`.req` と `.flow`）、Task 1 の部品見本。

**本文:** `books/postgresql-query-journey/05-memory-and-buffers.md` の26〜27行目。前後の文は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/05-memory-and-buffers.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![メモリの中の共有バッファとOSキャッシュ、ストレージの中の表ファイルの関係](/images/postgresql-query-journey/shared-buffer-reuse.png)',
     '![検索が共有バッファにないページをOSキャッシュから、そこにもなければストレージの表のファイルから読み、共有バッファに置く（shared read）。次の検索は共有バッファのページを使う（shared hit）](/images/postgresql-query-journey/shared-buffer-reuse.png)'),
    ('*読み込み経路の模型。ページ7は説明用の番号です。メモリに残っている間は、別の接続からも使えます。*',
     '*④で共有バッファに置いたページを、⑤の次の検索がそのまま使います（読み込み経路の模型。P7は説明用のページ番号）。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `読み込んだページを、次も使う`、`description` は `仕組み：共有バッファ・OSキャッシュ・ストレージの読み込み経路（模型）`。

**コミット:** `docs(query-journey): 第5章の読み込み経路の図に、OSキャッシュの枝と shared read・hit の番号を描く`（本文：`OSキャッシュからストレージへの枝が一本道に見え、共有バッファのページを緑の行カードで描いていた。①〜⑤の番号付きの経路にし、ストレージへ行くのは OSキャッシュにもないときだけと枝で示した。説明の行と副題を外して縦を収めた。`）

---

### Task 4: 第5章 新規 `04-two-levels`（観察・実測）

**問い:** 同じ検索を3回実行して、何が変わり、何が変わらなかったか。

**数値と出典:** `books/postgresql-query-journey/05-memory-and-buffers.md` の116〜146行目の3回の出力と150〜156行目の表（1回目 `shared read=8`、2・3回目 `shared hit=8`、`Rows Removed by Filter: 999` が3回とも、返した行 `rows=1.00`、調べた行1,000）、90行目（2026年9月25日、PostgreSQL 18.6）、100行目（表本体8ページ）、158〜162行目の説明。ログは `_drafts/postgresql-query-journey/verification/chapter05-evict-20260925.log`（99〜130行目）。`Planning` の値（`shared hit=11`、173行目で別物と断っている）と時間（168行目で理由を言えないとしている）は使わない。

**描く（観察の型）:**
- 見出し：`ページは再利用、行は毎回比べる`。札「実測」（`.real`、幅68、x=548）。
- 3列（「1回目」「2回目」「3回目」）×2段。
- 上段「ページ（8ページ）」：各列にページのアイコン8枚（`03-row-width` の小さなページのアイコン）。1回目は表のファイルから読んだ見た目（ストレージの色の小さな印や、下からの矢印など）で等幅の `shared read=8`、2回目と3回目は共有バッファにあった見た目で `shared hit=8`。見た目の違いは色だけにせず、印か矢印を添える。
- 下段「比べた行（1,000行）」：各列に同じ長さの量の帯（`.band`）で、除外999と一致1（`.match` の小さな印）。段の見出しの近くに等幅で `Rows Removed by Filter: 999` を1か所。
- 下段の3本の帯をまとめて焦点の枠（`.hot`）で囲む。

**焦点:** 下段の、3回とも同じ1,000行の帯。

**描かない:** 時間、`Planning` の値、追い出しの11ページ、行の中身、メモリの配置（次の節）、「バックエンド」の語。

**参考にする図:** `images/postgresql-query-journey/sources/05-limit-bands.svg`・`01-scan-and-filter.svg`（観察の帯）、`03-row-width.svg`（ページのアイコン）、`07-sort-bands.svg`（観察の型の段）。

**本文:** 162行目の段落と164行目の段落の間に、図の直前の1文・図・キャプションを入れる。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/05-memory-and-buffers.md')
text = path.read_text(encoding='utf-8')
anchor = 'SQLも、返る1行も、3回とも同じです。'
block = ('図で、3回分のページの使い方と、比べた行の数を見比べてください。\n\n'
         '![1回目は8ページをすべてファイルから読み（shared read=8）、2回目と3回目は共有バッファの8ページを使った（shared hit=8）。比べた行は3回とも1,000行で、999行を除外した](/images/postgresql-query-journey/04-two-levels.png)\n'
         '*ページは2回目から共有バッファのものを使い、比べた行は3回とも1,000行です（2026年9月25日の実測）。*\n\n')
assert text.count(anchor) == 1
text = text.replace(anchor, block + anchor)
path.write_text(text, encoding='utf-8')
```

**catalog.json（第5章の `shared-buffer-reuse` の直後）:** `{"name": "04-two-levels", "chapter": 5, "title": "ページは再利用、行は毎回比べる", "description": "観察：3回の実行のページの使い方と比べた行（実測）"}`

**コミット:** `docs(query-journey): 第5章に、ページの使い方と比べた行を3回分並べる観察の図を足す`（本文：`ページは2回目から共有バッファのものを使い、比べた行は3回とも1,000行だったことを、3回分の列で並べる。2026-09-25 に追い出してから測り直した本文の出力（1回目 shared read=8、2・3回目 shared hit=8、Rows Removed by Filter 999）を使った。`）

---

### Task 5: 第6章 `02-client-scene`（問い・手直し）

**今の問題:** 副題・断り書き・「。」の文、文字14〜21、代替テキストが見出しと同じ。画面が一つで、問い（psqlを二つ開いたら）と合わない。「バックエンド」を描いていて、答えを見せている。

**問い:** psqlを二つ開いたら、SQLを受け取る側も二つになるか。

**数値と出典:** `books/postgresql-query-journey/06-process-and-execution.md` の11行目（psqlを二つ開き、接続先で動くプログラムを調べる）、13行目（クライアント。SQLを受け取って処理するのはサーバ側）、41〜44行目（別のターミナルで同じコマンドで接続）。答え（62・64行目の PID とバックエンドプロセス）は描かない。

**描く（問いの型。背景 `#fffdf7`）:**
- 見出し：`SQLを受け取る側は、いくつ？`。札は付けない。
- 左：画面の枠（部品見本）を二つ上下に「ターミナルA：psql」「ターミナルB：psql」。
- 右：枠「PostgreSQL（サーバ）」の中に、受け取る側の場所を破線の枠で1つ描き、中に大きく「？」（数を描かない）。
- 二つの画面から「？」へ、茶の破線の矢印（`.req`）を1本ずつ。ラベル「SQLを送る」は1か所。
- 「？」を焦点の枠（`.hot`）にする。
- 最下：問いの箱「psqlを二つ開いたら、受け取る側も二つ？」。
- 二つの画面の位置と大きさは、Task 6 の `02-connections` がそのまま写す。報告に座標を書く。

**焦点:** 「？」。

**描かない:** 「バックエンド」の語、PID、共有バッファ・作業領域、人物、断り書き。

**参考にする図:** `images/postgresql-query-journey/sources/01-search-window.svg`（依頼の茶の破線）、`00-reading-service.svg`（画面の枠と問いの箱）、Task 1 の部品見本。

**本文:** `books/postgresql-query-journey/06-process-and-execution.md` の15〜16行目。前後の文は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/06-process-and-execution.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![画面の向こうで、SQLが動く](/images/postgresql-query-journey/02-client-scene.png)',
     '![二つのターミナルのpsqlからSQLを送ると、サーバで受け取る側がいくつになるかは「？」のまま](/images/postgresql-query-journey/02-client-scene.png)'),
    ('*学ぶきっかけを描く、説明用の場面。矢印はSQLを送る向きです。*',
     '*二つのpsqlから送ったSQLを、サーバの中で受け取るのは何か。「？」の中身を、この後で確かめます。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `SQLを受け取る側は、いくつ？`、`description` は `問い：psqlを二つ開いたときのサーバ側`。

**コミット:** `docs(query-journey): 第6章の入口の絵を、二つのpsqlと「？」で問う形にする`（本文：`画面が一つで、問いの「二つ開いたら」と合わず、「バックエンド」を描いて答えを見せていた。二つのターミナルから SQL を送る先を「？」にし、問いの箱を1文にした。`）

---

### Task 6: 第6章 `02-connections`（仕組み・描き直し。Task 5 の後）

**今の問題:** 副題が断り書き、「。」の文、代替テキストが見出しと同じ。旧来のクラスで描いている。

**問い:** 二つの接続で、SQLを処理するプロセスはどうなっているか。

**数値と出典:** `books/postgresql-query-journey/06-process-and-execution.md` の33・39・62行目（接続Aの PID `952`）、58・62行目（接続Bの PID `22521`）、64行目（接続ごとにバックエンドプロセス）、69行目（二つのバックエンドプロセスが同じDBに接続、DBの複製は作られない）。PID は2026-09-22 のユーザー提供の実行例（`_drafts/postgresql-query-journey/verification/first-draft-20260922/README.md` 52行目）。

**描く:**
- 見出し：`接続ごとにプロセスが動く`（今のまま）。札「模型」。
- 上：Task 5 で承認された `02-client-scene.svg` の二つの画面（「ターミナルA：psql」「ターミナルB：psql」）を、同じ位置・大きさで写す。
- 中：各画面から、それぞれの「バックエンドプロセス」の箱へ `.req`「SQLを送る」（`02-client-scene` と同じ書き方）。箱の中に等幅で `PID 952`、`PID 22521`。
- 下：二つのバックエンドプロセスから、一つのストレージの枠（部品見本）の中の「DB（表のファイル）」（`.file`）へ、細い灰色の矢印（`.ref`）。ラベル「同じDBを使う」は1か所。
- 二つのバックエンドプロセスの箱を焦点の枠（`.hot`、比べる2枚）にする。
- 作業領域と共有バッファは描かない（156〜162行目の節で、第5章の図とプロセスを対応させるため）。

**焦点:** 二つのバックエンドプロセス（PID 952・22521）。

**描かない:** 作業領域・共有バッファ・メモリ、第5章の値カード、時間、`pg_stat_activity` の出力。

**参考にする図:** Task 5 の `images/postgresql-query-journey/sources/02-client-scene.svg`（画面をそのまま写す）、`04-memory-regions.svg`（接続を横に並べる配置）、Task 1 の部品見本。

**本文:** `books/postgresql-query-journey/06-process-and-execution.md` の66〜67行目。前後の文は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/06-process-and-execution.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![接続ごとにプロセスが動く](/images/postgresql-query-journey/02-connections.png)',
     '![二つのターミナルのpsqlが、それぞれ別のバックエンドプロセス（PID 952と22521）につながり、二つとも同じDBを使う](/images/postgresql-query-journey/02-connections.png)'),
    ('*PIDは今回の例。配置は共有範囲を示す模型です。*',
     '*接続ごとに別のバックエンドプロセスが動き、DBは一つのままです（PIDは今回の実行例。配置は模型）。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `接続ごとにプロセスが動く`、`description` は `仕組み：接続ごとのバックエンドプロセスと同じDB（模型）`。

**コミット:** `docs(query-journey): 第6章の接続の図を、二つのpsqlと二つのバックエンドプロセスと同じDBで描き直す`（本文：`副題と文が画像の中にあり、旧来の部品で描いていた。入口の絵と同じ位置の二つのターミナルから、PID 952・22521 の二つのバックエンドプロセスへつなぎ、同じDBを使う形にした。作業領域と共有バッファは、156行目の節で扱うので描いていない。`）

---

### Task 7: 第6章 `02-execution-tree`（仕組み・描き直し）

**今の問題:** 副題、文字21、縦横比1.34。出力の値（`rows=3`・`rows=1000000`）がノードにない。旧来のクラス。設計書は型を「観察」としていたが、出力は `EXPLAIN` だけで実測の行数がない（145行目）。

**問い:** `Limit` は `Index Scan` から何行を受け取り、いつ要求を止める計画か。

**数値と出典:** `books/postgresql-query-journey/06-process-and-execution.md` の138〜141行目の出力（`Limit  (cost=0.42..0.57 rows=3 width=30)`、`Index Scan using books_title_idx on books  (cost=0.42..49666.10 rows=1000000 width=30)`）、143〜152行目（Limit が3行まで受け取る、`rows=1000000` は最後まで実行した場合の見積もり、EXPLAIN だけなので実際の行数はない、上が下に次の1行を要求し3行で止める）。ログは `_drafts/postgresql-query-journey/verification/million-start-20260923/million-followup-2026-09-23.txt` 62〜67行目。

**描く（仕組み・模型。計画の木は親が上・子が下・行は下から上）:**
- 見出し：`Limitは3行で要求を止める`。札「模型」。
- 上のノード（`.node`）：等幅で `Limit`、横に `rows=3`（見積もり）。
- 下のノード（`.node`）：等幅で `Index Scan using books_title_idx on books`、横か下に `rows=1000000`（見積もり）。ノード名は出力と同じ字面。
- 二つのノードの間：右に下向きの `.req`「次の行を要求」、左に上向きの `.flow`「行を返す」（147行目「左の矢印が行を返す向き、右が次の行を要求する向き」のまま）。要求と行に①②③を付けて3往復を示す（実際にその順に起きる）。
- 4回目：茶の破線に紺の文字の×、ラベル「4回目は要求しない」。これを焦点の枠（`.hot`）にする。
- 下のノードの下：Index の項目の帯（題名の順）。先頭の3件を①②③の小さなカード、その先は「…」と `.ghost` の破線で「4件目から先は要求されない」（「読まない」とは書かない。Index はページ単位で読むため）。
- 「psqlへ結果を返す」の箱は描かない。

**焦点:** 「4回目は要求しない」。

**描かない:** 実際の行数・時間・Buffers（出力は EXPLAIN だけ）、題名の文字列（出典がない）、Index の葉の枚数、行数に比例した帯、「実測」の札。

**参考にする図:** `images/postgresql-query-journey/sources/05-limit-search.svg`（試作。`.node`・`.req`・`.flow`・「もう求めない」の×）、`07-sort-bands.svg`・`09-loops.svg`（計画のノードの値の書き方）。

**本文:** `books/postgresql-query-journey/06-process-and-execution.md` の149〜150行目。前後の文は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/06-process-and-execution.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![Index Scanが題名順に1行ずつ返し、Limitが3行で要求を止める](/images/postgresql-query-journey/02-execution-tree.png)',
     '![Limitが次の行を3回要求し、Index Scanが題名の順に3行を返す。4回目は要求しない。出力の見積もりはLimitがrows=3、Index Scanがrows=1000000](/images/postgresql-query-journey/02-execution-tree.png)'),
    ('*直前のIndex ScanとLimitの計画に対応する模型。実測した行数の図ではありません。*',
     '*①〜③の3往復の後、4回目の要求をしないことを見てください（直前の計画に対応する模型。rowsは見積もり）。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `Limitは3行で要求を止める`、`description` は `仕組み：LimitとIndex Scanの要求と行の受け渡し（模型）`。

**コミット:** `docs(query-journey): 第6章の計画の木の図に、出力の見積もりと3往復の要求を描く`（本文：`出力の値がノードになく、旧来の部品で描いていた。Limit と Index Scan のノードに出力の見積もり（rows=3・rows=1000000）を添え、①〜③の要求と行の3往復と、4回目は要求しないことを描いた。EXPLAIN だけの出力なので、実測の札と行数の帯は付けていない。`）

---

### Task 8: 第7章 `07-recent-records`（問い・手直し）

**今の問題:** 副題・断り書き・「。」の文、文字14〜21、代替テキストが見出しと同じ。記録の色が並んだ位置で変わる。問いの箱が旧来の書き方。

**問い:** 1週間分（約50万件）の記録を新しい順に並べるには、どうするか。

**数値と出典:** `books/postgresql-query-journey/07-sort.md` の11〜13行目、18〜26行目の SQL（`ORDER BY finished_at DESC, book_id ASC`、26行目「日時が同じ場合は本の番号順」）、約50万件＝88行目の `rows=499998.00`（134行目「約50万行」）。`finished_at` は日時。同じ日時の2件は模型だけの例（実データの200万件は日時がすべて異なる）。

**描く（問いの型。背景 `#fffdf7`）:**
- 見出し：`読み終えた順に、並べたい`（今のまま）。札は付けない。
- 左：入っている順の記録カード（白い行カード `.row`、「本番号・日時」）4枚：「本4・9月16日 10:00」「本8・9月14日 09:30」「本5・9月20日 08:00」「本2・9月20日 08:00」。
- 中：太い白抜きの矢印（`.step`）「新しい順に並べる」。
- 右：画面の枠（部品見本）「最近の読了記録」に、並べた後の4枚「本2・9月20日 08:00」「本5・9月20日 08:00」「本4・9月16日 10:00」「本8・9月14日 09:30」。同じ日時の2枚（本2・本5）を焦点の枠（`.hot`）で囲み、ラベル「同じ日時なら、本の番号順」。
- 最下：問いの箱「1週間分（約50万件）なら、どう並べる？」。

**焦点:** 右の画面の、同じ日時の2枚。

**描かない:** 色で記録を見分けさせる塗り、並べ方の答え（比較・Sort）、人物、断り書き。

**参考にする図:** `images/postgresql-query-journey/sources/00-reading-service.svg`（画面の枠・行カード・問いの箱）、Task 1 の部品見本。

**本文:** `books/postgresql-query-journey/07-sort.md` の15〜16行目。前後の文は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/07-sort.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![読み終えた順に、並べたい](/images/postgresql-query-journey/07-recent-records.png)',
     '![入っている順の4件を、新しい日時の順に並べ直す。日時が同じ2件は本の番号順になる](/images/postgresql-query-journey/07-recent-records.png)'),
    ('*学ぶきっかけを描く、説明用の場面。*',
     '*日時が同じ2件は、本の番号順に並びます（説明のための場面。実際の200万件に同じ日時の記録はありません）。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `読み終えた順に、並べたい`、`description` は `問い：約50万件の記録を新しい順に並べる`。

**コミット:** `docs(query-journey): 第7章の入口の絵を、白い記録カードと同じ日時の2件で描き直す`（本文：`記録の色が並んだ位置で変わり、日付だけで並べていた。白い行カードに本番号と日時を書き、同じ日時の2件が本の番号順になる所を焦点にした。問いは「1週間分（約50万件）なら、どう並べる？」にした。`）

---

### Task 9: 第7章 `07-merge-cards`（仕組み・描き直し）

**今の問題:** 副題が断り書き、代替テキストが見出しと同じ、縦横比1.38。並べる前の4枚（1段目）がなく、比較の回数が分からない。旧来の緑のカード。

**問い:** 8・3・6・1の4枚を並べるのに、何回比べるか。

**数値と出典:** `books/postgresql-query-journey/07-sort.md` の30行目（8、3、6、1を8、6、3、1にする。数字が大きいほど新しい）、32行目（二つの小さな並びを作って合流する模型。この図は比較して順序を作る点だけを示す）、37行目（比較ソート、O(n log n)）。図で新しく出す数は、この模型で数えた「比較5回・2段」だけ。

**描く:**
- 見出し：`4枚を、比較5回で並べる`。札「模型」。
- 上：入力の値カード（`.val`）4枚「8」「3」「6」「1」。
- 1段目：二組に分けて比べる。「8と3」から [8, 3]（札「比較1」）、「6と1」から [6, 1]（札「比較2」）。
- 2段目：二つの並びの先頭同士を比べて合流する。8と6 から8（比較3）、3と6 から6（比較4）、3と1 から3（比較5）、残りの1はそのまま。出力 [8, 6, 3, 1]。
- 札「比較1」〜「比較5」は小さな灰色の札。比べた2枚を細い線で結ぶ。
- 下に数のまとめ「4枚なら 比較5回・2段」を焦点の枠（`.hot`）にする。
- 2段目の比べ方の見た目は、Task 10 の `07-external-sort` の合流がそのまま写す。

**焦点:** 「4枚なら 比較5回・2段」。

**描かない:** 499,998行、19段、PostgreSQL のソートの名前（quicksort など）。

**参考にする図:** `images/postgresql-query-journey/sources/06-tree-levels.svg`（数のまとめの焦点）、部品見本の値カード。

**本文:** `books/postgresql-query-journey/07-sort.md` の34〜35行目。前後の文は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/07-sort.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![二つの並びを、比べながら合流する](/images/postgresql-query-journey/07-merge-cards.png)',
     '![8・3・6・1を二組に分けて2回比べ、二つの並びの先頭同士を3回比べて合流し、8・6・3・1にする。比較は合わせて5回で2段](/images/postgresql-query-journey/07-merge-cards.png)'),
    ('*比較の模型で、PostgreSQLの実装そのものではありません。*',
     '*比べるたびに付けた番号で、4枚なら5回の比較で並ぶことを見てください（比較の模型。PostgreSQLの実装そのものではありません）。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `4枚を、比較5回で並べる`、`description` は `仕組み：二組に分けて比べ、合流する比較の回数（模型）`。

**コミット:** `docs(query-journey): 第7章の比較の図を、4枚から比較5回で並べる2段の図にする`（本文：`並べ済みの二組から始まり、比較の回数が分からなかった。8・3・6・1から二組を作る2回と、合流の3回に「比較1〜5」の札を付け、「4枚なら比較5回・2段」を焦点にした。設計書にあった「499,998行なら約19段」は、出典がなく実際の Sort とも違うので入れていない。`）

---

### Task 10: 第7章 `07-external-sort`（仕組み・描き直し。Task 9 の後）

**今の問題:** 副題が断り書き、代替テキストが見出しと同じ、縦横比1.55。作業用メモリを実線の塗りで描き、一時ファイルがストレージの中にない。

**問い:** 作業用メモリに2枚しか置けないとき、4枚をどう並べるか。

**数値と出典:** `books/postgresql-query-journey/07-sort.md` の142行目（置けない分を別の場所へ置き、最後に合流させる＝外部ソート）、144行目（机は `work_mem` で決まる作業用メモリ、置き場は一時ファイル。並べたまとまりを一時ファイルへ書き、最後に読み戻して合流させる）、30行目の値（8・3・6・1）。図の数は模型の「2枚分」だけ。出力の項目名（external merge・Disk・temp）と値は描かない（166行目で読者が確かめる前のため）。

**描く:**
- 見出し：`メモリに収まらないときの並べ替え`（今のまま）。札「模型」。
- ① 作業用メモリ（`.work` の破線の枠「作業用メモリ（2枚分）」）に 8・3 を入れて並べ、[8, 3] を下のストレージの一時ファイルへ「書き出す」（`.flow`）。続けて 6・1 も同じく [6, 1]。
- ストレージの枠（部品見本）の中に「一時ファイル」（`.file`）、その中にまとまりA [8, 3]・まとまりB [6, 1]。一時ファイルを焦点の枠（`.hot`）にする。
- ② 二つのまとまりの先頭から少しずつ「読み戻す」（`.flow`）。作業用メモリ（2枚分）には先頭同士の2枚だけを置いて比べ、出力 8・6・3・1 は枠の外に置く。比べる単位（値カード2枚・`.leader` の括弧線・薄い札 `.cmp`・札から出る `.flow`）は Task 9 の `07-merge-cards.svg` を写すが、3組を横に並べる形と「比較n」の番号は写さない（札の文字は「比べる」）。

**焦点:** 一時ファイル。

**描かない:** external merge・Disk・temp read/written の名前と値、work_mem の実際の値（64kB・64MB）、時間、「先頭だけ読む」の言い方（最後にはほぼすべて読み戻すため）。

**参考にする図:** Task 9 の `images/postgresql-query-journey/sources/07-merge-cards.svg`、`07-sort-bands.svg`（作業用メモリの枠）、Task 1 の部品見本のストレージとファイル。

**本文:** `books/postgresql-query-journey/07-sort.md` の146〜147行目。前後の文は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/07-sort.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![メモリに収まらないときの並べ替え](/images/postgresql-query-journey/07-external-sort.png)',
     '![作業用メモリに2枚ずつ入れて並べたまとまりを一時ファイルへ書き出し、二つのまとまりを少しずつ読み戻して合流し、8・6・3・1にする](/images/postgresql-query-journey/07-external-sort.png)'),
    ('*外部ソートの模型。まとまりの個数と容量は模式的です。*',
     '*並べたまとまりを一時ファイルへ書き出し、少しずつ読み戻して合流します（外部ソートの模型。まとまりの数と大きさは縮めています）。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `メモリに収まらないときの並べ替え`、`description` は `仕組み：作業用メモリと一時ファイルを使う外部ソート（模型）`。

**コミット:** `docs(query-journey): 第7章の外部ソートの図を、作業用メモリと一時ファイルの部品で描き直す`（本文：`作業用メモリを実線の塗りで描き、一時ファイルがストレージの中になかった。破線の作業用メモリ（2枚分）からストレージの一時ファイルへ書き出し、少しずつ読み戻して合流する形にした。出力の項目名は、読者が64kBで確かめる前なので描いていない。`）

---

### Task 11: 第8章 `08-twenty-window`（問い・手直し）

**今の問題:** 副題、断り書き、文字14〜21、代替テキストが見出しと同じ。記録が並べ済みで答えを見せている。画面の「残りの順位は不要」も答え。「調べる」の語が第7章（200万行）と第8章（499,998行）で指す物が違う。

**問い:** 画面に出すのは20件。`LIMIT 20` で減るのは、読む行・持つ行・返す行のどれか。

**数値と出典:** `books/postgresql-query-journey/08-top-n-heap.md` の11行目（対象週の499,998行、画面は20件）、18〜30行目（`LIMIT 20`）、33行目の予想の3項目（読む行数、候補として持つ行数、返す行数）。答え（69・72行目）は描かない。

**描く（問いの型。背景 `#fffdf7`）:**
- 見出し：`画面に欲しいのは、最新20件`（今のまま）。札は付けない。
- 左：並びがばらばらの記録カード（白い行カード「本番号・日付」、日付を不ぞろいに5枚と「⋮」）と「対象週 約50万件」。この山を焦点の枠（`.hot`）で囲む。
- 右：画面の枠（部品見本）「最近の読了記録」に「20件」。
- 下：三つの枠を横に並べる「読む ？件」「持つ ？件」「返す 20件」（「調べる」は使わない）。
- 最下：問いの箱「LIMIT 20で、減るのはどれ？」（`LIMIT 20` は等幅）。

**焦点:** 左の約50万件の記録の山。

**描かない:** 並べ済みの並び、「残りの順位は不要」、ヒープ、答えの数、人物、断り書き。

**参考にする図:** `images/postgresql-query-journey/sources/00-reading-service.svg`、Task 1 の部品見本。

**本文:** `books/postgresql-query-journey/08-top-n-heap.md` の13〜14行目。前後の文は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/08-top-n-heap.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![画面に欲しいのは、最新20件](/images/postgresql-query-journey/08-twenty-window.png)',
     '![並びがばらばらの約50万件から、画面に最新20件を出す。読む件数と持つ件数は「？」、返すのは20件](/images/postgresql-query-journey/08-twenty-window.png)'),
    ('*学ぶきっかけを描く、説明用の場面。*',
     '*読む・持つ・返すの三つのうち、LIMIT 20で減るのはどれかを考えてください（説明のための場面）。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `画面に欲しいのは、最新20件`、`description` は `問い：LIMIT 20で減るのは、読む・持つ・返すのどれか`。

**コミット:** `docs(query-journey): 第8章の入口の絵を、ばらばらの約50万件と読む・持つ・返すの三つの枠で問う形にする`（本文：`記録を並べ済みで描き、画面に「残りの順位は不要」と答えを書いていた。ばらばらの約50万件から20件を出す場面にし、33行目の予想の語で「読む？件・持つ？件・返す20件」の枠を置いた。「調べる」は第7章と指す物が違うので使っていない。`）

---

### Task 12: 第8章 `top-three-heap`（仕組み・手直し）

**今の問題:** 縦横比2.80（本の中で最も縦長）。副題が断り書き、「。」で終わる文が9つ。届く順と、そのコマで読んだ位置がない。

**問い:** 上位3枚を保つとき、届いたカードと根を比べて、入れ替えるのはいつか。

**数値と出典:** `books/postgresql-query-journey/08-top-n-heap.md` の37行目（届く順 8、3、5、9、2）、39・41行目（最小ヒープ、根が最小）、45〜56行目（1コマ目：根3・左8・右5。2コマ目：3を外して9を根へ。3コマ目：小さいほうの子5と9を交換して根5・左8・右9。4コマ目：2は根5より小さいので入れない）。

**描く（1枚のまま2×2のコマにし、縦を収める。本文の「1コマ目」〜「4コマ目」はそのまま使える）:**
- 見出し：`根の最小値と比べて、入れ替える`。札「模型」。
- コマに①〜④の番号を付け、左上・右上・左下・右下の順に置く（目安：コマ1つ幅296・高さ340前後、全体の高さ832以下）。
- 各コマの上に届く順の帯「8 3 5 9 2」を小さな値カードで描き、そのコマで届いたカードの上に「▼」（①②③は9、④は2）。
- ① 根3（左8・右5）と届いた9を比べる（比べる2枚を `.hot`）。「根＝候補の最小値」のラベルは①に1か所だけ。
- ② 3を外し（破線＋灰色の×、ラベル「候補の外へ」）、9を根へ。9と小さいほうの子5に、交換の札（設計書4.3の「太枠＋札」。札の語は本文52行目の「交換」。62行目は候補を替えることを「入れ替え」、値を取り替えることを「交換」と分けているので、「入れ替え」は使わない）。
- ③ 根5・左8・右9。
- ④ 届いた2と根5を比べ、2は候補に入れない（2の横に紺の文字の×）。
- 各コマの中の説明の文は描かない（本文50〜54行目が説明する）。

**焦点:** 各コマ1か所（①は比べる2枚）。

**描かない:** 出力順に並べ直す最後の手順（54行目）、PostgreSQL のメモリ配置、100が来る話（60行目）。

**参考にする図:** `images/postgresql-query-journey/sources/06-btree-path.svg`（木の枝）、`06-range-scan.svg`（紺の文字の×）、部品見本の値カードと札。

**本文:** `books/postgresql-query-journey/08-top-n-heap.md` の47〜48行目。前後の文は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/08-top-n-heap.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![根3の最小ヒープに9が届き、3を除いて9と5を交換し、根5になる。次の2は候補に入れない4コマの図](/images/postgresql-query-journey/top-three-heap.png)',
     '![届く順8・3・5・9・2のうち、9が根の3より大きいので3を外して9を根へ入れ、小さい子の5と交換して根を5にする。次の2は根の5より小さいので候補に入れない](/images/postgresql-query-journey/top-three-heap.png)'),
    ('*大きい値を上位3枚に残す説明用の模型。カードは行に対応します。PostgreSQL内部の実際のメモリ配置を示した図ではありません。*',
     '*各コマの上の▼が、いま届いたカードです。根の最小値と比べて、入れ替えるかを決めます（説明のための模型。カードは行に対応します）。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `根の最小値と比べて、入れ替える`、`description` は `仕組み：上位3枚を保つ最小ヒープの4コマ（模型）`。

**コミット:** `docs(query-journey): 第8章のヒープの図を、届く順の帯を付けた2×2のコマで描き直す`（本文：`4コマを縦に並べて縦横比2.80になり、各コマに説明の文があった。2×2のコマにして縦を収め、各コマの上に届く順の帯と「▼」を付けた。外した3は破線と×、入れない2は紺の×にした。`）

---

### Task 13: 第8章 `08-top-n-vs-index`（比較・手直し）

**今の問題:** 副題が断り書き、「。」の文、代替テキストが見出しと同じ、縦横比1.33。橙の太枠が6枚ある。

**問い:** 同じ上位3件を得るのに、読む数と持つ数はどう違うか。

**数値と出典:** `books/postgresql-query-journey/08-top-n-heap.md` の37行目（届く順 8、3、5、9、2）、39・54行目（候補3枚、出力9、8、5）、60行目（順序が分からない入力では最後まで確かめる）、81行目（必要な件数がそろえばその先を調べずに終われる場合がある）、103行目（上位3件を選ぶ模型で、入力の順序が分からない場合と大きい順に取り出せる場合）。図で新しく出す数は、模型から数えた「読む5・持つ3・返す3」と「読む3・持つ なし・返す3」だけ。

**描く（比較の型。上下の2段を同じ配置にする）:**
- 見出し：`全部読むか、3件で止まるか`。札「模型」。
- 上段「順序が分からない入力」：カード 8・3・5・9・2 をすべて読む → 作業用メモリの枠（`.work`「候補（3枚）」）に 9・8・5 → 返す 9・8・5。まとめ「読む5・持つ3・返す3」。
- 下段「大きい順のIndex」：9・8・5 を読み、3・2 は破線（`.ghost`、×なし）でラベル「要求しない」→ 候補の枠はない → 返す 9・8・5。まとめ「読む3・持つ なし・返す3」。
- 下段の「読む3」を焦点の枠（`.hot`）にする（今の6枚の橙はやめる）。
- ノードの列（計画の木）は描かない（101行目で、Indexを作った後の計画を読者が確かめる課題のため）。

**焦点:** 下段の「読む3」。

**描かない:** 計画のノード、実際の20件・499,998行、Heap Fetches・Buffers、時間。

**参考にする図:** `images/postgresql-query-journey/sources/08-sort-vs-topn.svg`（第8章の比較の型と作業用メモリ）、`05-limit-search.svg`（「比べない」の破線）。

**本文:** `books/postgresql-query-journey/08-top-n-heap.md` の105〜106行目。前後の文は変えない。

```python
import pathlib
path = pathlib.Path('books/postgresql-query-journey/08-top-n-heap.md')
text = path.read_text(encoding='utf-8')
pairs = [
    ('![候補を絞る方法と、途中で止まる方法](/images/postgresql-query-journey/08-top-n-vs-index.png)',
     '![順序が分からない入力では5件をすべて読み、候補3件を持って9・8・5を返す。大きい順のIndexなら3件を読んだところで止まり、候補を持たずに9・8・5を返す](/images/postgresql-query-journey/08-top-n-vs-index.png)'),
    ('*大きい順に3件を求める模型。本文は日時順20件。上段の候補は値を示しており、ヒープ内の配置ではありません。*',
     '*同じ3件を返すのに、上は5件を読んで3件を持ち、下は3件を読んで止まります（上位3件を求める模型。本文の実験は日時順20件）。*'),
]
for old, new in pairs:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
```

**catalog.json:** `title` は `全部読むか、3件で止まるか`、`description` は `比較：候補を持って全部読む方法と、Indexの順で3件で止まる方法（模型）`。

**コミット:** `docs(query-journey): 第8章の比較の図で、焦点を読む数の違い1か所にし、要求しない2件を破線にする`（本文：`橙の太枠が6枚あり、どこを比べるかが分からなかった。上下を同じ配置にし、「読む5・持つ3・返す3」と「読む3・持つ なし・返す3」を並べて、下段の「読む3」だけを焦点にした。Indexを作った後の計画は読者が確かめる課題なので、ノードの列は描いていない。`）

---

### Task 14: 一覧を合わせ、記録を更新して ship する（Task 1〜13 の後）

- [ ] **Step 1: Task 2〜13 のコミットを作業ブランチへ cherry-pick する**（コントローラー）
- [ ] **Step 2: catalog.json を各章の本文の順にし（第5章に `04-two-levels` が入る）、README の一覧を catalog から作り直して枚数を53枚にする。** 執筆方針 `books/postgresql-query-journey/AGENTS.md` の図の枚数も53枚にし、第5〜8章の12枚を書き足す。
- [ ] **Step 3: book-flow.html の第5〜8章の図の一覧を本文の順にし、段階Dの12枚のラベルを catalog の見出しにする（`04-two-levels` を足す）。** `node scripts/book-figures/build-index.cjs` で `index.html を更新しました（53枚）`。book-flow.html の第5章の flow・notes の「3回ともhit=8」は範囲外（別の作業で直す）。
- [ ] **Step 4: 設計書を更新する。** 8章の第5〜8章の表で、11枚の判定に「（2026-09-25 直した）」、`04-two-levels` に「新規・中（2026-09-25 描いた）」、`07-work-mem-total` に「見送り（2026-09-25 のユーザーの判断。…）」を付け、「下調べとユーザーの判断」に書いた描き方の変更を各行の直し方に注記する。`04-two-levels` と `04-repeat-observation` のセルは今の本文（1回目 read=8）に合わせる。11章の未決事項に、2026-09-25 の判断を書き足す。
- [ ] **Step 5: 全体を確かめる。** `check-figures.cjs` で、段階Cまでの31枚と段階Dの12枚（`04-repeat-observation shared-buffer-reuse 04-two-levels 02-client-scene 02-connections 02-execution-tree 07-recent-records 07-merge-cards 07-external-sort 08-twenty-window top-three-heap 08-top-n-vs-index`）が `43枚中 43枚が約束を満たしています`。`npm test` で `ℹ pass 12`。章の画像参照53件がすべて実在。`git grep -n "バックエンド" -- images/postgresql-query-journey/sources/04-*.svg images/postgresql-query-journey/sources/shared-buffer-reuse.svg` が出力なし。段階Dの12枚に `transform` がない。
- [ ] **Step 6: コミットし、ブランチ全体をレビューしてから ship する**（PR は main 向け）。
