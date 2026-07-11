---
title: "GitHub Actions の parallel でデプロイは8分→3分、CI はコスト3割減になった"
emoji: "⚡"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["githubactions", "cicd", "ci", "ecs", "devops"]
published: false
---

こんにちは、hatsu です。

先日、GitHub Actions で同じ job の中にある複数のステップを並列に実行できる `parallel` / `background` が [2026-06-25 に GA](https://github.blog/changelog/2026-06-25-actions-steps-can-now-be-run-in-parallel/) になりましたね。
これまで job の並列化はできましたが、step の並列化はできませんでした。

今回この `parallel` を実際のワークフローに入れてみて、ちゃんと速くなった例と、そこまででもなかった例があったので、そのあたりを書いていきます。

## TL;DR

- 2026-06-25 に steps 並列（`parallel:` / `background:` + `wait:`）が GA。同じ job、同じランナーの中で独立したステップを並列化できる
- 効き方は大きく2種類あった
  - 直列だった処理を並列にして、終わるまでの時間を縮める（本番デプロイが8分→3分）
  - 別ランナーに分かれていた job を1つに畳んでセットアップの重複を消し、コスト（runner の合計時間）を下げる（フロント CI が約10分半→約7分）。こちらは終わるまでの時間はほとんど変わらない
- ただし 1 CPU のランナーに重い処理まで詰め込むと、CPU の奪い合いで逆に遅くなる

## parallel / background の機能と書き方

これまで GitHub Actions での並列といえば、`needs` や `matrix` を使った job の並列でした。
job の並列は、それぞれの job が別のランナーに割り当てられるため独立性が高い一方で、`checkout` や `pnpm install`、`bundle install` などのセットアップが各ランナーで重複します。

今回 GA になった `parallel` / `background` は、step 単位の並列です。
同じ job、同じランナー、同じファイルシステムの中で並列に動くため、`pnpm install` で生成した `node_modules` をそのまま使い回せます。

構文は2種類あります。

```yaml
# パターン1: parallel: ブロック
steps:
  - parallel:
      - name: Build frontend
        run: npm run build:frontend

      - name: Build backend
        run: npm run build:backend

      - name: Build docs
        run: npm run build:docs

  - name: Run tests after all builds complete
    run: npm test
```

```yaml
# パターン2: background: + wait:
steps:
  - name: Build frontend
    id: build-frontend
    run: npm run build:frontend
    background: true

  - name: Build backend
    id: build-backend
    run: npm run build:backend
    background: true

  - name: Run linter while builds run
    run: npm run lint

  - name: Wait for both builds to finish
    wait: [build-frontend, build-backend]

  - name: Run tests
    run: npm test
```

`parallel:` は、グループ内のステップを background 化して、末尾で暗黙的に `wait` する書き方です。
「A、B、C をまとめて並列実行して、全部終わったら次へ」というよくあるパターンには `parallel:` が簡潔です。
非同期で起動しておいて任意の位置で待つ、といった細かい制御をしたいときは `background:` + `wait:` を使います。

## 導入した3ケース

実際に、次の3か所で使いました。

- 本番 ECS デプロイ
- Ruby の静的解析
- フロントエンドの CI

3つを並べてみると、`parallel` の効き方は大きく2種類に分かれました。

- 直列だった処理を並列にして、終わるまでの時間を縮める
- もともと別 job で並列だったものを1つにまとめて、セットアップの重複を消す

## 実戦①：本番 ECS デプロイの並列化

このプロダクトの本番デプロイは、web（Rails + Nginx）と worker の2つの ECS サービスを更新しています。
どちらのデプロイ step も `wait-for-service-stability: true` でサービスの安定を待つため、1 step あたり4分程度かかっていました。

そしてこの2つの step は直列に並んでいました。
web の安定を待ってから worker のデプロイを始めるので、全体では約8分かかっていました。

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

web と worker のデプロイは互いに独立しているので、並列にできます。
2本を `parallel:` で囲むだけです。

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

書き方も簡単ですね。

| Before | After |
|---|---|
| ![デプロイ時間 Before](/images/github-actions-steps-parallel/deploy-before.png) | ![デプロイ時間 After](/images/github-actions-steps-parallel/deploy-after.png) |

効果は画像のとおりです。
直列だった頃は概ね8分前後だったものが、並列化後は3分前後になりました。
単純には長いほうの安定待ち（約4分）に律速されるはずですが、この run では各デプロイ自体も4分かからず終わったため、それより短く収まっています。
これは「直列だったものを並列にする」ことで効いたパターンです。

## 実戦②③：静的解析と CI への横展開

残る2つは、①とは性質が違います。
もともと job やワークフローを分けて並列にしていたものを、1つのランナーにまとめたケースです。

### ② Ruby の静的解析：別ワークフロー2つを統合

以前は RuboCop と Brakeman を、`rubocop.yml` と `brakeman.yml` という別々のワークフローで動かしていました。
どちらも Ruby のコードを読む静的解析なのに、それぞれで `checkout` → Ruby セットアップ → `bundle install` を実行しており、セットアップが重複していました。
そこで2つを `static-analysis.yml` の1 job にまとめ、セットアップ後に `parallel:` で同時実行する形にしました。

```yaml
# after: static-analysis.yml に統合
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

実測を Before / After で並べます。
Before は `rubocop.yml` / `brakeman.yml` それぞれの job 全体の時間、After は `static-analysis.yml` の1 job で `parallel:` に並べた各ステップの時間です。

| 対象 | Before（別 workflow の job 全体） | After（`parallel:` 内のステップ） |
|---|---:|---:|
| RuboCop | 2分51秒 | 2分13秒 |
| Brakeman | 1分08秒 | 19秒 |
| セットアップ | 各 workflow で個別に実行 | 1回だけ（`checkout` 2秒 + Ruby 8秒） |
| ワークフロー全体 | 約2分51秒（2本が並走） | 2分31秒 |

`parallel:` グループの時間は長いほうの RuboCop に律速されるので、Brakeman を足しても終わるまでの時間はほぼ増えません。

効果を整理すると、終わるまでの時間は 2分51秒→2分31秒 と、わずかに縮んだ程度です。
もともと2本が別ワークフローで並走していたので、デプロイの例のように半分になる改善ではありません（RuboCop 単体もキャッシュや runner の状態で 2分06秒〜2分41秒とブレます）。
効いたのはコストのほうで、Before は2ランナーぶん（合計約4分）動いていたのが、After は1ランナーの2分31秒で済むようになりました。
つまりこのケースの主な効果は、時間短縮というよりセットアップ重複の削減です。

なお、同じく別ワークフローだった RSpec は統合していません。
実測で約10分かかるうえ DB セットアップも要る重い処理なので、`rspec.yml` の独立ワークフローのまま残し、RuboCop / Brakeman のような軽くて独立したチェックだけをまとめました。

### ③ フロントエンド CI：4つの別 job を1つに

フロントの CI は、Before では `install` / `test` / `lint` / `prettier` / `type-check` / `build` の6 job 構成でした。
このうち `test` / `lint` / `prettier` / `type-check` の4つは互いに独立したチェックですが、各 job で `checkout` → `corepack enable` → `setup-node` → `pnpm install` を繰り返していました。

Before の job 定義はこんな形です。

```yaml
jobs:
  install:
    ...
  build:
    needs: install
    ...
  test:
    needs: install
    ...
  lint:
    needs: install
    ...
  prettier:
    needs: install
    ...
  type-check:
    needs: install
    ...
```

代表的な run の実測は、`install` 1分03秒 / `test` 2分55秒 / `lint` 1分34秒 / `prettier` 1分15秒 / `type-check` 2分00秒 / `build` 1分36秒でした。
6つの job は `install` を待ってから別々のランナーで並列に走るので、CI が終わるまでの時間は約4分（実測 4分13秒）です。
ただし各ランナーで `pnpm install` までのセットアップが6回ぶん重複するため、runner の合計時間（コスト）は約10分半（10分23秒）にふくらみます。

独立している4つのチェックを `install` 後の1 job にまとめて `parallel:` で走らせれば、セットアップは1回で済みます。
ところが、4つを素直に全部混ぜると**逆に遅くなりました**。

#### なぜ全部混ぜると遅くなるのか

この CI のランナーは `ubuntu-slim`（1 CPU / メモリ 5 GB）です。
ここに CPU を食う4つのチェックを同時に走らせると、互いに CPU を奪い合ってどれも単独のときより遅くなります。
特に一番重い `test` の膨らみ方が大きく、他の3つが先に終わっても、job 全体は `test` の完了を待ち続けます。

「4つを全部1 job に混ぜた場合」と「`test` だけ別 job に残した場合」を実測で並べたのが次の表です。

| Run | 元々の6 job（別ランナー） | 統合して test も混ぜる | 統合して test を分ける（採用） |
|---|---:|---:|---:|
| test | 2分55秒 | 4分44秒 | 2分11秒 |
| lint | 1分34秒 | 2分41秒 | 1分53秒 |
| prettier | 1分15秒 | 1分50秒 | 1分21秒 |
| type-check | 2分00秒 | 2分21秒 | 1分42秒 |
| セットアップ（`install` など） | 6回ぶん重複 | 1回で共有 | 1回で共有 |
| CI が終わるまでの時間 | 約4分（4分13秒） | 約6分（6分15秒） | 約4分（3分57秒） |
| runner の合計時間（コスト） | 約10分半 | 約7分 | 約7分 |

※「分ける」列の `lint` / `prettier` / `type-check` は `checks` 1 job で並列に走るので、3つの合計ではなく最長の `lint` に律速され、`checks` 全体は2分34秒。「混ぜる」列は `test` と CPU を奪い合うぶん、各チェックが単独時より膨らんでいます。

混ぜた場合、単独なら2分55秒の `test` が4分44秒まで膨れ、job 全体がそれに引きずられて約6分かかります。
`test` を別ランナーの独立 job に出すと2分11秒で終わり、`lint` / `prettier` / `type-check` だけになった `checks`（全体2分34秒）と並走するので、終わるまでの時間は約4分に収まりました。

元々の6 job 構成と見比べると、終わるまでの時間は約4分のままほとんど変わっていません。
6 job のときも `install` 後は別ランナーで並列に走っていたからです。
その代わり、セットアップの重複が6回→1回に減ったぶん、runner の合計時間は約10分半→約7分に下がりました。

最終的には、`lint` / `prettier` / `type-check` の3つだけを `checks` job に `parallel:` でまとめ、`test` は別 job のまま残しました。
`build` も `NODE_OPTIONS=--max-old-space-size=4096` を指定するほどメモリを使うため、同じ理由で別 job にしています。

## job 並列（needs / matrix）との使い分け

「なんでも steps 並列にすればいい」わけではありません。
実際、フロントの `ci.yml` では job 並列と steps 並列を1つのワークフローの中で併用しています。
2種類の並列は次のように整理できます。

| 観点 | job 並列（needs / matrix） | steps 並列（parallel:） |
|---|---|---|
| ランナー | 別ランナー | 同一ランナー |
| セットアップ | 各 job で重複 | 1回で共有できる |
| ファイルシステム | 分離 | 共有 |
| 向いている処理 | リソースを食い合う重い処理、完全に独立した処理 | 軽い独立チェック、待ち時間の重ね合わせ |

同一ランナーであることは、セットアップを共有できる利点であると同時に、CPU やメモリも共有してしまう制約です。
フロント CI の `test` や `build` のように重い処理は、job で分けたほうが速いことがあります。

## おわりに

steps 並列は待望の機能で、デプロイの安定待ちのような「直列の待ち時間」には素直に効きました。
一方で、同一ランナーに処理を詰め込みすぎると、CPU やメモリの奪い合いで逆に遅くなることも実測で確認できました。
「直列を並列にして時間を縮める」のか、「別ランナーを1つに畳んでコストを下げる」のか、どちらを狙うかを意識して使い分けるのが良さそうです。
