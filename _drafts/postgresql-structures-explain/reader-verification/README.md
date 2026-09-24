# 本文初稿の検証記録

検証日：2026-09-22（JST）

## 環境と対象

- Docker `reading-log-lab` 内のPostgreSQL 18.6、aarch64 Linux。
- 既存の読書実験DBとは別に `reading_map_reader_verify_20260922` を作成して検証。
- 第1章は本1,000冊・記録2万件、第5章で本100万冊、第7章で記録200万件。
- 第5章以降は原則として並列実行とJITを無効、work_memは4MB。第7章では64MBと64kBも比較。
- 通常テーブルを使用。序章の過去実測（Homebrew 18.3、一時テーブル、記録2,000万件）とは別条件。

## SQL

- `chapter-sql.sql`：本文から抽出したSQLと、「同じSQLを再実行」の比較を一部明示した実行用ファイル。
- `chapter-sql.log`：第1〜10章・第12章の検証出力。psqlのON_ERROR_STOPを有効にし、終了コード0。
- 第1章冒頭の準備前のSQLは読み方の例として明示し、実行は表の準備後にする。
- データ生成や、結果表示を含むログ。多数の行がある部分は性能の根拠に使わない。
- 記録の本番号が本に対応しない件数：0。
- ランキングの元SQLと、集計後に上位選択して結合するSQLの双方向EXCEPT ALL差分：0。
- 比較はサンプルに対する確認。任意の条件での意味の同値性を証明するものではない。
- `check-two-sessions.py` / `two-sessions.log`：独立した二つの接続でRepeatable Readを確認。Aの継続中は元の題名、COMMIT後の新しい検索は改訂版。検証後に題名を復元。
- `visibility.sql` / `visibility.log`：同じ検索で、VACUUM後・UPDATE後・再VACUUM後のHeap Fetchesが0・4・0。実験用の追加索引は削除。
- 本文の新しい実測抜粋は第1・7・8・11・12章。最終ランキングの時間の倍率は本文で断定せず、読者が同条件で記録する形式。
- 新しいコンテナを作るDockerコマンド自体は実行せず、既存の同じPostgreSQL 18コンテナ内の専用DBで検証した。

## 図とプレビュー

- 全13章・Mermaid 38点をMermaid 11.12.0でparseとSVG生成。構文・描画エラー0。
- ページ配置、B-tree、MVCCの図をブラウザで並べて表示確認。
- Zenn CLIの第8章プレビューで本文・見出し・図の埋め込みを確認。
- Zennの図は外部iframeで遅延読み込みされるため、全38点のZenn上での表示を個別確認したわけではない。全図の生成確認はMermaid単体で行った。

## 原稿の位置付け

- 序章〜第12章の読者向け本文初稿。公開設定はfalse。
- 執筆前の詳細構成は `../twelve-chapter-outline/` に保管。
- 全章Summaryと説明順序は本フォルダの `CHAPTER-SUMMARIES.md`、インタラクティブ地図は `knowledge-map.html` に保持。

## 2026-09-22：第1章の掲載出力を実験リポジトリで再採取

第1章の現在の掲載値は、隣接する独立リポジトリ `../postgresql-structures-lab` の `results/chapter01-2026-09-22.txt` が出典。測定条件は同リポジトリの `results/README.md` に記録。従来の本検証用DBとは別のCompose環境で、新規ボリュームから初期化して採取した。第2章の接続コマンドもComposeへ揃えた。

## 序章のランキング出力

2026-09-22にユーザーが共有した、初期データ（本1,000冊・読了記録2万件）でのランキング20行を序章に掲載。プロンプトと中断操作は除き、結果の表を転記した。序章の過去実測約4.6秒とは異なる条件であり、この追記のための再計測は行っていない。

## 第2章の接続と実行計画の出力

2026-09-22にユーザーが共有したPostgreSQL 18.6の実行結果を掲載。接続AのPID 952、接続BのPID 22521、接続Bからのpg_stat_activity（Bがactive、Aがidle）、題名順LIMIT 3のEXPLAINを転記した。シェルの個人情報・プロンプトと重複出力は含めていない。今回の追記のための再実測ではない。

## 第3章の保存先・サイズ・ページサイズ

2026-09-22にユーザーが共有した出力を掲載。pg_relation_filepath('books')はbase/16384/16385、table_sizeは64 kB、total_sizeは136 kB、block_sizeは8192。今回の追記のための再計測は行っていない。表本体8ページは64 kB÷8 kBから算出した値であり、実行時のアクセス回数とは区別した。

## 第3章のctidと行幅の比較

2026-09-22にユーザーが共有した結果を掲載。先頭8行のctidは(0,1)〜(0,8)。size_shortは65,536バイト、size_longは262,144バイト、いずれも1,000行。ページ数8・32は既出のblock_size=8192で割って算出。BEGIN、SELECT 1000×2、ROLLBACKの出力も掲載した。今回の再実測ではない。

## 第4章の3回の検索結果

2026-09-22のユーザー提供ログを掲載。3回ともSeq Scan、rows=1、除外999、shared hit=8。Planning Timeは1.044/0.081/0.083 ms、Execution Timeは0.823/0.183/0.140 ms。実行計画の見出し・罫線・末尾行数を省き転記。今回の再実測ではない。共有バッファ未保持から保持への変化を示すログではなく、既存の3コマ模型とは区別する。

## 第4章のメモリ設定値

2026-09-22のユーザー提供出力を掲載。shared_buffers=128MB、work_mem=4MB、temp_buffers=8MB、maintenance_work_mem=64MB。SHOWの設定値であり、実際のメモリ使用量や推奨値とは区別した。今回の再実測ではない。

## 第5章の1,000冊での基準結果

2026-09-22にユーザーが共有したcount(*)=1000と題名検索の出力を掲載。Seq Scan、actual time=0.016..0.052、rows=1.00、loops=1、除外999、shared hit=8、Planning Time=0.053 ms、Execution Time=0.064 ms。今回の再実測ではない。ユーザー提供ログにはSETの出力がないため、設定を実測確認済みとは扱わない。

## 第5章のデータ追加出力

2026-09-22のユーザー提供ログからINSERT 0 99000、INSERT 0 900000、および各ANALYZEの完了出力を掲載。共有された2本目の入力には `|| na` があり、AS nのSQLとしては成功出力と整合しないことをユーザーに伝えた。本文の既存SQLは `|| n` のまま保持。追加件数は共有された値で、再実測・総件数の再確認は行っていない。

## 第5章のLIMIT 1の結果

2026-09-22のユーザー提供ログを掲載。Limitの子はSeq Scan、返却1行、除外41行、loops=1、実行時shared hit=2。Planningはshared hit=17 dirtied=2、Planning Time=0.797 ms、Execution Time=0.122 ms。42行の確認は返却1＋除外41から算出。今回の再実測ではなく、このログ自体にはcount(*)や設定確認は含まれない。

## 第6章の題名索引の追加前後

2026-09-22のユーザー提供ログを掲載。索引追加前はSeq Scan、返却1・除外999999、loops=1、shared hit=7353、Planning Time=0.510 ms、Execution Time=81.675 ms。CREATE INDEXとANALYZE後はbooks_title_idxのIndex Scan、Index Searches=1、実行時shared hit=1 read=3、Planningはhit=8 read=1、Planning Time=0.631 ms、Execution Time=0.191 ms。各1回の出力で、今回の再実測ではない。実行時のhit+read=4はアクセス数として扱い、物理I/O回数や索引の比較回数とは区別した。

## 第6章の索引サイズと範囲検索

2026-09-22のユーザー提供結果を掲載。books_title_idxのpg_relation_sizeをpg_size_prettyで表示した値は39 MB。id BETWEEN 400000 AND 400010はbooks_pkeyのIndex Scan、推定11・実測11行、実行時hit=7、Planning hit=6、Planning Time=0.272 ms、Execution Time=0.087 ms。id BETWEEN 1 AND 900000はSeq Scan、推定902218・実測900000行、除外100000、実行時hit=7353、Planning hit=4、Planning Time=0.093 ms、Execution Time=93.493 ms。今回の再実測ではない。39 MBは表示値であり正確なバイト数とは扱わず、番号の範囲検索と題名索引を区別した。

## 第7章の200万件の準備とメモリ内ソート

2026-09-22のユーザー提供ログを掲載。TRUNCATE TABLE、INSERT 0 2000000、ANALYZE、count(*)=2000000を転記。max_parallel_workers_per_gather=0、jit=off、work_mem=64MBと各SETの完了出力を確認。対象週のSeq Scanは実測499998行・除外1500002行、loops=1、shared hit=10811。Sortは推定502425・実測499998行、quicksort、Memory: 27913kB、actual time=182.059..207.760。Planning Time=0.083 ms、Execution Time=223.929 ms。プロンプト・重複した入力・実行計画の見出し罫線と末尾行数を省略。出力のないSELECTについて結果を補完していない。今回の再実測ではなく、既存の64MB/64kB比較表は別途行った原稿検証のログであることを本文に明記。再共有された索引サイズ・範囲検索は第6章の既存掲載値と一致し、重複追記していない。
