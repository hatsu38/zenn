---
title: "GitHub Actions の parallel でデプロイが 8 分から 4 分になった話"
emoji: "⚡"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["githubactions", "cicd", "ci", "ecs", "devops"]
published: false
---

こんにちは、hatsu です。

GitHub Actions で、同じ job の中にある複数のステップを並列に実行できる `parallel` / `background` が [2026-06-25 に GA](https://github.blog/changelog/2026-06-25-actions-steps-can-now-be-run-in-parallel/) になりましたね。これはかなり待っていた機能です。

今まで Job の並列化はできましたが、 Step の並列化はできませんでした。

今回この `parallel` を触ってみて、ちゃんと早くなった例と、そこまででもなかった例があったので、そのあたりを書いていきます。


## TL;DR

- 2026-06-25 に steps 並列（`parallel:` / `background:` + `wait:`）が GA。**同じ job・同じランナー**の中で独立したステップを並列化できる。
- うまくいったのは、**直列を並列にして時間（wall-clock）を縮める**ケースと、**別ランナーを1つに畳んでセットアップの重複を消し、コスト（runner-minutes）を下げる**ケース。後者は実行時間そのものはほとんど変わらない。
- 一番ハマるのは、**`background` ステップの outputs / env は `wait` するまで後続ステップに反映されない**こと。出力を消費するステップを同じ並列グループに入れると壊れる。

## まずは使い方の紹介です

これまで GitHub Actions で並列は、`needs` や `matrix` を使って **job の並列** をしていました。job 並列は、それぞれが**別のランナー**に割り当てられます。独立性は高い一方で、`checkout` や依存関係のインストールといった**セットアップが各ランナーで重複**します。

今回 GA になったのは、それとは別レイヤーの **step の並列**です。決定的な違いは、**同じ job・同じランナー・同じファイルシステムの中で並列に動く**こと。セットアップを1回で共有できるのが大きな特徴です。

構文は2種類あります。

```yaml
# パターン1: parallel: ブロック
steps:
  - parallel:
      - name: A
        run: ...
      - name: B
        run: ...

# パターン2: background: + wait:
steps:
  - name: A
    id: a
    background: true    # 非同期に起動し、すぐ次のステップへ進む
    run: ...
  - name: B
    run: ...
  - wait: a             # ここで A の完了を待つ
```

`parallel:` は「グループ内のステップを background 化して、末尾で暗黙的に `wait` する」ための糖衣構文です。「これらをまとめて並列実行して、全部終わったら次へ」というよくあるパターンには `parallel:` が簡潔です。より細かく「非同期で起動しておいて、任意の位置で待つ」制御をしたいときは `background:` + `wait:` を使います。

## 3つのパターン

実際に入れたのは次の3つです。

- 本番 ECS デプロイ
- Ruby の静的解析
- フロントエンドの CI

この3つを並べてみると、`parallel` の効き方は大きく2種類に分かれました。

- 直列だった処理を並列にして、実行時間そのものを縮める
- もともと別 job で並列だったものを1つにまとめて、セットアップの重複を消す

## どういうときに効くのか

ここが今回いちばん大事なところです。3つのワークフローに入れて分かったのは、steps 並列の恩恵は**2つの異なる軸**に分かれる、ということでした。

- **軸A（時間）**: これまで**直列**だった処理を並列化する。実行時間（wall-clock）がそのまま縮む。
- **軸B（コスト）**: すでに **job を分けて並列**にしていたものを、1つのランナーに畳む。実行時間はほぼ変わらないが、各ランナーで**重複していたセットアップ**（`checkout` / `bundle install` / `pnpm install`）が N 回 → 1 回になり、課金される runner-minutes が減る。

「並列化したら速くなった」と一括りにすると、軸B のケースで話が破綻します。実際に測った結果は次のとおりでした。

| ケース | before の構造 | before 実測 | after 実測 | 勝ち筋 |
|---|---|---|---|---|
| ① 本番 deploy | web/worker の deploy を**直列** | 約 8 分（≈490s） | 約 4 分（≈255s） | **軸A**: wall-clock 約半減 |
| ② 静的解析 | rubocop / brakeman を**別ワークフロー** | rubocop ~250s / brakeman ~100s（別ランナーで並列） | ~170s | **軸B**（＋実行時間も微減） |
| ③ フロント CI | 4チェックを**別 job**（各 job で setup） | 全体 ~320〜540s | 全体 ~270〜730s（**横ばい**） | **軸B**: runner-minutes 削減 |

以下、それぞれを見ていきます。

## 実戦①：本番 ECS デプロイの待ち時間を 8 分 → 4 分（軸A）

このプロダクトの本番デプロイは、web（Rails + Nginx）と worker の2つの ECS サービスを更新します。それぞれ `wait-for-service-stability: true` で**サービスが安定するまで待つ**ため、1本あたり最大 15 分（`timeout-minutes: 15`）かかります。

これが**直列**に並んでいました。web の安定を待ってから worker を始めるので、最悪ケースは 15 + 15 = 30 分です。

```yaml
# before（直列）
    - name: Deploy Amazon ECS task definition          # web (Rails + Nginx)
      uses: aws-actions/amazon-ecs-deploy-task-definition@v2
      timeout-minutes: 15
      with:
        task-definition: ${{ steps.nginx-render-app-container.outputs.task-definition }}
        wait-for-service-stability: true

    - name: 【Worker】Deploy Amazon ECS task definition  # web の完了を待ってから開始
      uses: aws-actions/amazon-ecs-deploy-task-definition@v2
      timeout-minutes: 15
      with:
        task-definition: ${{ steps.worker-render-container.outputs.task-definition }}
        wait-for-service-stability: true
```

web と worker のデプロイは互いに独立しているので、並列にできます。2本を `parallel:` で囲むだけです。

```yaml
# after（並列）
    - parallel:
        - name: Deploy Amazon ECS task definition
          uses: aws-actions/amazon-ecs-deploy-task-definition@v2
          timeout-minutes: 15
          with:
            task-definition: ${{ steps.nginx-render-app-container.outputs.task-definition }}
            wait-for-service-stability: true

        - name: 【Worker】Deploy Amazon ECS task definition
          uses: aws-actions/amazon-ecs-deploy-task-definition@v2
          timeout-minutes: 15
          with:
            task-definition: ${{ steps.worker-render-container.outputs.task-definition }}
            wait-for-service-stability: true
```

ここで注目してほしいのは、**`parallel:` の中身が `uses:` ステップ**だという点です。steps 並列は `run:` だけでなくアクション呼び出しにも使えます。この deploy ワークフローがまさにその実例です。

### 最初の罠：outputs は wait まで反映されない

実はこのデプロイ、`parallel:` を付ける前段に **`ecs-render-task-definition` の render ステップ**があります。render は、イメージタグを埋め込んだ task-definition JSON を生成して `outputs.task-definition` に出力し、それを deploy ステップが**消費**します。

ここで素朴に「render も deploy もまとめて並列にすればいい」と考えると壊れます。理由は、**`background`（＝ `parallel:` の中身）ステップの outputs / env は、`wait` するまで後続ステップにフラッシュされない**からです。公式ドキュメントにも、`wait` は「後続ステップのために環境変数や outputs がセットされることを保証するまでブロックする」と書かれています。

つまり render を deploy と同じ `parallel:` グループに入れると、deploy は render の出力（task-definition）を受け取れません。

解決策はシンプルで、**出力を消費する依存があるものは並列に入れない**。render の3本は前段で直列に実行して出力を確定させ、独立した deploy の2本だけを `parallel:` にしました。実際のワークフローには、この判断をそのままコメントで残してあります。

```yaml
    # task definition の render は数秒で完了し、直後の deploy が outputs.task-definition を消費するため、
    # 3 つとも並列ブロックの前段で直列に実行して出力を確定させておく。
    # （steps 並列機能では background ステップの outputs が wait までフラッシュされないため、
    #   render を deploy と同じ parallel グループに入れると deploy が render 出力を受け取れない）
```

### 実測

デプロイはリリース公開時にだけ走るのでサンプルは多くありませんが、直列だった頃は概ね **8 分前後（約 490s）**、並列化後は **4 分前後（約 255s）** になりました。ほぼ半分ですね。これは「直列だったものを並列にした」＝**軸A**の効果で、素直に wall-clock が縮んだケースです。

## 実戦②③：CI と静的解析への横展開（軸B）

残る2つは、性質が違います。**もともと job / ワークフローを分けて並列にしていた**ものを、1つのランナーに畳んだケースです。

### ② Ruby の静的解析：別ワークフロー2つを統合

以前は RuboCop と Brakeman を、`rubocop.yml` と `brakeman.yml` という**別々のワークフロー**で動かしていました。それぞれが `checkout` → Ruby セットアップ（`bundle install`）を実行してから、本体のチェックを走らせます。別ワークフローなので同時に起動し、実行そのものは並列です。

これを1つの job に統合し、セットアップを1回だけにしました。

```yaml
    steps:
      - uses: actions/checkout@v7
      - name: Ruby セットアップ
        uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true          # ← セットアップはこの1回だけ

      - parallel:
          - name: RuboCop を実行
            run: bundle exec rubocop --parallel ...
          - name: Brakeman を実行
            run: bundle exec brakeman -A
```

### ③ フロントエンド CI：4つの別 job を1つに

フロントの CI は、`test` / `lint` / `prettier` / `type-check` という4つのチェックを、**それぞれ独立した job**で走らせていました。すべて `needs: install` で、かつ**各 job が `checkout` + `setup-node` + `pnpm install` を繰り返して**いました。セットアップが4回分重複していたわけです。

```yaml
  # before: test / lint / prettier / type-check がそれぞれ独立 job で、
  #         各 job が checkout + corepack + setup-node + pnpm install を繰り返す（setup 4 回）
  # after:
  checks:
    needs: install
    steps:
      - uses: actions/checkout@v7
      - run: corepack enable
      - uses: actions/setup-node@v6.4.0
        with: { node-version: 24.x, cache: pnpm }
      - run: pnpm install --frozen-lockfile      # ← setup はこの1回だけ

      - parallel:
          - name: Test
            run: pnpm run test
          - name: Lint
            run: pnpm run lint .
          - name: Prettier Format
            run: pnpm run format .
          - name: Type Check
            run: pnpm run type:check
```

### 速くなったのではなく、安くなった

②③に共通する構図は「**重いセットアップを1回だけ実行し、その上で独立したチェックを並列に走らせる**」です。

ここが軸B の肝で、正直に書くと **wall-clock（実行時間）はほとんど変わりません**。もともと別 job / 別ワークフローで並列に動いていたので、同時実行の効果は最初から得られていたからです。実際、フロント CI の全体時間は統合の前後でほぼ横ばい（誤差の範囲）でした。フロント CI の実行時間はメモリを大量に使う `build` job が支配的で、そちらは別 job のまま残していることもあり、`checks` の統合は全体時間をほとんど動かしません。

では何が変わったのか。**重複していたセットアップが消えました**。フロントは `pnpm install` を含むセットアップが 4 回 → 1 回に、静的解析は `bundle install` を含むランナーが 2 台 → 1 台に。つまり課金される **runner-minutes（コスト）が減った**のです。静的解析は運良く実行時間も少し縮みました（rubocop 単体のワークフローが長い時で ~250s だったのが、統合後は ~170s 前後）が、これは副次的な効果です。

「並列化 = 高速化」ではなく、このケースでは「**並列化 = 重複排除によるコスト削減**」。同じ機能でも効き方が違う、というのがこの2軸の話です。

:::message
`rake parallel:spec` は別レイヤー
このリポジトリの RSpec ワークフローには `bundle exec rake parallel:spec` がありますが、これは [parallel_tests](https://github.com/grosser/parallel_tests) gem による**プロセス並列**で、GitHub Actions の steps 並列とは無関係です。「同じ parallel でもレイヤーが違う」ことに注意してください。
:::

## ハマりどころ／非自明な制約

導入前に知っておきたい点をまとめます（一次情報は公式 changelog と [community discussion #14484](https://github.com/orgs/community/discussions/14484)）。

- **`uses:` ステップも並列できる。** `run:` 限定ではありません。さっきのデプロイ例が `uses:` を `parallel:` で回している実例です。
- **`background` ステップの outputs / env は `wait` まで反映されない。** 出力を消費する後続ステップを同じ並列グループに入れてはいけません。§1 のデプロイの罠の正体がこれです。
- **1 job 内で同時に走らせられる background は最大 10。** ランナーを圧迫しないための安全上限として設定されています。
- **composite action の内部では `background` / `parallel` を宣言できない。** ただし composite action **そのもの**を1つの background ステップとして起動するのは可能です。
- `wait` / `cancel` は `if:` に対応しない（＝常に実行される）想定です。成否による分岐は通常ステップ側に書きます。※ここは公開前に公式ドキュメントで最終確認してください。

## job 並列（needs / matrix）との使い分け

「なんでも steps 並列にすればいい」わけではありません。フロントの `ci.yml` は、同じワークフローの中で**2種類の並列を意図的に使い分けて**います。

- `build`（`NODE_OPTIONS=--max-old-space-size=4096` でメモリを大量に使う）→ **別 job のまま**。steps 並列にすると同一ランナー上で他のチェックと**メモリを奪い合う**ため。
- `test` / `lint` / `prettier` / `type-check`（軽く、セットアップを共有すると得）→ **steps 並列**。

判断軸を整理すると次のようになります。

| 観点 | job 並列（needs / matrix） | steps 並列（parallel:） |
|---|---|---|
| ランナー | 別ランナー | 同一ランナー |
| セットアップ | 各 job で重複 | 1回で共有できる |
| ファイルシステム | 分離 | 共有 |
| 向いている | リソース競合する重い処理・完全に独立した処理 | 軽い独立チェック・待ち時間の重ね合わせ |

同一ランナーであることは、セットアップ共有という利点であると同時に、**リソースを共有してしまう**という制約でもあります。メモリや CPU を食い合う重い処理は、あえて job で分けたほうが速いことがあります。

## まとめ

- steps 並列が効くのは「**セットアップが重く、並列にしたい処理が軽い、または待ち時間が主体**」なケース。
- 勝ち筋は2軸あります。**直列を並列にする（時間）**か、**別ランナーを1つに畳んでセットアップ重複を消す（コスト）**かです。自分のワークフローがどちらの課題を抱えているかを見極めてから入れると、期待と結果がズレにくいです。
- 最初に効かせやすいのは、デプロイの stability 待ちのように**直列だった待ち時間**の並列化（軸A）です。
- 一番刺さる制約は、**`background` の outputs / env が `wait` まで反映されない**ことです。出力に依存するステップは並列に入れないほうがいいです。

## 参考リンク

- [Actions steps can now be run in parallel — GitHub Changelog](https://github.blog/changelog/2026-06-25-actions-steps-can-now-be-run-in-parallel/)
- [Parallel Steps · community · Discussion #14484](https://github.com/orgs/community/discussions/14484)
- [Workflow syntax for GitHub Actions — GitHub Docs](https://docs.github.com/en/actions/reference/workflow-syntax-for-github-actions)
