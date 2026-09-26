# Virtualization from zero

## Container vs VM, in web-developer terms

- A **container** is a normal Linux process with a restricted view of the system (namespaces for its own
  filesystem/network/PIDs, cgroups for CPU/memory limits). It **shares the host's kernel**. Its root filesystem is
  built from image layers plus a thin writable layer that is thrown away when the container is recreated.
- A **VM** runs a **whole separate kernel** on emulated/virtualized hardware: virtual CPUs, virtual RAM, a virtual
  disk (a file or block device on the host), virtual network card, virtual GPU. The guest OS thinks it's on a real
  PC. Its disk is just a big file that persists like any other file.

Analogy: a container is like a tenant in a shared apartment (same plumbing, separate room). A VM is like a separate
house built inside a warehouse — heavier, but it has its own everything, including a permanent foundation (the disk).

## Hardware virtualization and KVM

Running another kernel efficiently needs CPU help. Modern CPUs have **virtualization extensions**:

- Intel: **VT-x**, shown in `/proc/cpuinfo` as the `vmx` flag
- AMD: **AMD-V**, the `svm` flag

Linux exposes these through **KVM** (Kernel-based Virtual Machine): a kernel module (`kvm`, plus `kvm_intel` or
`kvm_amd`) that creates the device **`/dev/kvm`**. A userspace program — **QEMU** — opens `/dev/kvm` and says "run
this guest code at near-native speed". QEMU also emulates the devices (disk controller, network card, USB tablet,
GPU).

```
  Guest OS (Ubuntu / Arch)
  ─────────────────────────
  QEMU (userspace process: devices, disk file, VNC server)
  ─────────────────────────
  KVM (/dev/kvm, kernel module: runs guest CPU instructions natively)
  ─────────────────────────
  Host Linux kernel  →  real CPU with VT-x
```

Without `/dev/kvm`, QEMU can *emulate* a CPU in software (TCG), but it's 10–50× slower — useless for a desktop.

**Checking for KVM on a machine** (we did this on every node):

```bash
grep -cw vmx /proc/cpuinfo   # > 0 means the CPU exposes VT-x to this OS
ls -l /dev/kvm               # must exist
lsmod | grep kvm             # kvm_intel + kvm loaded
```

## Nested virtualization (why AWS was tricky)

Most cloud servers are **themselves VMs**. On AWS, your EC2 instance runs on AWS's hypervisor (the Nitro system).
Running KubeVirt on it means a VM *inside* a VM:

```
  L2: Omarchy guest          ← our VM
  L1: Ubuntu on EC2 + KVM    ← your instance, acting as a hypervisor
  L0: AWS Nitro hypervisor   ← AWS's physical host
```

For L1 to use KVM, L0 must pass VT-x through to it. That's **nested virtualization**. AWS supports it only on
certain instance families (C7i/M7i/R7i, C8i/M8i/R8i, their `-flex` variants, I7i, …) and **only when you enable it**
(`--cpu-options NestedVirtualization=enabled` at launch, or "Change CPU options" while stopped).

What we saw: the first boot of the m7i-flex.xlarge had `vmx` count **0**, no `/dev/kvm`, and `modprobe kvm_intel`
failed with `Operation not supported` — the module existed, but the CPU feature wasn't exposed. After enabling the
option, `vmx` showed 8 (once per vCPU) and `/dev/kvm` appeared.

Alternatives: **bare-metal** instances (e.g. Hetzner dedicated servers, AWS `*.metal`) run KVM directly with no
nesting. Hetzner *Cloud* VMs don't offer nested virtualization, which is why we used a Hetzner *dedicated* server
before AWS.

Performance note: nested virtualization mostly costs you on "VM exits" (I/O, interrupts) rather than raw CPU
arithmetic, so CPU-bound work like video encoding stays close to native; boots and disk-heavy work are slower.

## Virtio devices

QEMU can emulate old real hardware (an Intel e1000 network card, an IDE disk), but it's faster to use **virtio**
devices — paravirtualized devices designed for VMs, where the guest has drivers that know they're talking to a
hypervisor. In our VM specs you'll see `bus: virtio` for disks and `video: { type: virtio }` for the GPU.

## How a VM's disk becomes persistent

The VM's disk is a file (or block device) on a Kubernetes PersistentVolume. Reboots, pod restarts, even moving the
VM (if storage allows) keep the disk. That's the whole reason we switched: `apt install gcc` writes into the disk,
and the disk persists.

✅ **Check yourself:** What does `/dev/kvm` give QEMU? Why did `modprobe kvm_intel` fail on the first AWS boot even
though the module file existed?

