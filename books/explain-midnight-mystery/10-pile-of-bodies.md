---
title: "第10話 死体の山 ─ VACUUM と autovacuum"
---

:::message
この物語はフィクションですが、登場する SQL と EXPLAIN の出力はすべて実測値です（数値の一部は環境により変動するため `...` 表記）。技術書版[「PostgreSQL の EXPLAIN と内部のしくみ」](https://zenn.dev/hatsu38/books/cddb89f9abfaca)第 10 章と同じサンプル DB で再現できます。
:::

## 1

午前5時38分。レイテンシのグラフは 0.3 秒で凪いでいる。だが桐生さんの捜査は終わっていなかった。

「第 4 話でやった MVCC を思い出せ。UPDATE は上書きじゃない──古い行に xmax を刻んで残し、新しい行を追記する。つまり昨日のバッチが articles を全行 UPDATE したということは」

「10 万行の**死体**が、まだテーブルの中に……」

「実物を見せる。サンドボックスで、ロールバックで戻せる形でな」

```sql
BEGIN;

-- 全行に「無意味な」UPDATE を打つ（title を title で更新）
UPDATE articles SET title = title;

-- 生きてる行と死んだ行を数える
SELECT n_live_tup, n_dead_tup
FROM pg_stat_user_tables
WHERE relname = 'articles';
--  n_live_tup | n_dead_tup
-- ------------+------------
--      100000 |     100000

ROLLBACK;
```

「うわ……live 10 万、dead 10 万。**テーブルの中身が実質 2 倍**になってる。値を変えない UPDATE でもですか」

「MVCC は中身を見ない。UPDATE という行為そのものが、旧版に享年を刻んで新版を産む。ついでに、行の生没を直接覗く方法も教えておく」

```sql
SELECT ctid, xmin, xmax, id FROM articles LIMIT 5;
```

「`ctid` は行の物理的な住所──(ページ番号, ページ内の位置) だ。xmin と xmax は第 4 話でやった生年と享年。seed で一括投入したテーブルなら、xmin がずらっと同じ値で並んでるはずだ」

「dead tuple って、放っておくとどうなるんですか」

「テーブルが太る。Seq Scan は死体のぶんまでページを読まされる。visibility map は倒れたまま。Index Only Scan は名前だけになる。──だから**清掃人**がいる。VACUUM だ」

## 2

「VACUUM の仕事は 4 つ。①dead tuple の場所を**再利用可能**とマークする。②第 4 話の visibility map のビットを立て直す。③pg_class の reltuples / relpages を更新する。④……は後で言う。──ひとつ、意外と知られてない事実を言っておく。**通常の VACUUM はテーブルを縮めない**」

「え。掃除するのに？」

「死体を片付けて『この区画、次の入居者どうぞ』と札を立てるだけだ。ディスク上のファイルサイズは変わらない。物理的に縮めたければ ④ の `VACUUM FULL`──ただしこいつは**テーブルを丸ごとロックして作り直す**劇物だ。本番で気軽に打つものじゃない」

「その清掃人、いつ来るんですか」

「自動で来る。**autovacuum** という常駐プロセスだ。発火条件は統計のときと同じ形で」

```sql
SHOW autovacuum;                       -- on
SHOW autovacuum_vacuum_scale_factor;   -- 0.2
SHOW autovacuum_vacuum_threshold;      -- 50
```

「dead tuple が『行数 × 0.2 + 50』を超えたら起動する。10 万行のテーブルなら 20,050 行。昨日のバッチは 10 万行の dead を作ったから、**とっくに発火してるはず**なんだ。analyze のほうも同じだ。──さて湊、第 9 話の宿題だ。**なぜ来なかった？**」

## 3

僕らは本番の状況を覗いた。答えは、意外なほどあっさり画面に出ていた。

```sql
SELECT pid, query, state, backend_start
FROM pg_stat_activity
WHERE backend_type = 'autovacuum worker';
```

「……いた。autovacuum worker が 3 匹とも、**昨日の夜からずっと comments を掃除してる**。comments って 100 万行ですよ。バッチは articles だけじゃなくて、comments のカウンタ列も洗い替えてたんだ」

「見えたな。autovacuum のワーカーはデフォルトで **3 匹**しかいない。しかも本番への影響を抑えるため、わざと**ゆっくり掃除する**ようにコスト制限で首輪が付いてる。100 万行の死体の山に 3 匹全員が張り付いて、何時間も匍匐前進──**articles は清掃待ちの行列に並んだまま**、朝を迎えるところだった。autoanalyze も同じワーカーの仕事だから、一緒に遅れた」

「清掃人は、サボってたんじゃなくて……**現場が多すぎて回りきれてなかった**」

「そういうことだ。誰も悪意はない。バッチは仕様どおり動き、autovacuum は設定どおり働き、プランナは統計どおり見積もった。**全員が正しく動いて、システムだけが壊れる**──深夜障害というのはたいていそういう顔をしてる」

その言葉は、少しだけ胸に刺さった。犯人捜しのつもりでいた自分に、だ。

「articles の後始末は手動でやっておけ。ANALYZE と同じで、通常の VACUUM はロックで固まらない」

```sql
VACUUM ANALYZE articles;
```

数秒で終わった。visibility map が立ち直り、レプリカで見た例の Index Only Scan は `Heap Fetches: 0` に戻っていた。完全犯罪が、完全犯罪に戻った。

## 4

「仕上げに、後始末の検算だ。articles の行数を数えてみろ」

```sql
EXPLAIN ANALYZE SELECT count(*) FROM articles;
```

```
 Aggregate  (cost=... rows=1 width=8) (actual time=... rows=1 loops=1)
   ->  Seq Scan on articles  (cost=0.00..12181.00 rows=100000 width=0) (actual ... rows=100000 loops=1)
```

「あれ。count(\*) って、**全件 Seq Scan** するんですか。行数くらいどこかにメモしてあるんじゃ……」

「無い。それも MVCC の代償だ。考えてみろ──『テーブルの行数』は、**誰から見た行数だ？** トランザクションごとにスナップショットが違うんだから、万人共通の『正確な行数』なんて数字は原理的に存在しない。**自分から見える行を自分で数える**しかない。だから count(\*) は見た目より重いクエリだ」

「うわ、ダッシュボードの管理画面、count(\*) 撃ちまくってます……」

「対症療法はある。`count(id)` にすれば Index Only Scan が使える可能性が出る──第 4 話の知識だ。ヒープ 11,181 ページを舐める代わりに、もっと小さいインデックスを舐めて、visibility map で可視性を判定する。VACUUM が効いてる今なら Heap Fetches: 0 で走るはずだ。試して Buffers を見比べてみろ」

「……count(\*) が遅い理由まで、今夜の話が全部繋がってるんですね。MVCC があるから dead tuple が生まれて、dead tuple がいるから VACUUM がいて、VACUUM が visibility map を立てるから Index Only Scan が生きて、count の速さまで決まる」

「それが**内部のしくみを 1 本の線で知る**ということだ」

窓の外は、もう完全に朝だった。午前6時2分。

「──さて。応急処置は済んだ。後始末も済んだ。だが湊、**再発防止**がまだだ。それと、プランナと*交渉*する道具を、まだ半分しか渡してない。……とはいえ、もう限界だろう。少し寝ろ。夕方、続きをやる」

通話が切れた。僕はベッドに倒れ込む直前、Slack の障害チャンネルに一行だけ書いた。

『復旧しました。原因と再発防止は本日中に共有します。#explain-捜査資料 参照』

（第11話「プランナとの交渉術 ─ enable スイッチと pg_hint_plan」につづく）

---

## 今夜の捜査メモ

- **UPDATE / DELETE は dead tuple を産む**。値を変えない `UPDATE t SET x = x` でも全行ぶんの死体ができる（`pg_stat_user_tables` の `n_dead_tup` で観察）
- 行の生没は `SELECT ctid, xmin, xmax` で直接覗ける。`ctid` は (ページ番号, 行位置) の物理住所
- **VACUUM の仕事**: dead tuple の再利用マーク / visibility map 再設定 / reltuples・relpages 更新。**テーブルは縮めない**。縮めるのは `VACUUM FULL`（フルロックの劇物）
- **autovacuum の発火条件**: dead tuple > 行数 × 0.2 + 50。ただしワーカーは**デフォルト 3 匹**で、I/O 影響を抑えるコスト制限付き──**巨大テーブルの掃除に全員が張り付くと、他のテーブルの VACUUM / autoanalyze が行列で待たされる**
- `autovacuum = off` は禁じ手。「重いから止める」は数週間後の激遅テーブルで返済することになる
- **count(\*) が遅いのは MVCC の原理**: 万人共通の行数は存在せず、自分に見える行を全件数えるしかない。`count(id)` + 整った visibility map なら Index Only Scan で軽くなる余地がある
- 深夜障害の実像: バッチも autovacuum もプランナも**全員が仕様どおりに動いて**、組み合わせだけが壊れる。悪者探しではなく、しくみの線を繋いで読むこと

:::message
MVCC タプルのタイムライン図、VACUUM 前後の対比図、count(\*) と count(id) の Buffers 比較実験は技術書版の[第 10 章](https://zenn.dev/hatsu38/books/cddb89f9abfaca)にあります。
:::
