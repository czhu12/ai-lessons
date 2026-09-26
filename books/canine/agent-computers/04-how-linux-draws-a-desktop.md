# How Linux draws a desktop: X11 and Wayland

This part explains the vocabulary you'll see in Selkies docs and in our code (DISPLAY, Xvfb, XTest, compositor…).

## The web-developer analogy

Think of the display system as a **server** and every app window as a **client**:

- Apps don't draw pixels onto the screen directly. They send drawing requests or finished buffers to a display
  server.
- The display server combines all windows into the final screen image and routes input (keyboard, mouse) to the
  right window.

## X11 (the old, networked design)

- **X server**: owns the screen and input devices. Apps (**X clients**) connect to it via a socket.
- **`DISPLAY=:1`**: environment variable telling an app *which* X server to connect to (like a database URL).
- **`XAUTHORITY`**: a file holding a cookie that authorizes clients (like a session token).
- **Window manager**: a separate X client that decides window placement and decorations (XFCE's `xfwm4`).
- **Xvfb** ("X virtual framebuffer"): an X server with **no physical screen**; it draws into memory. Perfect for a
  headless VM: the desktop exists, and something else (Selkies) reads the pixels.
- **X11 is permissive:** any client can read the whole screen, see all input, and inject fake input. That's a
  security problem for normal desktops, but it's *exactly* what automation needs:
  - **XTest** extension: inject fake key presses/mouse moves. Used by `xdotool` (our agent) **and** by Selkies (the
    person's input). That's why the takeover lock can't tell them apart by device.
  - **XInput2 raw events**: receive every input event system-wide. Our `input_watch.c` uses these.
  - Screen reading: `mss` (screenshots) just reads the framebuffer.

## Wayland (the modern design)

- The **compositor** *is* the display server *and* the window manager in one process. Hyprland is a Wayland
  compositor; so are GNOME's Mutter and KDE's KWin.
- **Wayland is locked down on purpose:** a normal app cannot read other windows or inject input. Screen capture and
  remote input must go through explicit protocols the compositor chooses to offer (e.g. screen-copy and
  virtual-keyboard/pointer protocols on wlroots-style compositors, or desktop "portals" with user permission).
- `WAYLAND_DISPLAY=wayland-1` plays the role `DISPLAY` plays in X11: which compositor socket to talk to.
- **XWayland** runs X11 apps inside a Wayland session, but X11 tools see only the X11 apps, not the whole desktop.

**Why this matters for us:** our agent computer server is built entirely on X11 tools (`xdotool`, `mss`,
`input-watch`, `wmctrl`). It works on the Ubuntu/XFCE/Xvfb image. It would **not** work on Omarchy (Hyprland,
Wayland) as-is; porting it means using Hyprland's IPC (`hyprctl`), Wayland capture protocols, and virtual input
devices instead.

## Cursors and "the double mouse"

In a streamed desktop there are two possible cursors:

1. The **remote** cursor — drawn into the video frames by the guest's compositor. It lags by the full round trip.
2. The **local** cursor — your browser's own pointer over the page. Instant.

If both show, you see two pointers, one trailing the other. Our fix on Omarchy: tell Hyprland not to draw its
cursor at all (`cursor:invisible = true`), so only the browser's instant cursor remains.

## Scaling and "tiny text"

A desktop has a pixel resolution (1920×1080) and a **scale** factor. At scale 1.25, apps lay themselves out as if
the screen were 1536×864 logical pixels, then render at full 1920×1080 — everything is 25% bigger and still sharp.
Separately, Selkies' **CSS scaling** shrinks/grows the video element to fit your browser window (like
`object-fit`), which can make text smaller if the remote resolution is larger than your viewport. We used both:
CSS scaling for fit, and Hyprland `scale = 1.25` for readable text.

✅ **Check yourself:** What's `DISPLAY`? Why is X11 convenient for agents but Wayland isn't? Why did we see two
mouse pointers, and why does hiding the *remote* one make the pointer feel faster?

