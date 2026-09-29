# Pressing keys and clicking on Wayland

Seeing the screen was easy: Hyprland answers questions. **Acting** is harder, because Wayland was designed so that
programs *can't* fake input for each other. This chapter covers the three mechanisms the server combines, and why
each job went to the one it did.

## The options

| Mechanism | What it is | Can do | Can't do |
|---|---|---|---|
| `hyprctl dispatch` | Hyprland's own commands | move the cursor anywhere, switch workspaces, focus windows | click, scroll, press keys in apps |
| Virtual-keyboard protocol (`wtype`) | a Wayland protocol: a client gives the compositor its own keymap and "types" | type any Unicode text | trigger Omarchy's shortcuts (see below) |
| **uinput** | a kernel interface that creates a new input device | anything a real keyboard and mouse can | type characters the keyboard layout doesn't have |

The server uses all three, each for what it's best at:

| Action | How |
|---|---|
| Move the cursor | `hyprctl dispatch "hl.dsp.cursor.move({ x = X, y = Y })"` (layout coordinates, absolute) |
| Click, scroll, press/release buttons | uinput mouse buttons and wheel |
| Key combinations (`ctrl+a`, `super+2`, `Return`) | uinput key codes, as on a US keyboard |
| Typing text | `wtype -- "text"` |

## uinput: a keyboard made of software

`/dev/uinput` is how the kernel lets a program create a device, the same kind of thing a USB keyboard becomes when
you plug it in. Once it exists, *everything* above the kernel treats it as hardware: libinput, Hyprland, its
shortcuts, and the focused app. Nothing at that level can tell it apart from a real keyboard, which is exactly what
computer use needs.

Creating one takes a few `ioctl` calls. Here's `computer_use/uinput.py`, trimmed:

```python
EV_SYN, EV_KEY, EV_REL = 0x00, 0x01, 0x02
UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_RELBIT = 0x40045564, 0x40045565, 0x40045566
UI_DEV_SETUP, UI_DEV_CREATE = 0x405C5503, 0x5501

self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_KEY)          # it sends key events (keys and mouse buttons)
fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_REL)          # and relative motion (mouse movement, wheels)
for code in [*range(1, 256), *BUTTONS.values()]:    # every keyboard key, plus left/right/middle
    fcntl.ioctl(self.fd, UI_SET_KEYBIT, code)
...
fcntl.ioctl(self.fd, UI_DEV_SETUP, struct.pack("HHHH80sI", 0x06, 0x1234, 0x5678, 1, b"canine-computer-use", 0))
fcntl.ioctl(self.fd, UI_DEV_CREATE)
```

After that, pressing a key means writing `struct input_event` records, each followed by a `SYN_REPORT` that says
"that's one complete report":

```python
def emit(self, event_type, code, value):
    os.write(self.fd, struct.pack("llHHi", 0, 0, event_type, code, value))   # time, type, code, value

def key(self, code, down):
    self.emit(EV_KEY, code, 1 if down else 0)
    self.sync()                                                             # EV_SYN / SYN_REPORT
```

The ioctl numbers and struct layouts come from `linux/uinput.h` and `linux/input.h`. Python's standard library is
enough; no `python-evdev` needed. Lab 4 builds a 25-line keyboard from scratch and uses it to switch workspaces.

Hyprland sees the server's device as a keyboard (`canine-computer-use`) plus a mouse (`canine-computer-use-1`),
alongside QEMU's own tablet and keyboard. The device is created lazily, on the first click or key press.

### Permission to open /dev/uinput

By default only root can open `/dev/uinput`, and the server runs as the desktop user. `omarchy-setup.sh` fixes that
with two files:

```text
/etc/modules-load.d/canine-uinput.conf   uinput
/etc/udev/rules.d/60-canine-uinput.rules KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput",
                                         GROUP="wheel", MODE="0660"
```

The desktop user is in `wheel`. Getting there took three tries; see [war stories](07-war-stories.md).
`static_node=uinput` is the important part: `/dev/uinput` is created at boot before any udev event, so a rule that
only matches events never applies to it.

## Key codes are physical keys

A uinput keyboard doesn't send characters. It sends **key codes**, numbers for physical keys (`KEY_A` = 30,
`KEY_2` = 3, `KEY_LEFTMETA` = 125). The keyboard layout then decides what character each key makes. So
`keyboard.py` has a table for a US keyboard, plus which characters need Shift:

```python
MODIFIER_CODES = {"shift": 42, "ctrl": 29, "alt": 56, "super": 125}
KEYS = {..., "return": 28, "escape": 1, "tab": 15, "up": 103, "next": 109, ...}   # xdotool's names
SHIFTED = dict(zip('!@#$%^&*()_+{}:"~|<>?', "1234567890-=[];'`\\,./"))         # "?" is Shift + "/"
```

`press("ctrl+shift+Tab")` presses the modifiers, taps the key, and releases in reverse order. Names follow xdotool
(`Return`, `Page_Down`, `BackSpace`) because that's what Anthropic's computer-use spec uses, and models already
know them. `cmd`, `win` and `meta` all mean Super.

## Why keys don't go through wtype

The first version pressed everything with `wtype`, because it's simple and already on Omarchy. Text worked. Then
`super+2` did **nothing**.

Omarchy binds many shortcuts by **key code**, not by character:

```lua
-- /usr/share/omarchy/default/hypr/bindings/tiling.lua
local key = "code:" .. tostring(workspace + 9)
```

That keeps Super+1…9 working on any keyboard layout (on a French keyboard, the top-row keys aren't digits). But
`wtype` works by sending the compositor **its own made-up keymap**, where "2" can be any code wtype likes. The
character is right, but the code doesn't match the bind. A uinput keyboard sends the real code for the physical "2"
key, so the bind fires. Lab 4 shows both side by side.

## Why text still goes through wtype

The reverse problem: uinput can only press keys that exist on the layout. `é`, `✓` or `日本` aren't on a US keyboard.
wtype's made-up keymap can include any character, so typing text through it is exact:

```python
def type_text(text):
    subprocess.run(["wtype", "--", text], capture_output=True, text=True, check=True, timeout=60)
```

(`--` stops text that starts with `-` from being read as an option.) Lab 2 types `café ✓ → 日本` into a terminal.

## The mouse

Moving: Hyprland can put the cursor at an absolute position, which is simpler than steering a relative mouse:

```python
def move_to(x, y):
    layout_x, layout_y = desktop.to_layout(x, y)
    desktop.hyprctl("dispatch", f"hl.dsp.cursor.move({{ x = {round(layout_x)}, y = {round(layout_y)} }})")
    # A zero-distance nudge makes the app under the cursor notice it arrived (hover state, drag targets)
    device().emit(EV_REL, REL_X, 0)
    device().sync()
```

Clicking, scrolling and dragging then use the uinput device: a click is button down + up, a double click is two of
them 50 ms apart, scrolling is `REL_WHEEL` steps, and a drag is press, 20 small moves, release. Modifiers can be held
around any of them. Anthropic's spec passes them in `text`, e.g. `{"action": "left_click", "coordinate": [...],
"text": "shift"}`:

```python
@contextmanager
def holding(modifiers):
    codes = [keyboard.MODIFIER_CODES[m] for m in modifiers]
    for code in codes:
        device().key(code, down=True)
    try:
        yield
    finally:
        for code in reversed(codes):
            device().key(code, down=False)
```

The `finally` matters: if a click fails halfway, Shift must not stay stuck down on someone's desktop.

## One action at a time

The HTTP server is threaded, but every request takes one global lock. Two requests moving the same mouse at once
would interleave into nonsense (a drag from one request and a click from another). Actions are fast, so serializing
them costs nothing.

## Check yourself

**Q: Why does `super+2` work through uinput but not through wtype?**

<details>
<summary>Answer</summary>

Omarchy binds workspace shortcuts by key code (`code:11` is the physical "2" key). uinput sends that real code.
wtype sends the character through its own keymap with arbitrary codes, so the character is right but the code isn't.

</details>

**Q: Why not type text through uinput too, and drop wtype?**

<details>
<summary>Answer</summary>

uinput can only press keys that exist on the keyboard layout. Characters like `é` or `日本` have no key on a US
layout. wtype sends its own keymap, so it can type any Unicode character.

</details>

**Q: The server moves the cursor with `hyprctl`, not uinput's relative motion. Why?**

<details>
<summary>Answer</summary>

`hyprctl` puts it at an exact absolute position in one step. With relative motion you'd have to know where the
cursor is and account for pointer acceleration. The zero-distance uinput nudge afterwards makes the app under the
cursor notice it arrived.

</details>

Next: [The accessibility tree](04-the-accessibility-tree.md).
