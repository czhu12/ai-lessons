# War stories

Every bug found while building computer use and writing this book: what we saw, what caused it, and the fix. Several
were only found because the labs were run against a real machine.

## 1. The ready-made computer-use library drove an invisible screen

**Seen:** Selkies' `pixelflux` package has a `computer_use_bind` that already implements Anthropic's computer-use
actions. It looked like the whole job was done, until a closer look at what it actually drives.

**Cause:** Selkies can run its own Wayland compositor, or stream an existing one (`--wayland-host-display`, our
mode). `computer_use_bind` always drives *Selkies' own* compositor, which in our mode is an empty screen nobody
sees.

**Fix:** our own server, talking to Hyprland. The one useful thing we kept from pixelflux was confirmation of the
action names and fields.

## 2. `super+2` did nothing

**Seen:** typing text with `wtype` worked perfectly, and `ctrl+l` worked in Chromium, but Omarchy's shortcuts
(`super+2` to switch workspace) were ignored.

**Cause:** Omarchy binds them by key code (`"code:" .. workspace + 9`) so they work on any layout. `wtype` sends the
compositor its own keymap with its own made-up codes, so the character is right but the code isn't.

**Fix:** a uinput virtual keyboard that sends real US-layout key codes for all key presses, with `wtype` kept only for
text. [Chapter 3](03-pressing-keys-and-clicking.md), and Lab 4 shows both.

## 3. /dev/uinput stayed root-only (three tries)

**Seen:** the server, running as the desktop user, was refused permission to open `/dev/uinput`.

**Tries:**

1. A udev rule tagging it `uaccess`, which usually grants the logged-in user access. That applies to seat devices
   through logind, and nothing changed.
2. A `GROUP="wheel"` rule, then `udevadm trigger --action=change`. No change either: `/dev/uinput` is a **static
   node**, created at boot from the module's alias before udev ever sees an event for it, so event rules never
   match.
3. `OPTIONS+="static_node=uinput"` in the rule, which tells udev to apply the permissions to the static node, plus
   `modules-load.d` so the module is always loaded. That worked.

## 4. Links on web pages were 25% off

**Seen:** the accessibility tree's bounds for Chromium's toolbar buttons matched the screenshot, but a link on
example.com came back 25% too far right and down.

**Cause:** Chromium reports its own UI in layout units, but *web content* in device pixels, and the scale is 1.25.

**Fix:** a `device_pixels` flag that switches on at Chromium's `document web` element and is inherited below it
([chapter 4](04-the-accessibility-tree.md)). Verified by zooming into the reported bounds, which show exactly the
link.

## 5. Full-size screenshots would have made Claude miss

**Seen:** nothing, at first. Every test used curl, and curl doesn't resize images. Timing the MCP tools for Lab 5
made us look at the 3 MB, 1920x1080 screenshots more closely.

**Cause:** Anthropic's API shrinks images above about 1.15 megapixels before the model sees them. The model would
answer in the shrunken image's coordinates (about 1430x805), and every click would land about 34% too far right and
down.

**Fix:** screenshots are scaled to fit 1280x800 (1280x720 here), and that scaled image *is* the coordinate system.
[Chapter 2](02-seeing-the-screen.md).

**Lesson:** test through the same path the real user takes. For computer use, that path includes the model.

## 6. 1280 x 719

**Seen:** the first scaled screenshot was one pixel short.

**Cause:** `grim -s 0.8333333333333334` computes 864 × 0.8333… = 719.99999 and truncates.

**Fix:** add `1e-6` to the scale. An off-by-one here would reject clicks on the bottom row, since the server checks
that coordinates are on screen.

## 7. "push button" found nothing

**Seen:** `find role="push button"` returned an empty list for Chromium's toolbar.

**Cause:** the examples used "push button", the role's name in older AT-SPI and in a lot of documentation. The
installed version reports `button`: a survey of every role in Chromium's tree found 27 `button`s and no
`push button`.

**Fix:** corrected the examples in the MCP tool description, the server docstrings and the Ruby client's comment.
The tool description is what Claude reads, so a wrong example there would have misled every agent.

## 8. set_text refused Chromium's address bar

**Seen:** `entry 'Address and search bar' isn't editable`, although its states said `editable`.

**Cause:** Chromium's address bar doesn't offer AT-SPI's `EditableText` interface; web page inputs do.

**Fix:** when the interface is missing but the field is editable, focus it through AT-SPI, press `ctrl+a`, and type
over it. The reply says `"method": "typed"` so the agent knows which way it went.

## 9. MCP access check used the wrong scope

**Seen:** the first version of the access check used `AgentComputer.for_account(...)` with a list of accounts.

**Cause:** that scope takes one account, and a user can belong to several.

**Fix:** `AgentComputer.joins(:account_user).where(account_users: { account_id: [...] })`, a single query across
all of them.

## 10. The lab helpers broke in zsh

**Seen:** in bash the labs worked. In zsh, the Mac's default shell, `act '{"action": "key", ...}'` returned
`Unknown action None`, and `forward` printed `disown: no current job`.

**Cause:** `curl ... ${3:+-H 'Content-Type: application/json' -d "$3"}` relies on bash splitting that expansion into
separate words, and zsh doesn't split. curl got one strange argument and sent no body. Separately, zsh's
`disown` refused a job started inside a function.

**Fix:** an explicit `if [ -n "$3" ]` with two curl calls, and `(kubectl port-forward ... &)` in a subshell, which
runs in the background the same way in both shells.

## 11. The new book's secrets weren't ignored

**Seen:** before the first commit, `git status --ignored` listed `labs/.secrets/kubeconfig` and `ssh_key` as
*untracked*, not *ignored*.

**Cause:** the ignore rules for `.secrets/` live in the *other* book's `labs/.gitignore`, not at the repo root.

**Fix:** a `labs/.gitignore` for this book, then checked again: `!! labs/.secrets/...` (ignored). This repo is public,
so the check comes before every commit, not after.

## Check yourself

**Q: Which of these bugs would unit tests with mocks have caught?**

<details>
<summary>Answer</summary>

Almost none. The wrong ActiveRecord scope (#9) would have been caught. The rest only showed up against the real
system: Hyprland's code binds, udev static nodes, Chromium's units, the API's image limits, grim's rounding, the
installed AT-SPI's role names, zsh. That's why the labs run against a real agent computer.

</details>

Next: [Current state and open work](08-current-state-and-open-work.md).
