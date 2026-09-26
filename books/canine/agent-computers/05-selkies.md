# Selkies: streaming a desktop into a browser tab

## What Selkies is

**Selkies** (v2.0.0) is an open-source "desktop → browser" streamer. It runs **inside the guest** and:

1. **Captures** the screen (via its `pixelflux` capture library) — from its own X/Wayland display or from an
   existing compositor.
2. **Encodes** frames as video (H.264 via x264 on the CPU when there's no GPU; it tries VAAPI hardware encoding
   first — hence the harmless `No hardware encoder on render node 0 (vaapi)` log line).
3. **Serves** a web client (HTML/JS) on a port (we use **8080**) and streams frames over a **WebSocket**
   (`/api/websockets`) — or over **WebRTC** in its other mode.
4. **Receives input** from the browser (mouse, keyboard, clipboard, resize) over the same connection and injects it
   into the desktop.
5. Optionally streams audio (PulseAudio/PipeWire).

It's the same idea as a video call where one side is a computer screen and the other side can send back mouse
clicks.

## WebSocket mode vs WebRTC mode

| | WebSocket mode (what we use) | WebRTC mode |
|---|---|---|
| Transport | TCP, one WebSocket | UDP (SRTP), plus a signaling channel |
| Through proxies | Easy: it's just HTTP upgrade | Needs UDP reachability, often a TURN relay |
| On packet loss | TCP stalls everything until the retransmit arrives ("head-of-line blocking") | Drops/conceals the lost frame and keeps going |
| Latency | Good on clean networks, spiky on lossy Wi-Fi | Best for real-time |

We chose WebSocket mode because it flows through Canine's existing Rack proxy with no extra infrastructure.

## Settings we touched (env vars / flags)

| Setting | Why |
|---|---|
| `--public --port=8080` | Listen on the VM's network interface (not just localhost) so port-forward can reach it |
| `--enable-basic-auth=false --enable-https=false` | Canine does authentication and (in prod) TLS; inside the VM it's plain HTTP |
| `SELKIES_USE_CSS_SCALING=true` | Fit the video to the browser window client-side |
| `SELKIES_MANUAL_WIDTH/HEIGHT=1920/1080` | Lock the resolution (stops a resize feedback loop with Hyprland) |
| `SELKIES_WAYLAND=true`, `--wayland-host-display=$WAYLAND_DISPLAY` | Omarchy: attach to Hyprland's *existing* session instead of starting a new display |

## Two ways Selkies gets a desktop

1. **Selkies owns the display** (Ubuntu agent image): `selkies-session --session=xfce` starts Xvfb (a virtual X
   server) + PulseAudio + XFCE. The desktop only exists because Selkies created it. Needs `xvfb` and `pulseaudio`
   installed (its `.deb` doesn't depend on them — a bug we hit).
2. **Selkies attaches to someone else's compositor** (Omarchy): Hyprland is already running on the VM's virtual
   screen (started by the login manager). Selkies connects to Hyprland's socket and captures it. That's
   `--wayland-host-display`.

## Browser security rules Selkies runs into

These were two of our debugging sagas, and they're pure web-platform knowledge:

- **Origin check.** Selkies 2.0 rejects a WebSocket upgrade whose `Origin` header doesn't match its `Host` (a
  cross-site WebSocket hijacking defence). Through Canine's proxy, the browser sends
  `Origin: http://localhost:3000` but the upstream sees `Host: 127.0.0.1:<port>` → **403**. Fix in
  `AgentComputerProxy`: the user is already authenticated, so rewrite `Origin` to match the upstream host.
- **Secure context.** Selkies' client refuses to run on a non-secure page: *"This application requires a secure
  connection (HTTPS)"*. It needs APIs (clipboard, some media/input APIs) that browsers only expose in **secure
  contexts**. Key detail: **`http://localhost` counts as a secure context**, which is why the Canine dev server on
  `http://localhost:3000` works without HTTPS, but `http://c12.<aws-node-ip-dashed>.sslip.io` did not.

## Selkies on the two guests

- **Ubuntu image:** a system service (`/etc/systemd/system/selkies.service`) running as the `computer` user with
  `PAMName=login` (so it gets a proper login session), plus accessibility env vars (Part 8).
- **Omarchy:** a **user** service (`~/.config/systemd/user/selkies.service`), `PartOf=graphical-session.target`,
  so it starts when the Hyprland session starts and inherits `WAYLAND_DISPLAY` from **uwsm** (the Wayland session
  manager Omarchy uses).

✅ **Check yourself:** Why does WebSocket mode suffer more on lossy Wi-Fi than WebRTC? Why did the proxy need to
rewrite `Origin`? Why does `http://localhost:3000` count as secure but `http://c12...sslip.io` doesn't?

