#!/usr/bin/env bash
# Lab 4 walkthrough: how the server presses keys on Wayland. Looks at /dev/uinput and the server's virtual device,
# builds a keyboard from scratch to press Super+7, and shows why wtype can't do the same. Only switches workspaces.
source "$(dirname "$0")/../env.sh"
cd "$(dirname "$0")"
workspace() { vm_ssh_desktop 'hyprctl -j activeworkspace' | jq -r '"   now on workspace \(.id)"'; }

step "1. /dev/uinput: the kernel's door for making input devices. The desktop user may open it (wheel group)"
run "vm_ssh 'ls -l /dev/uinput; id -Gn; cat /etc/udev/rules.d/60-canine-uinput.rules /etc/modules-load.d/canine-uinput.conf'"
note "Written by omarchy-setup.sh. static_node=uinput: the node exists before the module loads, so the rule applies."

step "2. The server's own virtual device, created on its first click or key press"
run "act '{\"action\": \"key\", \"text\": \"super+1\"}'"
run "vm_ssh 'grep -A1 -B1 canine-computer-use /proc/bus/input/devices'"
run "vm_ssh_desktop 'hyprctl -j devices' | jq -c '{keyboards: [.keyboards[].name], mice: [.mice[].name]}'"
note "To Hyprland it's a keyboard and a mouse like any USB one."

step "3. Build one yourself: lab_keyboard.py creates 'lab-keyboard' and presses Super+7 (read it first: ~25 lines)"
workspace
run "vm_ssh_desktop python3 - < lab_keyboard.py"
workspace
note "Key events carry physical key codes (KEY_7 = 8), not characters. Hyprland maps them through the keyboard layout."

step "4. The same combination with wtype, which types text through Wayland's virtual-keyboard protocol"
run "vm_ssh_desktop 'hyprctl dispatch \"hl.dsp.focus({ workspace = 1 })\"'"
workspace
run "vm_ssh_desktop 'wtype -M logo -k 3 -m logo'"
workspace
note "Still on 1. Omarchy binds workspaces by key code (\"code:\" .. workspace + 9), and wtype sends its own"
note "made-up keymap, so the codes don't match. That's why the server uses uinput for keys and wtype only for text."
run "vm_ssh_desktop 'hyprctl -j binds' | jq -c '.[] | select(.description == \"Switch to workspace 3\") | {modmask, key, description}' | head -1"
note "key is empty: the bind is on a key code, which hyprctl binds doesn't print. modmask 64 = Super."

step "5. And through the server: key presses by name become these same key codes"
run "act '{\"action\": \"key\", \"text\": \"super+3\"}'"
workspace
run "act '{\"action\": \"key\", \"text\": \"super+1\"}'"
workspace
run lab_stop_forwards
