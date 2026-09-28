# Desktops in Kubernetes: Agent Computers, KubeVirt, Selkies and Omarchy

A study guide to everything built and debugged in this project: what each piece is, why it's there, how the pieces
talk to each other, and what went wrong along the way. Written for a full-stack web developer who knows HTTP,
HTML/CSS, databases and general infra, but hasn't worked with virtualization, Kubernetes VMs, X11/Wayland or
remote-desktop streaming.

**How to use it:** read the chapters in order (each one ends with "check yourself" questions and links to the next),
then do the labs. Reading on your phone? Every lab page has the questions with hidden answers and a collapsible
**expected output**: a real transcript captured while building the lab, so you can follow along without running
anything.

## Chapters

| # | Chapter | What you'll understand |
|---|---|---|
| 1 | [The big picture](01-the-big-picture.md) | What we built, the final architecture, and the decision trail from containers to VMs |
| 2 | [Virtualization from zero](02-virtualization-from-zero.md) | Containers vs VMs, KVM and `/dev/kvm`, QEMU, nested virtualization, virtio |
| 3 | [KubeVirt](03-kubevirt.md) | VMs as Kubernetes objects: VM/VMI/DataVolume, the components, storage, masquerade networking, cloud-init |
| 4 | [How Linux draws a desktop](04-how-linux-draws-a-desktop.md) | X11 vs Wayland, `DISPLAY`, Xvfb, XTest, compositors, cursors, scaling |
| 5 | [Selkies](05-selkies.md) | Streaming a desktop into a browser tab, WebSocket vs WebRTC, the Origin check, secure contexts |
| 6 | [The Canine side](06-the-canine-side.md) | The data model, provision/destroy jobs, the Rack proxy, the VNC relay, the installer bug |
| 7 | [The golden image pipeline](07-the-golden-image-pipeline.md) | Content-versioned images, the builder VM, reading results off the serial console |
| 8 | [The computer server](08-the-computer-server.md) | The agent API: pixels vs accessibility tree vs CDP, and the takeover lock |
| 9 | [Omarchy](09-omarchy.md) | Unattended OS install in KubeVirt, streaming a Wayland session, the Hyprland tweaks |
| 9b | [Automating Omarchy](26-automating-omarchy.md) | How "New computer" installs and sets up Omarchy unattended (added 2026-09-28) |
| 10 | [Moving to AWS](10-moving-to-aws.md) | Picking an instance, nested virtualization, k3s setup, the IP problem |
| 11 | [Latency](11-latency.md) | Where the time goes, what we measured, what Selkies told us about its pipeline |
| 12 | [The direct-connection experiment](12-the-direct-connection-experiment.md) | Ticket/gatekeeper auth design, iframes and cookies, and why we rolled it back |
| 13 | [Debugging war stories](13-debugging-war-stories.md) | Every bug and its cause, including the ones found while building the labs |
| 14 | [Current state and open work](14-current-state-and-open-work.md) | What exists where, what's uncommitted, what's next |
| 15 | [Glossary and cheat sheet](15-glossary-and-cheat-sheet.md) | Terms and commands in one place |

## Labs

Scripts live in [`labs/`](labs/); each page below explains the lab and shows its expected output.

| Lab | Page | You'll see |
|---|---|---|
| — | [Setup](16-lab-setup.md) | Prerequisites, the `env.sh` helpers, safety rules |
| 1 | [KVM on a real node](17-lab-1-kvm.md) | VT-x on the AWS node, `/dev/kvm`, Omarchy's QEMU as a plain process |
| 2 | [Your first VM](18-lab-2-first-vm.md) | VM → VMI → launcher pod, QEMU inside it, console, pause/stop/start |
| 3 | [Persistence and golden images](19-lab-3-persistence.md) | containerDisk forgets, DataVolume remembers, clones inherit |
| 4 | [Port-forward and masquerade](20-lab-4-port-forward.md) | Reaching a port inside a guest; why NetworkPolicy doesn't block Canine |
| 5 | [X11 playground](21-lab-5-x11.md) | Xvfb, injecting input with XTest, reading the screen, sniffing keystrokes |
| 6 | [Wayland and Hyprland](22-lab-6-wayland.md) | `hyprctl`, wtype, grim, live config on Omarchy |
| 7 | [Selkies up close](23-lab-7-selkies.md) | Selkies without Canine, the Origin check, the CPU pipeline |
| 8 | [Build the proxy yourself](24-lab-8-mini-proxy.md) | A 60-line Rack proxy; reproduce and fix the Origin bug |

Rough time: chapters ~2 hours of reading; labs ~45 minutes of running (or ~20 minutes reading the transcripts).
