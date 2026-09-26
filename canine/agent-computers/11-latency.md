*Chapter 11 of 15*

# Latency: where the time actually goes

"It feels slow" has many causes. We measured instead of guessing.

## The pipeline

```
 your hand moves the mouse
  → browser sends input event over WebSocket            ┐
  → network to the server (RTT/2)                        │ network
  → Canine proxy → Kube API → kubelet → pod → guest      ┘ + relay hops
  → Selkies injects the event
  → compositor redraws (CPU rendering, no GPU)           ┐
  → Selkies captures the frame                           │ inside the VM
  → x264 encodes it (CPU)                                ┘
  → back over the same path (RTT/2 + relays)
  → browser decodes and paints the frame
```

## What we measured

| Measurement | Result |
|---|---|
| TCP connect to Hetzner Helsinki | ~120–215 ms |
| TCP connect to AWS us-east-1 | ~22–26 ms (occasional spikes ~100 ms → local Wi-Fi jitter) |
| AWS host CPU steal | 0% |
| Selkies CPU in the Omarchy VM | ~40% of one core while streaming |

Moving to AWS cut network latency by ~5×. Then bypassing Canine's proxy entirely (Part 12) did **not** feel much
faster. Conclusion: what's left is mostly **inside the VM** — CPU rendering, capture, and software encoding on a
burstable 4-vCPU instance — plus WebSocket/TCP behaviour on Wi-Fi.

## What Selkies says about its own pipeline

Found while building Lab 7. Selkies logs its whole pipeline at startup (`journalctl --user -u selkies` in Omarchy):

```
[Wayland] Failed to init VAAPI H264: Failed to derive VAAPI device: Input/output error
[Wayland] Readback capture: output 1 1920x1080 rendered in software (Pixman), read back for the encode thread (no GPU renderer).
[Wayland] Readback encode: no hardware encoder opened; encoding in software (x264).
[Wayland] Stream settings active -> Res: 1920x1080 | FPS: 60.0 | ... | Mode: H264 (x264) FullFrame Streaming | CRF: 25 | VBV: 8000 kbps
```

Read it as a budget:
- **Rendering:** Hyprland draws with **Pixman**, a CPU rasterizer, because the VM has no GPU. Hyprland showed
  ~100% of a core in `ps`.
- **Capture:** each frame is *read back* from Hyprland's CPU buffer to Selkies.
- **Encoding:** **x264** in software, targeting 60 FPS at CRF 25 with an 8 Mbps cap. The VAAPI hardware encoder
  fails because the virtio GPU has no video engine.
- **Idle work:** Omarchy's **screensaver** (`foot --app-id=org.omarchy.screensaver`) starts after a few idle
  minutes and animates, so the CPU is busy even when nobody is looking. Disabling hypridle/the screensaver in
  the VM is a cheap win.

Cheap knobs to try: lower FPS (30 is plenty for desktop work), higher CRF (smaller, lower-quality frames), a smaller
resolution. Each one trades quality for CPU and latency.

## A finding on the Ubuntu agent computers

Lab 9 showed that the XFCE agent computer's X screen is **8192×4096** (`xrandr --current`), because Selkies' X11
session sizes the virtual screen to its maximum. Consequences: agent screenshots are huge PNGs that are mostly
empty, and dialogs open centred around (4000, 2000). Whether a person notices depends on how Selkies resizes the
screen when a browser connects; worth checking. The fix is
the same as on Omarchy: pin the resolution (`SELKIES_MANUAL_WIDTH/HEIGHT`) in `provision.sh`.

## Levers, cheapest first

1. Disable compositor effects (done: no animations, blur, shadows; hidden remote cursor).
2. Tune Selkies (frame rate, encoder/CRF, bitrate) — not done yet.
3. Measure guest CPU while dragging windows; if pegged, try a non-flex instance (c7i/c8i).
4. WebRTC mode (UDP) — better on lossy networks, but needs UDP ports and possibly TURN.
5. GPU encoding/rendering — the real fix at scale, but needs GPU nodes and GPU passthrough into VMs.

Also discovered: something on the Mac (Cloudflare WARP/iCloud Private Relay/VPN) was routing some HTTPS traffic
through Cloudflare (`104.28.172.151` in Traefik's access log). Any such hop adds latency; disable it when measuring.

✅ **Check yourself:** Why didn't removing the proxy hops help much? What would you measure next?

---

← [Moving to AWS](10-moving-to-aws.md) · [Index](README.md) · [The direct-connection experiment (and why we rolled it back)](12-the-direct-connection-experiment.md) →
