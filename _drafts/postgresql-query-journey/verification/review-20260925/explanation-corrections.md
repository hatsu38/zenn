# 説明修正の確認記録

2026年9月25日22時台。販売前レビューを受けて、本文7章と図2枚の説明を修正した。本文のSQL入力・実行出力ブロックはHEADと比較して同一。実験結果の追加・測り直しは今回の修正に含めていない。

## 図の根拠と確認

既存のreading_mapへ読み取り専用のSELECTを実行し、次のctidを確認した。下表は取得結果の転記であり、初期化直後の配置を保証するものではない。

| id | ctid |
| ---: | --- |
| 40001 | (294,17) |
| 40002 | (294,18) |
| 400009 | (2941,33) |
| 400010 | (2941,34) |
| 400020 | (2941,44) |

06-bitmap-scanは、上の5項目の位置をページごとにまとめた図へ変更した。09-merge-joinは、重複する記録1を二件とも返し、合計4組になる図へ変更した。両方ともSVGからPNGを再出力し、check-figuresで2枚とも合格。PNGを目視し、文字の欠けや重なりがないことを確認した。

figure-pixel-comparison.jsonは修正前の54枚に対する一致記録。今回の修正後の全54枚を再比較した記録ではない。

## 参照した仕様

- Bitmapのexact/lossy：[PostgreSQL 18のtidbitmap.c](https://raw.githubusercontent.com/postgres/postgres/REL_18_STABLE/src/backend/nodes/tidbitmap.c)
- BuffersとWALの計測対象：[EXPLAIN](https://www.postgresql.org/docs/18/sql-explain.html)
- work_memとhash_mem_multiplier：[Resource Consumption](https://www.postgresql.org/docs/18/runtime-config-resource.html)
- WALの保存順、synchronous_commit、wal_log_hints：[Write Ahead Log](https://www.postgresql.org/docs/18/runtime-config-wal.html)
- Indexの掃除を省く条件：[VACUUM](https://www.postgresql.org/docs/18/sql-vacuum.html)
- ソートのDisk表示：[PostgreSQL 18のtuplesort.c](https://raw.githubusercontent.com/postgres/postgres/REL_18_STABLE/src/backend/utils/sort/tuplesort.c)

変更した文章をnatural-japaneseのtech設定で検査し、翻訳調と常套句の指摘を修正した。残った語彙の反復は、ページ・行・Indexなどを同じ意味で繰り返す技術説明のため維持した。

実験リポジトリhatsu38/postgresql-structures-labは、gh repo viewでPUBLICを確認した。レビュー本文に同日の更新を追記し、非公開という修正前の指摘と区別した。
