---
title: "GitHub Actions の parallel でデプロイが 8 分から 4 分になった話"
emoji: "⚡"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["githubactions", "cicd", "ci", "ecs", "devops"]
published: false
---

こんにちは、hatsu です。

先日、GitHub Actions で、同じ job の中にある複数のステップを並列に実行できる `parallel` / `background` が [2026-06-25 に GA](https://github.blog/changelog/2026-06-25-actions-steps-can-now-be-run-in-parallel/) になりましたね。

今まで Job の並列化はできましたが、 Step の並列化はできませんでした。

今回この `parallel` を触ってみて、ちゃんと早くなった例と、そこまででもなかった例があったので、そのあたりを書いていきます。


## TL;DR

- 2026-06-25 に steps 並列（`parallel:` / `background:` + `wait:`）が GA。**同じ job・同じランナー**の中で独立したステップを並列化できる。
- うまくいったのは、**直列を並列にして終わるまでの時間を縮める**ケースと、**別ランナーを1つに畳んでセットアップの重複を消し、コスト（runner-minutes）を下げる**ケース。後者は実行時間そのものはほとんど変わらない。

## parallel / background の機能 と 書き方

これまで GitHub Actions での並列は、`needs` や `matrix` を使った **job の並列** がありました。job の並列は、それぞれが**別のランナー**に割り当てられるため、独立性は高い一方で、`checkout` や `pnpm install`, `bundle install` などの **セットアップが各ランナーで重複**しています。

今回 GA になった `parallel` や `background` の機能は **step の並列** を行います。つまり、**同じ job・同じランナー・同じファイルシステムの中で並列に動く** ため、`pnpm install` などをして生成された `node_modules` をそのまま使い回せます。

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

`parallel:` は「グループ内のステップを background 化して、末尾で暗黙的に `wait` 」します。
「A, B, C をまとめて並列実行して、全部終わったら次へ」というよくあるパターンには `parallel:` が簡潔です。

より細かく「非同期で起動しておいて、任意の位置で待つ」制御をしたいときは `background:` + `wait:` を使います。

## 導入した3ケース

実際にこの機能を使った例を紹介します

- 本番 ECS デプロイ
- Ruby の静的解析
- フロントエンドの CI

で利用しました。

この3つを並べてみると、`parallel` の効き方は大きく2種類に分かれました。

- 直列だった処理を並列にして、実行時間そのものを縮める
- もともと別 job で並列だったものを1つにまとめて、セットアップの重複を消す

まずは利用した実際のケースを見ていきます。

## 実戦①：本番 ECS デプロイの待ち時間を 8 分 → 4 分

このプロダクトの本番デプロイは、web（Rails + Nginx）と worker の2つの ECS サービスを更新しています。
それぞれ `wait-for-service-stability: true` で**サービスが安定するまで待つ**ため、その1Stepだけで、4分程度かかっていました。

これが**直列**に並んでいました。web の安定を待ってから worker を始めるので、全体では約 8 分かかっていました。


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

書き方も簡単ですね。

| Before | After |
|---|---|
| ![デプロイ時間 Before](/images/github-actions-steps-parallel/deploy-before.png) | ![デプロイ時間 After](/images/github-actions-steps-parallel/deploy-after.png) |

実際の効果が、画像のように直列だった頃は概ね **8 分前後**だったものが、並列化後は **3 分前後** になりました。ほぼ半分ですね (この例では 1step そもそもの時間も減っているので、4分に短縮ではなかった)。これは「直列だったものを並列」によって効果が出たパターンです。


## 実戦②③：CI と静的解析への横展開

残る2つは、先ほどのとは性質が違います。**もともと job / ワークフローを分けて並列にしていた**ものを、1つのランナーにまとめたケースです。

### ② Ruby の静的解析：別ワークフロー2つを統合

以前は RuboCop と Brakeman を、`rubocop.yml` と `brakeman.yml` という**別々のワークフロー**で動かしていました。

どちらも Ruby のコードを読む静的解析なのに、それぞれで `checkout` → Ruby セットアップ → `bundle install` を実行していたため、セットアップが重複していました。そこで、2つを `static-analysis.yml` の1 job にまとめ、セットアップ後に `parallel:` で同時実行する形にしました。

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

反映させたところ、`parallel:` の中はこうなりました。Before は `rubocop.yml` / `brakeman.yml` の**別々のワークフロー**（それぞれ自前で `checkout`・`bundle install` する）、After は `static-analysis.yml` の1 job で `parallel:` に並べた**各ステップ**の時間です。

| 対象 | Before（別 workflow の job 全体） | After（`parallel:` 内のステップ） |
|---|---:|---:|
| RuboCop | 2分51秒 | 2分13秒 |
| Brakeman | 1分08秒 | 19秒 |
| セットアップ | 各 workflow で個別に実行 | 1回だけ（`checkout` 2秒 + Ruby 8秒） |
| ワークフロー全体 | 約2分51秒（2本が並走） | **2分31秒**（`parallel:` は重い RuboCop に律速され 2分13秒） |

`parallel:` グループの時間は、長いほうの RuboCop に依存するので、Brakeman を足しても終わるまでの時間はほぼ増えません。

しかし、同じように元々別ワークフローだった RSpec は統合していません。RSpec は実測で約10分かかるうえ DB セットアップも要る重い処理なので、`rspec.yml` の独立ワークフローのまま残しました。

効果を整理すると、終わるまでの時間は **2分51秒 → 2分31秒** とわずかに縮んだ程度です。もともと2本が別ワークフローで並走していたので、デプロイの例のように半分になる改善ではありません（RuboCop 単体もキャッシュや runner の状態で 2分06秒〜2分41秒 とブレます）。むしろ効いたのは**コスト**で、Before は2ランナーぶん（合計 約4分）動いていたのが、After は1ランナー 2分31秒 で済むようになりました。

つまりこのケースの主な効果は、時間短縮というより**セットアップ重複の削減**です。RSpec のような重い処理は分けたまま、RuboCop / Brakeman のように軽くて独立したチェックだけをまとめるのがちょうどよかったです。

### ③ フロントエンド CI：4つの別 job を1つに

フロントの CI は、Before だと `install` / `test` / `lint` / `prettier` / `type-check` / `build` の6 job でした。独立チェックは4つですが、各 job で `checkout` → `corepack enable` → `setup-node` → `pnpm install` を繰り返していました。

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

このときの代表 run は、`install` 1分03秒 / `test` 2分55秒 / `lint` 1分34秒 / `prettier` 1分15秒 / `type-check` 2分00秒 / `build` 1分36秒。6つは `install` を待ってから別々のランナーで並列に走るので、**CI が終わるまでは約4分（実測 4分13秒）**。ただし各ランナーで `pnpm install` までのセットアップが6回ぶん重複するので、**runner の合計時間（コスト）は約10分半（10分23秒）**にふくらみます。

独立している4つのチェック（`test` / `lint` / `prettier` / `type-check`）は、`install` 後の1 job にまとめて `parallel:` で同時に走らせれば、セットアップは1回で済みます。……のですが、**4つを素直に全部混ぜると、逆に遅くなりました。**

#### test を混ぜると、test に律速される

`ubuntu-slim` は 1 CPU / 5 GB しかありません。ここに CPU を食う4つを詰め込むと、一番重い `test` がリソースを奪ってさらに重くなり、他の3つ（`lint` 2分41秒 / `prettier` 1分50秒 / `type-check` 2分21秒）も遅くなりました。しかも3つが先に終わっても、job 全体は `test` の完了をずっと待ちます。

これを踏まえて「独立チェック4つを全部 `checks` に混ぜた場合」と「`test` だけ別 job に残した場合」を実測で並べたのがこの表です。

| Run | 元々（6 job・別ランナー） | 統合して test も混ぜる | 統合して test を分ける（採用） |
|---|---:|---:|---:|
| test | 2分55秒 | **4分44秒**（1 CPU の奪い合いで膨張） | 2分11秒（専用ランナー） |
| lint | 1分34秒 | 2分41秒 | 1分53秒 |
| prettier | 1分15秒 | 1分50秒 | 1分21秒 |
| type-check | 2分00秒 | 2分21秒 | 1分42秒 |
| セットアップ（`install` など） | 6 回ぶん重複 | 1 回で共有 | 1 回で共有 |
| CI が終わるまでの時間 | 約4分（4分13秒） | **約6分**（6分15秒） | **約4分**（3分57秒） |
| runner の合計時間（コスト） | 約10分半 | 約7分 | 約7分 |

※ 「分ける」列の `lint` / `prettier` / `type-check` は `checks` 1 job で**並列**に走るので、3つの合計ではなく最長の `lint` に律速され、`checks` 全体は 2分34秒。「混ぜる」列は `test` と CPU を奪い合うぶん、各チェックも単独時より膨らみました。

混ぜた場合、`test` は単独なら 2分55秒 なのに **4分44秒 まで膨れ**、`checks` 全体がそれに引きずられます。`test` を別ランナーの独立 job に出すと 2分11秒で終わり、`lint` / `prettier` / `type-check` だけの `checks`（2分34秒）と並走するので、終わるまでの時間は約4分に収まりました。

そして**元々の6 job と見比べると、統合して test を分ける場合は、終わるまでの時間は約4分のままほとんど変わっていません**。6 job のときも `install` 後は別ランナーで並列に走っていたので、統合しても終わるまでの時間はそう縮みません。
しかし runner の合計時間は、セットアップの重複が6回→1回に減り、runner の合計時間が**約10分半 → 約7分**に下がりました。

なので最終的には、`lint` / `prettier` / `type-check` の3つだけを `checks` に `parallel:` でまとめ、`test` は別 job のまま残しました。`build` も `NODE_OPTIONS=--max-old-space-size=4096` でメモリを大量に使うので、同じ理由で別 job にしています。

## job 並列（needs / matrix）との使い分け

「なんでも steps 並列にすればいい」わけではありません。フロントの `ci.yml` は、同じワークフローの中で**2種類の並列を意図的に使い分けて**います。

- `build`（`NODE_OPTIONS=--max-old-space-size=4096` でメモリを大量に使う）→ **別 job のまま**。steps 並列にすると同一ランナー上で他のチェックと**メモリを奪い合う**ため。
- `test`（他のチェックと混ぜると 4分超まで膨れるが、単独なら 2分台）→ **別 job**。
- `lint` / `prettier` / `type-check`（軽く、セットアップを共有すると得）→ **steps 並列**。

整理すると次のようになります。

| 観点 | job 並列（needs / matrix） | steps 並列（parallel:） |
|---|---|---|
| ランナー | 別ランナー | 同一ランナー |
| セットアップ | 各 job で重複 | 1回で共有できる |
| ファイルシステム | 分離 | 共有 |
| 向いている | リソース競合する重い処理・完全に独立した処理 | 軽い独立チェック・待ち時間の重ね合わせ |

同一ランナーであることは、セットアップ共有という利点であると同時に、**リソースを共有してしまう**という制約でもあります。メモリや CPU を食い合う重い処理は、あえて job で分けたほうが速いことがあります。

## 終わり

`parallel:` という Step の並列化機能がリリースされて、それを試してみました。
待望の機能で、効果あるところに使えたのが良かったです。
逆に、やりすぎると CPU や メモリ を奪い合って、それほど時間短縮の効果がないパターンも確認できて良かったです。
