# Computer Use: Letting Claude Drive an Agent Computer

How Canine lets Claude see and operate its agent computers (Omarchy desktops running as KubeVirt VMs): a small Python
server inside each VM that speaks Anthropic's computer-use actions and reads the accessibility tree, the Wayland
details that make that harder than it sounds, and the Canine code that connects Claude Code to it over MCP.

Written for a full-stack web developer. It assumes the companion book,
[Desktops in Kubernetes](../agent-computers/README.md), for how the desktops themselves work (KubeVirt, Selkies,
Omarchy), but each chapter says what it needs from it.

**How to use it:** read the chapters in order (each ends with "check yourself" questions), then do the labs. Reading
on your phone? Every lab page has the questions with hidden answers and a collapsible **expected output**: a real
transcript captured against a real agent computer.

## Chapters

| # | Chapter | What you'll understand |
|---|---|---|
| 1 | [What computer use is](01-what-computer-use-is.md) | The agent loop, Anthropic's actions, the architecture, why the server lives in the VM |
| 2 | [Seeing the screen](02-seeing-the-screen.md) | hyprctl and grim, three coordinate spaces, why screenshots are 1280x720, zoom |
| 3 | [Pressing keys and clicking](03-pressing-keys-and-clicking.md) | Input on Wayland: uinput, key codes vs characters, wtype for text, the mouse |
| 4 | [The accessibility tree](04-the-accessibility-tree.md) | AT-SPI: roles, names, paths, press and set_text, and getting positions right |
| 5 | [The server as a Python package](05-the-server-as-a-python-package.md) | The HTTP API, pyproject.toml, the venv, how it's installed on new computers |
| 6 | [The Canine side](06-the-canine-side.md) | MCP tools, access checks, the port-forward, what each call costs |
| 7 | [War stories](07-war-stories.md) | Every bug found while building it and writing the labs |
| 8 | [Current state and open work](08-current-state-and-open-work.md) | What exists, what's tested, what's next |
| 9 | [Glossary and cheat sheet](09-glossary-and-cheat-sheet.md) | Terms, API calls, Omarchy keys, commands |

## Labs

Scripts live in [`labs/`](labs/). Each page below explains the lab and shows its expected output.

| Lab | Page | You'll see |
|---|---|---|
| — | [Setup](10-lab-setup.md) | Fetching access from Canine, the `env.sh` helpers, safety rules |
| 1 | [The raw API](11-lab-1-the-api.md) | Status, windows, a screenshot, one point in three coordinate spaces, errors |
| 2 | [Drive the desktop](12-lab-2-drive.md) | Shortcuts, Unicode text, keys by name, zoom, a right-click |
| 3 | [The accessibility tree](13-lab-3-accessibility.md) | Find by role, press a link without the mouse, check the bounds, stale paths |
| 4 | [uinput from scratch](14-lab-4-uinput.md) | A 25-line virtual keyboard, and why wtype can't press Omarchy's shortcuts |
| 5 | [Through Canine's MCP tools](15-lab-5-mcp.md) | The tools Claude sees, and what each call costs |

Rough time: chapters ~1 hour of reading; labs ~10 minutes of running (or ~15 minutes reading the transcripts).
