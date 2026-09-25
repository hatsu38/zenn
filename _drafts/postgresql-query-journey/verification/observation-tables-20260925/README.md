# 第4・5章：通常テーブルの引き継ぎの検証

2026年9月25日、PostgreSQL 18.6 / aarch64 Linuxで実施。既存Dockerコンテナ `postgresql-structures-lab-db-1` に専用DB `journey_observation_20260925_2301` を作成し、読者用DBには変更を加えていない。

## 実行順と条件

1. `setup.sql`：本100万冊と題名Indexを準備。第4・5章が参照しない読了記録は作っていない。
2. `04.sql`：本文の入力SQLを掲載順に実行。ページごとの行数を確認する補助SQLも追加。
3. psqlを終了し、別の接続で `05.sql`：第4章のテーブルを引き継ぎ、追い出した直後に同じ検索を3回実行。最後に観察用テーブルの削除と、100万冊・題名Indexの保持を確認。
4. `05-standalone.sql`：第5章の補足に載せた準備SQLから再開する経路を別の接続で実行し、後片付けまで確認。

各SQLに `ON_ERROR_STOP` と共通設定を含め、各実行の終了コードは0。`.out` は対応する出力で、末尾の空白だけ除去している。本文の第5章の掲載値は `05.out` を使用し、単独開始の測定値とは混ぜていない。冒頭の `block-N` は本文のコードブロックを識別する検証用の印。

## 確認結果

- books_observation：1,000行、64 kB・8ページ、Indexなどを含め136 kB。ページ0〜6は各136行、ページ7は48行。
- 元のbooks：100万行、7,353ページ。題名Indexの根のlevelは2。
- 行幅比較：size_shortは65,536バイト、size_longは262,144バイト。行のあるページは6・30ページで、各ページの最大行数は185・34行。
- 第5章：追い出し11、書き出し8、スキップ0。検索はread=8 → hit=8 → hit=8、除外行は毎回999。
- 第5章の実行時間：0.329 / 0.041 / 0.040 ms。環境依存の実測で、性能の保証ではない。
- 後片付け後：books_observationは存在せず、booksの100万行とbooks_title_idxは残る。

## 再実行

空の専用DBを作り、そのDB名を指定して以下を順に実行する。読者用DBに対して実行しない。

```sh
docker exec -i postgresql-structures-lab-db-1 psql -X -U postgres -d <専用DB名> < setup.sql
docker exec -i postgresql-structures-lab-db-1 psql -X -U postgres -d <専用DB名> < 04.sql
docker exec -i postgresql-structures-lab-db-1 psql -X -U postgres -d <専用DB名> < 05.sql
docker exec -i postgresql-structures-lab-db-1 psql -X -U postgres -d <専用DB名> < 05-standalone.sql
```

第10章のトランザクションは変更していない。自動の統計更新の介入を避けるという、別の目的で使用している。
