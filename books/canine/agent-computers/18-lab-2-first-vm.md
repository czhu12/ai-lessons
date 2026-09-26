# Lab 2: Your first VM

**Goal:** create a VM as a Kubernetes object, find QEMU inside its pod, read its console, then pause, stop and
start it. **Time:** 5 minutes. **Chapter:** [KubeVirt](03-kubevirt.md).

```bash
./labs/02-first-vm/run.sh
cat labs/02-first-vm/hello-vm.yaml     # read this first, every line is commented
```

The VM is **CirrOS**, a ~20 MB Linux made for testing, booted from a *containerDisk* (a disk image shipped inside a
container image). It boots in about 5 seconds.

## What you'll see

- **Three objects** for one VM: `VirtualMachine` (definition), `VirtualMachineInstance` (this boot), and the
  `virt-launcher-hello-xxxxx` pod (runs QEMU). It's the same relationship as Deployment → Pod.
- **Inside the pod:** `virtqemud` (libvirt) and `qemu-kvm -name guest=lab_hello ...`, plus `/dev/kvm` passed in.
- **The serial console** as container logs: a line printed by cloud-init from *inside* the guest.
- **Pause/unpause** in ~0.3 s each, **stop** (VMI and pod disappear, VM stays) and **start** (a new pod name).

## Questions

**Q: After `vm_stop`, the VMI and the launcher pod are gone but `kubectl get vm` still shows `hello`. Why?**

<details>
<summary>Answer</summary>

The VM is the durable definition, like a Deployment scaled to 0. Stopping sets `runStrategy: Halted`, so KubeVirt deletes the running instance (VMI) and its pod, but keeps the definition to start again later.

</details>

**Q: Pause took ~0.3 s but start took ~5 s. What's the difference?**

<details>
<summary>Answer</summary>

Pause only stops scheduling the guest's vCPU threads; its RAM stays in place. Start creates a new pod, starts QEMU, and boots the guest kernel from scratch.

</details>

**Q: This VM uses a containerDisk. What happens to files written inside it after a stop/start?**

<details>
<summary>Answer</summary>

They're gone: a containerDisk is rebuilt from the image on every boot, like a container's filesystem. Lab 3 proves it and fixes it.

</details>


## Expected output

<details>
<summary>📜 Expected output (a real run, captured while building the lab)</summary>

```text
== 1. Create the VM (a Kubernetes object like any other)
$ kubectl apply -f hello-vm.yaml
virtualmachine.kubevirt.io/hello created

  hello: Running after 5s

== 2. Three objects now exist: the VM (definition), the VMI (this boot), and the launcher pod (runs QEMU)
$ kubectl get vm,vmi,pods -n lab -o wide
NAME                               AGE   STATUS    READY
virtualmachine.kubevirt.io/hello   5s    Running   True

NAME                                       AGE   PHASE     IP            NODENAME           READY   LIVE-MIGRATABLE   PAUSED
virtualmachineinstance.kubevirt.io/hello   6s    Running   10.42.0.102   ip-172-31-22-204   True    True

NAME                            READY   STATUS    RESTARTS   AGE   IP            NODE               NOMINATED NODE   READINESS GATES
pod/virt-launcher-hello-9dsfq   2/2     Running   0          6s    10.42.0.102   ip-172-31-22-204   <none>           1/1

== 3. Inside the launcher pod: libvirt + QEMU, and /dev/kvm passed in from the node
$ kubectl exec -n lab virt-launcher-hello-9dsfq -c compute -- sh -c 'for p in /proc/[0-9]*; do tr "\\0" " " < $p/cmdline 2>/dev/null; echo; done' | grep -E 'qemu-kvm|v...
/usr/sbin/virtqemud -f /var/run/libvirt/virtqemud.conf
/usr/libexec/qemu-kvm -name guest=lab_hello,debug-threads=on -S -object {"qom-type":"secret","id":"masterKey0","format":"raw","file":"/var/run/kubevir
$ kubectl exec -n lab virt-launcher-hello-9dsfq -c compute -- ls -l /dev/kvm
crw-rw---- 1 qemu qemu 10, 232 Sep 26 04:25 /dev/kvm
   qemu-kvm is the actual virtual machine. Its args (-machine, -smp, -m, -drive...) come from your YAML.

== 4. The VM's serial console, exposed as container logs
$ vm_console_log hello | grep -E 'hello from inside|login:' | head -3
=== hello from inside the VM: Linux hello 5.3.0-26-generic #28~18.04.1-Ubuntu SMP Wed Dec 18 16:40:14 UTC 2019 x86_64 GNU/Linux ===
   That line was printed by the cloud-init script in hello-vm.yaml, from inside the guest.

== 5. Pause: freeze the guest's CPUs, keep its RAM. Resume is near-instant.
$ vm_pause hello
pause: hello
   took 0.30s
$ kubectl get vmi hello -n lab -o jsonpath='{.status.conditions[?(@.type=="Paused")].status}'; echo
True
$ vm_unpause hello
unpause: hello
   took 0.31s

== 6. Stop: the VMI and launcher pod go away; the VM object stays (like scaling a Deployment to 0)
$ vm_stop hello
virtualmachine.kubevirt.io/hello patched
$ kubectl get vm,vmi,pods -n lab
NAME                               AGE   STATUS    READY
virtualmachine.kubevirt.io/hello   22s   Stopped   False

== 7. Start again: a new VMI and a new launcher pod (note the new pod name)
$ vm_start hello
virtualmachine.kubevirt.io/hello patched

  hello: Running after 5s
$ kubectl get pods -n lab
NAME                        READY   STATUS    RESTARTS   AGE
virt-launcher-hello-hg2hq   2/2     Running   0          6s

== 8. Clean up
$ kubectl delete vm hello -n lab
virtualmachine.kubevirt.io "hello" deleted
   Done. Try: edit hello-vm.yaml (cores: 2, memory 512Mi), re-apply, and compare the qemu-kvm args.
```

</details>


## Try next

- Change `memory: { guest: 256Mi }` to `512Mi` and `cores: 1` to `2`, re-apply, and compare the `qemu-kvm` args
  (`-m` and `-smp`).
- While it's paused, run `vm_console_log hello --tail=5` twice a few seconds apart: nothing new, the guest is frozen.
- `kubectl get vmi hello -n lab -o yaml | less` and find `guestOSInfo`, `interfaces`, `phaseTransitionTimestamps`.

