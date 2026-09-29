# Glossary and cheat sheet

## Glossary

| Term | Meaning |
|---|---|
| **Computer use** | A model operating a computer through screenshots and mouse/keyboard actions |
| **Harness** | The code that carries out the model's actions and sends back screenshots |
| **Anthropic's computer-use tool** | The action JSON models are trained on: `screenshot`, `left_click`, `type`, `key`, `scroll`, `zoom`... |
| **MCP** | Model Context Protocol: how Claude Code calls tools on servers like Canine's `/mcp` |
| **Wayland** | The modern Linux display protocol. The compositor is the only authority over the screen and input |
| **Compositor** | The program that draws the desktop and routes input (Hyprland on Omarchy) |
| **hyprctl** | Hyprland's command-line client: query monitors, windows and the cursor; dispatch commands |
| **Layout units** | Hyprland's coordinates: monitor pixels ÷ monitor scale (1536x864 for 1920x1080 at 1.25) |
| **Screenshot pixels** | The API's coordinates: the scaled screenshot (1280x720) |
| **Device pixels** | The monitor's real pixels (1920x1080); Chromium reports web content in these |
| **grim** | Wayland screenshot tool (wlr-screencopy); `-s` scales, `-g` picks a region in layout units |
| **uinput** | Kernel interface for creating virtual input devices that look like hardware |
| **Key code** | A number for a physical key (`KEY_A` = 30); the layout maps it to a character |
| **`code:` bind** | A Hyprland shortcut bound to a key code rather than a character; layout-independent |
| **wtype** | Types text through Wayland's virtual-keyboard protocol with its own keymap |
| **Static node** | A `/dev` node created at boot before udev sees an event; needs `OPTIONS+="static_node=..."` |
| **AT-SPI** | The Linux accessibility bus: apps publish their UI as a tree for screen readers |
| **Role / name / path** | An element's kind (`button`), label ("Reload"), and child-index address ("4/0/2/7") |
| **`document web`** | The role where a web page starts in Chromium's tree, and where device pixels begin |
| **PEP 668** | "Externally managed" system Python: pip refuses to install into it; use a venv |
| **`--system-site-packages`** | A venv that can also import the system's packages (Omarchy's PyGObject) |
| **Entry point** | `[project.scripts]` in pyproject.toml: a command pip creates that calls a Python function |
| **virt-launcher pod** | The pod that runs a KubeVirt VM's QEMU; port-forwarding to it reaches the guest |

## Cheat sheet

### The server's API (inside the VM, port 8000)

```bash
curl -s localhost:8000/status
curl -s localhost:8000/windows
curl -s -X POST localhost:8000/computer-use -d '{"action": "screenshot"}'
curl -s -X POST localhost:8000/computer-use -d '{"action": "left_click", "coordinate": [640, 360]}'
curl -s -X POST localhost:8000/computer-use -d '{"action": "left_click", "coordinate": [640, 360], "text": "shift"}'
curl -s -X POST localhost:8000/computer-use -d '{"action": "key", "text": "super+Return"}'
curl -s -X POST localhost:8000/computer-use -d '{"action": "type", "text": "hello\n"}'
curl -s -X POST localhost:8000/computer-use -d '{"action": "scroll", "coordinate": [640, 360], "scroll_direction": "down", "scroll_amount": 5}'
curl -s -X POST localhost:8000/computer-use -d '{"action": "zoom", "region": [0, 0, 320, 180]}'
curl -s -X POST localhost:8000/accessibility/find -d '{"app": "chromium", "role": "link", "name": "learn"}'
curl -s -X POST localhost:8000/accessibility/press -d '{"path": "4/0/0/0/5/2/0/1/3/6"}'
curl -s -X POST localhost:8000/accessibility/set_text -d '{"path": "...", "text": "example.com"}'
```

### Omarchy keys an agent needs

| Keys | Does |
|---|---|
| `super+Return` | terminal (foot) |
| `super+shift+Return` | browser (Chromium) |
| `super+w` | close window |
| `super+1` … `super+9` | switch workspace |
| `super+space` | the Omarchy menu |
| `super+k` | the key bindings cheatsheet |

### On the VM

```bash
systemctl --user status canine-computer-use          # is it running?
journalctl --user -u canine-computer-use -f           # its log (each request, and tracebacks)
~/.local/share/canine/venv/bin/pip show canine-computer-use
hyprctl -j devices | jq '.keyboards[].name'           # the virtual keyboard shows up here
grep -A4 canine-computer-use /proc/bus/input/devices
```

### From Canine (Rails console)

```ruby
computer = AgentComputer.find(14)
cu = AgentComputers::ComputerUse.new(computer, K8::Connection.new(computer.cluster, computer.user))
cu.perform(action: "cursor_position")
cu.windows
cu.accessibility(:find, app: "chromium", role: "link")
```
