#!/usr/bin/env bash
# Lab 3 walkthrough: read and use an app through the accessibility tree (AT-SPI) instead of pixels. Opens Chromium on
# an empty workspace, finds and presses a link by name, and checks where the tree says things are against a zoom.
source "$(dirname "$0")/../env.sh"
cd "$(dirname "$0")"
a11y() { cu POST "/accessibility/$1" "$2"; }

step "1. Open a browser window (Super+Shift+Return) on workspace 6, and load example.com through its address bar"
run "act '{\"action\": \"key\", \"text\": \"super+6\"}'"
run "act '{\"action\": \"key\", \"text\": \"super+shift+Return\"}'"
run "act '{\"action\": \"wait\", \"duration\": 4}'"
APP=$(cu GET /windows | jq -r '.windows[] | select(.focused) | .app')
[ "$APP" = chromium ] || { echo "Chromium isn't focused (got '$APP'); stopping before typing"; exit 1; }
ADDRESS=$(a11y find '{"app": "chromium", "role": "entry"}' | jq -c '.elements[0]')
echo "$ADDRESS"
note "The address bar, found by role. set_text fills it (Chromium doesn't support setting it directly, so the"
note "server focuses it and types over it); then Return loads the page."
run "a11y set_text '$(echo "$ADDRESS" | jq -c '{path, text: "example.com"}')'"
run "act '{\"action\": \"key\", \"text\": \"Return\"}'"
run "act '{\"action\": \"wait\", \"duration\": 3}'"
run "cu GET /windows | jq -c '.windows[] | {title, app, bounds}'"

step "2. The apps publishing an accessibility tree, and the top of Chromium's"
run "a11y tree '{\"max_depth\": 0}' | jq -c '[.apps[] | {path, role, name}]'"
run "a11y tree '{\"app\": \"chromium\", \"max_depth\": 3}' | jq -c '.apps[0] | .. | objects | select(.role) | {path, role, name}' | head -12"
note "Every element has a role, a name and a path (child indexes from the desktop down)."

step "3. Find the page's links, and the buttons in the browser's own toolbar"
run "a11y find '{\"app\": \"chromium\", \"role\": \"link\"}' | jq -c '.elements[]'"
run "a11y find '{\"app\": \"chromium\", \"role\": \"button\"}' | jq -c '.elements[] | {name, bounds}' | head -5"

step "4. Is the tree right about where things are? Zoom into the link's bounds"
LINK=$(a11y find '{"app": "chromium", "role": "link", "name": "learn more"}' | jq -c '.elements[0]')
REGION=$(echo "$LINK" | jq -r '.bounds | "\(.x) \(.y) \(.x + .width) \(.y + .height)"')
run shot "$LABS/out/lab3-link.png" $REGION
note "The zoom should show exactly the words 'Learn more'. (Web content is reported in device pixels, the"
note "browser's own UI in layout units: accessibility.py handles both. Chapter 4 has the details.)"

step "5. Press the link through its accessibility action: no coordinates, no mouse"
run "a11y press '$(echo "$LINK" | jq -c '{path}')'"
run "act '{\"action\": \"wait\", \"duration\": 3}'"
run "cu GET /windows | jq -c '.windows[] | {title}'"

step "6. Paths go stale when the UI changes: the old path now points somewhere else, or nowhere"
run "a11y press '$(echo "$LINK" | jq -c '{path}')'"
note "So agents find an element and use its path right away."

step "7. Close the window (Super+W) and go back to workspace 1"
[ "$(cu GET /windows | jq -r '.windows[] | select(.focused) | .app')" = chromium ] && run "act '{\"action\": \"key\", \"text\": \"super+w\"}'"
run "act '{\"action\": \"key\", \"text\": \"super+1\"}'"
run lab_stop_forwards
