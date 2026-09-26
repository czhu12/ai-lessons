# Moving to AWS

## Picking the instance

Requirements: nested virtualization + enough CPU/RAM for desktops (Omarchy VM: 4 vCPU / 8 GiB; agent computer:
2 vCPU / 4 GiB) + k3s overhead.

- Chosen for testing: **m7i-flex.xlarge** (4 vCPU, 16 GiB), us-east-1, ~$0.19/hr.
- "Flex" instances guarantee 40% of CPU and can burst to 100% most of the time — fine for testing, a possible
  bottleneck for constant video encoding.
- Better for real use: c8i/m8i `.2xlarge`–`.4xlarge`. Bare metal (`*.metal`) only when packing many desktops.
- Region: us-east-1 (Virginia) is ~7–25ms from NYC. Local Zones (NYC) don't offer nested-virt-capable types.
- AMI: Ubuntu Server LTS x86_64 (Intel families only). The instance actually came up with Ubuntu 26.04 — fine.

## Setting up the node

```bash
# after enabling nested virtualization and rebooting
grep -cw vmx /proc/cpuinfo; ls -l /dev/kvm

# k3s, with the public IP added to the API server's TLS certificate
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --tls-san <aws-node-ip>" sh -

# kubeconfig for Canine: copy /etc/rancher/k3s/k3s.yaml, replace 127.0.0.1 with the public IP
```

Security group: 22 and 6443 from your IP only (Canine only needs the Kubernetes API; everything reaches the VMs via
port-forward). 80/443 are only needed if you expose ingress.

Then in Canine: add the cluster (id **34**) → install the KubeVirt package → golden image builds automatically.

**The IP problem:** without an **Elastic IP**, stop/start gives a new public IP (we saw `<previous-ip>` →
`<aws-node-ip>).` Both the kubeconfig and the k3s certificate (`--tls-san`) are tied to the IP. Attach an Elastic IP
before you rely on this cluster.

## Scheduling on a small node

When the Omarchy VM was created while the image builder VM was running, Omarchy stayed `Pending` until the builder
finished — the node didn't have room for both VMs' memory requests (KubeVirt requests the guest's memory plus
per-VM overhead for the launcher/QEMU). Memory, not CPU, is usually the constraint for packing VMs.

✅ **Check yourself:** What three things must be true for KubeVirt to run on an EC2 instance? What breaks if the
instance's public IP changes?

