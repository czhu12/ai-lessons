# The big picture

## What we were trying to build

A **computer in a browser tab** that both a person and an AI agent can use:

- The **person** sees a full Linux desktop in Canine (`/agent_computers/:id/connect`), with mouse, keyboard,
  clipboard, a real Chrome, a terminal. It should feel good enough that someone would *want* to use it.
- An **agent** drives the same desktop over an HTTP/WebSocket API (screenshots, clicks, typing, shell commands,
  reading the accessibility tree, driving Chrome).
- If the person grabs the mouse, the agent pauses (the "takeover lock").
- Everything runs on the user's own Kubernetes cluster, managed by Canine like any other workload.
- Installed software must **survive restarts**. That requirement is what pushed us from containers to VMs.

## The final architecture in one diagram

```
 Your browser (localhost:3000)
   │  HTTPS/HTTP + WebSocket, logged-in Canine session
   ▼
 Canine (Rails)  ── AgentComputerProxy (Rack middleware, lib/agent_computer_proxy.rb)
   │   checks the Warden session + account membership
   │   spawns `kubectl port-forward` per computer/port
   ▼
 Kubernetes API server (:6443 on the node)
   │   port-forward stream (API server → kubelet → pod network namespace)
   ▼
 virt-launcher pod  (one per VM; runs QEMU)            namespace: computer-<name>  (or omarchy-spike)
   │   masquerade networking: pod ports are NAT'ed into the guest
   ▼
 The VM (guest OS)
   ├── Selkies        :8080  → streams the screen (H.264 over WebSocket) and injects your input
   └── computer server :8000 → the agent API (only in the Ubuntu agent-computer image)
```

Two different guest operating systems existed while this was being built (the Ubuntu one has since been removed;
every agent computer is now Omarchy, see [Automating Omarchy](26-automating-omarchy.md)):

| | Agent computer (Ubuntu image) | Omarchy spike |
|---|---|---|
| OS | Ubuntu 24.04 + XFCE | Arch Linux + Hyprland (Omarchy 4.0.4) |
| Display system | X11 (Xvfb, virtual screen) | Wayland (Hyprland is the compositor) |
| How it's created | Canine clones a golden image, fully automatic | Hand-installed from the Omarchy ISO, unattended |
| Selkies mode | `selkies-session` owns the display | Selkies attaches to Hyprland's existing session |
| Agent API | Yes (computer server on :8000) | No (the computer server is X11-only; see Part 9) |

## How we got here (the decision trail)

It helps to remember *why* each piece exists, because each one replaced something:

1. **Containers + Agent Sandbox (kubernetes-sigs) + a desktop image (Webtop/Cua)** — the first version. Fast to
   start, but a container's filesystem is rebuilt from the image on every restart. Anything you `apt install`
   disappears. You can mount volumes for `/home`, but not for "the whole OS".
2. **"Can we make it stateful?"** — We looked at overlays, Nix, devcontainers, Codespaces, Kata Containers,
   Firecracker. The key insight: to persist *the entire root filesystem* including `/usr`, you want a **disk**, and
   the natural thing that boots from a disk is a **VM**.
3. **KubeVirt** won over Firecracker/Kata because it's portable (any node with `/dev/kvm`), it's a Kubernetes-native
   API, persistent disks are first-class, and it supports pause/resume.
4. **Renamed "Agent Sandbox" → "Agent Computer"**, built our own golden VM image, and replaced Cua with our own
   Linux-only **computer server**.
5. **Omarchy** — the user wanted a desktop people would *love*, so we got Omarchy (Arch + Hyprland) running in a VM
   and streamed it with Selkies in Wayland mode.
6. **AWS** — Hetzner in Helsinki was ~120ms+ away from New York; moved to an EC2 instance with nested virtualization
   in us-east-1 (~25ms).
7. **Direct-to-VM routing experiment** — tried bypassing Canine's proxy; not noticeably faster, much more complex,
   rolled back.

✅ **Check yourself:** Why couldn't containers give us "install gcc and it's still there after a restart"? What does
a VM have that a container doesn't?

