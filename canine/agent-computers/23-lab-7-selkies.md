*Lab page 7 of 9*

# Lab 7: Selkies up close

**Goal:** use Selkies without Canine in the way, reproduce the Origin check, and read Selkies' own description of
its pipeline. **Time:** 5 minutes (+ DevTools poking). **Chapters:** [Selkies](05-selkies.md), [Latency](11-latency.md).

```bash
./labs/07-selkies/run.sh
```

1. Port-forward Omarchy's Selkies to `localhost:18088` and open it in your browser: the same desktop, no Canine.
2. `origin-check.rb` sends WebSocket upgrades with different `Origin` headers.
3. DevTools → Network → WS → Messages: binary frames in, your input out.
4. What the stream costs in CPU inside the VM.
5. Selkies' config and its startup log lines about capture and encoding.

## Questions

**Q: Why does `http://localhost:18088` work, but `http://c12.<aws-node-ip-dashed>.sslip.io` showed 'This application requires a secure connection'?**

<details>
<summary>Answer</summary>

Browsers treat `localhost` (and loopback IPs) as secure contexts even over plain HTTP. Any other hostname needs HTTPS for the APIs Selkies' client uses, such as the clipboard.

</details>

**Q: Selkies rejects `Origin: https://evil.example` but accepts a request with no Origin at all. Is that a hole?**

<details>
<summary>Answer</summary>

No: it's a defence for browsers. A browser always sends Origin on WebSocket upgrades, so this stops other websites from driving the desktop through a victim's browser. Scripts can omit Origin, which is why real authentication has to live in front of Selkies (Canine's proxy + the NetworkPolicy).

</details>

**Q: From the log lines: which parts of the pipeline run on the CPU?**

<details>
<summary>Answer</summary>

All of them. Hyprland renders with Pixman (CPU), frames are read back, and x264 encodes in software after the VAAPI hardware encoder failed. At 1920×1080 and 60 FPS that's a lot of CPU, and a big part of the remaining latency.

</details>

**Q: The no-Origin row sometimes says 101 and sometimes '(connection reset)'. Why?**

<details>
<summary>Answer</summary>

Both were seen while building the lab. Selkies accepted the upgrade in one run and closed the socket in another. The script just reports what the server did; the important rows are the 101 vs 403 for matching vs foreign Origin.

</details>


## Expected output

<details>
<summary>📜 Expected output (a real run, captured while building the lab)</summary>

```text
== 1. Port-forward Omarchy's Selkies (guest port 8080) to localhost:18088
$ curl -s localhost:18088/ | grep -o '<title>[^<]*</title>'
<title>Selkies</title>
   Open http://localhost:18088 in your browser: the same desktop as Canine's connect page, minus Canine.
   It works over plain HTTP only because localhost counts as a 'secure context'. On any other hostname
   Selkies' page refuses to start: 'This application requires a secure connection (HTTPS)'.

== 2. The Origin check: Selkies compares the Origin header to the Host it was reached on
$ ruby origin-check.rb 18088
http://127.0.0.1:18088           HTTP/1.1 101 Switching Protocols same origin as the Host header (what the proxy now sends)
http://localhost:3000            HTTP/1.1 403 Forbidden       Canine's origin, forwarded unchanged (the original bug)
https://evil.example             HTTP/1.1 403 Forbidden       some other website trying to connect
(none)                           (connection reset)           no Origin header at all (curl, scripts)
   Browsers always send Origin on WebSocket upgrades, so this stops OTHER websites from driving the desktop
   through your browser. It does nothing against scripts (no Origin at all), so real auth must live elsewhere.
   Canine forwarded Origin: http://localhost:3000 unchanged -> 403. The proxy now rewrites it (after its own
   session check) in lib/agent_computer_proxy.rb, handle_websocket.

== 3. Look at the stream in DevTools (manual)
   In the tab from step 1: DevTools -> Network -> filter 'WS' -> click 'websockets' -> Messages.
   Incoming binary messages are encoded video frames; outgoing small text messages are your mouse and keys.
   Move the mouse and watch outgoing messages appear. Leave the page idle and see frames slow down.

== 4. What streaming costs inside the VM
$ omarchy_ssh 'ps -eo pid,pcpu,rss,comm --sort=-pcpu | head -6'
    PID %CPU   RSS COMMAND
   1020  104 400068 Hyprland
   1204 14.3 375972 selkies
   5489 11.1 143764 chromium
  18209  9.6 27556 foot
  12356  9.3 165852 chromium
   selkies = capturing + encoding H.264 on the CPU (no GPU in this VM). Hyprland = drawing the desktop.
   If Omarchy's screensaver (foot --app-id=org.omarchy.screensaver) is running, it's animating while idle.
   Drag a window around in the browser and run this step again: both jump. That's the latency budget.

== 5. Selkies' own settings: the user service on Omarchy
$ omarchy_ssh 'grep -E "^(Environment|ExecStart)" ~/.config/systemd/user/selkies.service'
Environment=SELKIES_WAYLAND=true
Environment=SELKIES_USE_CSS_SCALING=true
Environment=SELKIES_MANUAL_WIDTH=1920
Environment=SELKIES_MANUAL_HEIGHT=1080
ExecStart=/bin/sh -c 'exec /usr/bin/selkies --public --port=8080 --enable-basic-auth=false --enable-https=false --wayland-host-display="$WAYLAND_DISPLAY"'
$ omarchy_ssh 'journalctl --user -u selkies -o cat | grep -E "Stream settings active|Readback|Failed to init VAAPI" | sort -u | cut -c1-170'
[Wayland] Failed to init VAAPI H264: Failed to derive VAAPI device: Input/output error
[Wayland] Readback capture: output 1 1920x1080 rendered in software (Pixman), read back for the encode thread (no GPU renderer).
[Wayland] Readback encode: no hardware encoder opened; encoding in software (x264).
[Wayland] Stream settings active -> Res: 1920x1080 | FPS: 60.0 | Stripes: 1 | Mode: H264 (x264) FullFrame Streaming | CRF: 25 | VBV: 8000 kbps | PaintOver CRF: 18 (Burst:
   Read these lines closely, they're the whole pipeline: 1920x1080 at 60 FPS, H.264 at CRF 25 / 8 Mbps,
   Hyprland rendering in software (Pixman, no GPU), frames read back and encoded by x264 on the CPU after the
   VAAPI hardware encoder failed. Every one of those is a latency and CPU cost a GPU would remove.

== 6. Clean up
port-forward stopped
```

</details>


## Try next

- In the Selkies page's side panel, change the frame rate to 30 and watch Selkies' CPU in step 4 drop.
- Open `http://127.0.0.1:18088` instead of `http://localhost:18088`. Also a secure context? (Yes: loopback addresses
  count too.)

---

← [Lab 6: Wayland and Hyprland (Omarchy)](22-lab-6-wayland.md) · [Index](README.md) · [Lab 8: Build the proxy yourself](24-lab-8-mini-proxy.md) →
