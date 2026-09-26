*Chapter 15 of 15*

# Glossary and command cheat sheet

## Glossary

- **AT-SPI** — Linux accessibility API; a tree of UI elements (roles, names, states) apps publish for screen readers.
- **CDI** — Containerized Data Importer: fills Kubernetes disks (import/clone/upload) for KubeVirt.
- **CDP** — Chrome DevTools Protocol; what Playwright/Puppeteer use to drive Chrome (port 9222 here).
- **cloud-init** — first-boot configuration for cloud images, driven by "user data".
- **Compositor** — combines window buffers into the final screen; in Wayland it's also the display server + WM.
- **CRD** — Custom Resource Definition; how KubeVirt adds `VirtualMachine` etc. to the Kubernetes API.
- **DataSource / DataVolume** — CDI objects: a named pointer to a disk / a PVC plus how to populate it.
- **ForwardAuth** — Traefik middleware that asks another service "allow this request?" before proxying.
- **Golden image** — a pre-built disk every new machine is cloned from.
- **Hyprland** — tiling Wayland compositor at the core of Omarchy.
- **KVM / `/dev/kvm`** — Linux kernel hypervisor interface; lets QEMU run guests at native speed.
- **Launcher pod** — `virt-launcher-<vm>-…`, the pod that runs QEMU for one VM.
- **local-path** — k3s's default storage provisioner (PVCs are directories on the node).
- **Masquerade** — KubeVirt network mode: the guest sits behind NAT in the pod; pod ports reach guest ports.
- **Nested virtualization** — running a hypervisor inside a VM (L0 → L1 → L2).
- **noVNC / RFB** — browser VNC client / the VNC wire protocol.
- **pixelflux** — Selkies' screen capture + encode library.
- **Port-forward** — `kubectl port-forward`: tunnel a local port to a pod port through the API server + kubelet.
- **QEMU** — the userspace program that emulates a PC's devices and runs the guest (with KVM).
- **runStrategy** — whether/how KubeVirt keeps a VM running (`Always`, `Once`, `Halted`, …).
- **SDDM / uwsm** — Omarchy's graphical login manager / Wayland session manager.
- **Secure context** — a page on HTTPS or localhost; browsers only expose some APIs there.
- **Selkies** — desktop-to-browser streamer (capture → encode → WebSocket/WebRTC; input back).
- **sslip.io** — DNS service mapping `anything.1-2-3-4.sslip.io` → `1.2.3.4`.
- **Virtio** — paravirtualized device family for fast VM I/O (disk, net, GPU).
- **VM vs VMI** — the durable definition vs one running boot of it.
- **VT-x / `vmx`** — Intel's hardware virtualization extension / its CPU flag.
- **Wayland / X11** — modern locked-down vs old permissive Linux display protocols.
- **XTest / XInput2** — X11 extensions to inject fake input / observe (raw) input events.
- **Xvfb** — an X server that draws into memory; a desktop with no physical screen.


## Command cheat sheet

Set `KUBECONFIG=~/Downloads/aws-devserver-kubeconfig.yml` (cluster 34) first, or `source labs/env.sh`.

```bash
# --- KubeVirt state ---------------------------------------------------------------------------
kubectl get vm,vmi -A                                   # VMs and running instances
kubectl get dv,pvc -A                                   # disks and their import/clone progress
kubectl get datasource -n canine-agent-computers        # the published golden image
kubectl get kubevirt -n kubevirt; kubectl get cdi       # phase should be "Deployed"
kubectl get nodes -o jsonpath='{.items[*].status.allocatable.devices\.kubevirt\.io/kvm}'  # KVM advertised?

# --- One VM -------------------------------------------------------------------------------------
NS=omarchy-spike; VM=omarchy
POD=$(kubectl get pods -n $NS -l vm.kubevirt.io/name=$VM --field-selector=status.phase=Running -o name | head -1)
kubectl port-forward -n $NS $POD 8080:8080              # then open http://localhost:8080 (Selkies)
kubectl port-forward -n $NS $POD 2223:22                # then ssh -p 2223 omarchy@127.0.0.1
kubectl logs -n $NS $POD -c guest-console-log           # serial console output
kubectl top pod -n $NS                                  # launcher CPU/memory
source labs/env.sh                               # helpers below (virtctl gets killed by macOS here)
vm_pause $VM $NS; vm_unpause $VM $NS                    # = PUT .../virtualmachineinstances/$VM/pause|unpause
vm_stop $VM $NS; vm_start $VM $NS                       # = patch spec.runStrategy Halted|Always
vm_console_log $VM $NS                                  # serial console

# --- Inside Omarchy (over SSH) ----------------------------------------------------------------------
systemctl --user status selkies                         # the stream
journalctl --user -u selkies -n 50 -o cat               # its logs
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1000/hypr/ | head -1)
hyprctl monitors; hyprctl getoption cursor:invisible; hyprctl reload; hyprctl configerrors

# --- Node ---------------------------------------------------------------------------------------
ssh -i ~/Downloads/devserver-keypair.pem ubuntu@<aws-node-ip>
grep -cw vmx /proc/cpuinfo; ls -l /dev/kvm

# --- Canine -------------------------------------------------------------------------------------
bin/rails runner 'p AgentComputer.all.map { |c| c.slice(:id, :name, :namespace, :status, :cluster_id) }'
grep AgentComputerProxy log/development.log | tail     # proxy decisions and port-forwards
```

---

← [Current state and open work](14-current-state-and-open-work.md) · [Index](README.md) · [Labs: setup](16-lab-setup.md) →
