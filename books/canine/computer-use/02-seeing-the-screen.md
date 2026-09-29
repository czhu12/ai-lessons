# Seeing the screen

`computer_use/desktop.py` answers three questions: how big is the screen, what's on it, and what does it look like.
It's the smallest module, but it holds the idea everything else depends on: **there are three sizes for one
screen, and agents only ever see one of them.**

## Asking Hyprland

On Wayland the compositor knows everything, and Hyprland answers over a socket through `hyprctl`. With `-j` the
answers are JSON:

| Command | Answers |
|---|---|
| `hyprctl -j monitors` | each monitor's size in pixels, its `scale`, and its position in the layout |
| `hyprctl -j clients` | every window: title, `class` (the app), `pid`, workspace, `at` and `size` |
| `hyprctl -j activewindow` | the focused window |
| `hyprctl cursorpos` | where the cursor is |
| `hyprctl dispatch ...` | do something: switch workspace, move the cursor, focus a window |

`hyprctl` finds the running Hyprland through `HYPRLAND_INSTANCE_SIGNATURE`, which only processes inside the session
have. That's one reason the server runs as a user service in the session. (The labs' `vm_ssh_desktop` helper copies
the session's environment into an SSH command for the same reason.)

## Three sizes for one screen

Canine's VMs have a 1920x1080 monitor at **scale 1.25**, so text is big enough to read in a browser tab. Scaling
means Hyprland lays windows out in **layout units** (sometimes called logical pixels), and each one covers 1.25
real pixels:

| Space | Size | Who uses it |
|---|---|---|
| Monitor (device) pixels | 1920 x 1080 | the video Selkies streams; Chromium's web content (chapter 4) |
| Layout units | 1536 x 864 (1920 / 1.25) | Hyprland: window positions, the cursor, `grim -g` regions |
| **Screenshot pixels** | **1280 x 720** | **agents: every coordinate in the API** |

Lab 1 shows all three for one point: the middle of the screenshot, `(640, 360)`, is `hyprctl cursorpos` →
`768, 432`, which is the monitor's pixel `(960, 540)`.

`desktop.py` keeps this in one small record:

```python
MAX_SCREENSHOT = (1280, 800)

# The monitor as agents see it: its position in the layout, the screenshot's size, screenshot pixels per layout unit
# (`scale`), and the monitor's own pixels per layout unit (`device_scale`, Hyprland's monitor scale)
Screen = namedtuple("Screen", ["x", "y", "width", "height", "scale", "device_scale"])

def screen():
    m = hyprctl_json("monitors")[0]
    fit = min(MAX_SCREENSHOT[0] / m["width"], MAX_SCREENSHOT[1] / m["height"], 1)
    return Screen(m["x"], m["y"], round(m["width"] * fit), round(m["height"] * fit), m["scale"] * fit, m["scale"])

def to_layout(x, y):
    s = screen()
    return s.x + x / s.scale, s.y + y / s.scale

def to_pixels(x, y):
    s = screen()
    return round((x - s.x) * s.scale), round((y - s.y) * s.scale)
```

For our monitor, `fit` is 2/3 and `scale` is 1.25 × 2/3 = 0.833: one layout unit is 0.833 screenshot pixels. Every
action converts on the way in (`to_layout`), and everything the server reports converts on the way out
(`to_pixels`). Nothing in the middle mixes them up.

(The real `screen()` also caches the answer for a second. The accessibility tree converts thousands of positions per
request, and running `hyprctl` for each one would take seconds.)

## Why 1280 x 720, not the full 1920 x 1080?

The first version sent full-size 1920x1080 screenshots, and it looked fine: the tools returned images, and clicks
landed where they should when we tested with curl. Building Lab 5 turned up the problem. **Anthropic's API limits
image size** (about 1.15 megapixels, and 1568 pixels on the long edge) and quietly shrinks anything bigger before the
model sees it. A 1920x1080 image arrives as roughly 1430x805. The model then gives coordinates in *that* image, and
the server would read them as 1920x1080 pixels, so every click would land about 34% too far right and down.

Anthropic's advice is to scale screenshots down yourself and scale coordinates back up. The cleanest way to do that
is to make the scaled screenshot *the* coordinate system, which is what `screen()` does. 1280x720 fits the limit,
and 1920 → 1280 is an exact 2/3.

`grim` can scale while it captures:

```python
def screenshot(region=None):
    if region is None:
        # grim rounds the image size down, so nudge the scale up: 864 x 0.83333 is 719.99..., and should be 720
        scale = screen().scale + 1e-6
        return subprocess.run(["grim", "-s", str(scale), "-"], capture_output=True, check=True).stdout
    left, top = to_layout(region[0], region[1])
    right, bottom = to_layout(region[2], region[3])
    geometry = f"{round(left)},{round(top)} {round(right - left)}x{round(bottom - top)}"
    return subprocess.run(["grim", "-g", geometry, "-"], capture_output=True, check=True).stdout
```

That `1e-6` nudge exists because the first scaled screenshot came out **1280x719**. `grim` truncates, and 864 ×
0.8333… in floating point is 719.9999.

## Zoom: the detail you gave up

Scaling down loses detail, and small text gets hard to read. The `zoom` action gets it back: give it a region in
screenshot pixels and it returns that region at the **monitor's full resolution** (`grim -g` without `-s` captures at
the output's own scale). In Lab 3, a 74x22 region around a link comes back as a 111x32 image, sharp enough to read.

## Windows

`GET /windows` turns `hyprctl clients` into screenshot pixels:

```json
{"title": "Example Domain - Chromium", "app": "chromium", "pid": 12049, "workspace": 6,
 "focused": true, "bounds": {"x": 10, "y": 32, "width": 1260, "height": 678}}
```

Agents use it to check what's open and focused before typing, since keys go to whatever has focus. The labs do the
same check before they type anything.

## Check yourself

**Q: An agent clicks `(1279, 719)`. Which monitor pixel is that, and which layout point?**

<details>
<summary>Answer</summary>

Layout: 1279 / 0.8333 = 1534.8, 719 / 0.8333 = 862.8 (just inside 1536x864). Monitor pixels: × 1.25 → about
(1918, 1078), the bottom-right corner.

</details>

**Q: Why not keep full-size screenshots and scale the model's coordinates by 1920/1430 on the way in?**

<details>
<summary>Answer</summary>

You'd need to know exactly how the API resized the image, and that depends on the model and can change. If the
server sends an image that's already small enough, nothing gets resized, and the coordinates the model returns are
exactly the image's.

</details>

**Q: What does `zoom` give you that a second screenshot doesn't?**

<details>
<summary>Answer</summary>

Resolution. A screenshot is scaled to 1280x720. A zoom captures its region at the monitor's native 1920x1080
density, so small text is readable, and a small region costs few image tokens.

</details>

Next: [Pressing keys and clicking](03-pressing-keys-and-clicking.md).
