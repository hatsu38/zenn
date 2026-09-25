# 2026-09-25 販売前レビューの検証記録

調査結果は[レビュー](/Users/hatsu/development/github.com/hatsu38/zenn/_drafts/postgresql-query-journey/review-20260925.md)を参照。

## 環境と実行範囲

- PostgreSQL 18.6、aarch64 Linux。既存Dockerコンテナ `postgresql-structures-lab-db-1` 内に、新規の専用DB `journey_review_20260925_2156` を作って実行した。
- 第1章相当の配布setup.sql、第2〜5・7〜10・12章の入力SQLを選択して実行。第7章冒頭の全200万行を表示するSELECTは除き、EXPLAINで観察した。
- 第5章の同一SQLの3回反復など、文章で指示された反復を全て展開したものではない。全章・全手順の完全な通しテストとは区別する。
- 第6章の二接続を含む全手順は再実行していない。第11章の二接続MVCC実験は別に実行した。
- 並列クエリとJITは無効。work_memは原則4MB、章のSQLに従って変更。新規DBの既定設定でautovacuumを無効にしていない。
- 元のreading_mapの表・データを変更していない。測定は他DBも存在する共有コンテナ内であり、性能測定の隔離はしていない。
- 検証終了後、今回作成した専用DBは削除済み。ログとSQLのみを保存している。

## ファイル

| ファイル | 内容 |
| --- | --- |
| reader-selected.sql / reader-selected.log | 新規DBでのデータ準備と、本文から選択したSQLの実行。終了コード0 |
| two-sessions.log | AでREPEATABLE READを開始して題名を読む→Bで題名変更・COMMIT→Aで旧題名を確認→AのCOMMIT後に新題名を確認→題名を復元 |
| chapter11-selected.sql / chapter11-selected.log | 本文の可視性とWALの実験。Heap Fetchesは0→4→2。終了コード0 |
| vacuum-followup.log | 続けて実行したVACUUM VERBOSE。掃除できないdead tupleは0、Index掃除の省略とdead item identifiers 2個を確認 |
| ranking-repeat.sql / ranking-repeat.log | 第11章の実験・VACUUM後に、最終章の3方式を3回ずつ測定。終了コード0 |
| vacuum-index-cleanup.log | 実験用Indexを再作成後、INDEX_CLEANUP ONを比較。dead item identifiers 2個が除去され、2ページがall-visibleになった。Index再作成後の最初のHeap Fetchesは既に0だったため、0化をこの追加VACUUMだけの効果とはしない |
| figure-pixel-comparison.json | 54枚のSVGをChromium・deviceScaleFactor=2で再描画し、掲載PNGのRGBAピクセルと比較。54枚全て一致 |

二接続実験のSQLは本文第11章の通り。ログは操作ごとに取得し、Aの最初のSELECTを終えてからBを開始した。既存の過去ログを今回の再実測として使っていない。

## 結果を解釈するときの注意

最終章の3回測定の中央値は、基準695.730ms、集計後に結合242.852ms、事前集計表の読出し0.038ms。キャッシュ消去なし、順序固定。事前集計の準備・継続更新時間は読出し時間に含まれない。

図の既存検査スクリプトでは30枚に更新時刻の警告が出たが、ピクセル比較では全54枚一致した。図の意味や可読性の合格を自動検査だけで保証するものではない。

入力と出力がどちらもsqlコード枠にあるため、最初の抽出器が出力のSETまで拾って一度失敗した。抽出条件を修正し、専用DBを作り直して最初から再実行した。保存しているreader-selected.logは再実行の成功ログであり、この抽出器の失敗を本文のSQL不具合として扱っていない。
