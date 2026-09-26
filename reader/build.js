// Builds every book under ../books into a static site in ../dist (or $OUT_DIR).
//
//   books/<series>/series.yml          title, description
//   books/<series>/<book>/book.yml     title, subtitle, description, parts: [{ title, chapters: [file.md] }]
//   books/<series>/<book>/*.md         chapters; the first "# " heading is the chapter title
//
// Everything is rendered here, at build time: markdown, syntax highlighting, tables of contents, the search index.
// The browser only runs reader.js, which keeps reading progress and settings in localStorage. The server just serves
// files, so it holds no state and needs almost no memory.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import yaml from "js-yaml";
import MarkdownIt from "markdown-it";
import anchor from "markdown-it-anchor";
import hljs from "highlight.js";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "..");
const BOOKS_DIR = path.resolve(process.env.BOOKS_DIR || path.join(ROOT, "books"));
const OUT = path.resolve(process.env.OUT_DIR || path.join(ROOT, "dist"));
const REPO_URL = (process.env.REPO_URL || "https://github.com/czhu12/ai-lessons").replace(/\/$/, "");
const SITE_TITLE = process.env.SITE_TITLE || "AI Lessons";
const WORDS_PER_MINUTE = 220;

const escape = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const slugify = (s) => String(s).toLowerCase().replace(/<[^>]+>/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
const write = (file, content) => { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, content); };
const readYaml = (file) => (fs.existsSync(file) ? yaml.load(fs.readFileSync(file, "utf8")) || {} : {});
const minutes = (words) => Math.max(1, Math.round(words / WORDS_PER_MINUTE));

// ---------------------------------------------------------------------------------------------------------------
// Discover series and books

function loadLibrary() {
  const series = [];
  for (const seriesSlug of fs.readdirSync(BOOKS_DIR).sort()) {
    const seriesDir = path.join(BOOKS_DIR, seriesSlug);
    if (!fs.statSync(seriesDir).isDirectory()) continue;
    const meta = readYaml(path.join(seriesDir, "series.yml"));
    const books = [];
    for (const bookSlug of fs.readdirSync(seriesDir).sort()) {
      const bookDir = path.join(seriesDir, bookSlug);
      if (!fs.statSync(bookDir).isDirectory() || !fs.existsSync(path.join(bookDir, "book.yml"))) continue;
      books.push(loadBook(seriesSlug, bookSlug, bookDir));
    }
    if (books.length) series.push({ slug: seriesSlug, title: meta.title || seriesSlug, description: meta.description || "", books });
  }
  return series;
}

function loadBook(seriesSlug, bookSlug, dir) {
  const meta = readYaml(path.join(dir, "book.yml"));
  const id = `${seriesSlug}/${bookSlug}`;
  const book = { id, seriesSlug, slug: bookSlug, dir, url: `/${id}/`, title: meta.title || bookSlug, subtitle: meta.subtitle || "",
                 description: meta.description || "", updated: meta.updated instanceof Date ? meta.updated.toISOString().slice(0, 10) : String(meta.updated || "").slice(0, 10), parts: [], chapters: [] };
  const parts = meta.parts?.length ? meta.parts
    : [{ title: "Chapters", chapters: fs.readdirSync(dir).filter((f) => f.endsWith(".md") && f !== "README.md").sort() }];
  for (const part of parts) {
    const entry = { title: part.title || "", chapters: [] };
    for (const file of part.chapters || []) {
      const source = fs.readFileSync(path.join(dir, file), "utf8");
      const title = (source.match(/^#\s+(.+)$/m) || [null, file])[1].trim();
      const chapter = { file, slug: file.replace(/\.md$/, ""), title, source, book, number: book.chapters.length + 1, part: entry.title };
      chapter.url = `${book.url}${chapter.slug}/`;
      entry.chapters.push(chapter);
      book.chapters.push(chapter);
    }
    book.parts.push(entry);
  }
  return book;
}

// ---------------------------------------------------------------------------------------------------------------
// Markdown rendering

function markdownFor(book, assets) {
  const md = new MarkdownIt({
    html: true,
    linkify: true,
    typographer: false,
    highlight(code, lang) {
      const language = lang && hljs.getLanguage(lang) ? lang : null;
      const html = language ? hljs.highlight(code, { language, ignoreIllegals: true }).value : escape(code);
      const label = lang && !["text", "plain", "txt"].includes(lang) ? `<span class="code-lang">${escape(lang)}</span>` : "";
      return `<pre class="code">${label}<code class="hljs${language ? ` language-${language}` : ""}">${html}</code></pre>`;
    },
  });
  md.use(anchor, { slugify, tabIndex: false, permalink: anchor.permalink.headerLink({ safariReaderFix: true }) });

  // Chapter links become reader URLs; images are copied into the site; anything else local links to GitHub
  const byFile = new Map(book.chapters.map((c) => [c.file, c]));
  const rewrite = (href, isImage) => {
    if (!href || /^([a-z]+:|#|\/)/i.test(href)) return href;
    const [target, hash = ""] = href.split("#");
    const rel = path.posix.normalize(target);
    if (rel === "README.md") return book.url + (hash ? `#${hash}` : "");
    if (byFile.has(rel)) return byFile.get(rel).url + (hash ? `#${hash}` : "");
    const abs = path.join(book.dir, rel);
    if (isImage && fs.existsSync(abs)) { assets.add(rel); return `${book.url}${rel}`; }
    const kind = fs.existsSync(abs) && fs.statSync(abs).isDirectory() ? "tree" : "blob";
    return `${REPO_URL}/${kind}/main/books/${book.id}/${rel}${hash ? `#${hash}` : ""}`;
  };
  const defaultLink = md.renderer.rules.link_open || ((t, i, o, e, s) => s.renderToken(t, i, o));
  md.renderer.rules.link_open = (tokens, i, opts, env, self) => {
    const token = tokens[i];
    const href = rewrite(token.attrGet("href"), false);
    token.attrSet("href", href);
    if (/^https?:/.test(href)) { token.attrSet("target", "_blank"); token.attrSet("rel", "noopener"); }
    return defaultLink(tokens, i, opts, env, self);
  };
  const defaultImage = md.renderer.rules.image;
  md.renderer.rules.image = (tokens, i, opts, env, self) => {
    tokens[i].attrSet("src", rewrite(tokens[i].attrGet("src"), true));
    tokens[i].attrSet("loading", "lazy");
    return defaultImage(tokens, i, opts, env, self);
  };
  // Wide tables scroll inside their own box instead of widening the page
  md.renderer.rules.table_open = () => '<div class="table-wrap"><table>';
  md.renderer.rules.table_close = () => "</table></div>";
  // Images written as raw HTML (e.g. inside <details>) get the same treatment
  const fixHtml = (html) => html.replace(/(<img[^>]*\ssrc=")([^"]+)"/g, (_, pre, src) => `${pre}${rewrite(src, true)}"`)
    .replace(/(<a[^>]*\shref=")([^"]+)"/g, (_, pre, href) => `${pre}${rewrite(href, false)}"`);
  for (const rule of ["html_block", "html_inline"]) {
    const original = md.renderer.rules[rule];
    md.renderer.rules[rule] = (tokens, i, opts, env, self) => fixHtml(original(tokens, i, opts, env, self));
  }
  return md;
}

function renderChapter(md, chapter) {
  const body = chapter.source.replace(/^#\s+.+\n+/m, ""); // the title is rendered by the page template
  const tokens = md.parse(body, {});
  const headings = [];
  tokens.forEach((token, i) => {
    if (token.type === "heading_open" && token.tag === "h2") {
      headings.push({ id: token.attrGet("id"), text: tokens[i + 1].children.map((c) => c.content).join("") });
    }
  });
  const html = md.renderer.render(tokens, md.options, {});
  const text = body.replace(/```[\s\S]*?```/g, " ").replace(/<[^>]+>/g, " ").replace(/[#*_`>|\-[\]()]/g, " ").replace(/\s+/g, " ").trim();
  const words = body.split(/\s+/).filter(Boolean).length;
  return { html, headings, text, minutes: minutes(words) };
}

// ---------------------------------------------------------------------------------------------------------------
// Page templates

const icon = {
  book: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 4.5A2.5 2.5 0 0 1 6.5 2H20v17H6.5A2.5 2.5 0 0 0 4 21.5z"/><path d="M4 21.5A2.5 2.5 0 0 1 6.5 19H20v3H6.5A2.5 2.5 0 0 1 4 21.5z"/></svg>',
  search: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>',
  settings: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h10M18 7h2M4 17h4M12 17h8"/><circle cx="16" cy="7" r="2"/><circle cx="10" cy="17" r="2"/></svg>',
  list: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01"/></svg>',
};

function layout({ title, page, body, data = {}, crumbs = [] }) {
  const attrs = Object.entries({ page, ...data }).map(([k, v]) => ` data-${k}="${escape(v)}"`).join("");
  const trail = crumbs.map((c) => (c.url ? `<a href="${c.url}">${escape(c.title)}</a>` : `<span>${escape(c.title)}</span>`)).join('<span class="sep">/</span>');
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${escape(title)}</title>
<link rel="stylesheet" href="/assets/reader.css">
<link rel="icon" href="/assets/favicon.svg" type="image/svg+xml">
<script>try{var s=JSON.parse(localStorage.getItem("reader:settings")||"{}");if(s.theme&&s.theme!=="auto")document.documentElement.dataset.theme=s.theme;if(s.size)document.documentElement.style.setProperty("--font-scale",s.size)}catch(e){}</script>
</head>
<body${attrs}>
<div class="progress" aria-hidden="true"><div class="progress-bar"></div></div>
<header class="topbar">
  <a class="brand" href="/">${icon.book}<span>${escape(SITE_TITLE)}</span></a>
  <nav class="crumbs">${trail}</nav>
  <div class="tools">
    <a class="tool" href="/search/" title="Search (/)">${icon.search}</a>
    <button class="tool" type="button" data-action="settings" title="Reading settings">${icon.settings}</button>
  </div>
</header>
${body}
<dialog class="settings" id="settings">
  <form method="dialog">
    <h2>Reading settings</h2>
    <fieldset><legend>Theme</legend>
      <label><input type="radio" name="theme" value="auto"> Auto</label>
      <label><input type="radio" name="theme" value="light"> Light</label>
      <label><input type="radio" name="theme" value="dark"> Dark</label>
      <label><input type="radio" name="theme" value="sepia"> Sepia</label>
    </fieldset>
    <fieldset><legend>Text size</legend>
      <div class="size-row"><button type="button" data-size="-1">A−</button><output id="size-value">100%</output><button type="button" data-size="1">A+</button></div>
    </fieldset>
    <fieldset><legend>Your progress</legend>
      <p class="hint">Progress is stored in this browser only. Copy it to move to another device.</p>
      <div class="size-row"><button type="button" data-action="export">Copy progress</button><button type="button" data-action="import">Paste progress</button><button type="button" data-action="reset" class="danger">Reset</button></div>
      <textarea id="progress-io" rows="3" placeholder="Paste exported progress here, then press Paste progress" hidden></textarea>
      <p class="hint" id="progress-msg" role="status"></p>
    </fieldset>
    <div class="dialog-actions"><button value="close">Done</button></div>
  </form>
</dialog>
<div class="toast" role="status" hidden></div>
<script src="/assets/reader.js" defer></script>
</body>
</html>
`;
}

const bookChapterIds = (book) => book.chapters.map((c) => c.slug).join(" ");

function libraryPage(library) {
  const shelves = library.map((series) => `
  <section class="shelf">
    <h2>${escape(series.title)}</h2>
    ${series.description ? `<p class="shelf-desc">${escape(series.description)}</p>` : ""}
    <div class="books">
      ${series.books.map((book) => `
      <a class="book-card" href="${book.url}" data-book="${escape(book.id)}" data-chapters="${escape(bookChapterIds(book))}">
        <div class="spine" style="--hue:${hue(book.id)}"><span>${escape(book.title)}</span></div>
        <div class="book-info">
          <h3>${escape(book.title)}</h3>
          ${book.subtitle ? `<p class="subtitle">${escape(book.subtitle)}</p>` : ""}
          <p class="desc">${escape(book.description)}</p>
          <p class="meta">${book.chapters.length} chapters · ${book.minutes} min read${book.updated ? ` · updated ${book.updated}` : ""}</p>
          <div class="meter"><div class="meter-fill"></div></div>
          <p class="book-status" data-status>Not started</p>
        </div>
      </a>`).join("")}
    </div>
  </section>`).join("");
  return layout({
    title: SITE_TITLE,
    page: "library",
    body: `<main class="library">
  <div class="continue-banner" hidden><span class="label">Continue reading</span><a class="continue-link" href="#"></a></div>
  <h1>Library</h1>
  ${shelves}
</main>`,
  });
}

function bookPage(book, series) {
  const parts = book.parts.map((part) => `
  <section class="part">
    ${book.parts.length > 1 ? `<h2>${escape(part.title)}</h2>` : ""}
    <ol class="toc" start="${part.chapters[0]?.number || 1}">
      ${part.chapters.map((c) => `
      <li data-chapter="${escape(c.slug)}">
        <a href="${c.url}"><span class="num">${c.number}</span><span class="t">${escape(c.title)}</span><span class="mins">${c.minutes} min</span><span class="state" aria-label="not started"></span></a>
      </li>`).join("")}
    </ol>
  </section>`).join("");
  return layout({
    title: `${book.title} · ${SITE_TITLE}`,
    page: "book",
    data: { book: book.id, booktitle: book.title, chapters: bookChapterIds(book) },
    crumbs: [{ title: series.title }, { title: book.title }],
    body: `<main class="book">
  <header class="book-head">
    <div class="spine big" style="--hue:${hue(book.id)}"><span>${escape(book.title)}</span></div>
    <div>
      <p class="eyebrow">${escape(series.title)}</p>
      <h1>${escape(book.title)}</h1>
      ${book.subtitle ? `<p class="subtitle">${escape(book.subtitle)}</p>` : ""}
      <p class="desc">${escape(book.description)}</p>
      <p class="meta">${book.chapters.length} chapters · ${book.minutes} min read${book.updated ? ` · updated ${book.updated}` : ""}</p>
      <div class="meter"><div class="meter-fill"></div></div>
      <p class="book-actions"><a class="button primary continue-link" href="${book.chapters[0]?.url || "#"}">Start reading</a> <span class="book-status" data-status></span></p>
    </div>
  </header>
  ${parts}
</main>`,
  });
}

function chapterPage(book, series, chapter, rendered, prev, next) {
  const toc = rendered.headings.length ? `
    <nav class="on-page" aria-label="On this page">
      <p class="on-page-title">On this page</p>
      <ul>${rendered.headings.map((h) => `<li><a href="#${escape(h.id)}">${escape(h.text)}</a></li>`).join("")}</ul>
    </nav>` : "";
  const chapterList = `
    <nav class="book-nav" aria-label="${escape(book.title)}">
      <p class="on-page-title"><a href="${book.url}">${escape(book.title)}</a></p>
      ${book.parts.map((part) => `${book.parts.length > 1 ? `<p class="part-title">${escape(part.title)}</p>` : ""}
      <ol>${part.chapters.map((c) => `<li data-chapter="${escape(c.slug)}"${c === chapter ? ' class="current"' : ""}><a href="${c.url}"><span class="state"></span>${escape(c.title)}</a></li>`).join("")}</ol>`).join("")}
    </nav>`;
  const pager = `
  <nav class="pager">
    ${prev ? `<a class="prev" href="${prev.url}" rel="prev"><span>Previous</span>${escape(prev.title)}</a>` : "<span></span>"}
    ${next ? `<a class="next" href="${next.url}" rel="next"><span>Next</span>${escape(next.title)}</a>` : `<a class="next" href="${book.url}"><span>Finished</span>Back to the contents</a>`}
  </nav>`;
  return layout({
    title: `${chapter.title} · ${book.title}`,
    page: "chapter",
    data: { book: book.id, booktitle: book.title, chapter: chapter.slug, title: chapter.title, chapters: bookChapterIds(book), prev: prev?.url || "", next: next?.url || "" },
    crumbs: [{ title: series.title }, { title: book.title, url: book.url }, { title: `${chapter.number}. ${chapter.title}` }],
    body: `<div class="reading">
  <aside class="sidebar">
    <button class="sidebar-toggle" type="button" data-action="toc">${icon.list}<span>Contents</span></button>
    <div class="sidebar-body">${chapterList}${toc}</div>
  </aside>
  <main class="chapter">
    <header class="chapter-head">
      <p class="eyebrow">${escape(chapter.part ? `${chapter.part} · ` : "")}Chapter ${chapter.number} of ${book.chapters.length} · ${rendered.minutes} min</p>
      <h1>${escape(chapter.title)}</h1>
    </header>
    <article class="prose">${rendered.html}</article>
    <div class="chapter-end">
      <button class="button" type="button" data-action="toggle-done">Mark as read</button>
    </div>
    ${pager}
  </main>
</div>`,
  });
}

function searchPage() {
  return layout({
    title: `Search · ${SITE_TITLE}`,
    page: "search",
    crumbs: [{ title: "Search" }],
    body: `<main class="search">
  <h1>Search</h1>
  <input type="search" id="q" placeholder="Search every book…" autocomplete="off" autofocus>
  <p class="hint" id="search-status"></p>
  <ol class="results" id="results"></ol>
</main>`,
  });
}

function notFoundPage() {
  return layout({ title: `Not found · ${SITE_TITLE}`, page: "missing",
    body: `<main class="library"><h1>Page not found</h1><p><a href="/">Back to the library</a></p></main>` });
}

// A stable colour per book, for its spine
function hue(id) {
  let h = 0;
  for (const ch of id) h = (h * 31 + ch.charCodeAt(0)) % 360;
  return h;
}

// ---------------------------------------------------------------------------------------------------------------
// Build

function build() {
  const started = Date.now();
  fs.rmSync(OUT, { recursive: true, force: true });
  fs.mkdirSync(path.join(OUT, "assets"), { recursive: true });
  const library = loadLibrary();
  const search = [];
  let pages = 0;

  for (const series of library) {
    for (const book of series.books) {
      const assets = new Set();
      const md = markdownFor(book, assets);
      const rendered = book.chapters.map((c) => ({ chapter: c, ...renderChapter(md, c) }));
      rendered.forEach((r) => { r.chapter.minutes = r.minutes; });
      book.minutes = rendered.reduce((sum, r) => sum + r.minutes, 0);
      rendered.forEach((r, i) => {
        write(path.join(OUT, book.id, r.chapter.slug, "index.html"),
              chapterPage(book, series, r.chapter, r, book.chapters[i - 1], book.chapters[i + 1]));
        search.push({ u: r.chapter.url, b: book.title, t: r.chapter.title, h: r.headings.map((h) => [h.id, h.text]), x: r.text });
        pages++;
      });
      write(path.join(OUT, book.id, "index.html"), bookPage(book, series));
      for (const rel of assets) {
        fs.mkdirSync(path.dirname(path.join(OUT, book.id, rel)), { recursive: true });
        fs.copyFileSync(path.join(book.dir, rel), path.join(OUT, book.id, rel));
      }
    }
  }

  write(path.join(OUT, "index.html"), libraryPage(library));
  write(path.join(OUT, "search", "index.html"), searchPage());
  write(path.join(OUT, "search.json"), JSON.stringify(search));
  write(path.join(OUT, "404.html"), notFoundPage());
  for (const file of fs.readdirSync(path.join(HERE, "src"))) fs.copyFileSync(path.join(HERE, "src", file), path.join(OUT, "assets", file));

  const books = library.reduce((n, s) => n + s.books.length, 0);
  console.log(`Built ${books} book(s), ${pages} chapter page(s) into ${path.relative(process.cwd(), OUT) || OUT} in ${Date.now() - started}ms`);
}

build();
