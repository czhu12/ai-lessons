# Source this before any lab:   source labs/env.sh   (from books/canine/computer-use)
# Points kubectl at one agent computer's cluster and adds helpers for talking to its computer-use server.

export LABS="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
[ -f "$LABS/.local.env" ] && source "$LABS/.local.env"   # optional: CANINE_DIR
[ -f "$LABS/.secrets/computer.env" ] || { echo "Run labs/fetch-access.rb first (see the setup page)" >&2; return 1 2>/dev/null || exit 1; }
source "$LABS/.secrets/computer.env"                       # COMPUTER_ID, NAMESPACE, VM
export COMPUTER_ID NAMESPACE VM
export KUBECONFIG="$LABS/.secrets/kubeconfig"
export CANINE_DIR="${CANINE_DIR:-$HOME/Documents/Github/canine}"
export CU_PORT=18000 SSH_PORT_LOCAL=2224                    # local ends of the two port-forwards

# The virt-launcher pod running the computer's VM
vm_pod() {
  kubectl get pods -n "$NAMESPACE" -l "vm.kubevirt.io/name=$VM" --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}'
}

# Keep a kubectl port-forward open from a local port to a port inside the VM:   forward <local> <remote>
forward() {
  nc -z 127.0.0.1 "$1" 2>/dev/null && return
  (kubectl port-forward -n "$NAMESPACE" "$(vm_pod)" "$1:$2" >/dev/null 2>&1 &)   # a subshell: backgrounds cleanly in bash and zsh
  for _ in $(seq 1 30); do nc -z 127.0.0.1 "$1" 2>/dev/null && return; sleep 0.5; done
  echo "port-forward to $2 didn't come up" >&2; return 1
}

# Call the computer-use server:   cu GET /status    cu POST /computer-use '{"action": "cursor_position"}'
# Prints the JSON reply with any base64 image replaced by its length, so screenshots don't flood the terminal.
cu() {
  forward "$CU_PORT" 8000 || return 1
  if [ -n "$3" ]; then
    curl -s -X "$1" "http://127.0.0.1:$CU_PORT$2" -H 'Content-Type: application/json' -d "$3"
  else
    curl -s -X "$1" "http://127.0.0.1:$CU_PORT$2"
  fi | jq -c 'if .image then .image = "<\(.image | length) base64 chars>" else . end'
}
# A computer-use action:   act '{"action": "left_click", "coordinate": [960, 540]}'
act() { cu POST /computer-use "$1"; }
# Save a screenshot (or a zoom, given a region) as a PNG:   shot out.png [left top right bottom]
shot() {
  forward "$CU_PORT" 8000 || return 1
  mkdir -p "$(dirname "$1")"
  local body='{"action": "screenshot"}'
  [ $# -eq 5 ] && body="{\"action\": \"zoom\", \"region\": [$2, $3, $4, $5]}"
  curl -s -X POST "http://127.0.0.1:$CU_PORT/computer-use" -H 'Content-Type: application/json' -d "$body" |
    jq -r .image | base64 -d > "$1" && echo "saved $1 ($(wc -c < "$1" | tr -d ' ') bytes)"
}

# SSH into the VM as the desktop user. vm_ssh_desktop runs a command inside the Hyprland session (with its
# WAYLAND_DISPLAY and HYPRLAND_INSTANCE_SIGNATURE), the way the computer-use server runs.
vm_ssh() {
  forward "$SSH_PORT_LOCAL" 22 || return 1
  ssh -q -i "$LABS/.secrets/ssh_key" -p "$SSH_PORT_LOCAL" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    omarchy@127.0.0.1 "$@"
}
vm_ssh_desktop() {
  vm_ssh "eval \"\$(systemctl --user show-environment | grep -E '^(WAYLAND_DISPLAY|HYPRLAND_INSTANCE_SIGNATURE|XDG_RUNTIME_DIR)=' | sed 's/^/export /')\"; $*"
}

lab_stop_forwards() { pkill -f "^kubectl port-forward -n $NAMESPACE" && echo "port-forwards stopped" || true; }

# Walkthrough helpers: step prints a heading and waits for Enter (LAB_AUTO=1 runs straight through), run echoes a
# command before running it, note prints an explanation
step() { printf "\n\033[1;36m== %s\033[0m\n" "$*"; [ -n "$LAB_AUTO" ] || read -r -p "   (Enter to continue) " _; }
run() { printf "\033[2m\$ %s\033[0m\n" "$*"; eval "$@"; }
note() { printf "\033[33m   %s\033[0m\n" "$*"; }
