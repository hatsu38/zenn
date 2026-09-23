# 第1章 設計メモ

対象：`books/sql-data-structures/01-explain-basics.md`（新規、未公開）
作成日：2026-09-21
状態：2026-09-21 ユーザー承認。初稿レビュー後の変更は末尾の「設計からの変更」を参照

## 目的と成果物

序章の末尾で約束した第1章「SQLの動きを観察する道具を手に入れる」を書く。
読者が Docker で実験環境を用意し、`EXPLAIN` と `EXPLAIN ANALYZE` の出力を読めるようになる章にする。

成果物は次の 4 点。

- `books/sql-data-structures/01-explain-basics.md` の初稿
- `books/sql-data-structures/config.yaml` の chapters に `01-explain-basics` を追加
- `_drafts/sql-data-structures/experiments/ch01-setup.sql`、`ch01-explain.sql`、`results/ch01-explain-basics-docker-pg18-20260921.txt`（本文の数値の出典）
- `_drafts/sql-data-structures/experiments/README.md` に第1章の計測条件を追記

## 今日決めたこと

1. つくるのは第1章。単発記事や序章の改稿ではない。
2. 読者の環境は Docker の `postgres:18` と、本文に載せた SQL だけで完結させる。サンプルリポジトリは作らない。
3. 第1章のデータは「開発時の規模」の本 1,000 冊、読了記録 2 万件。100 万冊と 2,000 万件は「データが開発時の規模を超える」章まで増やさない。
4. 扱う範囲は `EXPLAIN` と `EXPLAIN ANALYZE` の読み方まで。コスト式の手計算は `:::details` に置き、`BUFFERS` の読み方は後の章に送る。
5. 主役の SQL は「題名で 1 冊探す」と「番号で 1 冊探す」の 2 本。全件取得は使わない。
6. 章の順序は、動機の会話、環境準備、予想、EXPLAIN、EXPLAIN ANALYZE、番号検索との比較、持ち帰り、次章への引き。
7. 今回は TODO(human) を置かず、初稿を全部書いてからレビューを受ける。

## 章の構成

見出しはトピック直接型にし、区切り記号や補足括弧を付けない。以下は節ごとの中身。

### はじめに

序章のランキングが約 4.6 秒かかった。原因を調べるには、PostgreSQL がどんな手順で処理したかを見る道具が要る。
その道具の使い方を、ランキングより簡単な SQL で覚える、という位置づけを 3 段落前後で書く。
序章と同じ `:::message` で、会話は架空、数値は実測、と断る。

### ランキングの前に、1冊を探すSQLで試す

二人の短い会話。序章の「本の詳細は見られるのに」を受けて、本の詳細画面で使っている「本を 1 冊取り出す SQL」で道具を試すと決める。
二人に名前は付けない。序章と同じく「二人」で通す。

### 実験環境を用意する

Docker が動く前提で、次の手順を載せる。

```bash
docker run --name reading-log-lab \
  -e POSTGRES_PASSWORD=reading-log-local \
  -e POSTGRES_DB=reading_log \
  -d postgres:18
docker exec reading-log-lab pg_isready -U postgres -d reading_log
docker exec -it reading-log-lab psql -X -U postgres -d reading_log
```

続けて、通常テーブルとして `books` と `reading_records` を作る SQL、`generate_series` で 1,000 冊と 2 万件を入れる SQL、`ANALYZE`、件数確認を載せる。
`ANALYZE` は「件数や分布の統計情報を集めるコマンド」と一言で説明し、`EXPLAIN ANALYZE` の `ANALYZE` とは別物だと注意する。
テーブル定義は序章の実験と同じ列と型にする（`books(id bigint PRIMARY KEY, title text NOT NULL)`、`reading_records(book_id bigint NOT NULL, finished_at timestamp NOT NULL)`）。
外部キー制約は付けない。序章の実測と条件を揃えるためで、ER 図では関連線を引きつつ、本文で「制約はまだ付けていない」と書く。

Mermaid の ER 図を 1 枚。直前に「この章と序章で使う 2 つのテーブルの関係を見る」と目的を書き、直後に「読了記録は本を指すが、まだインデックスも制約もない」と読み取れることを書く。

読了記録は第1章では使わない。作る理由は「序章のランキングと同じデータを、後の章でこのまま使うため」と一文で示す。

### 予想する。題名で1冊探すとき、PostgreSQL は何冊調べるか

```sql
SELECT * FROM books WHERE title = '実験用の本 42';
```

結果は 1 行。では、この 1 行を返すために PostgreSQL は何冊を調べたか。読者と二人の予想を置く。

- 1 冊だけ見て終わる
- 1,000 冊を全部見る
- 見つかったところで止まる

二人の会話は 3 行前後。どちらが正しいかは示さない。

### EXPLAIN で実行する予定を見る

`EXPLAIN` を前に付けて実行する。出力は Seq Scan と Filter の 2 行（実測ログの出力をそのまま載せる）。
1 行を表で分解する。ノードの種類、対象テーブル、`cost`、`rows`、`width`。
`Seq Scan` は「表を先頭から順に読む」と言い換える。
`cost` は「秒でもミリ秒でもない、PostgreSQL が手順を比べるための相対値」と説明し、公式 18 文書の「任意の単位」の記述を引用する。
`rows=1` は「返すと見込んだ行数」で、調べる行数ではない、とここで区別する。この区別が章の中心。
コスト式は `:::details` に置き、`seq_page_cost` と `cpu_tuple_cost` の式と、実測の `relpages` で再現できることだけ短く書く。

`EXPLAIN` は SQL を実行しない、と述べ、実測ログの「INSERT を EXPLAIN しても件数が変わらない」確認を根拠として添える。

### EXPLAIN ANALYZE で実際の行数と時間を見る

`EXPLAIN ANALYZE` に変えて実行する。増えた項目を列挙する。

- `actual time=A..B`：最初の 1 行までと全行までの実測ミリ秒
- `actual rows=1.00`：実際に返した行数。PostgreSQL 18 では小数で表示される
- `loops=1`：このノードを何回実行したか
- `Rows Removed by Filter: 999`：条件に合わず捨てた行数
- `Buffers` の行：読んだページ数。この章では読み飛ばし、後の章で扱うと予告
- `Planning Time` と `Execution Time`

答え合わせは `Rows Removed by Filter: 999`。返したのは 1 行、調べたのは 1,000 冊。
公式 18 文書の「実際にその問い合わせを実行し」の一文を引用し、`ANALYZE` は本当に実行するので更新系に打つときは `BEGIN` と `ROLLBACK` で囲む、という公式の手順を紹介する。
`actual time` は毎回少し変わる、を実測 3 回の値で示す。

### 番号で探すと計画が変わる

```sql
SELECT * FROM books WHERE id = 42;
```

同じ 1 冊を番号で探す。`EXPLAIN ANALYZE` の出力は `Index Scan using books_pkey`、`Index Cond`、`actual rows=1.00`、`Rows Removed` の行はない。
「同じ 1 冊を返すのに、題名では 1,000 冊を見て、番号では目録を 1 回引いた」と観察だけする。
主キーを作ったときに PostgreSQL が自動でインデックスを作っていた、という事実を書く。
なぜインデックスだと調べる量が減るのかは、第3章の木構造で扱うと節末に予告する。

行の流れを示す Mermaid のフローチャートを 1 枚。題名検索（1,000 行を読み、Filter で 999 行を捨て、1 行を返す）と番号検索（インデックスで 1 行）を縦に並べる。矢印は行の流れ。
（初稿レビュー後に 2 枚へ変更。末尾の「設計からの変更」を参照）

### この章で持ち帰ること

- `EXPLAIN` は予定を見せるだけで実行しない。`EXPLAIN ANALYZE` は実行して実測を並べる
- `rows` は返す行数。調べた行数は `Rows Removed by Filter` と合わせて見る
- 推定と実測を並べて読む。今回は推定 1 行、実測 1 行で一致した
- 同じ結果を返す SQL でも、計画が違えば仕事の量が違う

### 次の章へ

本が 1,000 冊から 10 万冊、100 万冊になったら、題名検索が読む冊数はどう増えるか。第2章「探す①」で全件探索を計算量から考える、と予告する。
序章のランキングの実行計画は、まだ読まない。

## 実験と数値の扱い

- 計測環境は Docker の `postgres:18`（2026-09-21 時点で PostgreSQL 18.6）。序章の Homebrew 18.3 とは版が違うので、章の `:::details` に版を明記する。
- 設定は Docker の既定値のまま。`work_mem`、並列、JIT は変更しない。読者に SET を打たせない。
- 本文に載せる出力は、実測ログからそのまま転記する。数値を丸めたり作ったりしない。
- `EXPLAIN ANALYZE` は 3 回実行し、本文には 1 回目の出力を載せ、`:::details` に 3 回の `Execution Time` を並べる。
- ログの保存先は `_drafts/sql-data-structures/experiments/results/ch01-explain-basics-docker-pg18-20260921.txt`。再実行手順を `README.md` に書く。
- コンテナ `reading-log-lab` は後の章でも使うため、計測後は `docker stop` で止めるだけにし、削除しない。

### 実測の要点（2026-09-21、Docker postgres:18 = PostgreSQL 18.6）

作業用ディレクトリに保存したログから、本文で使う値を抜き出した。

| 観察するもの | 題名で 1 冊 | 番号で 1 冊 |
| --- | --- | --- |
| ノード | Seq Scan on books | Index Scan using books_pkey on books |
| 条件の行 | Filter: (title = '実験用の本 42'::text) | Index Cond: (id = 42) |
| cost | 0.00..20.50 | 0.28..8.29 |
| rows（推定） | 1 | 1 |
| width | 27 | 27 |
| actual rows | 1.00 | 1.00 |
| Rows Removed by Filter | 999 | 表示なし |
| Execution Time 3 回 | 0.090 / 0.049 / 0.385 ms | 0.147 / 0.272 / 0.041 ms |

- `books` は 8 ページ、`books_pkey` は 5 ページ、`reading_records` は 109 ページ（`pg_class.relpages`）。
- Docker 既定値は `work_mem = 4MB`、`max_parallel_workers_per_gather = 2`、`jit = on`。
- `EXPLAIN ANALYZE` の出力には `Buffers: shared hit=N` と、Index Scan では `Index Searches: 1` が既定で付く。
- `EXPLAIN INSERT INTO books VALUES (1001, ...)` の前後で `count(*)` は 1,000 のまま。

## 文体と制約

- `books/sql-data-structures/AGENTS.md` の執筆方針に従う。
- `japanese-tech-writing` スキルの規範に従う。一文一行、ダッシュ禁止、並列の中黒禁止、LLM 口調の禁止。
- 見出しはトピック直接型。区切り記号、補足括弧、物語的な見出しを付けない。
- 教師口調と断定的な権威付けを避ける。「自分も調べながら書いている」立ち位置。
- 語彙は中学 2 年生に説明するくらいに噛み砕く。専門用語は初出で言い換える。
- 公式ドキュメントを引くときは、PostgreSQL 18 日本語版の URL と `>` 引用と出典行をセットにする。
- 序章の用語と表現を揃える。「読了記録」「本」「二人」「実行計画」。
- 序章で「並べ替えのない簡単なSQL」と予告した通り、この章の SQL に `ORDER BY` は出さない。
- 分量は、序章と同じく面白さと流れをすぐレビューできる長さにする。旧本の第1章より短くてよい。

## 制作の進め方

`subagent-driven-task-execution` の標準モードで進める。

| タスク | 担当 | モデル | 成果物 |
| --- | --- | --- | --- |
| T1 実測 | コントローラー | Fable（本セッション） | 実験 SQL とログ |
| T2 初稿 | 実行担当 | Sonnet | `01-explain-basics.md` |
| T3 独立レビュー | レビュアー | Opus | 要件適合と品質の判定 |
| T4 修正と再レビュー | T2 と T3 を再利用 | Sonnet と Opus | 修正版 |
| T5 全体レビュー | 全体レビュアー | Fable | 序章とのつながりを含む判定 |
| T6 統合 | コントローラー | Fable | config.yaml、README、zenn preview での表示確認 |

T2 の実行担当には、この設計メモ、序章、AGENTS.md、実測ログ、引用候補の文を渡す。会話履歴は渡さない。
T3 と T5 には期待する結論を伝えない。

## 対象外

- 序章の本文の変更
- 100 万冊と 2,000 万件のデータ生成
- `BUFFERS`、コスト式の本文での手計算、複数ノードの実行計画の読み方
- Excalidraw の図。この本は Mermaid を使う
- サンプルリポジトリの作成
- git のコミットと公開設定の変更

## 未確定と残るリスク

- PostgreSQL 18 では `EXPLAIN ANALYZE` に `Buffers` の行が既定で出る。読み飛ばしの一文で足りるかは、初稿レビューで判断する。
- 序章の実測（18.3）と第1章の実測（18.6）で版が違う。各章の `:::details` に版を書いて区別する。後の章で大きなデータを Docker で再計測するときに揃える。
- 二人の会話の量と口調は、初稿を読んでから調整する。

## 設計からの変更（初稿レビュー後、コントローラー判断）

- 行の流れの図は 1 枚ではなく 2 枚にする。題名検索（Seq Scan、Filter、捨てる 999 行、結果 1 行）と番号検索（books_pkey で場所を調べる、books からその行を読む、結果 1 行）をそれぞれ縦一列で描く。Zenn の Mermaid では subgraph の中が横並びになり、スマートフォンで読みにくいため。
- 題名の完全一致 SQL は「本を探す検索機能」の SQL、番号で引く SQL は「本の詳細画面」の SQL とする。詳細画面が題名で本を引くのは不自然で、序章の表「本を探す検索機能」ともつながるため。
- 番号検索は「インデックスで場所を調べてから、表からその 1 行を読む」の 2 段で説明する。「インデックスを 1 回調べただけ」とは書かない。
- 段落の書式は序章に合わせ、複数文を 1 行に書き、空行は段落の区切りにだけ使う。
- 「実験の中断と再開」は「この章で持ち帰ること」の末尾に h3 で置く。
