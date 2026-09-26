*Chapter 13 of 15*

# Debugging war stories

Short cause → fix notes. Each one teaches something transferable.

| Symptom | Cause | Fix / lesson |
|---|---|---|
| Agent-sandbox install failed on `/clusters/32/edit` | GitHub release downloads redirect twice; the installer followed only one | Follow redirects in a loop |
| Proxy couldn't find the pod | Labels on the Sandbox custom resource aren't copied to its pod | Put labels in the pod template too; for KubeVirt use `vm.kubevirt.io/name` |
| DataVolume stuck/failed | local-path StorageProfile has no default access mode | Always set `accessModes` + `volumeMode` |
| Builder VM rejected | Inline cloud-init user data > 2KB | Put it in a Secret (`secretRef`) |
| Build log stopped mid-way | The serial getty hung up `tee` writing to `ttyS0` | Log to a file, print the tail at the end |
| Build failed: `cc` missing, Selkies session wouldn't start | Missing `build-essential`; Selkies `.deb` doesn't depend on xvfb/pulseaudio | Install them explicitly |
| Clone failed across namespaces | CDI checks `datavolumes/source` permission for the target namespace's service accounts | Per-computer RoleBinding; grace period for stale `Failure` |
| Agent `run_command` hung forever | Launched GUI app inherited stdin and kept it open | Close stdin (`</dev/null`, `stdin=DEVNULL`) |
| Takeover lock never triggered | `xinput test-xi2` → `BadAccess`; XTest motion creates no raw motion on Xvfb | Custom `input_watch.c` (raw events + pointer polling) |
| VNC relay misbehaved | `websocket-driver` treats objects with `#env` as the server side | Separate client/server adapters |
| Selkies WebSocket 403 via Canine | Origin/Host mismatch check | Proxy rewrites `Origin` for authenticated users |
| Omarchy Selkies unreachable | `ufw` blocking 8080 in the guest | `ufw allow 8080/tcp` |
| Omarchy stream "Play stream" loop / resize flicker | Selkies and Hyprland fighting over resolution | Fixed monitor mode + Selkies manual resolution |
| "Install done" too early | The live ISO also answers SSH | Check login as the installed user + hostname |
| `undefined method 'split' for Process::Status` | Installer parsed output from a logging runner | Use an output-returning kubectl for reads |
| AWS: no `/dev/kvm` | Nested virtualization not enabled on the instance | Stop → Change CPU options → Start |
| Background watcher killed itself | `pkill -f "port-forward -n omarchy-spike"` matched the watcher's own command line | Anchor patterns: `pkill -f "^kubectl port-forward"` |
| Selkies: "requires a secure connection" | Page served over plain HTTP from a non-localhost origin | HTTPS (or localhost) |
| IP allow-list blocked the right IP | k3s load balancer SNAT; and a Cloudflare egress hop | `externalTrafficPolicy: Local`; basic auth instead |

## More from building the labs

| Symptom | Cause | Fix / lesson |
|---|---|---|
| `virtctl` exited with 137 on the Mac | macOS killed the unsigned arm64 download (even after ad-hoc signing) | Call KubeVirt's API directly with `kubectl replace --raw .../pause`; `virtctl` is just an API client |
| cloud-init `runcmd` "failed" | A list item contained `hostname: $(...)`; YAML read the bare `: ` as a key/value pair, so the item became a map | Put scripts in `write_files`, keep `runcmd` trivial |
| A lab VM stuck in `ErrorUnschedulable` | Two labs ran at once and the node ran out of memory (Omarchy already reserves 8 GiB) | Memory is the packing constraint; run one VM-heavy thing at a time |
| `kubectl run -i` printed nothing | The pod finished before `-i` attached | Run, wait for `Succeeded`/`Failed`, then `kubectl logs` |
| `timeout 4 xinput ...` never ended | Under `kubectl exec`, the alarm signal `timeout` relies on appears blocked | Background the process and `kill -9` its PID |
| `xdotool windowactivate` errored | No window manager in a bare Xvfb, so no `_NET_ACTIVE_WINDOW` | Without a WM, X focus follows the pointer: move the mouse over the window first |
| First API calls got "connection refused" | `kubectl port-forward` isn't ready instantly | Wait for the port (`until nc -z ...`) instead of `sleep 3` |
| **Typed into the user's Chromium** | `wtype` sends keys to whatever is focused; the lab window hadn't opened (wrong dispatch syntax) | Open your own window, identify it by app-id/PID, and check focus before typing, every time |
| The ssh session died mid-command | `pkill -f "foot --title lab-window"` matched the ssh shell whose command line contained that text | Anchor patterns (`^foot`) or kill by PID |
| `find_element` for editable text → `TypeError` | Computer-server bug: `text.get_text(0, n)` on the object the GObject bindings return | Call `Atspi.Text.get_text(text, 0, n)`; the same bug breaks `get_accessibility_tree` for apps with text fields |

Process mistakes worth remembering (mine): claiming a rejected command hadn't run when it had; printing "reachable"
unconditionally in a test; and giving you a password I hadn't actually read from the file. Moral for everyone:
**print what you verify; don't narrate what you expect.**

---

← [The direct-connection experiment (and why we rolled it back)](12-the-direct-connection-experiment.md) · [Index](README.md) · [Current state and open work](14-current-state-and-open-work.md) →
