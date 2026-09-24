# 第3章 進捗台帳

設計メモ：`_drafts/sql-data-structures/ch03-design.md`（コントローラー判断で確定。ユーザー指示「最後までやっておいて」）

| タスク | 状態 | 成果物 | 証拠 | 要求能力層 / 実行経路 / 制御状態 |
| --- | --- | --- | --- | --- |
| T1 実測 | complete | `experiments/ch03-btree.sql`, `ch03-cleanup.sql`, `results/ch03-btree-docker-pg18-20260921.txt` | ログ本体 | frontier / Fable 5.1（コントローラー直接） / pinned |
| T2 初稿 | fixing | `books/sql-data-structures/03-btree-index.md` | 実行報告 | standard / sonnet / pinned |
| T3 独立レビュー | complete | | | standard+ / opus / pinned |
| T4 修正と再レビュー | in_progress | | | sonnet と opus / pinned |
| T5 全体レビュー | pending | | | frontier / fable / pinned |
| T6 統合 | pending | config.yaml、README（済）、preview 確認 | | コントローラー |

## 決定事項の引き継ぎ

- 段数の定義は「根から葉まで降りるときに読むページの数」（level + 1）。
- 第2章の 7 ページは初回の余分として回収し、2 回目以降の 4 ページを基準にする。
- books_title_idx と pageinspect は読者の DB に残す。VACUUM books は代償の節の最後に置く。
- 実測時の books は 59MB（取り消した追加の跡を含む）、VACUUM 後 57MB。本文で「表の 57MB」と比べるときは VACUUM 後の値を使い、:::details に注記する。

## T2 の実行報告（要点、2026-09-21 22:37）

- Status: DONE_WITH_CONCERNS。10 節、text 17 ブロックがログと一致、SQL 14 ブロック一致（4 ブロックは表示順の ORDER BY を削除）、引用 3 件一致、Mermaid 1 枚、7,490 字。
- 懸念 1: 受け入れ条件「ORDER BY がない」を道具 SQL にも当てて ORDER BY relname などを削った → コントローラー判断: 題材の SQL に並べ替えを出さない意図だったので、道具 SQL の ORDER BY は実験 SQL どおりに戻す（T4）。
- 懸念 2: 実測の順（目録なしの追加 → CREATE INDEX → 目録ありの追加）と章の節順が違い、CREATE INDEX 後の pg_class に 7,721 ページが出る。

## コントローラーの通読メモ（T3 の結果と合わせて T4 に全件渡す）

1. 道具 SQL（pg_class ×3、段ごとのページ数）の ORDER BY を実験 SQL どおりに戻す。
2. 「目録なしの 1 万冊追加」の測定を「題名にも目録を作る」の冒頭へ移し、「目録を作る前に、あとで比べるために追加の時間を測っておく」とする。CREATE INDEX 後の 7,721 ページは「取り消した追加の跡。章の最後に片付ける」で受ける。「目録の代償」では目録ありの追加を測って表で比べる。実測の順序と章の順序が一致する。
3. VACUUM 前後の SQL の並びを「大きさを見る → VACUUM books; → ANALYZE books; → 大きさを見る」に直す（現状は VACUUM の後に同じ SELECT が 2 回並び、1 つ目の出力が VACUUM 前の値）。ANALYZE books は行数の推定を直すために実験 SQL（ch03-cleanup.sql）に追加済み。
4. 地の文の半角括弧「(ビーツリー)」「(第2章)」「(この章)」「(根、中間、葉)」「(文字の並び順を決める規則)」「(O(log n))」「(O(n))」を全角に。O(n) の記号自体の括弧は半角のまま。
5. 「読者が個別に作成の指示を出した覚えはありません」は読者の内心を書いている。「作る指示は出していません」など地の文に。
6. 「検索欄に入れる条件が title か id かだけで」は第1章の設定（題名は検索機能、番号は詳細画面）と合わない。「題名で探すか番号で探すかで」に。
7. 「1ページあたり200ページを超える数に枝分かれ」は 2,733 ÷ 10 ≒ 273 なので「およそ270」に。
8. 「葉のページの数2,733は、表のページ数7,353よりも少なく…複数の本の場所がまとめて書かれているため」は理由が弱い。「葉には番号と場所だけが入り、行そのものより小さいので 1 ページに約 366 冊分入る（表は 136 冊）」に。
9. VACUUM は :::details（前方一致）の前に置き、節を details で終える。
10. 「目録の話はここで終わりではなく」は軽い演出。事実だけに。

## T3 の結果（Opus、2026-09-21 22:51）

- 要件適合 PARTIAL、品質 NEEDS_FIXES。Critical 2、Important 5、Minor 11。
- Critical: :::details 計測条件と生の時間 が丸ごとない（3 回分の時間、生ログの保存先、59MB の注記も欠落）。章の順に貼っても再現しない（目録なしの追加測定が CREATE INDEX の後にある。VACUUM の前後の SQL の並び）。
- Important: はじめに で木構造と 1,000 倍の結論を先出し、道具 SQL の ORDER BY が落ちて出力の並びが保証されない、ANALYZE books がない、CREATE INDEX の待ち時間の予告なし、半角括弧（第1章・第2章は全角）。
- Minor: 葉が少ない理由の機構、言い換えの重複、予告型の言い回し、太字 3 箇所、「412番目」、表の見出し空、会話の pg_class、pageinspect の公式引用未使用、図の省略が根だけ、位置で変わらないの根拠、一時テーブルの言い換え。
- 数値は text 17 ブロックすべてログと一致。文字数 6,966（空白除く。details 追加で下限超えの見込み）。
- 確認不能: 冒頭の 59MB の理由（コントローラーが確定: 直前の試し測りで取り消した追加の跡。VACUUM 後 57MB）。

## コントローラーの裁定（T4 に渡した内容）

- T3 の 18 件と通読メモ 10 件を統合し A〜V の 22 項目にして修正担当（初稿と同じ Sonnet）へ渡した。ブリーフ: scratchpad/ch03/brief-t4.md。修正前の控え: 03-btree-index.v1.md。
- 決定: 道具 SQL の ORDER BY は実験 SQL どおりに戻す。「ORDER BY を出さない」は題材の SQL についての制約と明確化（以降の章のブリーフにも同じ注記を入れる）。
- 決定: 目録なしの追加測定を「題名にも目録を作る」の冒頭へ移し、章の順序を実測の順序に合わせる。
