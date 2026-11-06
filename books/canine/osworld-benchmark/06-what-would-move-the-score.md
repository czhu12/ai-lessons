# What would move the score

## The rule: don't change the product for the benchmark

The benchmark was built to measure Canine, not to be passed. So every change to Canine's core was to be called out,
and the bar for one is: **would a person using their own computer want it?** Everything below passes that bar. None
of it was made during the benchmark runs; they're candidates.

What the benchmark work did change in Canine was small, and is product work in its own right:

- The **desktop tool's description** and the system prompt point to it for what browse can't reach: Chromium's own
  `chrome://` pages, native dialogs, desktop apps. (Moving it from "last resort" to "for desktop apps" probably made
  the main agent reach for the desktop for files more often — chapter 5, theme 4.)
- **Model options** in the computer's settings: Qwen3.8 27B, Qwen3.8 Max and MiMo V2.6 Pro, with their prices.
  Defaults weren't changed; computer 3 was switched in the database.

## Ranked by likely effect

1. **A separate setting for the screen agent's model**, or a Claude default for the desktop tool. The biggest single
   effect seen: 0/9 → 6/9. Today it's the browse model, and Claude broke browse.
2. **Let the main agent work on files with scripts.** Ship python-openpyxl, python-docx and python-pptx on the
   computer image (or say packages come from `sudo pacman -S`), and say in the prompt that a document is one
   `soffice --headless --convert-to csv` away: read the data before planning, check the saved file after. Qwen showed
   what this is worth.
3. **Never type a computed value.** Values come from a formula or a script, and the summary says which.
4. **Save what you change** before finishing, in the prompt and the desktop tool's description.
5. **`blocked` for the impossible**: the finish rule says `done` means the request is fulfilled.
6. **Check before `done`**: compare the result with the task, from what's on screen or in the file, not from the
   screen agent's word.
7. **Bugs:**
   - `windows.open_url` with a `chrome://` URL when Chromium isn't running opens a New Tab. Start Chromium, wait for
     its debugging port, then open the page over CDP.
   - DesktopJob: a cut-off tool call should be one failed step ("your call was cut off, try again, shorter"), with
     more output tokens.
   - A wall-clock limit on each model call, since the per-read timeout doesn't fire.
   - Strip reasoning tags from model text before it's saved as a summary.
8. **Browser data lives in the browser**: cookies, history and settings on "my computer" are Chromium's, not a site's.
9. **Notice an unchanged screen** in DesktopJob (same screenshot, or the same action N times) and say so to the
   screen agent.
10. **Browse closes the person's tab** it was told to continue from. Matters more now that a run can be pointed at a
    workspace the person set up.

## Harness work, not core

- Do OSWorld's postconfig (bring the window forward, Ctrl+S) with the computer-use server's keyboard.
- Replay setup clicks that select something, or describe the selection in the context line.
- Undo packages a run installs, or run each model from a fresh computer, so results don't leak between tasks.
- Finish Impress and Writer (61 tasks left), then the GIMP, VLC, Thunderbird and VS Code domains if their graders
  can be reached.

## What this taught about benchmarking an agent product

- **A real, stateful computer is the point**, and also the main source of noise. Every reset step exists because a
  task once failed on what the previous one left behind.
- **Read every failure.** Counting alone would have blamed the agent for a cut-off file read, a hidden dialog, a
  missing setup step and a skipped click.
- **Cheap models change what's affordable.** At 8 cents a task, the whole supported set runs for about $5, which makes
  "run it after every prompt change" realistic.
- **Two models matter, not one**, and the product should let you pick each: the planner and the hands.

## Check yourself

**Q: Is "ship openpyxl on the computer image" a benchmark-only change?**

<details>
<summary>Answer</summary>

No. People ask agents to work on spreadsheets on their own computers, and without it the agent concludes the file
can't be touched from the shell and clicks through the whole job.

</details>

**Q: Is "press Ctrl+S after every run" a change for Canine or for the harness?**

<details>
<summary>Answer</summary>

The harness: it's how OSWorld grades. In Canine, the fix is the agent saving its own work (item 4), since a person
expects a finished run's changes to be saved.

</details>
