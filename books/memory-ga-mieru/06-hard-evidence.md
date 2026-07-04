---
title: "第6話 動かぬ証拠"
---

:::message
この物語はフィクションですが、登場する Ruby コードと、その出力の数値はすべて実測値です。rbenv の Ruby 4.0.5（macOS）で、あなたも同じ桁の数字を再現できます。前作「[午前2時のEXPLAIN](https://zenn.dev/hatsu38/books/explain-midnight-mystery)」と同じ世界観の物語です。「[第1話 覚醒](https://zenn.dev/hatsu38/books/memory-ga-mieru/viewer/01-awakening)」「[第2話 体の中の群衆](https://zenn.dev/hatsu38/books/memory-ga-mieru/viewer/02-crowd-inside)」「[第3話 増え続ける光](https://zenn.dev/hatsu38/books/memory-ga-mieru/viewer/03-growing-lights)」「[第4話 夜ごとの波](https://zenn.dev/hatsu38/books/memory-ga-mieru/viewer/04-nightly-waves)」「[第5話 波を生き延びる者](https://zenn.dev/hatsu38/books/memory-ga-mieru/viewer/05-survivors)」からの読了を推奨します。本編のステージング環境での試行は、環境固有の数値のため、コード出力は記載していません。
:::

## 1

月曜の朝。約束の、ヒープダンプの日だ。

出社するなり蓮見の席へ向かった私に、蓮見は片手を上げた。

「待て」

「え」

「まず手元で手法を確立しろ。刃物は、素振りしてから持ち出す」

その言葉は筋が通っていた。本番相当の環境とはいえ、初めての観測方法をぶっつけで試す場所ではない。

自分の席に戻った。手元のマシンで、本番の症状を、小さな世界で再現するところから始める。

```ruby
# mini_app.rb ── 本番の症状を手元で再現するミニアプリ
require "objspace"

ObjectSpace.trace_object_allocations_start  # オブジェクトの出生記録を採り始める

DEBUG_LOG = []  # ずっと昔に誰かが「あとで消す」つもりで置いたもの

def handle_request(i)
  entry = "GET /articles?page=#{i} 200 12ms" * 5
  DEBUG_LOG << entry            # リクエストのたびに握って、離さない
  body = "<html>page #{i}</html>"  # こっちは短命（返したら手放す）
  body
end

30_000.times { |i| handle_request(i) }

GC.start
File.open("heap.json", "w") { |f| ObjectSpace.dump_all(output: f) }
puts "ダンプ完了: #{(File.size("heap.json") / 1024.0 / 1024).round(1)}MB / #{`wc -l < heap.json`.strip} 行"
```

実行した。

```bash
ruby mini_app.rb
```

出力:

```
ダンプ完了: 20.2MB / 48182 行
```

## 2

48182 行。

モニタの前で、数字を眺めていた。

ドームの光を、すべて数字に変えた。一行一行が、一つのオブジェクト。住民登録簿だ。

heap.json を less で開いた。生の 1 行を読んだ（長い value は省略している）。

```json
{"address":"0x104150018","type":"STRING","value":"GET /articles?page=599 200 12ms...","memsize":320,"file":"mini_app.rb","line":9,"generation":4}
```

息が止まった。

address。type。value。memsize。file。line。generation。

ドームの中で、私だけが視ていた光の粒。それが、ここに、すべて書いてある。

中身。大きさ。生まれた場所。世代の番号まで。

「……ドームの、完全な写しだ」

呟いた。

「それも——誰にでも見える形の」

file と line。出生地の記録。その 1 行の光が、どのコード行から生まれたのか。その場所が、すべてのオブジェクトに付いている。

誰の能力でもなく、Ruby が標準で持っている、ただの機能で。

## 3

48182 行は、目では読めない。

別のスクリプトを書いた。出生地ごとに集計する。どのコード行が生み出したオブジェクトが、何個・何 MB 生き残っているか。

```ruby
# birthplace.rb ── ダンプを「出生地」ごとに集計する
require "json"

counts = Hash.new(0)
bytes  = Hash.new(0)

File.foreach("heap.json") do |line|
  obj = JSON.parse(line)
  next unless obj["file"]  # 出生記録のあるオブジェクトだけ
  key = "#{obj["file"]}:#{obj["line"]}"
  counts[key] += 1
  bytes[key]  += obj["memsize"] || 0
end

puts "生存数\tサイズ\t出生地"
counts.sort_by { |_, c| -c }.first(5).each do |key, count|
  puts "#{count}\t#{(bytes[key] / 1024.0 / 1024).round(1)}MB\t#{key}"
end
```

実行した。

```bash
ruby birthplace.rb
```

出力:

```
生存数	サイズ	出生地
30001	9.2MB	mini_app.rb:9
9	0.0MB	/Users/hajimewatanabe/.rbenv/versions/4.0.5/lib/ruby/4.0.0/objspace.rb:100
8	0.0MB	mini_app.rb:18
3	0.0MB	mini_app.rb:17
2	0.0MB	mini_app.rb:15
```

一位。mini_app.rb:9。30001 個。9.2MB。

9 行目を数えた。

```ruby
  entry = "GET /articles?page=#{i} 200 12ms" * 5
```

文字列が生まれた行。

その直後が 10 行目。

```ruby
  DEBUG_LOG << entry
```

握っている手。

「……あ」

一瞬の戸惑い。出生地は「生まれた行」。握る行ではない。その 1 行のズレ。でも、コードを 1 行読み下げれば、初めてリークの正体が見える。何が、どこで、誰に握られているのか。

DEBUG_LOG に、30001 個の文字列が、握り続けられている。

9 行目で生まれて、10 行目で握られた光たち。波を何度も生き延びて、old 世代に沈んで、その数は 30001 個。

これが、本番の症状を手元で再現したものだ。

蓮見に見せた。

「……手順、できました。ダンプを採って、出生地で集計するだけです」

蓮見が頷いた。

「よし。持ち出すぞ」

## 4

午後。ステージング環境で。

蓮見の席に、もう一つのモニタがセットされた。本番相当のサーバーに繋いで、同じ手順を実行する。

ObjectSpace.trace_object_allocations_start。数時間、ステージングアプリを動かす。GC.start。ObjectSpace.dump_all。

ダンプを採って、birthplace.rb で集計する。

蓮見の目が、画面を追った。

「……出た」

生存数の第一位。出生地を見ている。

それは、自作ミドルウェアの一行だった。リクエストのたびに、ログを配列に溜め込むコード。その文字列が数百万個、旧世代に積み重なっていた。

「消す」蓮見が言った。

シンプルだった。あのコードを、削除する。

「git blame」

蓮見がターミナルを開いた。その一行を書いた人物を、履歴の中に遡る。

3 年前のコミット。メッセージは「デバッグ用。あとで消す」。

蓮見は少し黙って、別のリポジトリを開いた。インフラ設定のほう。「朝の体操」の cron を定義しているファイルに、同じように blame を掛ける。

同じ名前が、出てきた。

応急処置と、原因。同じ人が、両方を置いていたのだ。ログを溜めるコードを仕込んで、メモリが太ることに気づいて、原因を探す代わりに毎晩の再起動を仕込んで——そのまま、会社を去った。

蓮見は、ページを閉じた。

「誰でもやる」蓮見が呟いた。

「え」

「消し忘れ。仕組みで防ぐもんだ」

短い言葉。でもその中には、責める気持ちはなく、ただ「これからどうするか」という確実さだけがあった。

蓮見がスクリーンを指した。

「動かぬ証拠だ」

その一言。

修正方針が確定した。ミドルウェアの削除。

## 5

蓮見の目が、初めて直にこちらを見た。

不思議な感覚だった。

これまで、蓮見は、数字を見ていた。RSS。live_slots。old_objects。GC の回数。私が持っていく数字を、黙って検分する先輩。

でも、この一瞬、蓮見は、私を見ていた。

「いい仕事だ」

それだけ。

短い。蓮見らしい。

でも、その短さの中に、すべてが詰まっていた。

「修正が入れば、朝の体操も卒業だな」

蓮見がスケジュールを見た。「デプロイは明日」

帰り道。電車の中。

朝の体操がなくなる。毎晩、cron で再起動する儀式がなくなる。その喜びがあった。

でも、帰路の中で、ふと思った。

ドームの体格。

旧市街に溜まっていた光が消えたら、この街は、ちゃんと痩せるんだろうか。

リークの光を握る手が、ようやく手放したら。RSS は、ちゃんと下がるんだろうか。

「……考えすぎだ」

つぶやいた。

今夜くらいは、喜ぼう。

（第7話「痩せない体」につづく）

---

## 今夜の観測メモ

- **ObjectSpace.dump_all** = 全オブジェクトの戸籍簿。1 行 1 オブジェクトの JSON として、address（メモリアドレス）、type（種類）、value（内容）、memsize（サイズ）等を出力。`require "objspace"` で標準ライブラリとして使える
- **trace_object_allocations_start** = dump_all の実行前に呼ぶと、各オブジェクトに「出生記録」（file と line）が付く。どのコード行が、そのオブジェクトを生み出したのかが、数字で分かる。外部 gem 不要
- **出生地集計** = dump_all の出力を file:line でグループ化して、memsize を合計する。結果から「どのコード行が生み出したオブジェクトが、何個・何 MB 生き残っているか」が分かる。実測: mini_app.rb の DEBUG_LOG に握られた 30001 個の文字列が 9.2MB を占有
- **出生地は「握った行」ではなく「生まれた行」** = オブジェクトはどこで生まれたのか（file:line）と、どこが握っているのか（参照元）は別。1 行のズレだが、コードを 1 行読み下げれば、リークの現場が見える。修正するのは「握っている手」のほう。次話で、修正後の RSS がどう変わるのか観測する
