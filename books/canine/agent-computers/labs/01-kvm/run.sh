#!/usr/bin/env bash
# Lab 1 walkthrough: what "hardware virtualization" looks like on a real machine, and that a VM is just a process.
source "$(dirname "$0")/../env.sh"

step "1. The node is itself a VM on AWS (L1). Is it? And does its CPU expose VT-x to it?"
run "node_ssh 'systemd-detect-virt; echo \"vCPUs: \$(nproc)  VT-x (vmx) exposed: \$(grep -qw vmx /proc/cpuinfo && echo yes || echo no)\"'"
note "systemd-detect-virt says 'amazon'/'kvm': we're inside AWS's hypervisor. vmx is exposed only because nested"
note "virtualization was enabled on the instance; before that it said no and there was no /dev/kvm."

step "2. The KVM kernel modules and the /dev/kvm device QEMU opens"
run "node_ssh 'lsmod | grep -E \"^kvm\"; ls -l /dev/kvm'"

step "3. How Kubernetes knows this node can run VMs: KubeVirt advertises /dev/kvm as a node resource"
run "kubectl get nodes -o jsonpath='{.items[*].status.allocatable.devices\\.kubevirt\\.io/kvm}'; echo"
run "kubectl get pods -n kubevirt -o wide | grep -E 'NAME|virt-handler'"
note "virt-handler (one per node) registers devices.kubevirt.io/kvm; VM pods request it, so they only land on KVM nodes."

step "4. A VM is just a process on the host: find Omarchy's QEMU"
run "node_ssh 'ps -eo pid,user,rss,pcpu,etime,args --sort=-rss | grep -E \"[q]emu-kvm\" | cut -c1-160'"
note "RSS is in KB: ~7 million KB is most of the guest's 8GiB (only pages the guest has touched are resident)."
note "pcpu can exceed 100%: it's summed over the guest's vCPUs (Hyprland drawing + Selkies encoding, all on CPU)."
note "Kill that process and the Omarchy VM 'loses power'. (Don't.)"

step "5. Which cgroup/pod does it belong to? (the launcher pod's container)"
run "node_ssh 'pid=\$(pgrep -f \"qemu-kvm.*omarchy\" | head -1); cat /proc/\$pid/cgroup | head -2'"
note "The QEMU process lives in the virt-launcher pod's cgroup, so Kubernetes CPU/memory limits apply to the VM."

step "6. For comparison: your Mac"
run "sysctl -n kern.hv_support 2>/dev/null | sed 's/1/macOS Hypervisor.framework available (what Docker Desktop, UTM use)/'"
note "macOS has its own hypervisor API instead of KVM. Same idea: the CPU runs guest code natively."
