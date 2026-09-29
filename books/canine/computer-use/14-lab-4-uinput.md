# Lab 4: uinput from scratch

**Goal:** see how the server presses keys: the device node and its permissions, the server's virtual keyboard, a
25-line keyboard of your own, and why wtype can't press Omarchy's shortcuts. **Time:** 2 minutes.
**Chapters:** [Pressing keys and clicking](03-pressing-keys-and-clicking.md).

```bash
./labs/04-uinput/run.sh
```

1. `/dev/uinput`: owned by group `wheel`, thanks to the udev rule and `static_node`.
2. The server's virtual device in `/proc/bus/input/devices` and in Hyprland's device list.
3. Run `labs/04-uinput/lab_keyboard.py` in the VM: it creates `lab-keyboard` and presses Super+7. The workspace
   changes.
4. The same combination through `wtype`: the workspace doesn't change.
5. The same combination through the server: it changes again.

`lab_keyboard.py` is the whole of chapter 3 in miniature:

```python
fd = os.open("/dev/uinput", os.O_WRONLY)
fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)                      # this device sends key events...
for code in (KEY_LEFTMETA, KEY_7):
    fcntl.ioctl(fd, UI_SET_KEYBIT, code)                   # ...for these two keys
fcntl.ioctl(fd, UI_DEV_SETUP, struct.pack("HHHH80sI", 0x06, 0x1, 0x1, 1, b"lab-keyboard", 0))
fcntl.ioctl(fd, UI_DEV_CREATE)                             # a new keyboard appears in /dev/input
...
for code, value in [(KEY_LEFTMETA, 1), (KEY_7, 1), (KEY_7, 0), (KEY_LEFTMETA, 0)]:   # 1 = down, 0 = up
    event(EV_KEY, code, value)
```

## Questions

**Q: `KEY_7` is 8, but Omarchy's bind for workspace 7 is `code:16`. How do they match?**

<details>
<summary>Answer</summary>

Hyprland uses XKB key codes, which are the kernel's evdev codes plus 8. evdev 8 + 8 = 16 = `code:16`, and Omarchy
computes it as workspace + 9 = 16.

</details>

**Q: Why does Hyprland list the server as both a keyboard (`canine-computer-use`) and a mouse
(`canine-computer-use-1`)?**

<details>
<summary>Answer</summary>

The device declares key events (keyboard keys and mouse buttons) and relative motion (movement and wheels).
libinput splits that into a keyboard and a pointer, the same as some real combo devices.

</details>

**Q: Why did the udev rule need `static_node=uinput`?**

<details>
<summary>Answer</summary>

`/dev/uinput` is created at boot from the module's alias, before udev sees any event for it. A normal rule only runs
on events, so it never set the group. `static_node` tells udev to apply the rule's permissions to that static node.

</details>

## Expected output

<details>
<summary>📜 Expected output (a real run, captured while writing this book)</summary>

```text
== 1. /dev/uinput: the kernel's door for making input devices. The desktop user may open it (wheel group)
$ vm_ssh 'ls -l /dev/uinput; id -Gn; cat /etc/udev/rules.d/60-canine-uinput.rules /etc/modules-load.d/canine-uinput.conf'
crw-rw---- 1 root wheel 10, 223 Sep 29 01:45 /dev/uinput
omarchy wheel
KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", GROUP="wheel", MODE="0660"
uinput
   Written by omarchy-setup.sh. static_node=uinput: the node exists before the module loads, so the rule applies.

== 2. The server's own virtual device, created on its first click or key press
$ act '{"action": "key", "text": "super+1"}'
{}
$ vm_ssh 'grep -A1 -B1 canine-computer-use /proc/bus/input/devices'
I: Bus=0006 Vendor=1234 Product=5678 Version=0001
N: Name="canine-computer-use"
P: Phys=
$ vm_ssh_desktop 'hyprctl -j devices' | jq -c '{keyboards: [.keyboards[].name], mice: [.mice[].name]}'
{"keyboards":["power-button","at-translated-set-2-keyboard","canine-computer-use"],"mice":["qemu-qemu-usb-tablet","imexps/2-generic-explorer-mouse","canine-computer-use-1"]}
   To Hyprland it's a keyboard and a mouse like any USB one.

== 3. Build one yourself: lab_keyboard.py creates 'lab-keyboard' and presses Super+7 (read it first: ~25 lines)
   now on workspace 1
$ vm_ssh_desktop python3 - < lab_keyboard.py
pressed Super+7 on lab-keyboard
   now on workspace 7
   Key events carry physical key codes (KEY_7 = 8), not characters. Hyprland maps them through the keyboard layout.

== 4. The same combination with wtype, which types text through Wayland's virtual-keyboard protocol
$ vm_ssh_desktop 'hyprctl dispatch "hl.dsp.focus({ workspace = 1 })"'
ok
   now on workspace 1
$ vm_ssh_desktop 'wtype -M logo -k 3 -m logo'
   now on workspace 1
   Still on 1. Omarchy binds workspaces by key code ("code:" .. workspace + 9), and wtype sends its own
   made-up keymap, so the codes don't match. That's why the server uses uinput for keys and wtype only for text.
$ vm_ssh_desktop 'hyprctl -j binds' | jq -c '.[] | select(.description == "Switch to workspace 3") | {modmask, key, description}' | head -1
{"modmask":64,"key":"","description":"Switch to workspace 3"}
   key is empty: the bind is on a key code, which hyprctl binds doesn't print. modmask 64 = Super.

== 5. And through the server: key presses by name become these same key codes
$ act '{"action": "key", "text": "super+3"}'
{}
   now on workspace 3
$ act '{"action": "key", "text": "super+1"}'
{}
   now on workspace 1
$ lab_stop_forwards
port-forwards stopped
```

</details>

## Try next

- Add `KEY_ENTER` (28) to `lab_keyboard.py` and send `super+Return` to open a terminal.
- `vm_ssh_desktop 'wtype -M logo -k 3 -m logo'` while a text field has focus: what does it type?
