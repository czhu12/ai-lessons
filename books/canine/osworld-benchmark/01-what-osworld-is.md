# What OSWorld is

OSWorld is a benchmark of 369 tasks on a real desktop: "make Bing the default search engine", "add a Profit column",
"strike through the first two lines of this to-do list". Each one starts from a known state on a VM, lets an agent
work, then checks the result with code. No human grades anything, so it can be run again after every change. That's
why it's useful for Canine: a regression test for the whole agent, not one tool.

## Anatomy of a task

Every task is one JSON file under `evaluation_examples/examples/<domain>/<id>.json`:

```json
{
  "instruction": "Could you help me add a strike-through on the first and second line?",
  "config": [
    { "type": "download", "parameters": { "files": [{ "url": "https://…/New_Club.data", "path": "/home/user/Desktop/New_Club.pptx" }] } },
    { "type": "open", "parameters": { "path": "/home/user/Desktop/New_Club.pptx" } },
    { "type": "execute", "parameters": { "command": ["python", "-c", "import pyautogui; …click(170, 250)…"] } }
  ],
  "evaluator": {
    "postconfig": [ { "type": "activate_window", … }, { "type": "execute", "…": "pyautogui.hotkey('ctrl', 's')" } ],
    "func": ["compare_pptx_files", "compare_pptx_files"], "conj": "or",
    "result":   { "type": "vm_file",    "path": "/home/user/Desktop/New_Club.pptx" },
    "expected": [ { "type": "cloud_file", "path": "https://…/Gold.pptx" }, … ]
  }
}
```

Four parts:

- **`instruction`**: what a person would type, often vague on purpose ("this sheet", "the page I'm looking at").
- **`config`**: setup steps run on the VM before the agent starts. Download files, open them, launch Chrome, open
  tabs, run commands, and sometimes **drive the GUI with pyautogui** (click a slide, press a shortcut).
- **`evaluator`**: *getters* fetch something (a file from the VM, Chrome's Preferences, a gold file from the cloud),
  and *metrics* compare them (`compare_pptx_files`, `compare_table`, `check_slide_orientation_Portrait`, and about a
  hundred more). Several metrics combine with `and`/`or`.
- **`postconfig`**: steps after the agent and before grading. Most office tasks bring the document's window to the
  front and press **Ctrl+S**, so the file graded is what the app has open.

A task scores between 0 and 1, almost always exactly 0 or 1. Some tasks are **infeasible** on purpose (the setting no
longer exists); the right answer is to say so, which OSWorld scores as the agent outputting `FAIL`.

## How it's scored, and what good looks like

OSWorld's own runner restores a VM snapshot before each task, runs setup, gives the agent screenshots (and optionally
the accessibility tree) for a fixed number of steps, then grades. The score is the share of tasks passed.

The human baseline on OSWorld-Verified is **72.4%**. Recent models report scores around and above that (the model
picker in Canine quotes 82–86% for MiMo V2.6 Pro and the Qwen3.8 models, as reported by their makers). Those are
screen-only agents on OSWorld's own Ubuntu VM. **Nothing in this book is comparable to them**: see chapter 2.

## The domains, and which ones a Canine computer can run

| Domain | Tasks | Run here |
|---|---|---|
| chrome | 45 | 17 (28 grade through the accessibility tree or a live CDP connection to Chrome) |
| libreoffice_calc | 47 | all 47 |
| libreoffice_impress | 47 | 45 queued, 7 run so far (2 need audio or the accessibility tree) |
| libreoffice_writer | 23 | 23 queued, none run yet |
| gimp, vlc, thunderbird, vs_code, os, multi_apps | 207 | not attempted |

Chrome and Calc came first: Omarchy ships Chromium and LibreOffice, and their graders only need files. Impress and
Writer needed no new setup either. The others need apps Omarchy doesn't have set up as OSWorld expects, or graders
that read the accessibility tree through OSWorld's own server, which Canine's computer-use server doesn't speak.

## Check yourself

**Q: Why can't you just compare a task's score here with a published OSWorld number?**

<details>
<summary>Answer</summary>

Different task subset, a 2026 Chromium against OSWorld's 2023–24 Chrome, a computer that isn't reset to a snapshot,
an added line of context, skipped GUI setup steps, and an agent with a shell. Chapter 2 lists them.

</details>

**Q: What does the postconfig's Ctrl+S mean for an agent that edits a file with a script?**

<details>
<summary>Answer</summary>

On OSWorld, the app's in-memory document is saved over the file after the agent finishes, so a script's changes are
lost unless the app reloaded them first. And the gold files are app saves, so a metric that compares shapes exactly
can fail a file written by anything other than the app.

</details>

Next: [The harness](02-the-harness.md).
