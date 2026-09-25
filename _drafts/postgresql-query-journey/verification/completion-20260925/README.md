# 後半の完成と再開手順の検証

実施日：2026年9月25日22時25〜26分。

- 既存コンテナpostgresql-structures-lab-db-1に、専用DB journey_completion_20260925_2225を新規作成した。
- 第1章の修正後のBEGIN〜COMMITで、本100万冊・記録200万件を用意した。
- 第2〜5・7〜10・12章の入力SQLを本文から抽出し、順に実行した。第7章の200万行をそのまま画面へ返すSELECTは省き、対応するEXPLAINで観察した。
- 第6章へ追加するEXPLAIN ANALYZEを、第5章の後に実行した。本文の二接続・PIDの実験は今回の一括実行に含めていない。
- 第11章は今回再実行していない。追加した二接続の答え合わせは、同日のreview-20260925/two-sessions.logを引用した。
- 最後に第1章へ追加した再開SQLを実行した。必要なIndexを削除・作成し、集計表を削除した後、本100万冊・記録200万件を確認した。
- psqlはON_ERROR_STOPを有効にし、終了コード0。records_without_bookとdiffering_rowsはともに0。
- 既存reading_mapの表・データは変更していない。検証専用DBは終了後に削除した。

## 掲載出力の出典

| 本文 | 出典 |
| --- | --- |
| 第6章のEXPLAIN ANALYZE | 今回のreader-check.log、CHAPTER 6 ADDITION |
| 第7章external merge | ../review-20260925/reader-selected.log、CHAPTER 7 |
| 第8章Index前後・LIMITなし | 同ログ、CHAPTER 8 |
| 第9章Merge Join・集約・64kB Hash Join | 同ログ、CHAPTER 9 |
| 第10章pg_stats・更新前後 | 同ログ、CHAPTER 10 |
| 第11章二接続の題名 | ../review-20260925/two-sessions.log |
| 第12章最初の各計画・同値性・事前集計の作成 | ../review-20260925/reader-selected.log、CHAPTER 12 |
| 第12章3回測定の比較 | ../review-20260925/ranking-repeat.log |

保存済みの結果を今回の再実測へ置き換えていない。第12章の初回計画は第11章の可視性実験前、3回測定はその後であり、本文でも区別した。両者の実行時間を一組の比較へ混ぜていない。

全文の日本語lintでは、章をまたぐ「実行結果」「第8章」などの反復や、技術上の区別を説明する対比表現が検出された。これは章ごとに読める説明のため維持し、無関係な語への置換はしていない。差分チェックと画像参照の存在、コード枠・折りたたみ枠の対応を確認した。Zennの実画面での全章表示は今回未検証。

## 22時30分の追加修正

別レビューと照合し、第3章前半の4計画をreview-20260925/reader-selected.logの同日通し実行へ統一した。第4章の参照と03-index-referenceの図も追随し、hitとreadの合計7,353回を示した。図を再出力して検査・目視確認した。

第5章には大きな表のSeq Scanでバッファを使い回す条件、第4章には行があるページと未使用ページを分ける説明を追加した。第7・9・11章の採取日・可視性・Indexの条件を明記し、SELECTにWALオプションがないのにWALなしとする観測の誤りを除いた。第12章には集計表のHeap Fetchesと片付け手順を追記した。既存の数値を新たに測った値と表現していない。

第12章末で集計表を削除する変更後、第1章の状態表も更新した。reader-check.sqlは22時25分の検証時点の手順であり、末尾のRESTART PREPARATION CHECKSで同じ集計表を削除している。
