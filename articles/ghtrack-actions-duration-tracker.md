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

## ghtrack でできること 

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


## ghtrack の 設計

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

GitHub の REST API には、1 回のリクエストで返ってくる件数に **上限** があります。`listJobsForWorkflowRun` の場合、`per_page` パラメータで指定できる件数は **最大 100 件** で、それを超える job は次のページに回されるんですね。

「次のページがあるかどうか」は、レスポンスの [`Link` ヘッダ](https://docs.github.com/en/rest/using-the-rest-api/using-pagination-in-the-rest-api) で「次のページの URL」を返してくる仕組みで判断します。たとえばこんな感じのヘッダが返ってきます。

```
Link: <https://api.github.com/.../jobs?page=2>; rel="next",
      <https://api.github.com/.../jobs?page=3>; rel="last"
```

これを自分で見て手で次ページを辿ってもいいんですが、Octokit には [`octokit.paginate`](https://github.com/octokit/plugin-paginate-rest.js) という、`Link` ヘッダを自動で辿って **全ページを結合して返してくれるヘルパ** が用意されているので、ghtrack ではこれを使っています。

逆に言うと、`paginate` を経由せずに素朴に 1 回だけ叩くやり方だと、**最初の 100 件しか取れず終わる** ことになるんですよね。


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

取得した 1 run 分のデータを `gh-pages` ブランチに書き出すのが `src/storage.ts` です。書き出し先のファイル構造はこんな感じになっています。

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



## gh-pages への書き込み(push時)で詰まったポイント 

この 1 run 分のデータを `gh-pages` にどう書くかは、ghtrack で一番設計の手数を使った部分です。
並行 push の競合を、**API レイヤー**（GitHub への書き込み方）と **ファイル構造**（書き込むデータの形）の 2 方向から吸収するようにしています。

### Git Data API で複数ファイルを 1 commit にまとめる

ghtrack は Contents API ではなく **Git Data API** で `gh-pages` を書き換えています。Contents API（[`createOrUpdateFileContents`](https://docs.github.com/en/rest/repos/contents#create-or-update-file-contents)）は path + sha + content で 1 ファイルを更新するだけのシンプルな API です。指定できる `path` は 1 つだけで、1 回の呼び出しごとに 1 commit が作られる作りなので、ghtrack で必要な複数ファイルを 1 commit にまとめることができないんですよね。

ghtrack が 1 commit で同時に書きたいのは、次の 3 つです。

- per-run の JSON ファイル（新規作成）
- workflow ごとの `index.json`（read-modify-write）
- `data/manifest.json`（初回登録時のみ）

これらを 3 回に分けて push すると、`gh-pages` 上で「per-run だけ追加されて `index.json` は古いまま」という中間状態が一瞬発生してしまって、その間にダッシュボードが読みに来ると不整合な表示になります。

[Git Data API](https://docs.github.com/en/rest/git) は、Git の内部構造（blob / tree / commit / ref）を直接操作する API です。普段ローカルで `git add` → `git commit` → `git push` でまとめてやってくれていることを、**API として 1 段ずつ自分で呼び出せる** イメージですね。

ghtrack で push するときも、次の 4 段を順番に呼んでいます。

1. **[`createBlob`](https://docs.github.com/en/rest/git/blobs#create-a-blob)**: ファイルの中身を「blob」として 1 つずつ登録します。書きたいファイルが 3 つなら 3 回呼びます。それぞれ sha が返ってきて、これがファイル本体の ID になります
2. **[`createTree`](https://docs.github.com/en/rest/git/trees#create-a-tree)**: さっきの blob 群に `path` を付けて、`[{path, sha}, {path, sha}, ...]` の形で **配列でまとめて 1 つのツリー（≒ ディレクトリ構造）に** します。**ここで複数ファイルが 1 つにまとまる** のがキモですね
3. **[`createCommit`](https://docs.github.com/en/rest/git/commits#create-a-commit)**: 上のツリーを、親 commit の sha と commit メッセージで包んで、新しい commit にします
4. **[`updateRef`](https://docs.github.com/en/rest/git/refs#update-a-reference)**: 最後に `gh-pages` ブランチが指す先を、いま作った commit に進めます。ここで初めて「ブランチに反映」されます

Contents API が「ファイルを書く」レベルの抽象度なのに対して、Git Data API は **Git のオブジェクトモデルそのまま** の抽象度ですね。手数は多いんですが、その分自由度が高くて、複数ファイルを 1 commit に入れる、みたいなこともできる、というわけです。

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
**`updateRef` の 422 が起きたら楽観的並行制御でやり直す**

Git Data API の最後の `updateRef` は、対象 ref の現在値が指定した親 commit と一致しないときに **422 を返してきます**。これは「自分が `base_tree` を読んでから push するまでの間に、他の run が先に push した（＝親 commit が古くなった）」って意味です。

なので、ghtrack ではこの 422 が起きたら **「他の run に先を越されたから、もう一度やり直す」** 方針で、指数バックオフ + jitter で retry するようにしています。
先にロックを取りに行くより「ぶつかったら後から来たほうがやり直す」というアプローチですね（[楽観的並行制御](https://ja.wikipedia.org/wiki/%E6%A5%BD%E8%A6%B3%E7%9A%84%E4%B8%A6%E8%A1%8C%E6%80%A7%E5%88%B6%E5%BE%A1) と呼ばれるパターンです）。指数バックオフ + jitter の組み合わせは AWS Builder's Library の [ジッターを伴うタイムアウト、再試行、およびバックオフ](https://aws.amazon.com/jp/builders-library/timeouts-retries-and-backoff-with-jitter/) という記事も解説されています。

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

注意点として、`updateRef` 以外の手順（`createBlob`、`createTree`、`createCommit`）でも 422 は返り得るんですが、それらは **バリデーションエラー** なので retry しても直りません。`appendOnce` 内では `updateRef` 呼び出し点でだけ 422 を「retry すべき合図」として拾うのが大事です。
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

「`updateRef` の retry」 と 「per-run file 化」は、どっちも「並行 push でぶつかったときどうするか」という同じ問題への対策なんですが、**前者は「ぶつかったときに、やり直しやすくする」、後者は「そもそもぶつかる場所を減らす」** って違いがあったりします。

## Chart.js と manifest による可視化

ダッシュボードは独立サービスにはせず、`gh-pages` の root に `index.html` を 1 枚同梱する形にしています。Chart.js v4 + date-fns adapter を jsDelivr CDN から読むだけの構成で、利用者は GitHub Pages を「Deploy from a branch → `gh-pages` / root」に設定するだけで使えるようになっています。

`index.html` の差分同期には、前述のコラムで触れた `computeGitBlobSha` の最適化が入っています。`index.html` を更新したリリースを切ったときだけ commit が発生する仕組みですね。

manifest 経由のファイル探索フローは、次のとおりです。

1. dashboard が `data/manifest.json` を fetch して workflow 一覧を得る
2. 各 workflow の `data/<track>/index.json` を fetch して run 一覧を得る
3. 期間フィルタ（デフォルト直近 30 日）で絞った per-run ファイルだけを並列 fetch する

:::message
**matrix shard は base 名にまとめて、一番遅い job だけ拾う**

GitHub Actions で `strategy.matrix` を使った job は、`test (8)` や `test (8, ubuntu)` のような括弧付きの名前で、組み合わせの数だけ返ってきます。たとえば 16 並列の matrix なら 16 個、という具合ですね。

これを愚直に全部別の線として描いてしまうと、グラフに線が 16 本並んでチャートがだいぶ読みづらくなります。

そこで ghtrack では、デフォルトでは括弧の中を無視して `test` という base 名で **1 本の線にまとめて**、その run で **一番時間がかかった matrix の job** の duration を表示するようにしています。

「いやいや、個別に見たい」という場合は、チャート上のチェックボックスで個別展開もできるようにしていて、その状態は `localStorage` に保存しています。
:::

## おわりに

gh-pages 便利ですね。というか、git でどんどん色々なログを貯めておけるのが便利です。
最近は、GitHub に投稿されたコメントを全部とあるブランチにためて、それを AI 向けのナレッジの参考にする、とかもやっています。git はデータストアとしていいですね。

あと、`Git Data API` を今回たくさんちゃんと触りました。良い機会でした。で、運用してみて困った点が出てきて、**同時実行で競合する問題** だったり、ファイル容量が大きくなりすぎて、push できなくなるとか、そういう問題にも遭遇して、回避策考えたりしたのも良かったな、と。

リポジトリは [hatsu38/ghtrack](https://github.com/hatsu38/ghtrack) です。ぜひ使ってみてください。
