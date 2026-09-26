*Chapter 14 of 15*

# Current state and open work

## Clusters and machines

| Cluster | Where | Contents |
|---|---|---|
| 32 `devserver` | <old-devserver-ip> | Old container-era cluster (the `testing` computer was deleted) |
| 33 `devserver` | Hetzner dedicated, Helsinki (<hetzner-ip>) | KubeVirt; golden image `agent-computer-1d9263000eef`; agent computer `desk-2` (id 10); Omarchy (id 11, ns `omarchy-spike`); the user's own `agent-desktop` VM (don't touch) |
| 34 `cluster` | AWS m7i-flex.xlarge, us-east-1 (<aws-node-ip>, **no Elastic IP yet**) | k3s v1.36, KubeVirt + CDI, golden image built, Omarchy (id 12, ns `omarchy-spike`) |

Study material: this lesson, in the `ai-lessons` repo under `canine/agent-computers/`.

Files outside the repo: `~/Downloads/aws-devserver-kubeconfig.yml` (cluster 34 kubeconfig) and
`~/Downloads/devserver-keypair.pem` (EC2 SSH key). The Omarchy SSH key, login password, VM spec and unattended-install
config were copied from the session scratchpad into `labs/.secrets/` (git-ignored, local only); the scratchpad itself is
temporary.

## Uncommitted repo changes

Everything from the rename onward: models, jobs, services, views, JS controllers, `lib/agent_computer_proxy.rb`,
`lib/kubevirt_vnc_relay.rb`, the KubeVirt installer (+ today's `output_reader` fix), migrations, `package.json`
(`@novnc/novnc`), `TODO.md`, `db/schema.rb`. Nothing has been committed.

## Deferred work

1. **Lifecycle (#3):** stop/start/pause/resume from the UI, auto-pause on idle, auto-resume on connect.
2. **Agent access from outside Canine (`TODO.md`):** API tokens on the proxy, `/api/v1/agent_computers`, protocol
   docs, optional per-computer token inside the VM.
3. **Productize Omarchy:** turn the manual steps (Part 9) into an automated golden image, like the Ubuntu one.
4. **Port the computer server to Wayland/Hyprland** if agents should drive Omarchy.
5. **Latency tuning:** Selkies encoder settings, CPU measurement, instance type, maybe WebRTC.
6. **Ops:** Elastic IP for cluster 34; the proxy's 60 s idle timeout for API WebSockets.
7. **Bugs found by the labs:** the AT-SPI `get_text` bug in `accessibility.py` (breaks reading editable text and the
   full tree), and the 8192×4096 X screen on the Ubuntu image (pin Selkies' resolution in `provision.sh`).
8. **Omarchy idle CPU:** disable hypridle/the screensaver inside the VM.

---

← [Debugging war stories](13-debugging-war-stories.md) · [Index](README.md) · [Glossary and command cheat sheet](15-glossary-and-cheat-sheet.md) →
