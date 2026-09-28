# Labs: setup

Eight hands-on labs against the real machines from this project. Each lab is a script that walks you through the
steps one at a time (press Enter to advance), printing every command before it runs so you can copy it later.

**On your phone?** Every lab page has the questions with hidden answers and a collapsible **expected output**
section: a real transcript captured while building the lab. You can follow along without running anything.

## What the labs use

| Lab | Runs against | Needs |
|---|---|---|
| 1. KVM on a real node | AWS node (cluster 34) | SSH key `~/Downloads/devserver-keypair.pem` |
| 2. Your first VM | cluster 34, namespace `lab` | ~300 MB free RAM on the node |
| 3. Persistence & golden images | cluster 34, `lab` | ~2 GiB free RAM |
| 4. Port-forward & masquerade | cluster 34, `lab` | ~1 GiB free RAM |
| 5. X11 playground | cluster 34, `lab` (a pod, not a VM) | macOS Screen Sharing (built in) |
| 6. Wayland & Hyprland | the Omarchy VM (cluster 34) | `labs/.secrets/spike_key` |
| 7. Selkies up close | the Omarchy VM | Ruby |
| 8. Build the proxy | the Omarchy VM + your Mac | Canine's bundle (Puma) |

The node has 15 GiB of RAM and Omarchy reserves 8 GiB of it, so **run one lab at a time**. Running two VM labs at
once is exactly how Lab 3's VM ended up `ErrorUnschedulable` while these were being built.

## One-time setup

The labs need a few machine-specific things that aren't in git:

| File | What | Where it came from |
|---|---|---|
| `labs/.local.env` | `NODE_IP=<aws-node-ip>` and optionally `CANINE_DIR=...` (default `~/Documents/Github/canine`), `KUBECONFIG_LABS=...` | write it yourself |
| `labs/.secrets/` | Omarchy's SSH key (`spike_key`) and login password | copied from the session that built Omarchy |
| `~/Downloads/aws-devserver-kubeconfig.yml`, `~/Downloads/devserver-keypair.pem` | cluster 34 kubeconfig, EC2 SSH key | the AWS setup |

```bash
cd ~/Documents/Github/ai-lessons/books/canine/agent-computers
source labs/env.sh     # sets KUBECONFIG to cluster 34 and loads the helpers
kubectl get nodes             # should list ip-172-31-22-204 Ready
```

`env.sh` gives you these helpers (read it, it's short):

| Helper | What it does |
|---|---|
| `vm_pod <vm> [ns]` | name of the virt-launcher pod running a VM |
| `wait_vm <vm> [ns]` | wait until the VM reports Running |
| `vm_pause` / `vm_unpause` | freeze/thaw a VM via KubeVirt's `pause` subresource (what `virtctl pause` does) |
| `vm_stop` / `vm_start` | set `runStrategy` to `Halted` / `Always` |
| `vm_console_log <vm>` | the VM's serial console |
| `node_ssh` | SSH to the AWS node |
| `omarchy_ssh` | SSH into the Omarchy VM through a port-forward |
| `lab_reset` | delete the whole `lab` namespace |

To run a lab: `./labs/02-first-vm/run.sh`. To run it straight through without pauses: `LAB_AUTO=1 ./...`.

## Why no `virtctl`?

`virtctl` is KubeVirt's CLI. The macOS arm64 build was killed on launch (exit 137) on your Mac, so the labs call the
same API endpoints with plain `kubectl`. That turned out to be a better lesson anyway: `virtctl pause vm x` is just
`PUT /apis/subresources.kubevirt.io/v1/namespaces/<ns>/virtualmachineinstances/x/pause`.

## Safety rules the labs follow

- Everything the labs create lives in namespace `lab`, and each lab cleans up after itself.
- Lab 6 acts on a **real desktop** (Omarchy). They only type into a window they opened themselves,
  and they check it has focus first. (One of the early test runs didn't, and typed into your Chromium. That's in
  the war stories.)
- Secrets (`.secrets/`, `.kube/`) are git-ignored.

