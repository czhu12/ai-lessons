# Benchmarking Computer Use: Running OSWorld on Canine's Agent Computers

What happened when [OSWorld](https://github.com/xlang-ai/OSWorld)'s tasks were run on a Canine agent computer (an
Omarchy desktop in a KubeVirt VM) by Canine's own agent: the main agent with its shell, browse, desktop and delegate
tools, not a screen-only agent. The benchmark lives in a separate repo, `canine-osworld`, and was built so it changes
nothing in Canine.

Written for a full-stack web developer. It assumes the companion books,
[Desktops in Kubernetes](../agent-computers/README.md) and [Computer Use](../computer-use/README.md), for how the
computers and the computer-use server work.

**How to use it:** read in order; each chapter ends with "check yourself" questions. Chapter 4 has the numbers;
chapters 5 and 6 are what they mean for Canine.

## Chapters

| # | Chapter | What you'll understand |
|---|---|---|
| 1 | [What OSWorld is](01-what-osworld-is.md) | Tasks, setup steps, evaluators, how it's scored, and which tasks a Canine computer can run |
| 2 | [The harness](02-the-harness.md) | Running a task on a stateful computer through `rails runner`, and a stand-in for OSWorld's VM controller |
| 3 | [When the harness was wrong](03-when-the-harness-was-wrong.md) | Every way the harness, not the agent, cost a task, and the fixes |
| 4 | [Results](04-results.md) | GPT-5.1, a Claude screen agent and Qwen3.8 27B: scores, costs and time |
| 5 | [What the agent gets wrong](05-what-the-agent-gets-wrong.md) | The failure themes, from bad clicks to invented values |
| 6 | [What would move the score](06-what-would-move-the-score.md) | Core changes worth making, ranked, and the rule about benchmark-only changes |

Rough time: ~45 minutes of reading.
