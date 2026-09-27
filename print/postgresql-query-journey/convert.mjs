// Zenn の原稿（books/postgresql-query-journey）を、Vivliostyle で組むための Markdown に変換する。
// 原稿は書き換えず、build/src に章ごとの Markdown と、使っている画像を書き出す。
//
// 使い方: [EDITION=ebook] node convert.mjs [章のスラッグ ...]
//   引数なしなら config.yaml の全章、指定すればその章だけを変換する。
//   EDITION=ebook なら電子版向けに、外部リンクをリンクのまま残す。
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(here, '..', '..');
const bookDir = join(repoRoot, 'books', 'postgresql-query-journey');
const imageDir = join(repoRoot, 'images', 'postgresql-query-journey');
const outDir = join(here, 'build', 'src');
const zennImagePrefix = '/images/postgresql-query-journey/';

// :::details は紙では畳めないので、破線の囲みにして種類のラベルを付ける（2026-09-28 のユーザー判断）。
// 「答え」は読者に予想や課題を出した直後の枠だけに付け、長い実行結果を畳んだ枠や補足とは分ける。
const ANSWER_DETAILS = new Set([
  '01-explain-basics:実行したSQLと結果',
  '11-mvcc-and-maintenance:二つの接続で確かめた結果',
  '12-ranking-revisited:集計してから題名を付けた実行結果',
  '12-ranking-revisited:調査メモの完成例',
]);

function detailsKind(slug, title) {
  if (title === '考え方' || ANSWER_DETAILS.has(`${slug}:${title}`)) return { name: 'answer', label: '答え' };
  if (/実行結果|読み出し/.test(title)) return { name: 'output', label: '実行結果' };
  return { name: 'note', label: '補足' };
}

function readChapterSlugs() {
  const config = readFileSync(join(bookDir, 'config.yaml'), 'utf8');
  const lines = config.split('\n');
  const start = lines.findIndex((line) => line.startsWith('chapters:'));
  const slugs = [];
  for (const line of lines.slice(start + 1)) {
    const match = line.match(/^\s+-\s+(\S+)/);
    if (!match) break;
    slugs.push(match[1]);
  }
  return slugs;
}

function escapeHtml(text) {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

// キャプションや details の見出しは HTML の中に置くので、インラインの Markdown を自前で HTML にする。
function inlineToHtml(text) {
  return escapeHtml(text)
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
}

// 本の中の別の章へのリンク（例: [「準備」の章](00-setup)）は、紙では押せないので文字だけ残す。
function unlinkInternal(line) {
  return line.replace(/\[([^\]]+)\]\((?!https?:)[^)]+\)/g, '$1');
}

// コード枠は1行ずつ span にして、行頭の空白の数を --indent に持たせる。
// 紙面で折り返したとき、続きがその行の字下げより右から始まり、実行計画の木の形が崩れない。
function codeBlockToHtml(info, codeLines) {
  const caption = info.includes(':') ? info.slice(info.indexOf(':') + 1) : '';
  const spans = codeLines.map((codeLine) => {
    const indent = codeLine.match(/^ */)[0].length;
    const text = codeLine.slice(indent);
    return `<span class="line" style="--indent: ${indent}">${text === '' ? '&#8203;' : escapeHtml(text)}</span>`;
  });
  const figcaption = caption ? `<figcaption>${escapeHtml(caption)}</figcaption>` : '';
  const kind = caption ? 'code-block output' : 'code-block input';
  return `<figure class="${kind}">${figcaption}<pre>${spans.join('')}</pre></figure>`;
}

// 注は、その語が出てくるページの下に置く。注の中身を参照の位置に span.footnote として埋め込み、
// CSS の float: footnote でページ下へ送る。
function footnoteSpan(html) {
  return `<span class="footnote">${html}</span>`;
}

// 印刷用では外部リンクを押せないので、リンクの文字の後ろに注を付け、URL は注に書く。
function footnoteExternalLinks(line) {
  return line.replace(/\[([^\]]+)\]\((https?:[^)\s]+)\)/g, (_, text, url) =>
    `${text}${footnoteSpan(`<span class="url">${escapeHtml(url)}</span>`)}`);
}

// Zenn の脚注（[^label] と、段落として置いた [^label]: 本文）を、参照の位置へ埋め込む。
function collectFootnotes(lines) {
  const notes = new Map();
  const rest = [];
  for (const line of lines) {
    const definition = line.match(/^\[\^([^\]]+)\]:\s*(.*)$/);
    if (definition) notes.set(definition[1], definition[2]);
    else rest.push(line);
  }
  return { notes, rest };
}

// 注の中のリンクは、注の中にさらに注を作らないよう、印刷用は「文字（URL）」、電子版はリンクにする。
function linkInsideNote(html, edition) {
  return html.replace(/\[([^\]]+)\]\((https?:[^)\s]+)\)/g, (_, text, url) =>
    edition === 'print' ? `${text}（<span class="url">${url}</span>）` : `<a href="${url}">${text}</a>`);
}

function inlineFootnoteRefs(line, notes, edition) {
  return line.replace(/\[\^([^\]]+)\]/g, (whole, label) => {
    if (!notes.has(label)) return whole;
    return footnoteSpan(linkInsideNote(inlineToHtml(unlinkInternal(notes.get(label))), edition));
  });
}

function convertChapter(slug, usedImages, edition) {
  const source = readFileSync(join(bookDir, `${slug}.md`), 'utf8');
  const frontmatter = source.match(/^---\n([\s\S]*?)\n---\n/);
  const title = frontmatter?.[1].match(/^title:\s*"?(.*?)"?\s*$/m)?.[1] ?? slug;
  const { notes, rest: lines } = collectFootnotes(source.slice(frontmatter ? frontmatter[0].length : 0).split('\n'));

  const out = [`# ${title}`, ''];
  const containers = [];
  let codeInfo = null;
  let codeLines = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    if (codeInfo === null && line.startsWith('```')) {
      codeInfo = line.slice(3).trim();
      codeLines = [];
      continue;
    }
    if (codeInfo !== null) {
      if (line.startsWith('```')) {
        out.push(codeBlockToHtml(codeInfo, codeLines));
        codeInfo = null;
      } else {
        codeLines.push(line);
      }
      continue;
    }

    const message = line.match(/^:::message(?:\s+(alert))?\s*$/);
    if (message) {
      containers.push('message');
      out.push(`<div class="message${message[1] ? ' alert' : ''}">`, '');
      continue;
    }
    const details = line.match(/^:::details\s+(.*)$/);
    if (details) {
      containers.push('details');
      const kind = detailsKind(slug, details[1].trim());
      out.push(
        `<div class="details ${kind.name}">`,
        `<p class="details-title"><span class="details-label">${kind.label}</span>${inlineToHtml(details[1])}</p>`,
        '',
      );
      continue;
    }
    if (line.trim() === ':::' && containers.length > 0) {
      containers.pop();
      out.push('', '</div>');
      continue;
    }

    // Zenn では画像の直後の斜体の行をキャプションとして書いている。
    const image = line.match(/^!\[(.*)\]\((\S+?)\)\s*$/);
    if (image) {
      const [, alt, src] = image;
      const fileName = src.startsWith(zennImagePrefix) ? src.slice(zennImagePrefix.length) : src;
      usedImages.add(fileName);
      const captionLine = lines[i + 1]?.match(/^\*(.+)\*\s*$/);
      const caption = captionLine ? `<figcaption>${inlineToHtml(captionLine[1])}</figcaption>` : '';
      if (captionLine) i++;
      out.push(`<figure><img src="images/${fileName}" alt="${escapeHtml(alt)}">${caption}</figure>`);
      continue;
    }

    // 外部リンクを注にしてから、Zenn の脚注を埋め込む（逆にすると、注の中のリンクまで注になる）
    const unlinked = unlinkInternal(line);
    const linked = edition === 'print' ? footnoteExternalLinks(unlinked) : unlinked;
    out.push(inlineFootnoteRefs(linked, notes, edition));
  }

  if (containers.length > 0) throw new Error(`${slug}: ::: の閉じ忘れがあります`);
  if (codeInfo !== null) throw new Error(`${slug}: コード枠の閉じ忘れがあります`);
  return out.join('\n');
}

const edition = process.env.EDITION === 'ebook' ? 'ebook' : 'print';
const requested = process.argv.slice(2);
const slugs = requested.length > 0 ? requested : readChapterSlugs();

rmSync(outDir, { recursive: true, force: true });
mkdirSync(join(outDir, 'images'), { recursive: true });

const usedImages = new Set();
for (const slug of slugs) {
  writeFileSync(join(outDir, `${slug}.md`), convertChapter(slug, usedImages, edition));
}
for (const fileName of usedImages) {
  copyFileSync(join(imageDir, fileName), join(outDir, 'images', fileName));
}
writeFileSync(join(outDir, 'chapters.json'), JSON.stringify(slugs));
console.log(`${slugs.length} 章、画像 ${usedImages.size} 枚を ${outDir} に書き出しました`);
