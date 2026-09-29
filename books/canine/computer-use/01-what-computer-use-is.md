# What computer use is, and what we built

**Computer use** means letting an AI model operate a computer the way a person does: it looks at the screen, decides
what to do, and moves the mouse or types. Nothing about the apps has to change. If a person can use it through a
screen, keyboard and mouse, so can the model.

This book is about how Canine gives Claude that ability on its **agent computers**: the Omarchy desktops (Arch Linux
plus the Hyprland compositor) that Canine runs as KubeVirt VMs and streams to your browser. The companion book,
[Desktops in Kubernetes](../agent-computers/README.md), explains how those desktops exist at all. This one picks up
where it stops: once there's a desktop, how does an agent drive it?

## The loop

Every computer-use agent runs the same loop:

```text
      ┌──────────────────────────────────────────────────────────────┐
      │                                                              │
      ▼                                                              │
 screenshot ──► model looks at it ──► model picks one action ──► run the action
                                      {"action": "left_click",
                                       "coordinate": [640, 400]}
```

The model never touches the machine. It only returns small JSON actions. Something else (the **harness**) carries each
one out and sends back a fresh screenshot. Anthropic's
[computer-use tool](https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/computer-use-tool) defines that JSON:
`screenshot`, `left_click`, `double_click`, `mouse_move`, `left_click_drag`, `scroll`, `key` (`"ctrl+s"`), `type`
(text), `wait`, `zoom`, and a few more. Coordinates are pixels in the most recent screenshot.

So "adding computer use" is two jobs:

1. **Inside the machine:** something that can take a screenshot and turn `{"action": "left_click", ...}` into a real
   click that the desktop believes.
2. **Between the model and the machine:** a way for Claude to send those actions, and for only the right person's
   Claude to reach that particular machine.

## What we built

```text
Claude Code
   │  MCP tool call: computer_action {agent_computer_id: 14, action: "left_click", coordinate: [640, 400]}
   ▼
Canine  /mcp  (OAuth token → user → account)
   │  Tools::ComputerAction ── checks the computer is yours and running
   │  AgentComputers::ComputerUse ── POST /computer-use {...}
   │  AgentComputers::PortForward ── kubectl port-forward to the VM's launcher pod, port 8000
   ▼
virt-launcher pod ── masquerade NAT ──► the VM (Omarchy)
                                          │
                                          ▼
                              canine-computer-use (Python, port 8000)
                              ├─ see:  hyprctl (monitor, windows, cursor), grim (screenshots)
                              ├─ act:  a uinput virtual keyboard + mouse, wtype for text,
                              │        hyprctl to place the cursor
                              └─ read: AT-SPI, the accessibility tree
```

| Piece | Where | Chapter |
|---|---|---|
| The server in the VM | `resources/agent_computer/computer_use/` (a Python package, ~750 lines) | [2](02-seeing-the-screen.md), [3](03-pressing-keys-and-clicking.md), [4](04-the-accessibility-tree.md), [5](05-the-server-as-a-python-package.md) |
| Installing it | `ProvisionJob` + the "Computer use" section of `omarchy-setup.sh` | [5](05-the-server-as-a-python-package.md) |
| Reaching it | `AgentComputers::PortForward`, `AgentComputers::ComputerUse`, a proxy route | [6](06-the-canine-side.md) |
| Claude's tools | `list_agent_computers`, `computer_screenshot`, `computer_action`, `computer_accessibility` | [6](06-the-canine-side.md) |

## Three ways to look at a screen

An agent can learn about the screen in three ways, and the server offers all three:

| | What the agent gets | Good at | Bad at |
|---|---|---|---|
| **Pixels** (`screenshot`, `zoom`) | an image | anything visible, including canvases, games and terminals | costs image tokens; the model has to guess exact coordinates |
| **Windows** (`GET /windows`) | titles, apps, workspaces, bounds | "is my window open and focused?" | nothing inside the window |
| **Accessibility tree** (`/accessibility/*`) | every button, link and field with its role, name and position | "press the Save button", reading text exactly | apps that don't publish a tree; custom-drawn UIs |

The pixel actions follow Anthropic's spec exactly, so a model trained on computer use already knows how to use them.
The accessibility operations are our own addition. They make the common case ("click the link called Learn more")
cheaper and more reliable than reading pixels.

## Why a server inside the VM?

On an old **X11** desktop, any program that could connect to the display could take screenshots and inject clicks
(the XTest extension). A computer-use harness could run anywhere with a `DISPLAY` variable.

Omarchy runs **Wayland**, where the compositor (Hyprland) is the only authority. Apps can't see each other's
windows, can't read the screen, and can't fake input for other apps. That's good for security, but it means every
way in is either:

- **a compositor feature**: `hyprctl` can list windows and move the cursor, and the `wlr-screencopy` protocol (used
  by `grim`) can capture the screen. All of these need access to the running session.
- **below the compositor**: the kernel's `uinput` makes a virtual device that looks like real hardware.

Either way, you have to be *inside the VM, in the user's session*. So the server runs there, as a systemd user
service that starts with the desktop, and Canine talks to it over HTTP.

> **A dead end first.** Selkies (the streamer) ships `pixelflux`, which has a `computer_use_bind` that already
> implements Anthropic's actions. It looked perfect. But in the mode we use (attaching to Hyprland as a Wayland client), it
> drives Selkies' *own* internal compositor, an empty screen nobody sees, not Hyprland. See the
> [war stories](07-war-stories.md).

## Check yourself

**Q: The model returns `{"action": "left_click", "coordinate": [640, 400]}`. What decides which point on the real
screen that is?**

<details>
<summary>Answer</summary>

The screenshot the model was looking at. Coordinates are pixels in the latest screenshot, so the server has to
convert them to whatever the desktop uses internally. On Omarchy those are three different spaces; see
[Seeing the screen](02-seeing-the-screen.md).

</details>

**Q: Why can't Canine just take screenshots from outside the VM, the way the Selkies stream already does?**

<details>
<summary>Answer</summary>

It could take screenshots, since Selkies is already capturing the screen. But it couldn't *act*, and on Wayland every
input and capture path goes through the session anyway. One server in the session does all three (see, act, read the
accessibility tree) with the same coordinate system, so there's one source of truth.

</details>

**Q: When would an agent use the accessibility tree instead of a screenshot?**

<details>
<summary>Answer</summary>

When the thing it wants has a name: a button, a link, a text field. Finding it by role and name is exact and cheap,
and pressing it doesn't depend on guessing pixels. Screenshots are for everything without a tree (terminals,
canvases) and for checking what actually happened.

</details>

Next: [Seeing the screen](02-seeing-the-screen.md).
