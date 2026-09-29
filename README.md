# AI Lessons

Study guides written with Claude while building things: what was built, how it works, what went wrong, and hands-on
labs. They're organised as books, and come with a reader that lets you browse them like a library, with your reading
progress saved as you go.

| Series | Book |
|---|---|
| Canine | [Desktops in Kubernetes](books/canine/agent-computers/README.md): KubeVirt VMs, Selkies streaming, X11/Wayland, Omarchy, and Canine's agent computers (16 chapters + 8 labs) |
| Canine | [Computer Use](books/canine/computer-use/README.md): letting Claude drive an agent computer: Anthropic's computer-use actions on Wayland, uinput, the accessibility tree, MCP tools (9 chapters + 5 labs) |

## Layout

```
books/
  <series>/                  one series per project, e.g. canine
    series.yml               title, description
    <book>/                  one book per topic, e.g. agent-computers
      book.yml               title, subtitle, description, updated, parts → chapters (in reading order)
      README.md              index for reading on GitHub
      01-*.md ...            chapters; each starts with a "# Title" heading
      labs/                  runnable lab scripts (secrets in labs/.secrets, .kube, .local.env are git-ignored)
reader/                      the reader: a static site generator + a tiny browser script
Dockerfile                   builds the site, serves it with busybox httpd
```

### Adding a book

1. Create `books/<series>/<book>/` with Markdown chapters, and `series.yml` if the series is new.
2. Add `book.yml`:
   ```yaml
   title: My Book
   subtitle: What it covers
   description: >-
     One or two sentences for the library card.
   updated: 2026-09-26
   parts:
     - title: Chapters
       chapters: [01-intro.md, 02-details.md]
     - title: Labs
       chapters: [03-lab-1.md]
   ```
   Without `parts`, every `.md` file except `README.md` is a chapter, in file-name order.
3. Link between chapters with relative links (`02-details.md#some-heading`) and images with relative paths. The
   reader rewrites them; links to other local files (scripts, folders) point at this repo on GitHub.
4. Keep placeholders like `<aws-node-ip>` inside backticks, or Markdown treats them as HTML tags and hides them.

## The reader

Everything is rendered at build time: Markdown, syntax highlighting (highlight.js), chapter tables of contents, and
the search index. The server only serves files, so it keeps no state and needs almost no memory (the image is ~4 MB
and uses ~0.5 MB of RAM). Everything that remembers you lives in your browser's localStorage:

- **Your place:** each chapter reopens where you left off (unless you followed a link to a specific heading).
- **Progress:** chapters are marked read when you reach the end (or with "Mark as read"); the library and each book's
  contents show what you've read, and "Continue reading" takes you back.
- **Settings:** theme (auto, light, dark, sepia) and text size.
- **Moving devices:** Reading settings → Copy progress, then Paste progress on the other device.
- **Search** across every book (`/`), and **← / →** between chapters.

### Run it locally

```bash
cd reader && npm install
npm run dev                 # builds into ../dist and serves http://localhost:8080
```

### Docker

```bash
docker build -t ai-lessons-reader .
docker run --rm -p 8080:8080 --read-only --memory 8m ai-lessons-reader
# or: docker compose up --build
```

Build arguments: `REPO_URL` (where links to lab files point; default this repo) and `SITE_TITLE`.
