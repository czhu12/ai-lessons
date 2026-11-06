# The harness

`canine-osworld` is a separate repo with OSWorld as a git submodule. It doesn't need an API, a server, or anything
in Canine changed: it's a Ruby script run with `bin/rails runner` inside the Canine checkout, so it uses Canine's
models directly, and a Python grader that runs OSWorld's own getters and metrics unchanged.

```bash
bin/osworld --computer 3 libreoffice_calc/357ef137-…     # one task
LOG=results/log-qwen.jsonl bin/batch tasks/supported.json 12   # the next 12 not yet in the log, then a digest
```

The first version had an API in Canine for the harness to call. It was thrown away: if the benchmark only ever runs
from a terminal next to the code, `rails runner` can call `AgentComputer`, `Task` and `Session` itself.

## How one task runs

1. **Reset** the computer: close LibreOffice (and clear its crash-recovery list), clear the computer's long-term
   memory (put back when the batch ends), delete the task's files, and for Chrome tasks restore a baseline copy of
   Chromium's profile.
2. **Start** a run: a disabled one-off task named `OSWorld <domain> <id>` with the instruction verbatim, a session,
   and `claim_workspace!` before its first turn, so setup knows which workspace to open things on.
3. **Set up** that workspace from `config`: downloads, `open` (LibreOffice for office files, `xdg-open` otherwise),
   launching Chromium, opening tabs in one window with the right one in front, commands (`python` mapped to
   `python3`), browser history, the reference date.
4. **Wait** for the run to end. An `ask_person` gets "No one is available…" as its answer, so it can't stall.
5. **Postconfig and grade**: `grade.py` runs the evaluator through a stand-in for OSWorld's VM controller.

Each task shows up in the computer's feed like any other run, which makes reading what it did easy.

## A stand-in for OSWorld's controller

OSWorld's getters call a Flask server inside its VM: `get_file`, `execute_python_command`,
`get_vm_desktop_path`, and so on. `grade.py` replaces that controller with a class that does each over the
computer-use server's `/run` endpoint (through a port-forward with the computer's token). A few details mattered:

- **Files come back in 14,000-byte chunks** (`tail -c +N | head -c 14000 | base64`), because `/run` cuts output at
  20,000 characters.
- Heavy optional imports OSWorld's metrics pull in (PDF, audio, image libraries) are stubbed, so a metric that needs
  one fails clearly instead of the whole grader failing to import.
- A run that finished with outcome `blocked` counts as OSWorld's `FAIL` action: right for infeasible tasks, a fail
  otherwise.

## What it changes on the computer

Nothing in Canine. On the benchmark computer only:

- `/home/user` is a symlink to the desktop user's home, because tasks use `/home/user/...` paths.
- `~/.config/google-chrome/Default` and `Local State` link to Chromium's, because OSWorld's Chrome checks read
  Google Chrome's profile.
- LibreOffice's "Keep current format?" and "Tip of the Day" are turned off, as on OSWorld's VM.
- Chromium's profile is replaced before every Chrome task. **Don't run it on a computer whose browser you use.**

## Differences from OSWorld

- **One line of context.** A Canine run's workspace normally starts empty, so the agent doesn't look at what's open.
  The harness adds what setup left there, e.g. "(On your workspace 3: /home/user/Sales.xlsx is open in LibreOffice.)",
  as a person handing over the task would.
- **GUI setup steps are skipped.** pyautogui runs on OSWorld's X11 VM; here they're listed in each result's
  `skipped_setup`. Chapter 3 shows what that cost.
- **No Ctrl+S after the run** (yet), so only what the agent saved counts.
- **The computer persists.** OSWorld restores a snapshot per task; here the reset above stands in for it, and anything
  the agent installs stays installed.
- **The agent isn't screen-only.** It has a shell, a browser agent and coding delegation.

## Running for hours on a laptop

Tasks run one at a time, 1–16 minutes each. Two runs froze overnight when the laptop suspended; batches now run under
`systemd-inhibit --what=idle:sleep:handle-lid-switch:handle-suspend-key`. `bin/next` skips ids already in the log,
so a batch can be stopped and resumed at any point.

## Check yourself

**Q: Why does the harness claim the workspace before setup, rather than letting the run pick one on its first turn?**

<details>
<summary>Answer</summary>

Setup has to open the task's files on the workspace the agent will work on. If the run picked one later, the files
would be open somewhere else, and a free workspace is cleared when a run claims it.

</details>

**Q: Why are files fetched in chunks instead of with one `cat`?**

<details>
<summary>Answer</summary>

The computer-use server's `/run` truncates output at 20,000 characters, so a spreadsheet read in one go came back
cut off and the grader compared a broken file.

</details>

Next: [When the harness was wrong](03-when-the-harness-was-wrong.md).
