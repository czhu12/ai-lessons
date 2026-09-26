# The golden image pipeline

## Why a golden image

Installing a desktop, Chrome, Selkies and the computer server takes many minutes. We do it **once per cluster**,
save the resulting disk, and **clone** it for every new computer (~70 s instead of ~10 min).

## Versioning by content

`AgentComputer::Image.version` = first 12 hex chars of SHA-256 over `provision.sh` + every computer-server file.
The image is named `agent-computer-<version>` (e.g. `agent-computer-1d9263000eef`). Change the script or the
server → new version → the next provision on each cluster builds a new image. Like cache-busting asset digests
(`application-3f2a1b.css`).

The server is shipped as a **deterministic tarball** (fixed file order, fixed gzip mtime) so identical files always
produce identical bytes.

## Build steps (`AgentComputers::BuildImageJob`)

```
1. namespace canine-agent-computers
2. discard any partial build (delete builder VM/Secret and the image DataVolume)
3. DataVolume agent-computer-<v>  ← CDI imports docker://quay.io/containerdisks/ubuntu:24.04 into a 20Gi PVC
4. Secret  <name>-builder         ← cloud-init user data: writes provision.sh + the server tarball, runs the script
5. VM      <name>-builder         ← runStrategy: Once, boots that disk with the cloud-init Secret
6. watch the serial console (container "guest-console-log") for AGENT_COMPUTER_BUILD_OK / _FAILED
7. publish DataSource agent-computer-<v>  → points at the finished PVC
8. delete builder VM + Secret
```

How the build reports back: the guest has no network path to Canine, but KubeVirt logs the VM's **serial console**
as a container log. The builder's last command prints the tail of the provision log plus a marker line to
`/dev/ttyS0`, then powers off. Canine reads `kubectl logs ... -c guest-console-log` and greps for the marker. On
failure, it shows the 40 log lines before the marker.

Gotcha we hit: when the serial login prompt (getty) starts mid-build, it hangs up other writers on `ttyS0`, so
streaming the build with `tee` to the console broke. The script now logs to a file and prints only the tail at the
end.

## `resources/agent_computer/provision.sh` highlights

- XFCE, fonts, `xdotool`/`xclip`/`wmctrl`, **Xvfb + PulseAudio** (needed by `selkies-session`),
  `qemu-guest-agent`, editors (neovim, micro), `build-essential` (needed to compile `input-watch`).
- **Google Chrome** with a wrapper at `/usr/local/bin/google-chrome` that always adds
  `--remote-debugging-port=9222` (so the agent can drive the person's real browser via CDP),
  a dedicated profile (Chrome only honors the debug port with a non-default profile), and
  `--force-renderer-accessibility` (web content shows up in the accessibility tree).
- A `computer` user with passwordless `sudo` (each computer is its own VM, so that's acceptable).
- Selkies 2.0.0 `.deb` **pinned by SHA-256**, run as a systemd service.
- The computer server in `/opt/computer-server` (Python venv with `--system-site-packages` so it can see the distro's
  AT-SPI bindings), autostarted *inside* the XFCE session so it inherits `DISPLAY` and the accessibility bus.
- Finally `cloud-init clean --machine-id` so every clone boots as a *new* machine (fresh machine-id, SSH host keys,
  cloud-init runs again).

✅ **Check yourself:** How does Canine learn whether the build succeeded, given the builder VM can't talk to Canine?
What would happen if two clones shared the same machine-id?

