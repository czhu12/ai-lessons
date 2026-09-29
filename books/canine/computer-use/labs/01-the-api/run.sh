#!/usr/bin/env bash
# Lab 1 walkthrough: talk to the computer-use server over plain HTTP, see the screen, and meet the two coordinate
# systems (screenshot pixels vs Hyprland's layout units). Moves the mouse; clicks nothing.
source "$(dirname "$0")/../env.sh"
cd "$(dirname "$0")"

step "1. Reach the server: a kubectl port-forward to the VM's launcher pod, port 8000 inside the guest"
run 'echo "launcher pod: $(vm_pod)"'
run cu GET /status
note "No authentication: only a port-forward (which needs cluster access) can reach it. Canine checks the user first."

step "2. What's on screen: Hyprland's windows, in screenshot pixels"
run cu GET /windows

step "3. A screenshot: one action, the same JSON an agent's model sends"
run "act '{\"action\": \"screenshot\"}'"
run shot "$LABS/out/lab1-screen.png"
note "The monitor is 1920x1080, but the screenshot is 1280x720: scaled to fit what Anthropic's API takes without"
note "shrinking it again. Its pixels are the coordinates every other action takes."

step "4. Move the mouse to the middle of the screenshot (640, 360) and ask where it is"
run "act '{\"action\": \"mouse_move\", \"coordinate\": [640, 360]}'"
run "act '{\"action\": \"cursor_position\"}'"

step "5. Ask Hyprland directly: the same spot in layout units"
run vm_ssh_desktop hyprctl cursorpos
run "vm_ssh_desktop 'hyprctl -j monitors' | jq -c '.[0] | {name, width, height, scale}'"
note "Three sizes for one screen: 1920x1080 monitor pixels, 1536x864 layout units (1920 / 1.25), 1280x720 screenshot"
note "pixels. The middle of the screenshot, (640, 360), is layout (768, 432). desktop.py converts at the edges."

step "6. Mistakes come back as errors the agent can read (HTTP 400)"
run "act '{\"action\": \"left_click\", \"coordinate\": [5000, 10]}'"
run "act '{\"action\": \"fly\"}'"
run "act '{\"action\": \"key\"}'"

step "7. Done"
run lab_stop_forwards
