---
title: "GitHub Actions の workflow duration を gh-pages に時系列で蓄積する Action を作った"
emoji: "⏱️"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["githubactions", "typescript", "github", "ci", "octokit"]
published: false
---


## はじめに

「最近 CI 遅くない？」とか「早くなった？」と感じたとき、過去と比較する方法がパッと出てこなくて困ったことがよくあります。

- CI の実行結果を BigQuery に流す仕組みを組むのは大袈裟
- Artifact に残しても並べて見れないし、日数が経つと消える可能性がある
- GitHub のコメントは流れていってしまう

って面倒があり、「workflow に 数行足すだけで、過去全 run の duration が時系列グラフで見られる」ようにしたい。と思って作ったのが [ghtrack](https://github.com/hatsu38/ghtrack) というカスタムアクションです。

https://github.com/hatsu38/ghtrack

会社のリポジトリとかにはもう入れているのですが、使ってみたら結構便利だったので、紹介 & 設計で工夫したポイントを紹介します。

## ghtrack とは

`ghtrack` は workflow の job / step ごとの duration を毎回 任意(デフォルトは `gh-pages`)の ブランチへ書き出し、グラフで閲覧できるようにするカスタムアクションです。 gh-pages ブランチに溜まるので、GitHub pages でみることができます。

例えば以下のような感じですね。

https://hatsu38.github.io/ghtrack/

画像は、上記と別のリポジトリの計測結果です。

![ghtrack のダッシュボード（unit-test workflow の例）](/images/ghtrack-actions-duration-tracker/unit-test-ci-ghtrack.png)

CI の日毎の時間がここに並んでいます。

その時間をさらに詳細に、**どのJobに時間がかかっているか、どのStepに時間かかっているか**もわかります。

さらに、**日毎 / 週毎 / Run毎 に分割**してみることができます。

便利ですね〜。自分が見たいと思っていたものを全部載せています！

ということで、ここからは、ghtrack を作るときに考えた設計の話を書いていきます。


## 設計の概要

まずは、簡単に ghtrack の動作フロー全体を一度ざっと紹介します。
利用者から見ると、CI の workflow の最後に以下のような 1 step 足すだけで使えます。便利ですねぇ。

```yml
    steps:
      - uses: hatsu38/ghtrack@v1
```

この Step を追加すると、そのリポジトリの `gh-pages` に CI 結果が json で溜まっていって、GitHub Pages がそれを Chart.js で表示してくれる、という形です。

で、やっていることは

1. **`action.yml`** で workflow から呼ばれる（`uses: hatsu38/ghtrack@v1` の 1 行）
2. **`src/collect.ts`** で `listJobsForWorkflowRun` を叩いて、自分が動いている workflow run の job / step duration を取得する
3. **`src/storage.ts`** で `gh-pages` に per-run JSON を追記して、`index.html`（Chart.js のダッシュボード）も同梱する

![ghtrack の動作フロー全体図](/images/ghtrack-actions-duration-tracker/design-overview-flow.png)

ですね。それぞれ順番に見ていきます。

:::message
**参考にしたアイデア**

簡単に CI の実行結果履歴を集めて閲覧できるような仕組みを作りたい、とは結構前から思っていたのですが、実現方法の案がなくて、できていなかったんですよね。で、そんな時に
 [benchmark-action/github-action-benchmark](https://github.com/benchmark-action/github-action-benchmark) を見つけて、GitHub Pages に吐き出してグラフを見るっていうのが、良いなと思って、参考にしました。
:::

### 1. action.yml で workflow から呼ばれる

利用者側は workflow ファイルの最後に track 用の job を 1 つ足すだけで使えます。

```yaml:.github/workflows/test.yml (利用例)
jobs:
  unit-test:
    runs-on: ubuntu-latest
    steps:
      - run: # 実際のテスト

  track:
    needs: unit-test
    runs-on: ubuntu-latest
    permissions:
      contents: write   # gh-pages への push に必要
      actions: read     # workflow run / job の API 取得に必要
    steps:
      - uses: hatsu38/ghtrack@v1
```

ghtrack 側の `action.yml` では、これに対応して inputs と runs を定義しています。

```yaml:action.yml
inputs:
  github-token:
    required: false
    default: ${{ github.token }}
  gh-pages-branch:
    required: false
    default: gh-pages
  track-name:
    required: false
runs:
  using: node24
  main: dist/index.js
```

`github-token` は default で [`${{ github.token }}`](https://docs.github.com/en/actions/security-for-github-actions/security-guides/automatic-token-authentication) を使うようにしているので、利用者は何も渡さなくて大丈夫です。workflow 側の [`permissions:` 設定](https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions#permissions) で `contents: write` を付けておけば、その権限の付いた token が自動で流れてきます。

そして `track-name` のデフォルトは workflow ファイル名（`test.yml` → `test`）にしています。これは作ってから運用してみて変えたもので、ファイル名をキーにしておくと、次の 2 つの嬉しさがあります。

#### a. workflow ファイル名は同一リポ内で必ず一意

job 名や workflow YAML の `name:` 属性ではなく、ファイル名（basename）をキーにすると、複数 workflow のデータが path で衝突しません。

たとえば自分のリポジトリでは、`test` という名前の job が `unit_test.yml` と `e2e.yml` の両方にいました。もし job 名や `name:` をキーにしていたら、別 workflow のデータがダッシュボード上で混ざってしまうところでした。

ファイル名なら GitHub Actions の workflow 一覧の単位そのままなので、衝突の心配がありません。しかも `name:` と違って、そうそう変更されないですしね。

#### b. matrix shard などで明示的に上書きもできる

matrix shard などで「1 workflow を複数 track に分けたい」ときは、`track-name: e2e-shard-${{ matrix.shard }}` のように上書きできます。デフォルトのファイル名キーで困ったときの逃げ道も用意してあります。


ちなみに ghtrack の **最初の最初は、workflow を区別する仕組みすら無くて `data/data.json` 1 ファイルに全 run を詰め込んでいました**。

「1 つのグラフに全 workflow が乗るほうが見やすいかな」と思っていたんですが、運用してみたら流石に見づらすぎて、複数 workflow を分けたくなったタイミングで manifest と track-name を一緒に入れた、という経緯です。

そこで「毎回 track-name を指定させるのは面倒」だったので、デフォルトをファイル名にした、という流れでした。

### 2. collect.ts で listJobsForWorkflowRun を使って duration を取得

duration の取得は、Octokit の [`actions.listJobsForWorkflowRun`](https://docs.github.com/en/rest/actions/workflow-jobs#list-jobs-for-a-workflow-run) を叩いて、戻り値の job 一覧から `started_at` / `completed_at` の差を取っているだけのシンプルなコードです。

```typescript:src/collect.ts (抜粋)
const jobs = await octokit.paginate(
  octokit.rest.actions.listJobsForWorkflowRun,
  { owner, repo, run_id: runId, per_page: 100 },
);

const jobEntries: JobEntry[] = jobs.map((job) => ({
  name: job.name,
  duration_sec: computeDurationSec(job.started_at, job.completed_at),
  status: job.status,
  conclusion: job.conclusion,
  steps: (job.steps ?? []).map(toStepEntry),
}));
```

シンプルなコードですが、運用してみると地味にハマりどころがあって、それぞれ意識して書いた箇所があるので紹介します。

#### Octokit の `paginate` を必ず通す

`listJobsForWorkflowRun` は `per_page` の上限が **100** で、それを超える job は次ページに回ります。GitHub の REST API は [`Link` ヘッダで次ページの URL を返す方式](https://docs.github.com/en/rest/using-the-rest-api/using-pagination-in-the-rest-api)なので、これを自動で辿ってくれる [`octokit.paginate`](https://github.com/octokit/plugin-paginate-rest.js) を経由しないと、matrix shard が多い workflow で **エラーも出さずに job を取りこぼす** ことになってしまうんですよね。

たとえば `shards=8 × OS=3 × Node=3` で 72 job、ここに [reusable workflow](https://docs.github.com/en/actions/sharing-automations/reusing-workflows)（別の workflow ファイルを `uses:` で呼び出して 1 つの run にまとめる仕組み）を組み合わせると簡単に 100 を超えます。matrix が多い workflow ほど duration トラッカーの価値が大きいので、ここは最初から `paginate` で通すようにしています。

#### duration の計算で `null` を扱う

`started_at` / `completed_at` は、job / step の状態によって `null` が返ってくることがあります。`computeDurationSec` ではこんな感じで分岐させています。

```typescript:src/collect.ts (computeDurationSec)
function computeDurationSec(
  startedAt: string | null | undefined,
  completedAt: string | null | undefined,
): number | null {
  if (!startedAt || !completedAt) return null;
  const start = new Date(startedAt).getTime();
  const end = new Date(completedAt).getTime();
  if (Number.isNaN(start) || Number.isNaN(end)) return null;
  return (end - start) / 1000;
}
```

- どちらかが `null` → duration も `null` を返す（`0` を返すと「一瞬で終わった step」とグラフ上で混同されてしまうので、明示的に "値なし" として描かないようにする）
- 日付として parse できない値 → 同じく `null` を返す（API のレスポンスが想定外だったときの防御）

これを決めておかないと、`null` と `0` と数値が混ざった汚いデータが `gh-pages` にどんどん蓄積されて、後から掃除するのが大変になります。

#### `status` / `conclusion` も一緒に残しておく

per-run JSON には duration だけでなく `status` / `conclusion` も残しています。理由は **後から取り直せないデータだから** ですね。

duration トラッカーとしては数値だけで動きますが、`conclusion` を持っておくと、後からこんなことができます。

- ダッシュボードで失敗 run を区別できる（赤マーカー表示など）
- duration 平均から `cancelled` / `timed_out` を除外できる（外れ値で平均が歪まないように）
- 「直近 1 週間の失敗率」のような副次指標を後付けで足せる

gh-pages 蓄積方式は「過去に遡って再収集」が事実上できないので、取得をしています。

### 3. storage.ts で gh-pages に per-run JSON を書き出す

取得した Entry を `gh-pages` ブランチに書き出すのが `src/storage.ts` です。書き出し先のファイル構造はこんな感じになっています。

```sh
gh-pages/
├── index.html                            ← Chart.js のダッシュボード
└── data/
    ├── manifest.json                     ← workflow 一覧
    └── <track-name>/
        ├── index.json                    ← この track の run 一覧
        └── <YYYY>/<MM>/<DD>/
            └── <run_id>-<attempt>.json   ← 1 run = 1 ファイル
```

`<run_id>-<attempt>.json` が run のたびに 1 ファイル増えていって、ブラウザで `index.html` を開くと `manifest.json` → 各 track の `index.json` → per-run ファイル、の順に fetch されて時系列グラフが描画される、という流れです。

この `storage.ts` での書き出し方は、ghtrack で詰まったりした箇所ですね。下で紹介します。



## 並行 push の競合を 2 つの設計で消す

Entry を `gh-pages` にどう書くかは、ghtrack で一番設計の手数を使った部分です。並行 push の競合を、**API レイヤー**（GitHub への書き込み方）と **ファイル構造**（書き込むデータの形）の 2 方向から吸収するようにしています。

### Git Data API で複数ファイルを 1 commit にまとめる

ghtrack は Contents API ではなく **Git Data API** で `gh-pages` を書き換えています。Contents API（[`createOrUpdateFileContents`](https://docs.github.com/en/rest/repos/contents#create-or-update-file-contents)）は 1 ファイルを path + sha + content で更新するだけのシンプルな API なんですが、1 commit 1 ファイルなので、ghtrack で必要な複数ファイルを同時に書けないんですよね。

ghtrack が 1 commit で同時に書きたいのは、次の 3 つです。

- per-run の JSON ファイル（新規作成）
- workflow ごとの `index.json`（read-modify-write）
- `data/manifest.json`（初回登録時のみ）

これらを 3 回に分けて push すると、`gh-pages` 上で「per-run だけ追加されて `index.json` は古いまま」という中間状態が一瞬発生してしまって、その間にダッシュボードが読みに来ると不整合な表示になります。

Git Data API では [`createBlob`](https://docs.github.com/en/rest/git/blobs#create-a-blob) → [`createTree`](https://docs.github.com/en/rest/git/trees#create-a-tree) → [`createCommit`](https://docs.github.com/en/rest/git/commits#create-a-commit) → [`updateRef`](https://docs.github.com/en/rest/git/refs#update-a-reference) の 4 段で、1 commit に複数 path を入れられます。

```typescript:src/storage.ts (appendOnce より抜粋)
const tree = await args.octokit.rest.git.createTree({
  owner: args.owner,
  repo: args.repo,
  base_tree: baseTreeSha,
  tree: [
    { path: entryPath, mode: "100644", type: "blob", sha: entryBlob.data.sha },
    { path: indexPath, mode: "100644", type: "blob", sha: indexBlob.data.sha },
  ],
});

const commit = await args.octokit.rest.git.createCommit({
  owner: args.owner,
  repo: args.repo,
  message: `chore(ghtrack): record ${trackName} ${args.entry.run_id}-${args.entry.run_attempt}`,
  tree: tree.data.sha,
  parents: [parentSha],
  author: COMMITTER,
  committer: COMMITTER,
});

try {
  await args.octokit.rest.git.updateRef({
    owner: args.owner,
    repo: args.repo,
    ref: branchRef,
    sha: commit.data.sha,
  });
} catch (err) {
  if (errorStatus(err) === 422) return false;
  throw err;
}
```

:::message
**`updateRef` の 422 を Optimistic concurrency control のシグナルとして使う**

Git Data API の最後の `updateRef` は、対象 ref の現在値が指定した親 commit と一致しないときに **422 を返してきます**。これは「自分が `base_tree` を読んでから push するまでの間に、他の run が先に push した（＝親 commit が古くなった）」ことを意味します。

ghtrack ではこの 422 を **「他の run に先を越されたから、もう一度やり直そう」のシグナル** として扱って、指数バックオフ + jitter で retry するようにしています。先にロックを取りに行かず、「ぶつかったら後から来たほうがやり直す」というアプローチですね（[Optimistic concurrency control / 楽観的並行制御](https://en.wikipedia.org/wiki/Optimistic_concurrency_control) と呼ばれるパターンです）。指数バックオフ + jitter の組み合わせは AWS の有名な記事 [Exponential Backoff And Jitter](https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/) で詳しく解説されています。

![並行 push の競合と retry の挙動](/images/ghtrack-actions-duration-tracker/concurrent-push-retry.png)

```typescript
for (let attempt = 1; attempt <= MAX_PUSH_ATTEMPTS; attempt++) {
  const ok = await appendOnce(args);
  if (ok) return;
  if (attempt >= MAX_PUSH_ATTEMPTS) {
    throw new Error(`Failed to push after ${MAX_PUSH_ATTEMPTS} ref-conflict retries.`);
  }
  const base = RETRY_BASE_DELAY_MS * 2 ** (attempt - 1);
  const jitter = Math.floor(Math.random() * RETRY_BASE_DELAY_MS);
  await sleep(base + jitter);
}
```

注意点として、`updateRef` 以外の手順（`createBlob`、`createTree`、`createCommit`）でも 422 は返り得るんですが、それらは **バリデーションエラー** なので retry しても直りません。`appendOnce` 内では `updateRef` 呼び出し点でだけ 422 を「retry すべきシグナル」として拾うのが肝になります。
:::

:::message
**ローカルで blob hash を計算してリモートとの差分判定を済ませる**

ghtrack は `gh-pages` の root に Chart.js のダッシュボード（`index.html`）も同梱していて、リリースのたびに自動で同期しています。ただ、`index.html` の中身が前回 push したときと変わっていなければ、書き込み API は呼ばずにスキップしたいですよね。

普通にやるなら、Contents API でリモートの `index.html` を fetch してきて、ローカルと中身を比較して、違っていたら書き込み API を叩く、という流れになります。これだと変更がないときでも **比較のために中身を毎回引き寄せる** ことになって、`index.html` が大きいほど無駄が増えていきます。

Git の内部の仕組みを使うと、この中身の引き寄せを省けます。Git ではファイルの中身が `blob` というオブジェクトとして格納されていて、その識別子（hash）は次の式で決まります（詳しくは Pro Git の [Git Internals - Git Objects](https://git-scm.com/book/en/v2/Git-Internals-Git-Objects) を参照）。

```ts
sha1("blob " + ファイルサイズ + "\0" + 中身)
```

そして Contents API のレスポンスには、この blob hash が `sha` というフィールドで返ってきます。つまり、**ローカルでこの式を同じように計算してやれば、リモートからは `sha` の文字列だけ見れば判定できる**（= 中身を取ってこなくていい）ということです。

```typescript:src/storage.ts
function computeGitBlobSha(content: Buffer): string {
  const header = Buffer.from(`blob ${content.length}\0`, "utf-8");
  return crypto.createHash("sha1").update(header).update(content).digest("hex");
}
```

実際のフローはこんな感じになります。

1. ローカルの `index.html` の blob hash を `computeGitBlobSha` で計算する
2. リモートの [`getContent`](https://docs.github.com/en/rest/repos/contents#get-repository-content) を呼んで、レスポンスの `sha` フィールドと比較する
3. 一致したら書き込みをスキップ、違ったら `createOrUpdateFileContents` で更新する

毎 run で必ず走る Action なので、こういう小さな最適化でも積み重なると CI 時間と rate limit に地味に効いてきますね。
:::

### per-run file による並行 push 競合の解消

API レイヤーで `updateRef` の 422 を拾って retry する仕組みを組んでも、もう一つ問題が残っています。
**ファイル構造そのもの** が並行 push 競合を増幅してしまうケースですね。

素朴な構成だと、workflow ごとに 1 ファイル（`data/<workflow>.json`）を持って、その中の `entries[]` 配列に run を追記していく方法が考えられます。dashboard 側からは 1 リクエストで全 run が取れて楽なんですが、書き込み側からするとひどい設計になります。

- **読み書きが全 run で発生する**: 1 run の追加でファイル全体を再 serialize する必要があって、Git Data API の retry 機会が無駄に増える
- **GitHub のファイルサイズ上限にぶつかる**: GitHub にはファイルサイズの制限があって、[50 MB で警告 / 100 MB で push が失敗](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github) します。集約ファイル方式だと run が増えるほど線形に膨らんでいくので、いつか必ずこのエラーを踏みます。というか、実際にこのエラーが出ちゃいました。
- **git history が肥大化する**: 毎 run でファイル全体が書き換わるので、`gh-pages` の commit ごとの diff も大きくなっていく

![集約方式 vs per-run 方式の対比](/images/ghtrack-actions-duration-tracker/aggregate-vs-per-run.png)

ということで、ghtrack ではこれを避けて、**1 run = 1 ファイル** の構成にしていました。

```sh
gh-pages/
└── data/
    ├── manifest.json
    └── <track-name>/
        ├── index.json
        └── <YYYY>/<MM>/<DD>/
            └── <run_id>-<attempt>.json
```

per-run ファイルは `(run_id, run_attempt)` を含む一意なパスへの **新規作成だけ** なので、複数 run が同時に走っても物理的に衝突しません。read-modify-write が残るのは `index.json`（「この track にどの run があるか」を列挙）と `manifest.json`（workflow 一覧）の 2 つだけで、こちらは小さいので前述の指数バックオフで吸収できます。

ファイル数は増えますが、Pages を経由した fetch は HTTP/2 多重化が効くので、dashboard 側の体感速度はむしろ良くなりました。GitHub Pages はディレクトリリスティングを返さないので、「どの per-run ファイルが存在するか」は `index.json` の `runs[]` 配列を経由して伝えています。

```jsonc
// data/<track-name>/index.json
{
  "schema_version": 1,
  "track_name": "test",
  "runs": [
    { "date": "2026/05/15", "run_id": 9876543210, "run_attempt": 1 },
    { "date": "2026/05/15", "run_id": 9876543211, "run_attempt": 1 }
  ],
  "last_updated": 1714397040000
}
```

API レイヤーの `updateRef` retry と、ファイル構造の per-run 化は、どちらも「並行 push の競合」という同じ問題への対策ですが、**前者は「競合したときの retry を容易にする」、後者は「競合が起きる場所を減らす」** という別方向の解になっています。

## Chart.js と manifest による可視化

ダッシュボードは独立サービスにはせず、`gh-pages` の root に `index.html` を 1 枚同梱する形にしています。Chart.js v4 + date-fns adapter を jsDelivr CDN から読むだけの構成で、利用者は GitHub Pages を「Deploy from a branch → `gh-pages` / root」に設定するだけで使えるようになっています。

`index.html` の差分同期には、前述のコラムで触れた `computeGitBlobSha` の最適化が入っています。`index.html` を更新したリリースを切ったときだけ commit が発生する仕組みですね。

manifest 経由のファイル探索フローは、次のとおりです。

1. dashboard が `data/manifest.json` を fetch して workflow 一覧を得る
2. 各 workflow の `data/<track>/index.json` を fetch して run 一覧を得る
3. 期間フィルタ（デフォルト直近 30 日）で絞った per-run ファイルだけを並列 fetch する
4. fetch 済み run はメモリにキャッシュして、期間プリセットを変えても差分だけ追加読み込みする

GitHub Pages はディレクトリリスティングを返さないので、`data/` 配下を `ls` するような手段は使えません。manifest と index が **「どのファイルが存在するか」をクライアントに伝える唯一の経路** になっています。

:::message
**matrix shard は base 名にまとめて、一番遅い job だけ拾う**

GitHub Actions で `strategy.matrix` を使った job は、`test (8)` や `test (8, ubuntu)` のような括弧付きの名前で、組み合わせの数だけ返ってきます。たとえば 16 並列の matrix なら 16 個、という具合ですね。

これを愚直に全部別の線として描いてしまうと、グラフに線が 16 本並んでチャートが完全に破綻するんですよね。

そこで ghtrack では、デフォルトでは括弧の中を無視して `test` という base 名で **1 本の線にまとめて**、その run で **一番時間がかかった matrix の job** の duration を表示するようにしています。

理由はシンプルで、matrix は並列実行なので、**全体の所要時間は「一番遅い 1 個」で決まる** からですね。平均でも合計でもなく `max` を取るのが、CI を遅くしている犯人を追いかけるのに一番実用的というわけです。

「いやいや、個別に見たい」という場合は、チャート上のチェックボックスで個別展開もできるようにしていて、その状態は `localStorage` に保存しています。
:::

## まとめ

ghtrack を作る中で「あ、これ自分の引き出しに増えたな」と思ったポイントを、最後に 3 つだけまとめておきますね。

- **`gh-pages` は時系列データストアとして結構使える**: benchmark-action 方式は duration 以外にもいろいろ応用できそうだなと思いました。SaaS を契約せず、リポ内完結で観測基盤を作る選択肢として案外有効です
- **Git Data API は複数ファイルを 1 commit にまとめる道具として便利**: `updateRef` の 422 を retry のシグナルとして拾えば、ロックを取らなくても並行 push を素朴な retry ループで捌けるんですよね
- **「同時実行で競合する」問題は、retry の前にファイル構造で消せないか考えてみる**: ghtrack でも結局 per-run file 化で競合点をほぼ消す形に落ち着きました。retry は「最後の砦」であって、設計の主役にはしないほうがいいかな、と思います

リポジトリは [hatsu38/ghtrack](https://github.com/hatsu38/ghtrack) です。動作を試したい場合は、自リポの workflow に 1 step 足して Pages を有効化するだけで動きます。Issue や PR、フィードバックも大歓迎です！
