# Results

All runs on one computer (computer 3), one task at a time, November 3–5 2026. A Canine run has two models that matter
here: the **main agent** (planning, the tool calls) and the **screen agent** that the desktop tool hands a job to.
In Canine, the screen agent uses the computer's browse model, so one setting drives both the screen agent and browse.

## The scoreboard

| Run | Main agent | Screen agent | Tasks | Passed | Cost |
|---|---|---|---|---|---|
| Pilot | GPT-5.1 | GPT-5.1 | 20 | 7 (Chrome 5/10, Calc 2/10) | $2.81 |
| Pilot failures again | GPT-5.1 | Claude Sonnet 5.5 | 9 | 6 | $4.25 |
| The other 44 | GPT-5.1 | Claude Sonnet 5.5 | 44 | 16 (Calc 15/37, Chrome 1/7) | $16.22 |
| **Best per task** | | | **64** | **29 (45%)** | ~$23 |
| Qwen3.8 27B everywhere | Qwen3.8 27B | Qwen3.8 27B | 64 | **36 (56%)**: Calc 25/47, Chrome 11/17 | **$5.25** |
| Impress (paused) | Qwen3.8 27B | Qwen3.8 27B | 7 of 68 | 1 | $1.15 |

## The pilot: GPT-5.1 everywhere, 7/20

Quick and cheap when it works: a Chrome toggle in one desktop call for 2–10 cents, under two minutes. Five of ten
Chrome tasks passed; two of ten Calc tasks. Almost every Calc failure was the screen agent's clicks landing in the
wrong place (chapter 5), or the main agent planning without looking at the data.

## Claude as the screen agent: 0/9 → 6/9

The nine pilot tasks that failed in the desktop tool, again, with the screen agent on Claude Sonnet 5.5 and the main
agent still GPT-5.1. **Six passed.** Claude's clicks landed, it read tab bars and dialogs correctly, and it **reported
what it saw** ("I didn't save", the counts in its pivot table) instead of reporting its own misses as the app being
broken. It cost about twice as much per task. The three that still failed were the main agent's: a wrong plan, work
left unsaved, and a big fill job done click by click.

The catch: with Claude as the browse model, **every browse call failed** (400 from the provider; browser-use's
structured output and that model on OpenRouter don't agree). You can't choose the screen agent without also changing
browse.

The other 44 tasks with that setup: 16 passed. Batch by batch, the failures were mostly the main agent: one step done
of several, values computed in its head, never reading the spreadsheet itself.

## Qwen3.8 27B everywhere: 36/64 for $5.25

The open-weight model, as main agent, screen agent and browse model, beat every earlier setup, at about **8 cents a
task**: a quarter of the GPT-5.1-plus-Claude cost, for seven more passes.

Why it did better is mostly *how* it worked, not its clicks:

- **Shell-first.** It read and wrote the .xlsx with scripts (9–60 shell calls a task, 0–3 desktop calls) and checked
  its work by recalculating through headless LibreOffice.
- **It installed what it needed** (`python-openpyxl`, `python-pillow`, `python-websocket-client`) with pacman. Those
  stay installed on a stateful computer, so later tasks start with tools the GPT-5.1 runs never had. That's a state
  leak between tasks, and it favours Qwen.
- **It read "on my computer" right**: clearing the browser's own cookies and history where GPT-5.1 went to the Amazon
  and YouTube accounts.
- **It finished impossible tasks `blocked`**, which GPT-5.1 didn't, and it was the only model that used `remember`.

The costs: 30–60 turns where GPT-5.1 used 2–5, so several tasks hit the 15-minute limit. And it's heavy-handed with a
browser: it edits Chromium's Preferences with Chromium stopped, drives Chromium over raw CDP WebSockets it writes
itself, and once made a throwaway profile and left Chromium on the profile picker. Effective, but not how you want an
agent touching a person's own browser.

## Impress, paused at 7

1 of 7, at about twice the per-task cost. Too few to judge the agent; the two "done but 0" runs were the harness
(chapter 3). The desktop tool ran out of steps on the two jobs a script can't do (export to PNG, the Summary Slide
feature).

## Check yourself

**Q: Qwen's 36/64 isn't a clean comparison with GPT-5.1's runs. Name two reasons.**

<details>
<summary>Answer</summary>

The packages it installed stayed for later tasks (and were there for none of GPT-5.1's), and it took far more time
and turns per task. Also, a frozen run counts as 0 for Qwen while the Claude screen agent passed that task.

</details>

**Q: Why couldn't the Claude screen agent just be switched on for real users?**

<details>
<summary>Answer</summary>

The screen agent's model is the browse model, and Claude as the browse model broke every browse call. It needs its own
setting first.

</details>

Next: [What the agent gets wrong](05-what-the-agent-gets-wrong.md).
