#!/usr/bin/env bash
# Lab 2 walkthrough: boot a VM, find QEMU inside its pod, read its console, pause/resume and stop/start it.
source "$(dirname "$0")/../env.sh"
cd "$(dirname "$0")"

step "1. Create the VM (a Kubernetes object like any other)"
lab_ns
run kubectl apply -f hello-vm.yaml
wait_vm hello

step "2. Three objects now exist: the VM (definition), the VMI (this boot), and the launcher pod (runs QEMU)"
run kubectl get vm,vmi,pods -n lab -o wide

POD=$(vm_pod hello)
step "3. Inside the launcher pod: libvirt + QEMU, and /dev/kvm passed in from the node"
run "kubectl exec -n lab $POD -c compute -- sh -c 'for p in /proc/[0-9]*; do tr \"\\\\0\" \" \" < \$p/cmdline 2>/dev/null; echo; done' | grep -E 'qemu-kvm|virtqemud' | cut -c1-150"
run kubectl exec -n lab "$POD" -c compute -- ls -l /dev/kvm
note "qemu-kvm is the actual virtual machine. Its args (-machine, -smp, -m, -drive...) come from your YAML."

step "4. The VM's serial console, exposed as container logs"
until vm_console_log hello 2>/dev/null | grep -q "hello from inside"; do sleep 2; done
run "vm_console_log hello | grep -E 'hello from inside|login:' | head -3"
note "That line was printed by the cloud-init script in hello-vm.yaml, from inside the guest."

step "5. Pause: freeze the guest's CPUs, keep its RAM. Resume is near-instant."
T=$(now); run vm_pause hello; echo "   took $(since $T)"
run "kubectl get vmi hello -n lab -o jsonpath='{.status.conditions[?(@.type==\"Paused\")].status}'; echo"
T=$(now); run vm_unpause hello; echo "   took $(since $T)"

step "6. Stop: the VMI and launcher pod go away; the VM object stays (like scaling a Deployment to 0)"
run vm_stop hello
until ! kubectl get vmi hello -n lab >/dev/null 2>&1; do sleep 1; done
run kubectl get vm,vmi,pods -n lab

step "7. Start again: a new VMI and a new launcher pod (note the new pod name)"
run vm_start hello
wait_vm hello
run kubectl get pods -n lab

step "8. Clean up"
run kubectl delete vm hello -n lab
note "Done. Try: edit hello-vm.yaml (cores: 2, memory 512Mi), re-apply, and compare the qemu-kvm args."
