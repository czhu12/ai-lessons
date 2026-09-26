# The computer server: letting an AI agent drive the desktop

Lives in `resources/agent_computer/computer_server/` (Python, FastAPI, ~44 commands). Protocol is compatible with
Cua's computer-server clients (we borrowed their good ideas, dropped their multi-platform code).

## Protocol

Every command is `{"command": "<name>", "params": {...}}` → `{"success": true|false, ...}`:
- `POST /cmd` — one command per request
- `WebSocket /ws` — many commands over one connection (echoes an `id` for matching replies)
- `GET /commands` — the list with one-line descriptions; `GET /status` — health + takeover state
- Aliases for Cua names (`click` → `left_click`, `type` → `type_text`, `shell` → `run_command`, …)

Through Canine: `/agent_computers/:id/api/cmd`, `/agent_computers/:id/api/ws` (session-authenticated today; API
tokens are item #2 in `TODO.md`).

## Three ways to "see" and "act"

| Layer | Module | How | Good for |
|---|---|---|---|
| Pixels | `desktop.py` | `mss` screenshots, `xdotool` for mouse/keys, `wmctrl` for windows | Anything, but the agent must reason from images |
| Accessibility tree | `accessibility.py` | **AT-SPI** via `gi.repository.Atspi`: the structured tree of buttons/fields/labels that screen readers use | Clicking "the Save button" by role/name instead of coordinates |
| Browser | `browser.py` | Playwright `connect_over_cdp("http://127.0.0.1:9222")` into the person's *own* Chrome | Reliable web automation in the same window the person sees |

Plus shell (`run_command`, with stdin closed — see war stories), files, clipboard.

AT-SPI is only populated if apps export accessibility data, which is why the Selkies service sets
`GTK_MODULES=gail:atk-bridge`, `ACCESSIBILITY_ENABLED=1`, `QT_ACCESSIBILITY=1`, and Chrome gets
`--force-renderer-accessibility`.

## The takeover lock (`takeover.py` + `input_watch.c`)

Goal: when a person touches the mouse/keyboard, the agent's input commands are refused until the person has been
idle for 5 s (or someone calls `takeover_release`).

The hard part: **Selkies and xdotool both inject input through XTest**, so you can't tell "human" from "agent" by
device. The trick is timing:
- `input_watch` (a small C program) prints a line for every input event on the X display.
- While an agent input command is running (`agent_acting` context manager), plus a 0.5 s grace period, events are
  attributed to the agent. Any other event is the human.
- `execute()` checks `takeover.locked()` before any command in `INPUT_COMMANDS`, returning
  `{"success": false, "takeover": true, ...}`.

Why a C program: `xinput test-xi2 --root` failed with `BadAccess`. Plain button events can only be selected by one
client per window, and the desktop already holds them. XInput2 **raw** events can be watched by any number of
clients. And because XTest-injected *pointer motion* on Xvfb doesn't produce raw motion events, `input_watch` also
**polls the pointer position** every 200 ms.

✅ **Check yourself:** Why can't the takeover lock just ask "which device did this event come from?" What are the
trade-offs of pixels vs the accessibility tree vs CDP for an agent?

