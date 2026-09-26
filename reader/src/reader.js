// AI Lessons reader: everything that remembers you lives here, in this browser's localStorage. The server is a plain
// static file server and knows nothing about readers.
//
// Progress (localStorage "reader:progress:v1"):
//   c: { "<series>/<book>/<chapter>": { p: furthest fraction read 0..1, y: scroll position 0..1, d: done, n: title, t: time } }
//   b: { "<series>/<book>": { c: last chapter slug, n: book title, t: time } }
(() => {
  const PROGRESS_KEY = "reader:progress:v1";
  const SETTINGS_KEY = "reader:settings";
  const body = document.body;
  const page = body.dataset.page;
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

  const load = (key, fallback) => {
    try { return JSON.parse(localStorage.getItem(key)) || fallback; } catch { return fallback; }
  };
  const store = (key, value) => {
    try { localStorage.setItem(key, JSON.stringify(value)); } catch { /* private mode or storage full: reading still works */ }
  };
  let progress = load(PROGRESS_KEY, {});
  progress.c ||= {};
  progress.b ||= {};
  const saveProgress = () => store(PROGRESS_KEY, progress);

  const chapterUrl = (book, slug) => `/${book}/${slug}/`;
  const bookStats = (book, slugs) => {
    const entries = slugs.map((slug) => progress.c[`${book}/${slug}`] || {});
    const done = entries.filter((e) => e.d).length;
    const fraction = entries.reduce((sum, e) => sum + (e.d ? 1 : Math.min(e.p || 0, 0.99)), 0) / (slugs.length || 1);
    const started = entries.some((e) => e.p > 0 || e.d);
    const last = progress.b[book]?.c;
    const lastEntry = last && progress.c[`${book}/${last}`];
    const resume = last && slugs.includes(last) && !lastEntry?.d ? last : slugs.find((s) => !progress.c[`${book}/${s}`]?.d);
    return { done, total: slugs.length, fraction, started, resume, finished: done === slugs.length };
  };
  const paintState = (el, entry) => {
    if (!el) return;
    el.classList.toggle("done", !!entry?.d);
    el.classList.toggle("partial", !entry?.d && (entry?.p || 0) > 0.02);
    el.style.setProperty("--p", Math.round((entry?.p || 0) * 100));
    el.setAttribute("aria-label", entry?.d ? "read" : entry?.p > 0.02 ? `${Math.round(entry.p * 100)}% read` : "not started");
  };
  const statusText = (stats) =>
    stats.finished ? "Finished ✓" : stats.started ? `${stats.done} of ${stats.total} read · ${Math.round(stats.fraction * 100)}%` : "Not started";

  let toastTimer;
  const toast = (html, ms = 6000) => {
    const el = $(".toast");
    el.innerHTML = html;
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { el.hidden = true; }, ms);
    return el;
  };

  // ---------------------------------------------------------------------------------------------------------------
  // Library: progress on every book card, plus "continue reading" for the most recent book

  if (page === "library") {
    for (const card of $$(".book-card")) {
      const stats = bookStats(card.dataset.book, card.dataset.chapters.split(" "));
      $(".meter-fill", card).style.width = `${stats.fraction * 100}%`;
      $("[data-status]", card).textContent = statusText(stats);
    }
    const recent = Object.entries(progress.b).sort((a, b) => b[1].t - a[1].t)[0];
    const card = recent && $(`.book-card[data-book="${CSS.escape(recent[0])}"]`);
    if (recent && card) {
      const stats = bookStats(recent[0], card.dataset.chapters.split(" "));
      if (!stats.finished && stats.resume) {
        const link = $(".continue-link");
        const title = progress.c[`${recent[0]}/${stats.resume}`]?.n;
        link.href = chapterUrl(recent[0], stats.resume);
        link.textContent = `${recent[1].n || recent[0]}${title ? ` — ${title}` : ""}`;
        $(".continue-banner").hidden = false;
      }
    }
  }

  // ---------------------------------------------------------------------------------------------------------------
  // Book contents: a state dot per chapter, overall progress, and a start/continue button

  if (page === "book") {
    const book = body.dataset.book;
    const slugs = body.dataset.chapters.split(" ");
    for (const li of $$(".toc li")) paintState($(".state", li), progress.c[`${book}/${li.dataset.chapter}`]);
    const stats = bookStats(book, slugs);
    $(".meter-fill").style.width = `${stats.fraction * 100}%`;
    $("[data-status]").textContent = statusText(stats);
    const button = $(".continue-link");
    if (stats.finished) button.textContent = "Read again";
    else if (stats.started) { button.textContent = "Continue reading"; button.href = chapterUrl(book, stats.resume); }
  }

  // ---------------------------------------------------------------------------------------------------------------
  // Chapter: reading progress, saved place, and navigation

  if (page === "chapter") {
    const { book, chapter, title, booktitle } = body.dataset;
    const id = `${book}/${chapter}`;
    const entry = (progress.c[id] ||= {});
    entry.n = title;
    progress.b[book] = { c: chapter, n: booktitle, t: Date.now() };
    saveProgress();

    for (const li of $$(".book-nav li")) paintState($(".state", li), progress.c[`${book}/${li.dataset.chapter}`]);

    const article = $(".prose");
    const bar = $(".progress-bar");
    const doneButton = $('[data-action="toggle-done"]');
    const paintDone = () => {
      doneButton.textContent = entry.d ? "✓ Read · mark as unread" : "Mark as read";
      doneButton.classList.toggle("is-done", !!entry.d);
      paintState($(`.book-nav li[data-chapter="${CSS.escape(chapter)}"] .state`), entry);
    };
    paintDone();

    // How far through the article (not the page) the bottom of the viewport is
    const readFraction = () => {
      const rect = article.getBoundingClientRect();
      const seen = window.innerHeight - rect.top;
      return Math.max(0, Math.min(1, seen / rect.height));
    };
    const scrollFraction = () => window.scrollY / Math.max(1, document.documentElement.scrollHeight);

    let saveTimer;
    const record = () => {
      const fraction = readFraction();
      bar.style.width = `${fraction * 100}%`;
      entry.p = Math.max(entry.p || 0, fraction);
      entry.y = scrollFraction();
      entry.t = Date.now();
      if (fraction >= 0.98 && !entry.d) { entry.d = true; paintDone(); }
      clearTimeout(saveTimer);
      saveTimer = setTimeout(saveProgress, 400);
    };
    let ticking = false;
    addEventListener("scroll", () => {
      if (ticking) return;
      ticking = true;
      requestAnimationFrame(() => { ticking = false; record(); });
    }, { passive: true });
    addEventListener("pagehide", saveProgress);
    document.addEventListener("visibilitychange", () => { if (document.hidden) saveProgress(); });

    doneButton.addEventListener("click", () => {
      entry.d = !entry.d;
      if (entry.d) entry.p = 1;
      saveProgress();
      paintDone();
    });

    // Put the reader back where they were, unless they followed a link to a specific heading
    const restore = () => {
      if (!location.hash && entry.y > 0.02 && !(entry.d && entry.y > 0.9)) {
        window.scrollTo(0, entry.y * document.documentElement.scrollHeight);
        const el = toast('Picked up where you left off. <button type="button">Start from the top</button>');
        $("button", el).addEventListener("click", () => { window.scrollTo(0, 0); el.hidden = true; });
      }
      bar.style.width = `${readFraction() * 100}%`;
    };
    if (document.readyState === "complete") restore(); else addEventListener("load", restore, { once: true });

    // Highlight the section being read in "On this page"
    const links = new Map($$(".on-page a").map((a) => [decodeURIComponent(a.hash.slice(1)), a]));
    if (links.size && "IntersectionObserver" in window) {
      const visible = new Set();
      const observer = new IntersectionObserver((items) => {
        for (const item of items) item.isIntersecting ? visible.add(item.target.id) : visible.delete(item.target.id);
        const headings = $$(".prose h2");
        const current = headings.filter((h) => visible.has(h.id))[0] || headings.filter((h) => h.getBoundingClientRect().top < 0).pop();
        links.forEach((a, key) => a.classList.toggle("active", current?.id === key));
      }, { rootMargin: "-10% 0px -70% 0px" });
      $$(".prose h2").forEach((h) => observer.observe(h));
    }

    // Narrow screens: the contents drawer
    const sidebar = $(".sidebar");
    $('[data-action="toc"]').addEventListener("click", () => sidebar.classList.toggle("open"));
    $$(".sidebar-body a").forEach((a) => a.addEventListener("click", () => sidebar.classList.remove("open")));

    // Keyboard: ← → between chapters
    addEventListener("keydown", (event) => {
      if (event.metaKey || event.ctrlKey || event.altKey || /^(INPUT|TEXTAREA|SELECT)$/.test(event.target.tagName)) return;
      if (event.key === "ArrowLeft" && body.dataset.prev) location.href = body.dataset.prev;
      if (event.key === "ArrowRight" && body.dataset.next) location.href = body.dataset.next;
    });

    // Copy buttons on code blocks
    for (const pre of $$("pre.code")) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "copy";
      button.textContent = "Copy";
      button.addEventListener("click", async () => {
        try {
          await navigator.clipboard.writeText($("code", pre).innerText);
          button.textContent = "Copied";
        } catch {
          button.textContent = "Select and copy";
        }
        setTimeout(() => { button.textContent = "Copy"; }, 1500);
      });
      pre.appendChild(button);
    }
  }

  // ---------------------------------------------------------------------------------------------------------------
  // Search: the index is built with the site; matching happens here

  if (page === "search") {
    const input = $("#q");
    const results = $("#results");
    const status = $("#search-status");
    const escapeHtml = (s) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
    const mark = (text, terms) => {
      let html = escapeHtml(text);
      for (const term of terms) html = html.replace(new RegExp(`(${term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")})`, "gi"), "<mark>$1</mark>");
      return html;
    };
    let index = null;
    const run = () => {
      const q = input.value.trim();
      history.replaceState(null, "", q ? `?q=${encodeURIComponent(q)}` : location.pathname);
      if (!index || q.length < 2) { results.innerHTML = ""; status.textContent = index ? "" : "Loading…"; return; }
      const terms = q.toLowerCase().split(/\s+/).filter(Boolean);
      const hits = [];
      for (const doc of index) {
        const title = doc.t.toLowerCase();
        const text = doc.x.toLowerCase();
        const headings = doc.h.map(([hid, h]) => [hid, h.toLowerCase()]);
        if (!terms.every((t) => title.includes(t) || text.includes(t) || headings.some(([, h]) => h.includes(t)))) continue;
        let score = 0;
        for (const t of terms) {
          if (title.includes(t)) score += 10;
          score += headings.filter(([, h]) => h.includes(t)).length * 4;
          score += Math.min(text.split(t).length - 1, 20);
        }
        const heading = headings.find(([, h]) => terms.some((t) => h.includes(t)));
        const at = Math.max(0, text.indexOf(terms[0]));
        const start = Math.max(0, at - 80);
        const snippet = (start ? "…" : "") + doc.x.slice(start, at + 160) + "…";
        hits.push({ doc, score, snippet, anchor: heading?.[0] });
      }
      hits.sort((a, b) => b.score - a.score);
      status.textContent = `${hits.length} chapter${hits.length === 1 ? "" : "s"}`;
      results.innerHTML = hits.slice(0, 40).map(({ doc, snippet, anchor }) => `
        <li><a href="${doc.u}${anchor ? `#${anchor}` : ""}">${mark(doc.t, terms)}</a>
        <p class="where">${escapeHtml(doc.b)}</p><p class="snippet">${mark(snippet, terms)}</p></li>`).join("");
    };
    let timer;
    input.addEventListener("input", () => { clearTimeout(timer); timer = setTimeout(run, 120); });
    input.value = new URLSearchParams(location.search).get("q") || "";
    status.textContent = "Loading…";
    fetch("/search.json").then((r) => r.json()).then((data) => { index = data; status.textContent = ""; run(); })
      .catch(() => { status.textContent = "Couldn't load the search index."; });
  }

  // Press "/" anywhere to search
  addEventListener("keydown", (event) => {
    if (event.key === "/" && page !== "search" && !/^(INPUT|TEXTAREA)$/.test(event.target.tagName)) {
      event.preventDefault();
      location.href = "/search/";
    }
  });

  // ---------------------------------------------------------------------------------------------------------------
  // Settings: theme, text size, and moving progress between devices

  const settings = load(SETTINGS_KEY, {});
  const dialog = $("#settings");
  const sizeValue = $("#size-value");
  const applySettings = () => {
    const root = document.documentElement;
    if (!settings.theme || settings.theme === "auto") delete root.dataset.theme; else root.dataset.theme = settings.theme;
    root.style.setProperty("--font-scale", settings.size || 1);
    sizeValue.textContent = `${Math.round((settings.size || 1) * 100)}%`;
    store(SETTINGS_KEY, settings);
  };
  $('[data-action="settings"]').addEventListener("click", () => {
    $$('input[name="theme"]', dialog).forEach((r) => { r.checked = r.value === (settings.theme || "auto"); });
    sizeValue.textContent = `${Math.round((settings.size || 1) * 100)}%`;
    $("#progress-io").hidden = true;
    $("#progress-msg").textContent = "";
    dialog.showModal();
  });
  $$('input[name="theme"]', dialog).forEach((r) => r.addEventListener("change", () => { settings.theme = r.value; applySettings(); }));
  $$("[data-size]", dialog).forEach((b) => b.addEventListener("click", () => {
    const next = Math.round(((settings.size || 1) + Number(b.dataset.size) * 0.05) * 100) / 100;
    settings.size = Math.min(1.5, Math.max(0.8, next));
    applySettings();
  }));
  const io = $("#progress-io");
  const msg = $("#progress-msg");
  $('[data-action="export"]', dialog).addEventListener("click", async () => {
    const data = JSON.stringify(progress);
    io.hidden = false;
    io.value = data;
    io.select();
    try { await navigator.clipboard.writeText(data); msg.textContent = "Copied. Paste it into Reading settings on your other device."; }
    catch { msg.textContent = "Select the text above and copy it."; }
  });
  $('[data-action="import"]', dialog).addEventListener("click", () => {
    if (io.hidden || !io.value.trim()) { io.hidden = false; io.value = ""; io.focus(); msg.textContent = "Paste exported progress, then press Paste progress again."; return; }
    try {
      const incoming = JSON.parse(io.value);
      for (const [key, value] of Object.entries(incoming.c || {})) {
        const mine = progress.c[key] || {};
        progress.c[key] = (value.t || 0) > (mine.t || 0) ? { ...value, p: Math.max(value.p || 0, mine.p || 0), d: value.d || mine.d } : { ...mine, d: mine.d || value.d };
      }
      for (const [key, value] of Object.entries(incoming.b || {})) if ((value.t || 0) > (progress.b[key]?.t || 0)) progress.b[key] = value;
      saveProgress();
      msg.textContent = "Merged. Reload to see it.";
    } catch {
      msg.textContent = "That isn't exported progress.";
    }
  });
  let resetArmed = false;
  $('[data-action="reset"]', dialog).addEventListener("click", (event) => {
    if (!resetArmed) { resetArmed = true; event.target.textContent = "Click again to erase"; msg.textContent = "This erases all reading progress in this browser."; return; }
    progress = { c: {}, b: {} };
    saveProgress();
    resetArmed = false;
    event.target.textContent = "Reset";
    msg.textContent = "Progress erased. Reload to see it.";
  });
})();
