---
title: "PR の概要や動作確認結果を HTML にして共有するのに、zip 化不要になった Artifact がちょうどよかった"
emoji: "📄"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["githubactions", "cicd", "ci", "artifact"]
published: false
publication_name: "she_techblog"
---

こんにちは、SHE株式会社でエンジニアをしています hatsu です。
日頃は CI の速度改善をしたり、Flaky テストを直したり、300 個以上のカラムに not null 制約を加えていったり、そういう改善をしています。
今回はそんな中でも、GitHub Actions の Artifact に関しての話です。

最近知ったのですが、2026年2月26日 に GitHub Actions の Artifact が [zip 化なしでアップロードできるようになった](https://github.blog/changelog/2026-02-26-github-actions-now-supports-uploading-and-downloading-non-zipped-artifacts/)んですね。

これが個人的には大変便利で、非常に良く利用しています。
詳しくは後述しますが、今までプルリクエストを出すときに、デザインの確認のためにも、動作確認の結果もスクショして載せていたんですよね。で、GitHub CLI(ghコマンド) や GitHub API では、プルリクエストのディスクリプションに画像を添付できなかったので、AI に自動化させるには、「AI に Chrome を立ち上げさせて...」などしていて非常に不便だったんです。

そんな悩みが、この Artifact の zip 化不要の変更で、解決して嬉しかったので、詳しく紹介していきます。

## TL;DR

- [`actions/upload-artifact@v7`](https://github.com/actions/upload-artifact/releases/tag/v7.0.0) の `archive: false` で、Artifact が zip 化されずにアップロードされる
- 単一ファイルの HTML や画像なら、Artifact の URL を開くだけでブラウザにそのまま表示される。プライベートリポジトリなら read 権限を持つ人しか開けないので、**Org 内限定の共有にちょうどいい**
- PR の変更概要をまとめたレビューガイドと、動作確認のスクリーンショットをまとめたレポートの2つを CI で生成し、Bot が URL を PR にコメントする運用にしている
- スクリーンショットは base64 で HTML に埋め込めば、画像が何枚あっても Artifact 1つ、URL 1つで済む
- 実体は Azure Blob Storage の署名付き URL で、リダイレクト後の URL は期限内（実測で約10分）なら未ログインでも開ける。リダイレクト後の URL は共有しちゃだめ

## AI に「人間が読むための HTML」を作らせる場面が増えた

コードや設計を人間が理解する手助けとして AI に HTML を作らせる、という使い方がこの1年で一気に広がった気がします。
Anthropic 社内でよく使われているという Claude Code の [`/eli5` スキル](https://github.com/anthropics/claude-plugins-community/tree/main/eli5)（5歳児にもわかるように大きな画像と少ない文章で説明するスキル）が話題になったり、ポッドキャスト [oss4.fun #96](https://oss4.fun/episode/96/) では t-wada さんが「人に優しい HTML」という話題で、人間が読むための HTML を AI に作らせる頻度が増えた話をされていたり。

↓は `/eli5 RFC 10008: HTTP QUERY Method` で生成された HTML（お手紙ごっこって可愛いw）。

![/eli5 で生成された RFC 10008 の図解 HTML の冒頭](/images/github-actions-artifact-no-zip/eli5-rfc-10008.png =450x)
*生成された HTML の冒頭部分。この調子で「困りごと → 解決 → 比較表」まで図解が続く*

私も PR のレビューのために、変更内容を HTML で図解させるのを個人的にやっていました。
手元で使うぶんには十分満足していました。
ただ、これだけ便利なら、毎回自動で生成して、チームの全員が使えるようにしたくなりますよね。
共有の手段はいくつかあって、HTML 共有サービスを自作して社内限定で共有する人もいますし、Claude の [Artifacts 機能](https://www.anthropic.com/news/artifacts) で共有リンクを作る手もあります。

ただ、CI で毎回自動生成する場合は、アップロードするのは人ではなく CI なので、ワークフローから機械的にアップロードできて、PR に貼る URL がその場で手に入ってほしいんですよね。

そのアップロードしたファイルを見せたい相手も「そのリポジトリのレビュアー」がメインなので、アクセス制御はリポジトリの権限とそろっていると便利です。で、GitHub Actions の Artifact なら、`upload-artifact` のステップ1つでアップロードでき、リポジトリの権限がそのままアクセス制御になります。

しかし大きな欠点が「zip でしか取り出せない」ことでした。
せっかく HTML を作っても、レビュアーは zip をダウンロードして、展開して、ようやく開ける。
しかも Artifact が載っている場所が分かりづらかったり遷移するのが面倒だったりするため、本当に必要にならないと見られませんでした。
実際、CI で動かしていた Playwright のテストの画面撮影結果を zip の Artifact にしていたのですが、まぁ見ないんですよね。

## zip 化がオプションになった

この欠点が、冒頭で紹介した zip 化不要の変更でようやく解消されました。素晴らしい！

- [`actions/upload-artifact`](https://github.com/actions/upload-artifact) の `with.archive` を `false` にすると、zip を作らずにアップロードする
- `archive: true`（デフォルト）や v7 より前でアップロードした Artifact は、今までどおり zip のまま

```yaml
- name: Upload HTML report
  id: upload
  uses: actions/upload-artifact@v7
  with:
    path: report.html
    archive: false
```

単一ファイルをこの設定でアップロードすると、Artifact の URL に遷移するだけで、zip の展開なしにファイルの中身をそのまま開けます。
HTML をアップロードすればページとして表示され、画像なら画像がそのまま表示される、という具合に、ブラウザで表示できる形式ならインラインで開きます（GitHub へのログインと、リポジトリの read 権限は必要です）。
URL は `steps.upload.outputs.artifact-url` で取れるので、そのまま PR コメントに埋め込めます。

![Bot が Artifact の URL を PR にコメントした例](/images/github-actions-artifact-no-zip/review-guide-bot-comment.png)
*Bot が Artifact の URL を PR にコメントした例。リンクを開くと、CI が生成した HTML がそのまま表示される（この運用は実例①で詳しく紹介します）*

冒頭に書いた「gh コマンドや GitHub API では PR に画像を添付できない」問題も、これで解決しました。
今は PR ごとに生成されるレビュー環境で、Claude が Playwright を使って動作確認し、その結果をスクリーンショット入りの HTML にまとめて Artifact で報告してくれます（この運用は実例②で詳しく紹介します）。
画像を PR に「添付」する代わりに Artifact の URL を貼る形になったので、画像添付のためだけに「AI に Chrome を立ち上げさせて...」とやる必要もなくなりました。とても便利です。

## 実例①：PR の変更概要をまとめたレビューガイド

1つ目の実例はレビューガイドです。
PR が作られたり push されたりするたびに、AI が diff を解析して「この PR がやっていること」「レビューで見てほしいポイント」「他機能への影響範囲」をまとめた HTML を生成し、Bot が PR にコメントします。

Artifact の URL を開くと、こんなレビューガイドが表示されます。

![Artifact の URL を開くと表示されるレビューガイド](/images/github-actions-artifact-no-zip/review-guide.png =600x)
*「30秒でつかむ」から始まり、影響が出る画面、レビューの経路の順に diff を案内してくれる（ぼかしは筆者によるもの）*

```yaml
- name: Upload review guide artifact
  id: upload
  uses: actions/upload-artifact@v7
  with:
    name: review-guide-pr${{ github.event.pull_request.number }}-${{ github.event.pull_request.head.sha }}
    path: review-guide.html
    archive: false
    retention-days: 3

- name: Find existing comment
  id: find_comment
  uses: peter-evans/find-comment@v4
  with:
    issue-number: ${{ github.event.pull_request.number }}
    comment-author: 'github-actions[bot]'
    body-includes: '<!-- review-guide -->'

- name: Comment with artifact link
  uses: peter-evans/create-or-update-comment@v5
  with:
    comment-id: ${{ steps.find_comment.outputs.comment-id }}
    issue-number: ${{ github.event.pull_request.number }}
    edit-mode: replace
    body: |
      <!-- review-guide -->
      ### 📋 レビューガイド

      この PR の diff を整理した HTML ガイドです（対象 head: `${{ github.event.pull_request.head.sha }}`）。

      [📄 レビューガイドを開く](${{ steps.upload.outputs.artifact-url }})
```

コメントが増えないように、新しく push されたら以前のコメントを上書きするようにしています。
Artifact 名とコメント本文の両方に head の SHA を入れているのは、新しい push があるとガイドの中身が古い head に対するものになるためです。
レビュアーが SHA を突き合わせて、最新の変更に対するガイドかどうかを確認できるようにしています。

気に入っているのは、このレポートのライフサイクルです。
CI が作って、Bot が貼って、`retention-days: 3` で3日後に勝手に消える。
恒久的なドキュメントではない使い捨てのレポートなので、消し忘れの心配がなく、Storage の使用量もたまりません。
そして URL は、プライベートリポジトリなら read 権限がある人しか開けないので、公開ホスティングと違って「社外に見える場所に置いてしまった」事故も起きません。

## 実例②：動作確認のスクショが何枚あっても、HTML 1枚で見せられる

2つ目は動作確認レポートです。
動作確認も AI に任せていて、Playwright でブラウザを操作させると、ログインから対象機能の操作完了までのスクリーンショットが複数枚できあがります。

以前はこれを zip の Artifact で共有していました（先ほど書いた「まぁ見ない」やつです）。
レビュアーは zip をダウンロードして、展開して、画像を1枚ずつ開く。
枚数が多いほど、どの画像がどの手順なのかも分かりにくくなります。

今は、手順の説明とスクリーンショットを対にして並べた HTML レポートに変換し、画像はすべて base64 で埋め込んでいます。

```js
function imageDataUri(file) {
  // 元 PNG のまま埋め込むと HTML が数十 MB に膨らむため、
  // ImageMagick があればリサイズ + JPEG 圧縮してから埋め込む
  if (magick) {
    const jpeg = resizeAndCompress(file); // 900px 幅・quality 82 程度
    return `data:image/jpeg;base64,${jpeg.toString("base64")}`;
  }
  return `data:image/png;base64,${readFileSync(file).toString("base64")}`;
}
```

これで、スクリーンショットが何枚あってもレポートは HTML 1枚に自己完結し、Artifact も1つで済みます。
レビュアーは PR コメントの URL を開くだけで、ログインから操作完了までの流れを上から順に追えます。
zip 時代に感じていた「画像がバラバラで文脈が分からない」問題も、手順の文章と画像が対になったことで一緒に解消しました。

実際の PR コメントとレポートは、こんな見た目です。

![Bot が動作確認レポートの URL を PR にコメントした様子](/images/github-actions-artifact-no-zip/verify-bot-comment.png)
*Bot が Artifact の URL を PR にコメントする*

![URL を開くと表示される動作確認レポート](/images/github-actions-artifact-no-zip/verify-report.png =500x)
*URL を開くと、結果サマリと手順ごとのスクリーンショットが並んだレポートがそのまま表示される（ぼかしは筆者によるもの）*

一方で、操作の録画（動画）は base64 で埋め込んでいません。
動画は数十 MB になりやすく、埋め込むとレポート自体が重くて開けなくなるためです。
動画だけは従来どおり zip の Artifact としてアップロードし、レポート HTML にはその URL をリンクとして書き込んでいます。

```yaml
- name: Upload verification video (zip archive)
  id: video_upload
  uses: actions/upload-artifact@v7
  with:
    name: verify-video-pr${{ env.PR_NUMBER }}
    path: verify.webm
    retention-days: 14

- name: Generate HTML report
  env:
    VIDEO_LINK: ${{ steps.video_upload.outputs.artifact-url }}
  run: node generate_report.mjs --video-link "$VIDEO_LINK" # レポート内に動画リンクを埋め込む

- name: Upload HTML report (direct link)
  uses: actions/upload-artifact@v7
  with:
    path: report.html
    archive: false
    retention-days: 14
```

「非圧縮にできるからすべて非圧縮にする」のではなく、「開いた瞬間に見たいものだけ非圧縮の HTML にまとめ、大きいファイルは zip のままリンクで逃がす」という使い分けに落ち着きました。
まぁその結果、動画まで見る機会は全然ないんですけどね。
やっぱり zip をダウンロードして展開して確認するのは面倒すぎます。

## Artifact は結局は Azure Blob Storage の署名付き URL

Artifact の URL（`github.com/<owner>/<repo>/actions/runs/<run_id>/artifacts/<artifact_id>`）を開くと、実際には Azure Blob Storage の署名付き URL（SAS）にリダイレクトされます。
このリダイレクト先の URL は、GitHub にログインしてなくても誰でも見れてしまうので、ここだけは利用する前に、具体的にどういう形になっているのかを確認しました。

リダイレクト先はこんな形の URL です（2026-08-13 に実測したもの。ハッシュ・署名・GUID は省略しています）。

```
https://productionresultssa14.blob.core.windows.net/actions-results/…/artifacts/….html
  ?rscd=inline%3B+filename%3D%22report.html%22
  &rsct=text%2Fhtml
  &se=2026-08-13T12%3A04%3A13Z
  &sig=…
  &ske=2026-08-13T12%3A59%3A10Z
  &skoid=…
  &sks=b
  &skt=2026-08-13T08%3A59%3A10Z
  &sktid=…
  &skv=2025-11-05
  &sp=r
  &spr=https
  &sr=b
  &st=2026-08-13T11%3A54%3A08Z
  &sv=2025-11-05
```

それぞれのパラメータの意味はこうです。

| パラメータ | 今回の値 | 意味 |
| --- | --- | --- |
| `sv` | 2025-11-05 | 署名に使う Storage サービスのバージョン |
| `sr` | b | 対象リソース。b は blob 単体 |
| `sp` | r | 権限。r は読み取りのみ（書き込み・削除は不可） |
| `st` | 2026-08-13T11:54:08Z | 有効期間の開始 |
| `se` | 2026-08-13T12:04:13Z | 有効期間の終了（開始の10分5秒後） |
| `spr` | https | HTTPS のみ許可 |
| `sig` | （省略） | 署名本体 |
| `skoid` / `sktid` | （GUID） | 署名した Microsoft Entra ID のプリンシパルとテナント（GitHub 側のもの） |
| `skt` / `ske` | 08:59:10Z 〜 12:59:10Z | 署名に使った user delegation key の有効期間 |
| `sks` / `skv` | b / 2025-11-05 | 委任キーの対象サービスとバージョン |
| `rscd` | inline; filename="report.html" | レスポンスの Content-Disposition を上書き |
| `rsct` | text/html | レスポンスの Content-Type を上書き |


zip 解凍なしで表示できる仕組みも、この URL に現れています。
`rsct=text/html` と `rscd=inline` が付与されることで、ブラウザがダウンロードではなくインライン表示を選ぶわけです（`inline` の挙動は [Content-Disposition（MDN）](https://developer.mozilla.org/ja/docs/Web/HTTP/Reference/Headers/Content-Disposition)を参照）。
この「クエリパラメータでレスポンスヘッダーを上書きする」挙動は [サービス SAS の作成（Microsoft Learn）](https://learn.microsoft.com/ja-jp/rest/api/storageservices/create-service-sas)で定義されている公式の仕様で、URL 全体の構成例は [サービス SAS の例（Microsoft Learn）](https://learn.microsoft.com/ja-jp/rest/api/storageservices/service-sas-examples)にも載っています。
`sk` で始まるパラメータ群は user delegation SAS（アカウントキーではなく Microsoft Entra ID の資格情報で署名する方式）のもので、[ユーザー委任 SAS の作成（Microsoft Learn）](https://learn.microsoft.com/ja-jp/rest/api/storageservices/create-user-delegation-sas)に定義があります。

権限チェックが行われる場所は、AWS S3 の presigned URL などでもおなじみの、署名付き URL の一般的な形です。

- ログインとリポジトリの read 権限のチェックは、github.com 側のリダイレクト前にだけ行われる
- リダイレクト後の Azure 側は署名しか見ない。つまり署名が有効な間（実測で10分5秒）は、GitHub にログインしていない第三者でもこの URL を開ける
- これは GitHub のバグではなく、SAS の仕様どおりの挙動

というわけで、共有するときは必ず github.com 側の URL を貼りましょう。
リダイレクト後の長い URL を Slack や Notion に貼ると、数分で 403 になって誰も見られなくなるうえに、期限内は GitHub にログインしていない人でも読めてしまいます。
いいことが何もないんですよね。

## おわりに

AI のおかげで、人間が読むための HTML を作るコストは一気に下がりました。
あとは「どこに置いて、どう共有するか」が悩みだったんですが、そこに zip 化不要になった Artifact がちょうどよかったんですよね。
リポジトリの権限で守られた URL が発行されて、PR に貼れて、期限が来たら勝手に消える。
一時的なレポートの共有に欲しいものが、追加のインフラなしで全部そろっています。
CI で HTML レポートを作っているなら、`archive: false`、ぜひ試してみてください。

## 参考リンク

- [GitHub Actions now supports uploading and downloading non-zipped artifacts（GitHub Changelog）](https://github.blog/changelog/2026-02-26-github-actions-now-supports-uploading-and-downloading-non-zipped-artifacts/)
- [REST API endpoints for GitHub Actions artifacts（GitHub Docs）](https://docs.github.com/ja/rest/actions/artifacts)
- [Shared Access Signatures（SAS）の概要（Microsoft Learn）](https://learn.microsoft.com/ja-jp/azure/storage/common/storage-sas-overview)
- [Allowed hosts for GitHub Action Summaries（GitHub community discussion）](https://github.com/orgs/community/discussions/46211)（Artifact の配信元ホスト `productionresultssa*.blob.core.windows.net` への言及がある）
