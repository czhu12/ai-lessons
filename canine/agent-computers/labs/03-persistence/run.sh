#!/usr/bin/env bash
# Lab 3 walkthrough: why containers "forget" and VMs with a real disk don't, and how cloning makes golden images.
source "$(dirname "$0")/../env.sh"
cd "$(dirname "$0")"

# Pull the most recent /var/boots.log the VM printed to its serial console
boots() {
  vm_console_log "$1" 2>/dev/null | tr -d '\r' |
    awk '/=== \/var\/boots.log ===/{buf=""; on=1; next} /=== end ===/{on=0; last=buf} on{buf=buf $0 "\n"} END{printf "%s", last}'
}
show_boots() {
  local start=$SECONDS
  until [ -n "$(boots "$1")" ]; do sleep 3; [ $((SECONDS - start)) -gt 240 ] && { echo "   (no boot log yet)"; return; }; done
  echo "   /var/boots.log on '$1':"; boots "$1" | sed 's/^/     /'
}
restart() { vm_stop "$1" >/dev/null; until ! kubectl get vmi "$1" -n lab >/dev/null 2>&1; do sleep 2; done; vm_start "$1" >/dev/null; wait_vm "$1"; }

step "1. Boot two identical Ubuntu VMs; only the root disk differs (containerDisk vs DataVolume)"
lab_ns
run kubectl apply -f ephemeral.yaml -f persistent.yaml
note "Watch the DataVolume import the Ubuntu image into a PVC: kubectl get dv -n lab -w"
wait_vm ephemeral; wait_vm persistent
run kubectl get dv,pvc -n lab

step "2. First boot: each VM wrote one line to /var/boots.log"
show_boots ephemeral; show_boots persistent

step "3. Restart both VMs (stop = QEMU exits, like pulling the power cord... gently)"
restart ephemeral; restart persistent

step "4. Compare: the containerDisk forgot everything; the DataVolume kept it"
show_boots ephemeral; show_boots persistent
note "This is exactly why agent computers moved from containers to VMs: apt install gcc lands on a disk that stays."

step "5. Golden image: clone the persistent disk into a brand-new VM"
note "CDI only clones a disk that isn't in use, so the persistent VM is stopped first."
run kubectl delete vm ephemeral -n lab
run vm_stop persistent
until ! kubectl get vmi persistent -n lab >/dev/null 2>&1; do sleep 2; done
run kubectl apply -f clone.yaml
wait_vm clone
show_boots clone
note "The clone inherited the original's history, then logged its own first boot. Canine does this for every agent"
note "computer: build one golden disk (provision.sh), then clone it instead of installing everything again."

step "6. Clean up (deletes the VMs and their disks)"
run kubectl delete vm persistent clone -n lab --wait=true
run kubectl get dv,pvc -n lab
note "dataVolumeTemplates are owned by the VM, so deleting the VM deleted its disk too."
