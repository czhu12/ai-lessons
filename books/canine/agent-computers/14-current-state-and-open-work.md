# Current state and open work

*Updated 2026-09-28, after the Ubuntu agent computer was removed and Omarchy provisioning was automated.*

## Clusters and machines

| Cluster | Where | Contents |
|---|---|---|
| 32 `devserver` | `<old-devserver-ip>` | Old container-era cluster (the `testing` computer was deleted) |
| 33 `devserver` | Hetzner dedicated, Helsinki `(<hetzner-ip>)` | KubeVirt; the hand-built Omarchy (id 11, ns `omarchy-spike`); `omarchy-auto`, the first computer Canine built by itself; the user's own `agent-desktop` VM (don't touch). `desk-2` and the golden image are deleted. |
| 34 `cluster` | AWS m7i-flex.xlarge, us-east-1 (`<aws-node-ip>`, **no Elastic IP yet**) | k3s v1.36, KubeVirt + CDI, the hand-built Omarchy (id 12, ns `omarchy-spike`). Golden image deleted. |

Study material: this lesson, in the `ai-lessons` repo under `books/canine/agent-computers/`.

Files outside the repo: `~/Downloads/aws-devserver-kubeconfig.yml` (cluster 34 kubeconfig) and
`~/Downloads/devserver-keypair.pem` (EC2 SSH key). The spike's Omarchy SSH key, login password, VM spec and
unattended-install config are in `labs/.secrets/` (git-ignored, local only). Computers Canine builds keep their own
password and SSH key on their database record.

## What changed on 2026-09-28

- **Removed:** the Ubuntu/XFCE image (`provision.sh`), the golden-image build (`AgentComputer::Image`,
  `BuildImageJob`), the X11 computer server and its Control tab and `/api` proxy route. See the notes at the top of
  [The golden image pipeline](07-the-golden-image-pipeline.md) and [The computer server](08-the-computer-server.md).
- **Added:** "New computer" now builds an Omarchy VM end to end. See [Automating Omarchy](26-automating-omarchy.md).
- **Kept:** the proxy (Selkies + VNC), the connect page, stats, and the KubeVirt installer (minus the image build).

## Deferred work

1. **Lifecycle:** Stop and Start work (a stopped computer keeps its disk and frees its memory and CPU; start is
   ~30 s to a streaming desktop). Still to do: stop idle computers automatically, start on connect.
2. **Agent control on Wayland:** built (in review): a computer-use server in each VM plus MCP tools, with its own
   book, [Computer Use](../computer-use/README.md). Still to do: API tokens on the proxy and `/api/v1/agent_computers`.
3. **Share the ISO:** each computer imports its own 6 GB copy; import once per cluster and clone it instead.
4. **Latency tuning:** Selkies encoder settings, CPU measurement, instance type, maybe WebRTC.
5. **Ops:** Elastic IP for cluster 34.
6. **Disk stats:** Omarchy has no QEMU guest agent, so the overview can't show disk usage. Installing it needs a full
   `pacman -Syu`, which provisioning deliberately avoids.
