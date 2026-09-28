# Source this before any lab:   source labs/env.sh   (from books/canine/agent-computers)
# Points kubectl at the AWS cluster (Canine cluster 34) and adds a few helpers used across the labs.

export LABS="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# Machine-specific settings live in labs/.local.env (git-ignored): NODE_IP, and optionally CANINE_DIR / KUBECONFIG_LABS
[ -f "$LABS/.local.env" ] && source "$LABS/.local.env"
export KUBECONFIG="${KUBECONFIG_LABS:-$HOME/Downloads/aws-devserver-kubeconfig.yml}"
export NODE_IP="${NODE_IP:?set NODE_IP (the AWS node public IP) in labs/.local.env}"
export CANINE_DIR="${CANINE_DIR:-$HOME/Documents/Github/canine}"   # Lab 8 uses the Canine repo
export LAB_NS=lab                                # every lab object lives here; `lab_reset` deletes it all
export NODE_SSH_KEY="$HOME/Downloads/devserver-keypair.pem"
# Copied from the session scratchpad so the labs keep working after it is cleaned up
export OMARCHY_DIR="${OMARCHY_DIR:-$LABS/.secrets}"   # Omarchy SSH key + password (git-ignored)

# virtctl (KubeVirt's CLI) is just a client for extra API endpoints KubeVirt adds ("subresources"). These helpers call
# the same endpoints with plain kubectl, so no extra tool is needed and you can see what's really happening.
#   vm_pause <vm> / vm_unpause <vm>   freeze the guest in RAM / thaw it   (PUT .../virtualmachineinstances/<vm>/pause)
#   vm_stop <vm> / vm_start <vm>      shut down / boot                     (patch the VM's spec.runStrategy)
_vmi_subresource() {
  echo '{}' | kubectl replace --raw \
    "/apis/subresources.kubevirt.io/v1/namespaces/${3:-$LAB_NS}/virtualmachineinstances/$2/$1" -f - >/dev/null && echo "$1: $2"
}
vm_pause()   { _vmi_subresource pause "$1" "$2"; }
vm_unpause() { _vmi_subresource unpause "$1" "$2"; }
vm_stop()    { kubectl patch vm "$1" -n "${2:-$LAB_NS}" --type merge -p '{"spec":{"runStrategy":"Halted"}}'; }
vm_start()   { kubectl patch vm "$1" -n "${2:-$LAB_NS}" --type merge -p '{"spec":{"runStrategy":"Always"}}'; }

# The VM's serial console output (what you'd see on a physical server's screen during boot)
vm_console_log() { kubectl logs -n "${2:-$LAB_NS}" "$(vm_pod "$1" "$2")" -c guest-console-log "${@:3}"; }

# The virt-launcher pod running a VM:   vm_pod <vm> [namespace]
vm_pod() {
  kubectl get pods -n "${2:-$LAB_NS}" -l "vm.kubevirt.io/name=$1" --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}'
}

# Wait until a VM reports Running:   wait_vm <vm> [namespace]
wait_vm() {
  local start=$SECONDS
  until [ "$(kubectl get vm "$1" -n "${2:-$LAB_NS}" -o jsonpath='{.status.printableStatus}' 2>/dev/null)" = Running ]; do
    printf "\r  %s: %-20s %3ss" "$1" "$(kubectl get vm "$1" -n "${2:-$LAB_NS}" -o jsonpath='{.status.printableStatus}' 2>/dev/null)" $((SECONDS - start))
    sleep 2
  done
  printf "\r  %s: Running after %ss%-20s\n" "$1" $((SECONDS - start)) ""
}

lab_ns() { kubectl get ns "$LAB_NS" >/dev/null 2>&1 || kubectl create ns "$LAB_NS" >/dev/null; }
lab_reset() { kubectl delete ns "$LAB_NS" --ignore-not-found --wait=true; }

# SSH to the AWS node
node_ssh() { ssh -i "$NODE_SSH_KEY" -o StrictHostKeyChecking=accept-new ubuntu@"$NODE_IP" "$@"; }

# SSH into the Omarchy VM as the omarchy user (keeps a port-forward to its sshd on local port 2223)
omarchy_ssh() {
  if ! nc -z 127.0.0.1 2223 2>/dev/null; then
    kubectl port-forward -n omarchy-spike "$(vm_pod omarchy omarchy-spike)" 2223:22 >/dev/null 2>&1 &
    for _ in $(seq 1 20); do nc -z 127.0.0.1 2223 2>/dev/null && break; sleep 0.5; done
  fi
  ssh -q -i "$OMARCHY_DIR/spike_key" -p 2223 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null omarchy@127.0.0.1 "$@"
}

# Stop every port-forward the labs started
lab_stop_forwards() { pkill -f "^kubectl port-forward" && echo "port-forwards stopped" || true; }

# Walkthrough helpers: step prints a heading and waits for Enter (set LAB_AUTO=1 to run straight through),
# run echoes a command before running it so you can copy it later
step() { printf "\n\033[1;36m== %s\033[0m\n" "$*"; [ -n "$LAB_AUTO" ] || read -r -p "   (Enter to continue) " _; }
run() { printf "\033[2m\$ %s\033[0m\n" "$*"; eval "$@"; }
note() { printf "\033[33m   %s\033[0m\n" "$*"; }
now() { python3 -c 'import time; print(time.time())'; }
since() { python3 -c "import time; print(f'{time.time() - $1:.2f}s')"; }
