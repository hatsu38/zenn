# 未知の計画の模範解答（2026-09-28、lab で確かめた）

直し方は `fixes.sql` を BEGIN〜ROLLBACK で実行して確かめた（`fixes.out`）。

| ID | 読む | なぜ | 直す（確かめた結果） | 本で足りるはずの知識 |
| --- | --- | --- | --- | --- |
| U1 | Seq Scan 329ms、Rows Removed by Filter 999,999 | 列に lower() を掛けたので books_title_idx を使えない。推定 rows=5000 は関数の式に統計がないための既定の見積もり | 式の Index `ON books (lower(title))` で Index Scan 0.196ms（約1,700倍） | Filter と Rows Removed（1章）、Index が使える条件（3章）、付録の「関数で Index が効かない」 |
| U2 | 1.6ms で速い。Merge Semi Join、books_pkey を 4,788 件読んだ時点で10件そろって止まる | EXISTS は1件見つかれば十分なので Semi Join。Limit が上流を途中で止める | 直さない | Merge Join（9章）、Limit で途中で止まる（8・12章）。Semi Join は本に無い |
| U3 | Index Scan が rows=500020 を読み Limit が20件だけ返す、71ms | OFFSET は捨てる行も読む | `WHERE id > 500000 ORDER BY id LIMIT 20` で 0.092ms | Limit と Index Scan（3・8章）、付録の「大きな OFFSET」 |
| U4 | Sort が external merge Disk 23528kB、全体 843ms。推定 rows=2000000 に対し実際4 | date_trunc の式に統計がなく、グループ数を行数と同じと見積もったので HashAggregate を選ばず Sort して GroupAggregate | `CREATE STATISTICS ... ON (date_trunc('week', finished_at))` と ANALYZE で推定4、HashAggregate 32kB・535ms（Seq Scan 334ms は残る） | Sort と Disk（7章）、HashAggregate（6章）、推定と実際のずれ（10章）。式の統計（CREATE STATISTICS）は本に無い |
| U5 | Hash Join 全体 322ms。reading_records の Seq Scan 200万件で9件しか結合しない、books も Seq Scan で LIKE 前方一致 | 照合順序 en_US.utf8 の books_title_idx は LIKE の前方一致に使えない。reading_records に book_id から引く Index がない | `title text_pattern_ops` の Index と `reading_records (book_id)` の Index で Nested Loop、0.197ms | 照合順序と COLLATE "C"（3章 #59）、Nested Loop と内側の Index（9章）、付録の text_pattern_ops |
| U6 | 30.9ms で速い。Gather の下で2ワーカー、Parallel Index Only Scan loops=3、rows=190476.67 は1プロセスあたり | 並列実行。Partial Aggregate を各プロセスで数え、Finalize Aggregate でまとめる | 直さない | loops の読み方（9章）。並列実行は準備の章で切っていると触れるだけで、読み方は本に無い |

## 読者役が選んだ U4 の書き換え（週の範囲で数える）を測った

generate_series で4週を作り、週ごとに範囲で count(*) する副問い合わせにすると、Index Only Scan（loops=4、Heap Fetches 184）で 266ms。元の 843ms、式の統計の 535ms より速い。本の知識（付録パターン1「列を関数で包まない」と第9章の Index Only Scan）だけで、模範解答より良い直し方にたどり着いた。ただし計画に出た `Function Scan` と `SubPlan` は本に無い。
