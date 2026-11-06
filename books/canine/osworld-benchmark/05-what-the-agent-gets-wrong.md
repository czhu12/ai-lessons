# What the agent gets wrong

Each failure was read, not just counted. These are the patterns, roughly in order of how many failures each explains.
Most aren't about benchmarks at all: they're what a person would hit using Canine on their own computer.

## 1. A screen agent that can't place clicks, and blames the app

GPT-5.1 as the screen agent clicked 150–250 px from a labelled sheet tab, picked the wrong column, opened the wrong
menu. Worse, it **reported its misses as app state**: "the sheet is not changing", "the wizard is frozen", "the sheet
may be protected". The main agent believed it, chased the wrong problem, and repeated it in the summary. Claude as the
screen agent fixed six of nine of these (chapter 4).

## 2. Repeating actions on an unchanged screen

Twenty clicks on the same cell, twelve scrolls in a row, the same URL typed four times. An unchanged screenshot means
something is in the way (a dialog, focus) or the action missed, and nothing tells the screen agent so.

## 3. Values it didn't compute, and claims it didn't check

The worst finding for real use: on the ages task it typed 28 ages and said it **calculated them from the reference
date**. Someone born in 1994 got 44; someone born in 1996 got 50. No formula, no script: invented numbers, described as
computed. Elsewhere, grades worked out by hand and wrong, "copied the Revenue column" (it copied two), "visible on
the bookmarks bar" (it was in Other bookmarks).

## 4. Desktop for files, and (later) shell for everything

GPT-5.1 took every spreadsheet to the desktop, planning from the instruction alone and leaving seeing the data to the
screen agent through screenshots. When it did try the shell, the computer had **no openpyxl and no pip**, and it
concluded "Calc isn't accessible via the shell". A spreadsheet is one `soffice --headless --convert-to csv` away.

Why would an agent use the shell for a Calc task at all? Because the grade, like the person's real goal, is the
**file**: a script that writes the right cells, then checks them, is more reliable than clicking. Qwen did exactly
that, and passed more. The desktop is for what has no file or command: a Chromium settings page, a native dialog, an
app feature like Impress's Summary Slide.

## 5. Retries that repeat the plan

A failed desktop call was followed by the same call with more detail. It never looked up where a setting lives now,
never tried other settings-search words, never switched approach until the calls ran out.

## 6. Reading the request

"Get rid of the tracking things Amazon saved on my computer" read as Amazon account settings; "whenever I launch
Chrome it opens funbrain.com… what should I do?" answered with advice when it could have fixed it. A problem on this
computer is something to fix, not to explain. Qwen's version: "set my slides upright instead of sideways" — it decided
they already were upright, reverted its change, and asked a person who wasn't there.

## 7. Work left unsaved

Five runs did the work and left it unsaved, telling the person to save ("the column remains selected if you want to
inspect it"). An unattended agent should save what it changes.

## 8. One step of several, then `done`

Asked for "Month" and "Total" headers with totals under them, it added the headers and finished `done`. It doesn't
check its result against the task before finishing.

## 9. `done` on the impossible

"Disable the new 2023 Chrome UI" can't be done in Chromium 152. GPT-5.1 found exactly why, wrote it in the summary, and
finished with outcome `done`. Two of three infeasible tasks went this way. `done` should mean the request is
fulfilled; "it's impossible, here's why" is `blocked`.

## 10. Desktop calls split too finely

A "look" call, then a "do" call, or "headers only": spending the three-call budget on what one call could do.

## 11. Leaks in the plumbing

- **A cut-off tool call fails a whole desktop call.** DesktopJob asks for `max_tokens: 1000`; when the reply runs out
  mid-arguments, `JSON.parse` raises and the call ends "stopped with an error" instead of one failed step.
- **A model call that never returned**, for 25+ minutes. `read_timeout: 180` limits each socket read, and OpenRouter's
  keep-alive bytes probably stop it firing.
- **Reasoning text in a summary:** a stray `</think>` from Qwen in the middle of a sentence.

## What works

When the main agent names the exact `chrome://` page and the job is a toggle or a field, the desktop tool is quick
and cheap (2–10 cents). Keyboard-heavy jobs (Save As with a typed path) work. And when an agent checks its own work
(an `ls` after a PDF export; XML, a PDF render and a reload after editing slides), it's usually right.

## Check yourself

**Q: Which of these failures would a real user of Canine hit, benchmark or not?**

<details>
<summary>Answer</summary>

All but the environment drift. Invented values, unsaved work, misreported misses, `done` on the impossible and stuck
model calls are the most serious, because the person reads a summary and trusts it.

</details>

**Q: Why is "the screen agent reports misses as app state" worse than just missing?**

<details>
<summary>Answer</summary>

A miss can be retried. A false diagnosis ("the sheet is protected") sends the main agent after a problem that doesn't
exist, and ends up in the summary the person reads.

</details>

Next: [What would move the score](06-what-would-move-the-score.md).
