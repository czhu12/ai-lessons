# Current state and open work

As of 2026-09-28.

## What exists

| Piece | Where | State |
|---|---|---|
| The server (Python package `canine-computer-use` 0.1.0) | `resources/agent_computer/computer_use/` | working; builds a wheel; key tests pass |
| Install on new computers | `ProvisionJob` (upload) + `omarchy-setup.sh` "Computer use" section | full setup re-run on computer 14 |
| `PortForward`, `ComputerUse` client | `app/services/agent_computers/` | working |
| MCP tools (4) + `AgentComputerAccess` concern | `app/mcp/tools/` | working; one spec |
| Proxy route `/agent_computers/:id/computer-use/*` | `lib/agent_computer_proxy.rb` | session auth only |
| Status probe | `AgentComputers::Stats` | shows whether port 8000 answers |

The Canine changes are on the agent-sandboxes branch, **in review, not yet committed**.

Tested end to end on one machine, computer 14 ("omarchy-auto"), by the five labs in this book and by calling the MCP
tools from Rails. Older computers (11, 12) were set up before the server existed and don't have it. Every new
computer gets it automatically.

## Open work

1. **Latency.** Each tool call spends ~2.8 s finding the pod and opening a port-forward before doing ~0.5 s of work.
   Keeping one forward open per computer (as the Rack proxy does for Selkies) would cut most of that. Also worth
   trying: JPEG screenshots. The PNG of Omarchy's wallpaper is ~860 KB, and a JPEG would be a fraction of that
   through the tunnel.
2. **API access.** Accept Canine API tokens on `/agent_computers/:id/computer-use/*` and add
   `/api/v1/agent_computers`, with swagger specs, so agents other than Claude Code over MCP can use it.
3. **More than one agent per computer.** The server serializes actions with one lock, which is right for one
   agent. Two agents on one desktop would also fight over focus, and that needs a design, not just a lock.
4. **Publishing the package.** It's packaged, but not on PyPI. Publishing would need a decision about the name
   (`computer_use` is a generic import name) and about supporting compositors other than Hyprland. `desktop.py`
   (hyprctl, grim) and `mouse.move_to` are the Hyprland-specific parts. uinput, wtype and AT-SPI work on any
   Wayland desktop.
5. **Human and agent at the same time.** Someone watching the Selkies stream sees the agent's actions live, but if
   they move the mouse too, both fight over it. A "take over" handoff, like the old computer server's takeover lock,
   would help.
6. **The keyboard question** (separate from computer use): Cmd on a Mac is sent as Super, which collides with some
   macOS shortcuts. Still to decide: remap the colliding Omarchy shortcuts in Hyprland config, or use a custom
   layout.

## Check yourself

**Q: Which parts would you rewrite to support GNOME or KDE instead of Hyprland?**

<details>
<summary>Answer</summary>

`desktop.py` (monitor, windows, cursor position, screenshots all come from `hyprctl` and `grim`, which needs
wlr-screencopy) and `mouse.move_to` (Hyprland's cursor dispatcher). The uinput device, wtype text (on compositors
with the virtual-keyboard protocol), AT-SPI, the HTTP server and the Canine side stay the same.

</details>

Next: [Glossary and cheat sheet](09-glossary-and-cheat-sheet.md).
