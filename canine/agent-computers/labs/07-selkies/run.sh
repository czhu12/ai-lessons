#!/usr/bin/env bash
# Lab 7 walkthrough: Selkies without Canine in the way. Open Omarchy's stream straight from a port-forward,
# poke at its WebSocket, and see what streaming costs inside the VM.
source "$(dirname "$0")/../env.sh"
cd "$(dirname "$0")"
POD=$(vm_pod omarchy omarchy-spike)

step "1. Port-forward Omarchy's Selkies (guest port 8080) to localhost:18088"
kubectl port-forward -n omarchy-spike "$POD" 18088:8080 >/dev/null 2>&1 & disown
until nc -z 127.0.0.1 18088 2>/dev/null; do sleep 0.5; done
run "curl -s localhost:18088/ | grep -o '<title>[^<]*</title>'"
note "Open http://localhost:18088 in your browser: the same desktop as Canine's connect page, minus Canine."
note "It works over plain HTTP only because localhost counts as a 'secure context'. On any other hostname"
note "Selkies' page refuses to start: 'This application requires a secure connection (HTTPS)'."
[ -n "$LAB_AUTO" ] || open http://localhost:18088

step "2. The Origin check: Selkies compares the Origin header to the Host it was reached on"
run ruby origin-check.rb 18088
note "Browsers always send Origin on WebSocket upgrades, so this stops OTHER websites from driving the desktop"
note "through your browser. It does nothing against scripts (no Origin at all), so real auth must live elsewhere."
note "Canine forwarded Origin: http://localhost:3000 unchanged -> 403. The proxy now rewrites it (after its own"
note "session check) in lib/agent_computer_proxy.rb, handle_websocket."

step "3. Look at the stream in DevTools (manual)"
note "In the tab from step 1: DevTools -> Network -> filter 'WS' -> click 'websockets' -> Messages."
note "Incoming binary messages are encoded video frames; outgoing small text messages are your mouse and keys."
note "Move the mouse and watch outgoing messages appear. Leave the page idle and see frames slow down."

step "4. What streaming costs inside the VM"
run "omarchy_ssh 'ps -eo pid,pcpu,rss,comm --sort=-pcpu | head -6'"
note "selkies = capturing + encoding H.264 on the CPU (no GPU in this VM). Hyprland = drawing the desktop."
note "If Omarchy's screensaver (foot --app-id=org.omarchy.screensaver) is running, it's animating while idle."
note "Drag a window around in the browser and run this step again: both jump. That's the latency budget."

step "5. Selkies' own settings: the user service on Omarchy"
run "omarchy_ssh 'grep -E \"^(Environment|ExecStart)\" ~/.config/systemd/user/selkies.service'"
run "omarchy_ssh 'journalctl --user -u selkies -o cat | grep -E \"Stream settings active|Readback|Failed to init VAAPI\" | sort -u | cut -c1-170'"
note "Read these lines closely, they're the whole pipeline: 1920x1080 at 60 FPS, H.264 at CRF 25 / 8 Mbps,"
note "Hyprland rendering in software (Pixman, no GPU), frames read back and encoded by x264 on the CPU after the"
note "VAAPI hardware encoder failed. Every one of those is a latency and CPU cost a GPU would remove."

step "6. Clean up"
pkill -f "^kubectl port-forward -n omarchy-spike $POD 18088" && echo "port-forward stopped"
