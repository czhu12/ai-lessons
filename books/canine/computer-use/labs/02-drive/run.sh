#!/usr/bin/env bash
# Lab 2 walkthrough: drive the desktop with keys, text and clicks, the way an agent does. Opens a terminal on an
# empty workspace, types into it (only after checking it has focus), and closes it again.
source "$(dirname "$0")/../env.sh"
cd "$(dirname "$0")"
focused_app() { cu GET /windows | jq -r '.windows[] | select(.focused) | .app'; }

step "1. Switch to workspace 5 with Omarchy's shortcut: a key combination through the virtual keyboard"
run "act '{\"action\": \"key\", \"text\": \"super+5\"}'"
run "vm_ssh_desktop 'hyprctl -j activeworkspace' | jq -c '{workspace: .id, windows}'"

step "2. Open a terminal (Super+Return) and find it in the window list"
run "act '{\"action\": \"key\", \"text\": \"super+Return\"}'"
run "act '{\"action\": \"wait\", \"duration\": 2}'"
run cu GET /windows
APP=$(focused_app)
[ -n "$APP" ] || { echo "No focused window; stopping before typing anything"; exit 1; }
note "Focused: $APP. Only now is it safe to type: keys go to whatever has focus."

step "3. Type a command. Text goes through wtype, so any Unicode works, whatever the keyboard layout"
run "act '{\"action\": \"type\", \"text\": \"echo \\\"typed by an agent: café ✓ → 日本\\\"\"}'"
run "act '{\"action\": \"key\", \"text\": \"Return\"}'"
run "act '{\"action\": \"wait\", \"duration\": 1}'"

step "4. Keys by name (xdotool's names): type, jump to the start of the line with ctrl+a, comment it out"
run "act '{\"action\": \"type\", \"text\": \"hello\"}'"
run "act '{\"action\": \"key\", \"text\": \"ctrl+a\"}'"
run "act '{\"action\": \"type\", \"text\": \"# \"}'"
run "act '{\"action\": \"key\", \"text\": \"Return\"}'"
run "act '{\"action\": \"key\", \"text\": \"ctrl+nope\"}'"

step "5. Look closely: zoom into the top of the terminal (a region of the screen, in pixels)"
BOUNDS=$(cu GET /windows | jq -r '.windows[] | select(.focused) | .bounds | "\(.x) \(.y) \(.x + .width) \(.y + 170)"')
run shot "$LABS/out/lab2-terminal.png" $BOUNDS
note "zoom returns just that region, at full resolution: cheaper than a whole screenshot, and easier to read."


step "6. A click: right-click in the middle of the terminal (its context menu, if it has one), then Escape"
CENTER=$(cu GET /windows | jq -c '.windows[] | select(.focused) | .bounds | [(.x + .width / 2 | floor), (.y + .height / 2 | floor)]')
run "act '{\"action\": \"right_click\", \"coordinate\": $CENTER}'"
run "act '{\"action\": \"key\", \"text\": \"Escape\"}'"

step "7. Close the terminal (Super+W) and go back to workspace 1"
[ "$(focused_app)" = "$APP" ] && run "act '{\"action\": \"key\", \"text\": \"super+w\"}'"
run "act '{\"action\": \"key\", \"text\": \"super+1\"}'"
run cu GET /windows
run lab_stop_forwards
