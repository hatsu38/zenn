---
title: "第7話 密室 ── Mutex とデッドロック"
---

:::message
コードと出力は Ruby 4.0.5（rbenv / macOS arm64）での実測です。デッドロックの再現コードは意図的に固まるコードです（Ruby が検出して自動終了するので安全に試せます）。
:::

## 1

火曜、僕は一日かけて修正版を書いた。武器は **Mutex**（ミューテックス、mutual exclusion ＝相互排他）。要するに**1 本しかない鍵**だ。

```ruby:fixed.rb
users = (1..200).map { |n| "user_#{n}" }
sent  = []
i     = 0
lock  = Mutex.new

threads = 4.times.map do
  Thread.new do
    loop do
      user = lock.synchronize do   # 取り出しと前進をひとつの鍵で守る
        break nil if i >= users.size
        u = users[i]
        i += 1
        u
      end
      break if user.nil?
      sleep 0.001                  # 送信（IO）は鍵の外で
      sent << user
    end
  end
end

threads.each(&:join)
puts "送信件数:   #{sent.size}"
puts "ユーザー数: #{sent.uniq.size}"
puts "二重送信:   #{sent.tally.count { |_, c| c > 1 }} 人"
```

```
$ ruby fixed.rb
送信件数:   200
ユーザー数: 200
二重送信:   0 人
```

3 回流して、3 回とも 200 / 200 / 0。完璧だ。

水曜の朝、僕は意気揚々と氷室さんの席に行った。──行く途中で、Slack が鳴った。

> [staging-alert] daily_digest が 2 時間経過しても完了していません。プロセスは生存中。CPU 使用率 0%。

staging に入れた僕の修正版が、**固まっていた**。エラーも吐かず、死んでもいない。生きたまま、何もしていない。

「……なるほどね」画面を見た氷室さんが、目を細めた。「レースは全員が動きすぎる事件。今度は**全員が動かない事件**。深町くん、staging に入れたコード、`race.rb` の修正だけじゃないでしょう」

図星だった。ついでに帳簿も直そうと、`sent_count` 用に**もうひとつ** Mutex を足していた。ログ出力の排他用の `log_lock` と、カウンタ用の `counter_lock`。丁寧にやったつもりだった。

## 2

「順番に行きましょう。まず、あなたの fixed.rb 自体は正しい。そこは自信を持ちなさい」

氷室さんは `fixed.rb` を指した。

「`lock.synchronize do ... end` は『鍵を取れた 1 人だけがブロックに入れる。他の人は**その人が鍵を返すまで、入り口で待つ**』。これで『読む→進める』の 3 手が、割り込まれない**ひとつの操作**になった。アトミック──原子的、それ以上割れない、って言うの。第 6 話の 2 類型で言えば、check-then-act の check と act を同じ鍵の中に入れた、ということね」

「書いてて気になったんですけど、送信の sleep を鍵の**外**に出したのは、勘なんです。中に入れても正しさは変わらない気がして。どっちでもいいんですか？」

「正しさは変わらない。**速さが死ぬ**。いい機会だから測りましょう。同じ 200 通を、『送信まで鍵の中』と『送信は鍵の外』で」

:::details lock_position.rb（全文。クリックで展開）
```ruby:lock_position.rb
require "benchmark"

users = (1..200).map { |n| "user_#{n}" }

# 悪手: 送信(IO)まで鍵の中
t_inside = Benchmark.realtime do
  i, lock, sent = 0, Mutex.new, []
  threads = 4.times.map do
    Thread.new do
      loop do
        done = lock.synchronize do
          break true if i >= users.size
          u = users[i]; i += 1
          sleep 0.001          # 送信も鍵の中
          sent << u
          false
        end
        break if done
      end
    end
  end
  threads.each(&:join)
end
puts "鍵の中で送信: %.2f 秒" % t_inside

# 定石: 取り出しだけ鍵の中、送信は外
t_outside = Benchmark.realtime do
  i, lock, sent = 0, Mutex.new, []
  threads = 4.times.map do
    Thread.new do
      loop do
        user = lock.synchronize do
          break nil if i >= users.size
          u = users[i]; i += 1
          u
        end
        break if user.nil?
        sleep 0.001            # 送信は鍵の外
        sent << user
      end
    end
  end
  threads.each(&:join)
end
puts "鍵の外で送信: %.2f 秒" % t_outside
```
:::

```
$ ruby lock_position.rb
鍵の中で送信: 0.25 秒
鍵の外で送信: 0.06 秒
```

「4 倍……ちょうどスレッド数ぶんだ」

「当然よね。鍵の中には 1 人しか入れないんだから、**送信まで鍵の中に入れたら、実質 1 人ずつの直列送信**。4 人雇った意味が消える。0.25 秒はほぼ 200 × 1ms──直列と同じ。だから定石はこう。**鍵の中は「共有データを触る最小限の手数」だけ。IO は絶対に鍵の外**。鍵は安全装置だけど、かけた範囲は直列に戻る。安全と速度の境界線を、意識して引くの」

## 3

「じゃあ、本題。なんで staging は固まったのか。鍵が**2 本**あるからよ。あなたが入れたコードの、固まる部分だけを蒸留したミニチュアを作ったわ」

```ruby:deadlock.rb
log_lock     = Mutex.new
counter_lock = Mutex.new

t1 = Thread.new do
  counter_lock.synchronize do
    sleep 0.1
    log_lock.synchronize { puts "t1: 完了" }
  end
end

t2 = Thread.new do
  log_lock.synchronize do
    sleep 0.1
    counter_lock.synchronize { puts "t2: 完了" }
  end
end

t1.join
t2.join
```

「t1 は**カウンタの鍵を持ったままログの鍵**を取りに行く。t2 は**ログの鍵を持ったままカウンタの鍵**を取りに行く。実行して」

```
$ ruby deadlock.rb
deadlock.rb:18:in 'Thread#join': No live threads left. Deadlock? (fatal)
3 threads, 3 sleeps current:0x00000009b8582e00 main thread:0x000000010324dd20
* #<Thread:0x0000000102668d18 sleep_forever>
   ...
* #<Thread:0x00000001220a2b20 deadlock.rb:4 sleep_forever>
   ...
   deadlock.rb:7:in 'Thread::Mutex#synchronize'
   deadlock.rb:5:in 'Thread::Mutex#synchronize'
* #<Thread:0x00000001220a2a08 deadlock.rb:11 sleep_forever>
   ...
   deadlock.rb:14:in 'Thread::Mutex#synchronize'
   deadlock.rb:12:in 'Thread::Mutex#synchronize'
```

「`No live threads left. Deadlock?`……Ruby が自分で言ってる」

「この出力、ちゃんと読めるのよ。**スレッドダンプ**──固まった瞬間の、全員の現場写真。t1 は 5 行目で 1 個目の鍵を取り、7 行目で 2 個目を**待ってる**。t2 は 12 行目で取って 14 行目で**待ってる**。お互いが、**相手が持ってる鍵を、自分の鍵を握りしめたまま待ってる**。どちらも絶対に手放さないから、永遠に終わらない。──**デッドロック**。ミステリーで言えば密室ね。中の 2 人は生きてるのに、部屋は永久に開かない」

「エラーで落ちてくれただけ、親切ですね……」

「そこ、大事な注意よ。Ruby がこの `fatal` を出せるのは、**プロセス内の全スレッドが眠って、もう誰も何もできなくなったときだけ**。あなたの staging では監視用のスレッドが 1 本生きてたでしょ。1 人でも起きてる人がいると、Ruby は『まだ何か起きるかも』と判断して検出しない。だから本番のデッドロックはエラーにならず、**ただ静かに固まる**。CPU 0% でプロセス生存──今朝のアラートそのものよ」

「あと、これも聞いていいですか。修正を staging に入れたのは火曜の夜です。でも火曜のバッチは正常に完走してて、固まったのは水曜。デッドロックって、書いた瞬間から毎回起きるものじゃないんですか？」

「レースの弟分だもの、こいつも**確率の犯罪**よ。deadlock.rb の `sleep 0.1` は、わざと衝突させるための細工。実物では、t1 が 2 本目の鍵を取りに行く*まさにその隙間*で、t2 が 1 本目を取ったときだけ密室が完成する。隙間が狭ければ何日も起きない。──書いた瞬間に必ず固まるなら、世界中の誰もデッドロックで苦労しないの。**「昨日は動いた」は、並行処理では何の弁護にもならない**」

## 4

「直し方は 2 段階。まず一般解。デッドロックの成立条件は『鍵を持ったまま、別の鍵を待つ』、それが**循環する**こと。だから──」

**ルール: 複数の鍵を取るときは、全員が必ず同じ順番で取る。**

「t2 の取り順を t1 と同じ『counter → log』に揃えるだけ。実験するわよ」

```ruby:lock_order.rb
log_lock     = Mutex.new
counter_lock = Mutex.new

# 両方とも counter_lock → log_lock の順で取る
t1 = Thread.new do
  counter_lock.synchronize do
    sleep 0.1
    log_lock.synchronize { puts "t1: 完了" }
  end
end

t2 = Thread.new do
  counter_lock.synchronize do
    sleep 0.1
    log_lock.synchronize { puts "t2: 完了" }
  end
end

t1.join
t2.join
puts "全員無事に退室"
```

```
$ ruby lock_order.rb
t1: 完了
t2: 完了
全員無事に退室
```

「密室が開いた。……理屈も分かります。全員が counter の鍵から取るなら、2 本目の log を持ったまま counter を待つ人は存在しえない。**循環が構造的に起きない**」

「そう。順番さえ守れば鍵は何本あってもいい。ただし『守れば』の部分は人間の規律だから、コードが増えるほど怪しくなる。──そこで 2 段目。**そもそも鍵を 2 本にしない**。あなたのケース、`log_lock` と `counter_lock` を分ける必要、本当にあった？」

「……パフォーマンスのつもりでした。ログとカウンタは別のデータだから、別の鍵の方が待ちが減るかなって」

「気持ちは分かるけど、さっき測ったでしょう。**鍵の中が一瞬なら、鍵の競合はボトルネックにならない**。ログ 1 行とカウンタ +1 なんてマイクロ秒の世界よ。それを守る鍵を 2 本に分けて得られる速度と、密室のリスク。割に合わない。**鍵の本数は、少なければ少ないほど安全**。1 本で足りるなら 1 本。──そしてね」

氷室さんは、ホワイトボードの隅に小さく書き足した。

「理想を言えば、**鍵なんて 1 本も持ちたくない**の。鍵が必要になるのは共有データを直接触るから。共有の触り方そのものを設計で消せるなら、レースも密室も、最初から起きようがない。Ruby にはそのための道具が標準で入ってる。金曜の最終報告までに、修正版をもう一度書き直しましょう。それと──」

「それと？」

「調査スレッドに、育休中の岸田さんからコメントが来てるの。『自分の PR が原因みたいで本当にすみません。ひとつ気になってるんですが──そもそも Ruby には GVL があって、スレッドは並列に動かないはずですよね。なのになんで自分の並列化は 3 時間を 40 分にできたんでしょう』って。──罪の告白より、いい質問のほうが先に来るあたり、あの人らしいわね。明日はこの事件の**舞台装置**の話。あなたのバッチが速くなった本当の理由と、第 6 話で棚上げにした『純 CPU ループはなぜ壊れなかったか』を、まとめて回収するわよ」

（第8話「一人しか立てない舞台 ── GVL」につづく）

---

## 捜査メモ

- **Mutex** = 1 本しかない鍵。`lock.synchronize { ... }` の中には同時に 1 スレッドしか入れず、「読む→書く」を**アトミック**（割り込み不可能な 1 操作）にできる（実測: 200 / 200 / 二重 0 人）
- 鍵の中は「共有データを触る最小限の手数」だけ。**IO を鍵の中に入れると実質直列**に戻る（実測: 送信を鍵の中に入れると 0.25 秒、外に出すと 0.06 秒──ちょうどスレッド数ぶんの差）
- **デッドロック** = お互いが「自分の鍵を握ったまま、相手の鍵を待つ」ことが循環する密室。エラーにならず**静かに固まる**（CPU 0%・プロセス生存）のが最大の特徴。レース同様、**確率でしか発生しない**
- Ruby の `No live threads left. Deadlock? (fatal)` は**全スレッドが停止したときだけ**出る。1 本でもスレッドが生きている本番では検出されない。出力はスレッドダンプ＝固まった瞬間の全員の現場写真として読める
- 対策: ① 複数の鍵は**全員が同じ順番で取る**（循環を構造的に断つ。実測で密室が開いた）② そもそも**鍵の本数を減らす**（鍵の中が一瞬なら競合はボトルネックにならない）③ 究極は共有の触り方を設計で消す（→ 最終話の Queue）
