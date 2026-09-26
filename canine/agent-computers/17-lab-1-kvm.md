*Lab page 1 of 9*

# Lab 1: KVM on a real node

**Goal:** see hardware virtualization with your own eyes, and prove that a VM is just a process.
**Time:** 5 minutes. **Chapter:** [Virtualization from zero](02-virtualization-from-zero.md).

```bash
./labs/01-kvm/run.sh
```

## What you'll do

1. Ask the node what it is (`systemd-detect-virt` says `amazon`: the node itself is a VM) and whether its CPU exposes
   VT-x.
2. See the `kvm_intel` and `kvm` kernel modules and the `/dev/kvm` device.
3. See how KubeVirt tells Kubernetes the node can run VMs (`devices.kubevirt.io/kvm: 1k`).
4. Find Omarchy's `qemu-kvm` process on the node with plain `ps`, and look at its memory.
5. Find which pod's cgroup it lives in.
6. Compare with your Mac's hypervisor.

## Questions

**Q: Why does the node report `amazon` from `systemd-detect-virt`, and why does that matter for KubeVirt?**

<details>
<summary>Answer</summary>

The EC2 instance is itself a VM on AWS's Nitro hypervisor. For KubeVirt to use KVM inside it, AWS must pass VT-x through: that's nested virtualization, which is why it had to be enabled on the instance.

</details>

**Q: Omarchy is configured with 8 GiB of RAM. Why does `ps` show less (about 7 million KB)?**

<details>
<summary>Answer</summary>

RSS counts only memory pages that are actually resident. The guest hasn't touched all of its 8 GiB, so QEMU hasn't needed all of it from the host yet.

</details>

**Q: Why can QEMU's %CPU be above 100%?**

<details>
<summary>Answer</summary>

`ps` sums CPU time over all threads. Each vCPU is a thread, so a 4-vCPU guest can use up to ~400%.

</details>

**Q: What would happen if you `kill -9` the qemu-kvm process?**

<details>
<summary>Answer</summary>

The VM instantly 'loses power'. KubeVirt sees the VMI fail and, because the VM's runStrategy is `Always`, starts a new launcher pod and boots it again. The disk survives; unsaved work in RAM doesn't.

</details>


## Expected output

<details>
<summary>📜 Expected output (a real run, captured while building the lab)</summary>

```text
== 1. The node is itself a VM on AWS (L1). Is it? And does its CPU expose VT-x to it?
$ node_ssh 'systemd-detect-virt; echo "vCPUs: $(nproc)  VT-x (vmx) exposed: $(grep -qw vmx /proc/cpuinfo && echo yes || echo no)"'
amazon
vCPUs: 4  VT-x (vmx) exposed: yes
   systemd-detect-virt says 'amazon'/'kvm': we're inside AWS's hypervisor. vmx is exposed only because nested
   virtualization was enabled on the instance; before that it said no and there was no /dev/kvm.

== 2. The KVM kernel modules and the /dev/kvm device QEMU opens
$ node_ssh 'lsmod | grep -E "^kvm"; ls -l /dev/kvm'
kvm_intel             552960  6
kvm                  1531904  5 kvm_intel
crw-rw---- 1 root kvm 10, 232 Sep 26 04:12 /dev/kvm

== 3. How Kubernetes knows this node can run VMs: KubeVirt advertises /dev/kvm as a node resource
$ kubectl get nodes -o jsonpath='{.items[*].status.allocatable.devices\.kubevirt\.io/kvm}'; echo
1k
$ kubectl get pods -n kubevirt -o wide | grep -E 'NAME|virt-handler'
NAME                                        READY   STATUS    RESTARTS   AGE    IP           NODE               NOMINATED NODE   READINESS GATES
virt-handler-g79gt                          1/1     Running   0          128m   10.42.0.29   ip-172-31-22-204   <none>           <none>
   virt-handler (one per node) registers devices.kubevirt.io/kvm; VM pods request it, so they only land on KVM nodes.

== 4. A VM is just a process on the host: find Omarchy's QEMU
$ node_ssh 'ps -eo pid,user,rss,pcpu,etime,args --sort=-rss | grep -E "[q]emu-kvm" | cut -c1-160'
  18842 107      7575400 147   01:59:13 /usr/libexec/qemu-kvm -name guest=omarchy-spike_omarchy,debug-threads=on -S -object {"qom-type":"secret","id":"masterKey
   RSS is in KB: ~7 million KB is most of the guest's 8GiB (only pages the guest has touched are resident).
   pcpu can exceed 100%: it's summed over the guest's vCPUs (Hyprland drawing + Selkies encoding, all on CPU).
   Kill that process and the Omarchy VM 'loses power'. (Don't.)

== 5. Which cgroup/pod does it belong to? (the launcher pod's container)
$ node_ssh 'pid=$(pgrep -f "qemu-kvm.*omarchy" | head -1); cat /proc/$pid/cgroup | head -2'
0::/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod65533ac7_a570_44ca_a5c8_f6b1f2f54bd1.slice/cri-containerd-683b83f9b2728ef81fadf1172baa551fdced284b999...
   The QEMU process lives in the virt-launcher pod's cgroup, so Kubernetes CPU/memory limits apply to the VM.

== 6. For comparison: your Mac
$ sysctl -n kern.hv_support 2>/dev/null | sed 's/1/macOS Hypervisor.framework available (what Docker Desktop, UTM use)/'
macOS Hypervisor.framework available (what Docker Desktop, UTM use)
   macOS has its own hypervisor API instead of KVM. Same idea: the CPU runs guest code natively.
```

</details>


## Try next

- `node_ssh 'sudo cat /proc/$(pgrep -f "qemu-kvm.*omarchy" | head -1)/status | grep -E "Threads|VmRSS"'`: how many
  threads does a 4-vCPU VM use? (One per vCPU, plus I/O and helper threads.)
- `node_ssh 'ls /sys/module/kvm_intel/parameters/ && cat /sys/module/kvm_intel/parameters/nested'`: is *this*
  node allowed to nest further?

---

← [Labs: setup](16-lab-setup.md) · [Index](README.md) · [Lab 2: Your first VM](18-lab-2-first-vm.md) →
