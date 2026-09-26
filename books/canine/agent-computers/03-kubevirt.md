# KubeVirt: VMs as Kubernetes objects

## The idea

Kubernetes schedules **pods**. KubeVirt adds VMs by running each VM **inside a pod**: the pod (called
`virt-launcher-<vm>-xxxxx`) contains QEMU, and QEMU runs the guest. So a VM gets everything pods get: scheduling,
resource requests, networking, storage, RBAC, namespaces.

## The objects (CRDs)

KubeVirt installs **Custom Resource Definitions**. The important ones:

| Object | Analogy | What it is |
|---|---|---|
| `VirtualMachine` (VM) | a Deployment with 1 replica | The durable definition: CPU, memory, disks, and a `runStrategy` saying whether it should be running |
| `VirtualMachineInstance` (VMI) | a Pod | One actual running boot of that VM. Stop the VM → the VMI disappears; start it → a new VMI |
| `DataVolume` (DV, from CDI) | a "PVC + how to fill it" | Creates a PVC and populates it: import from a URL/registry, clone another PVC, or blank |
| `DataSource` (CDI) | a named pointer | "The golden image is *this* PVC" — lets VMs say `sourceRef: DataSource/x` |

`runStrategy` values we used:
- `Always` — keep it running (restart it if it stops). Agent computers and Omarchy.
- `Once` — run once, and don't restart when the guest powers off. The image **builder** VM.
- (others exist: `Halted`, `Manual`, `RerunOnFailure` — these are what the future stop/start work will use.)

## The components (what runs on the cluster)

```
kubevirt namespace
  virt-operator     installs/upgrades everything else
  virt-api          validates VM objects; serves subresources (VNC, console, pause/unpause)
  virt-controller   watches VMs → creates VMIs → creates virt-launcher pods
  virt-handler      DaemonSet, one per node: talks to the local launchers, advertises /dev/kvm to the scheduler

per VM (in the VM's namespace)
  virt-launcher-<vm>-xxxxx   the pod: libvirt + QEMU running your guest
      container "compute"           QEMU itself
      container "guest-console-log" streams the VM's serial console as container logs (logSerialConsole: true)

cdi namespace (Containerized Data Importer)
  cdi-operator, cdi-apiserver, cdi-deployment, cdi-uploadproxy
  + short-lived importer/cloner pods that fill disks
```

**How KVM reaches the scheduler:** `virt-handler` registers a Kubernetes *device plugin* resource called
`devices.kubevirt.io/kvm`. Nodes with `/dev/kvm` advertise it (we saw `1k`, i.e. 1000 slots). VMs request it, so
the scheduler only places VMs on KVM-capable nodes. Canine's installer checks this resource
(`ensure_kvm!` in `app/models/cluster_package/installer/kube_virt.rb`) and refuses to continue without it.

## Installing KubeVirt (what Canine's installer does)

`ClusterPackage::Installer::KubeVirt#install!`:

1. If KubeVirt and CDI already report phase `Deployed`, reuse them (never clobber someone else's install).
2. Otherwise `kubectl apply` four manifests from GitHub releases: `kubevirt-operator.yaml`, `kubevirt-cr.yaml`
   (KubeVirt v1.9.0), `cdi-operator.yaml`, `cdi-cr.yaml` (CDI v1.66.1). Operators install the rest.
3. `kubectl wait ... --for=condition=Available` for both.
4. `ensure_kvm!` — confirm a node exposes `devices.kubevirt.io/kvm`.
5. Queue `AgentComputers::BuildImageJob` to build the golden image.

It records `installed_by_canine: true` in the package config so **uninstall** only removes KubeVirt if Canine
installed it.

## Storage: PVCs, local-path, and CDI quirks

- k3s ships the **local-path** provisioner: a PVC becomes a directory on the node's disk. Simple, fast, but tied to
  that node (no live migration across nodes).
- Its binding mode is `WaitForFirstConsumer`: the PVC isn't created on disk until a pod needs it. That's why you
  saw DataVolumes sit in `WaitForFirstConsumer` until the VM was scheduled.
- **Quirk we hit:** CDI looks up a `StorageProfile` for the storage class to decide access mode and volume mode.
  local-path's profile has no defaults, so DataVolumes failed until we **always spelled out**
  `accessModes: [ReadWriteOnce]` and `volumeMode: Filesystem`. You'll see a comment about this in every DataVolume
  we generate.

## Networking: masquerade mode

With `interfaces: [{ masquerade: {} }]` and `networks: [{ pod: {} }]`, the VM sits **behind NAT inside its own
pod**: the guest gets a private address, and traffic to the pod's IP is NAT'ed into the guest. Consequences:

- `kubectl port-forward pod/virt-launcher-... 8080:8080` reaches **port 8080 inside the guest**. This is how Canine
  reaches Selkies and the computer server. It's the single most important trick in the whole design.
- A Kubernetes `Service` selecting the launcher pod also reaches guest ports (we used this in the direct-routing
  experiment).
- The launcher pod's label `vm.kubevirt.io/name=<vm-name>` is how we find the pod for a VM.
- `virtctl port-forward` exists too, but it hung for HTTP in our tests, so we use plain `kubectl port-forward` to
  the launcher pod everywhere (including the helper commands shown on the computer's overview page).

## Cloud-init: configuring a VM on first boot

Cloud images (like Ubuntu's) run **cloud-init** at boot. It reads "user data" (a YAML `#cloud-config` document) from
a small attached disk and does what it says: set the hostname, write files, run commands. KubeVirt attaches that
disk for you via a `cloudInitNoCloud` volume.

Quirk: KubeVirt caps **inline** `userData` at 2KB, so the builder's user data (which embeds the whole provision
script and a tarball, base64-encoded) lives in a **Secret** referenced with `secretRef`.

## Useful KubeVirt features we measured

On the Hetzner dedicated node:

| Operation | Time |
|---|---|
| Pause (freeze the guest in RAM) | ≈ 0.09 s |
| Unpause | ≈ 0.5 s |
| Cold start (stopped → running) | ≈ 11.5 s |
| First create (import + boot) | ≈ 58 s |
| Agent computer from golden image (clone + boot) | ≈ 70 s |

Pause/unpause is what would make "idle computers cost nothing but resume instantly" possible later (still paused
VMs hold their RAM, though).

The **VNC subresource**: `virt-api` exposes each VM's *virtual monitor* (what QEMU's virtual GPU shows) as a
WebSocket speaking the RFB/VNC protocol. `virtctl vnc screenshot` uses it — we used it constantly to watch the
Omarchy installer, since no streaming server existed inside the guest yet.

✅ **Check yourself:** What's the difference between a VM and a VMI? Why does `kubectl port-forward` to a pod reach
a port inside the *guest*? Why did DataVolumes fail on local-path until we set `accessModes`?

