#!/usr/bin/env bash
# Lab 6 walkthrough: the same ideas as Lab 5 on Omarchy's Wayland desktop. There's no global X server to poke;
# you ask the compositor (Hyprland) through its IPC, and use Wayland protocols it chooses to offer for input
# injection (wtype) and screen capture (grim). Open the Omarchy connect page in Canine to watch it live.
#
# Safety: this is your real desktop. The lab only types into a window it opened itself (app-id "lab-window"),
# and refuses to type if that window doesn't have focus.
source "$(dirname "$0")/../env.sh"
H() {   # run a command in the Omarchy session's environment
  omarchy_ssh "export XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE=\$(ls -t /run/user/1000/hypr/ | head -1)
    export WAYLAND_DISPLAY=\$(hyprctl instances -j | python3 -c 'import json,sys; print(json.load(sys.stdin)[0][\"wl_socket\"])')
    $*"
}
ACTIVE_CLASS='hyprctl activewindow -j | python3 -c "import json,sys; print(json.load(sys.stdin).get(\"class\",\"\"))"'

step "1. Who draws the screen here? Hyprland is display server + window manager in one process"
run "H 'pgrep -a Hyprland | cut -c1-80; hyprctl instances | head -4; echo selkies: \$(systemctl --user is-active selkies)'"
note "Selkies is a separate program that asks Hyprland for frames and sends it input (--wayland-host-display)."

step "2. Ask the compositor about the screen and the windows (Wayland's answer to xdpyinfo/xwininfo)"
run "H 'hyprctl monitors -j | python3 -c \"import json,sys; m=json.load(sys.stdin)[0]; print(m[\\\"name\\\"], m[\\\"width\\\"], \\\"x\\\", m[\\\"height\\\"], \\\"scale\\\", m[\\\"scale\\\"])\"'"
run "H 'hyprctl clients -j | python3 -c \"import json,sys; [print(c[\\\"class\\\"], \\\"| workspace\\\", c[\\\"workspace\\\"][\\\"id\\\"], \\\"| at\\\", c[\\\"at\\\"], \\\"size\\\", c[\\\"size\\\"]) for c in json.load(sys.stdin)]\"'"
note "Only the compositor knows this. A normal Wayland app can't list other apps' windows at all."

step "3. Open a window by asking Hyprland to run a program (watch it appear in the connect page)"
run "H 'hyprctl dispatch \"hl.dsp.exec_cmd(\\\"foot --app-id lab-window\\\")\"'"
H "for i in \$(seq 1 20); do [ \"\$($ACTIVE_CLASS)\" = lab-window ] && break; sleep 0.5; done"
run "H '$ACTIVE_CLASS'"

step "4. Inject keystrokes with wtype (Wayland virtual-keyboard protocol), only into our own window"
run "H 'if [ \"\$($ACTIVE_CLASS)\" = lab-window ]; then wtype \"echo typed by wtype through the virtual-keyboard protocol\" -k Return && echo typed; else echo \"lab-window is not focused, not typing\"; fi'"
note "Keystrokes always go to the focused window, which is why the lab checks focus first. xdotool doesn't work"
note "here: it speaks X11, and Hyprland only runs XWayland (display :0) for old X apps, not for the whole desktop."

step "5. Screenshot just that window with grim (a Wayland screen-capture protocol the compositor offers; Selkies needs the same kind of access)"
run "H 'g=\$(hyprctl clients -j | python3 -c \"import json,sys; c=[c for c in json.load(sys.stdin) if c[\\\"class\\\"]==\\\"lab-window\\\"][0]; print(f\\\"{c[\\\"at\\\"][0]},{c[\\\"at\\\"][1]} {c[\\\"size\\\"][0]}x{c[\\\"size\\\"][1]}\\\")\"); grim -g \"\$g\" /tmp/lab-window.png && echo captured \$g'"
H 'cat /tmp/lab-window.png; rm -f /tmp/lab-window.png' > /tmp/lab-window.png && echo "   saved /tmp/lab-window.png"
[ -n "$LAB_AUTO" ] || open /tmp/lab-window.png

step "6. Change a setting live through Hyprland's Lua config API, then put it back"
run "H 'hyprctl eval \"hl.config({ general = { gaps_out = 60 } })\" >/dev/null; hyprctl getoption general:gaps_out | head -1'"
note "Look at the connect page: big gaps around the windows."
[ -n "$LAB_AUTO" ] || read -r -p "   (Enter to restore) " _
run "H 'hyprctl reload >/dev/null; sleep 1; hyprctl getoption general:gaps_out | head -1'"
note "reload re-reads ~/.config/hypr/*.lua. That's how we made our changes permanent: scale 1.25, no animations,"
note "invisible cursor. Try:  H 'grep -A8 \"Streamed through Selkies\" ~/.config/hypr/looknfeel.lua'"

step "7. Close the lab window (by its own PID, so nothing else can be hit)"
run "H 'kill \$(hyprctl clients -j | python3 -c \"import json,sys; print(\\\" \\\".join(str(c[\\\"pid\\\"]) for c in json.load(sys.stdin) if c[\\\"class\\\"]==\\\"lab-window\\\"))\") && echo closed'"
