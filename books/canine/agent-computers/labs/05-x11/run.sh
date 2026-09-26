#!/usr/bin/env bash
# Lab 5 walkthrough: X11 by hand. A display server with no screen (Xvfb), apps as clients of it, and how any
# client can inject input (XTest), read the screen and watch every keystroke. That permissiveness is what
# xdotool/Selkies/our takeover lock rely on, and what Wayland deliberately forbids.
source "$(dirname "$0")/../env.sh"
cd "$(dirname "$0")"
X() { kubectl exec -n lab x11-lab -- env DISPLAY=:1 bash -c "$*"; }   # run a command as an X client of display :1
BG() { kubectl exec -n lab x11-lab -- env DISPLAY=:1 bash -c "setsid nohup $* >/dev/null 2>&1 &"; }

step "1. Start the lab pod (Ubuntu + X11 tools; installing packages takes ~1 minute)"
lab_ns
run kubectl apply -f x11-lab.yaml
kubectl wait -n lab --for=condition=Ready pod/x11-lab --timeout=180s >/dev/null
until kubectl exec -n lab x11-lab -- test -f /ready 2>/dev/null; do printf "."; sleep 3; done; echo " ready"

step "2. Start an X server with no monitor: Xvfb draws into memory. DISPLAY=:1 is its address."
BG Xvfb :1 -screen 0 1280x800x24
sleep 1
run "X 'xdpyinfo | grep -E \"name of display|dimensions\"'"

step "3. Watch it: start a VNC server on the display and connect from your Mac"
BG x11vnc -display :1 -forever -shared -passwd lab -rfbport 5900 -quiet
kubectl port-forward -n lab pod/x11-lab 5901:5900 >/dev/null 2>&1 & disown
sleep 2
note "Open Screen Sharing: run   open vnc://localhost:5901   (password: lab)"
note "It's black: an X server with no apps and no window manager is just an empty framebuffer."
[ -n "$LAB_AUTO" ] || open vnc://localhost:5901

step "4. Apps are clients: start a terminal, a clock and eyes that follow the mouse"
BG xterm -geometry 90x20+40+40 -fa DejaVuSansMono -fs 12
BG xclock -geometry 200x200+900+40
BG xeyes -geometry 200x120+900+300
sleep 2
run "X 'xwininfo -root -children | grep -E \"xterm|xclock|xeyes\"'"
note "xwininfo lists the window tree, a bit like document.body.children in the DOM."

step "5. Inject input through XTest, the way xdotool (our agent) and Selkies (you, in the browser) both do"
run "X 'xdotool mousemove 300 200 && xdotool getmouselocation'"
note "Watch xeyes look at the pointer."
run "X 'xdotool mousemove 400 200 && xdotool type --delay 60 \"echo typed by xdotool through XTest\" && xdotool key Return'"
note "Watch the xterm: the keys were injected, no keyboard involved. With no window manager running, X sends"
note "keystrokes to whatever window is under the pointer, which is why we moved the mouse over the xterm first."

step "6. Any client can read the whole screen (this is what the agent's screenshot command does)"
run "X 'import -window root /tmp/screen.png' && kubectl cp lab/x11-lab:/tmp/screen.png /tmp/x11-lab-screen.png >/dev/null && echo saved /tmp/x11-lab-screen.png"
[ -n "$LAB_AUTO" ] || open /tmp/x11-lab-screen.png

step "7. Any client can watch every input event, system-wide (XInput2 raw events, like our input_watch.c)"
note "Listening to every input event while xdotool types \"secret\" into the xterm..."
kubectl exec -n lab x11-lab -- env DISPLAY=:1 bash -c '
  xinput test-xi2 --root > /tmp/events.txt 2>&1 & listener=$!
  sleep 1; xdotool type --delay 100 "secret"; sleep 1; kill -9 $listener' >/dev/null 2>&1
run "kubectl exec -n lab x11-lab -- sh -c 'grep -cE \"EVENT type (13|14) \" /tmp/events.txt | sed \"s/^/raw key events seen: /\"'"
note "13/14 = RawKeyPress/RawKeyRelease. A keylogger is 5 lines of X11 code. Wayland was designed to make this"
note "impossible for ordinary apps, which is why Omarchy needs compositor-specific tools instead (Lab 6)."

step "8. Clean up"
pkill -f "^kubectl port-forward -n lab pod/x11-lab" || true
run kubectl delete pod x11-lab -n lab --wait=false
