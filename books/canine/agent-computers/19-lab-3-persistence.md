# Lab 3: Persistence and golden images

**Goal:** prove why we moved from containers to VMs, and see how Canine makes agent computers fast (clone a golden
disk). **Time:** ~5 minutes (Ubuntu images). **Chapters:** [KubeVirt](03-kubevirt.md),
[The golden image pipeline](07-the-golden-image-pipeline.md).

```bash
./labs/03-persistence/run.sh
```

Three Ubuntu VMs with the same cloud-init: every boot, a `bootcmd` appends `boot at HH:MM:SS` to `/var/boots.log`
and prints the whole file to the serial console, so you can read it from outside.

| VM | Root disk |
|---|---|
| `ephemeral` | containerDisk (rebuilt from the image every boot) |
| `persistent` | DataVolume: CDI imports Ubuntu into a PVC **once**; the VM boots from that PVC forever |
| `clone` | DataVolume cloned from `persistent`'s PVC: the golden-image pattern |

## Questions

**Q: After the restart, `ephemeral` shows one line and `persistent` shows two. Why?**

<details>
<summary>Answer</summary>

`ephemeral` booted from a fresh copy of the image, so the first boot's line was thrown away. `persistent` boots from a PersistentVolumeClaim, so the file written during boot #1 was still on disk for boot #2.

</details>

**Q: Why must the persistent VM be stopped before cloning its disk?**

<details>
<summary>Answer</summary>

CDI won't clone a PVC that's in use: copying a disk while a running OS writes to it gives an inconsistent copy. Canine's golden image works the same way: the builder VM powers itself off before the DataSource is published.

</details>

**Q: The clone's log starts with the original's two lines. What was the equivalent in Canine?**

<details>
<summary>Answer</summary>

Canine used to run provision.sh once in a builder VM (installing XFCE, Chrome, Selkies, the computer server), and every agent computer's disk was a clone of that golden disk. It inherited everything installed, then diverged.

</details>

**Q: Deleting the VMs also deleted the PVCs. Why, when PVCs normally outlive pods?**

<details>
<summary>Answer</summary>

They were created from `dataVolumeTemplates`, which are owned by the VM. Kubernetes garbage-collects owned objects when the owner is deleted. A standalone DataVolume would survive.

</details>


## Expected output

<details>
<summary>📜 Expected output (a real run, captured while building the lab)</summary>

```text
== 1. Boot two identical Ubuntu VMs; only the root disk differs (containerDisk vs DataVolume)
$ kubectl apply -f ephemeral.yaml -f persistent.yaml
virtualmachine.kubevirt.io/ephemeral created
virtualmachine.kubevirt.io/persistent created
   Watch the DataVolume import the Ubuntu image into a PVC: kubectl get dv -n lab -w
$ kubectl get dv,pvc -n lab
NAME                                         PHASE       PROGRESS   RESTARTS   AGE
datavolume.cdi.kubevirt.io/persistent-root   Succeeded   100.0%                51s

NAME                                    STATUS   VOLUME                                     CAPACITY     ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/persistent-root   Bound    pvc-7fb0917a-84ac-4a4c-bf26-a5280bef6725   5690831668   RWO            local-path     <unset>                 51s

== 2. First boot: each VM wrote one line to /var/boots.log
   /var/boots.log on 'ephemeral':
     boot at 03:49:16 UTC
   /var/boots.log on 'persistent':
     boot at 03:49:56 UTC

== 3. Restart both VMs (stop = QEMU exits, like pulling the power cord... gently)

== 4. Compare: the containerDisk forgot everything; the DataVolume kept it
   /var/boots.log on 'ephemeral':
     boot at 03:57:13 UTC
   /var/boots.log on 'persistent':
     boot at 03:49:56 UTC
     boot at 03:57:21 UTC
   This is exactly why agent computers moved from containers to VMs: apt install gcc lands on a disk that stays.

== 5. Golden image: clone the persistent disk into a brand-new VM
   CDI only clones a disk that isn't in use, so the persistent VM is stopped first.
$ kubectl delete vm ephemeral -n lab
virtualmachine.kubevirt.io "ephemeral" deleted
$ vm_stop persistent
virtualmachine.kubevirt.io/persistent patched
$ kubectl apply -f clone.yaml
virtualmachine.kubevirt.io/clone created
   /var/boots.log on 'clone':
     boot at 03:49:56 UTC
     boot at 03:57:21 UTC
     boot at 03:59:13 UTC
   The clone inherited the original's history, then logged its own first boot. Canine does this for every agent
   computer: build one golden disk (provision.sh), then clone it instead of installing everything again.

== 6. Clean up (deletes the VMs and their disks)
$ kubectl delete vm persistent clone -n lab --wait=true
virtualmachine.kubevirt.io "persistent" deleted
virtualmachine.kubevirt.io "clone" deleted
$ kubectl get dv,pvc -n lab
No resources found in lab namespace.
   dataVolumeTemplates are owned by the VM, so deleting the VM deleted its disk too.
```

</details>


## Try next

- Watch the import live in a second terminal: `kubectl get dv -n lab -w`.
- `kubectl get pvc -n lab -o wide` then `node_ssh 'sudo ls -la /var/lib/rancher/k3s/storage/'`: local-path PVCs are
  just directories on the node, and the VM disk is a `disk.img` file inside one.

