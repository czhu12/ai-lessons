#!/usr/bin/env bash
# Lab 9 walkthrough: be the AI agent. Drive an agent computer (Ubuntu + XFCE image, cluster 33 "desk-2" by default)
# through the computer server's JSON API: see the screen, run commands, find and type into a window, read the
# accessibility tree, and hit the takeover lock.
#   ./run.sh [agent computer id]      (default 10 = desk-2)
source "$(dirname "$0")/../env.sh"
cd "$(dirname "$0")"
ID=${1:-10}
A() { ruby agent.rb "$@"; }
jq_py() { python3 -c "import json,sys; d=json.load(sys.stdin); $1"; }

step "1. Get the computer's cluster credentials from Canine and port-forward the computer server (guest :8000)"
mkdir -p "$LABS/.kube"
( cd "$CANINE_DIR" && bin/rails runner "
    c = AgentComputer.find($ID)
    File.write('$LABS/.kube/computer-$ID.yml', K8::Connection.new(c.cluster, c.user).kubeconfig.to_yaml)
    File.write('$LABS/.kube/computer-$ID.env', \"NS=#{c.namespace}\nVM=#{c.name}\n\")" 2>/dev/null )
chmod 600 "$LABS/.kube/computer-$ID.yml"
export KUBECONFIG="$LABS/.kube/computer-$ID.yml"; source "$LABS/.kube/computer-$ID.env"
kubectl port-forward -n "$NS" "$(vm_pod "$VM" "$NS")" 18000:8000 >/dev/null 2>&1 & disown
until nc -z 127.0.0.1 18000 2>/dev/null; do sleep 0.5; done
run "curl -s localhost:18000/status | python3 -m json.tool"

step "2. What can an agent do? The command catalogue"
run "curl -s localhost:18000/commands | jq_py 'print(len(d[\"commands\"]), \"commands:\", \", \".join(sorted(d[\"commands\"])))'"

step "3. See the screen (pixels): the first thing a computer-use model asks for"
run A screenshot
[ -n "$LAB_AUTO" ] || open /tmp/agent-screenshot.png

step "4. Run a shell command in the VM (stdin closed so launched programs can't hang it)"
run "A run_command '{\"command\": \"whoami; uname -r; df -h / | tail -1\"}' | jq_py 'print(d[\"stdout\"])'"

step "5. Windows: list them and launch an editor on a scratch file"
run "A list_windows | jq_py '[print((\"* \" if w[\"active\"] else \"  \") + w[\"title\"]) for w in d[\"windows\"]]'"
PID=$(A launch '{"app": "mousepad", "args": ["/tmp/agent-lab.txt"]}' | jq_py 'print(d["pid"])')
echo "   launched mousepad, pid $PID"
sleep 3

step "6. Read the UI as structure: the accessibility tree (AT-SPI)"
run "A find_element '{\"app\": \"mousepad\", \"role\": \"menu\"}' | jq_py 'print([(e[\"name\"], e.get(\"bounds\")) for e in d[\"elements\"]][:3], \"...\")'"
note "Every visible control has a role, a name and screen bounds. No image recognition needed to find 'File'."
DIALOG=$(A find_element '{"app": "mousepad", "role": "alert"}' | jq_py 'print(len(d["elements"]))')
if [ "$DIALOG" != 0 ]; then
  run "A find_element '{\"app\": \"mousepad\", \"role\": \"label\"}' | jq_py '[print(\" \", e[\"name\"]) for e in d[\"elements\"]]'"
  run "A find_element '{\"app\": \"mousepad\", \"role\": \"push button\"}' | jq_py 'print([e[\"name\"] for e in d[\"elements\"]])'"
  note "Mousepad is asking a question (it wasn't closed cleanly last time). Answer it by NAME, no pixels needed:"
  run "A click_element '{\"app\": \"mousepad\", \"role\": \"push button\", \"name\": \"No\"}'"
  sleep 2
else
  note "No dialog this time. (If Mousepad was ever killed mid-edit, it asks to restore the session; the lab then"
  note "reads the question and clicks 'No' by name.)"
fi

step "7. Focus the editor and type, ONLY after confirming it's the active window"
for _ in $(seq 1 20); do
  WIN=$(A list_windows | jq_py "print(next((w['id'] for w in d['windows'] if w['pid'] == $PID and 'Mousepad' in w['title']), ''))")
  [ -n "$WIN" ] && break; sleep 0.5
done
A activate_window "{\"id\": $WIN}" >/dev/null
run "A list_windows | jq_py 'print([w[\"title\"] for w in d[\"windows\"] if w[\"active\"]])'"
ACTIVE=$(A list_windows | jq_py "print(any(w['active'] and w['pid'] == $PID for w in d['windows']))")
if [ "$ACTIVE" = True ]; then
  run "A type_text '{\"text\": \"Hello from the agent API. Typed with xdotool via XTest.\"}'"
else
  note "mousepad isn't the active window, so not typing (never type blind into whatever has focus)."
fi
note "Now read it back WITHOUT a screenshot: editable text is exposed in the accessibility tree."
run "A find_element '{\"app\": \"mousepad\", \"role\": \"text\"}' | jq_py 'print([e.get(\"text\") for e in d[\"elements\"] if e.get(\"text\")] if d[\"success\"] else \"error: \" + d[\"error\"])'"
note "KNOWN BUG, found while building this lab: accessibility.py calls text.get_text(0, n) on the object the"
note "GObject bindings return, which fails. Fix: Atspi.Text.get_text(text, 0, n). Until then, reading editable"
note "text via the tree errors, but roles, names, bounds and clicks (step 6) work."
run A screenshot
[ -n "$LAB_AUTO" ] || open /tmp/agent-screenshot.png

step "8. Save and close the window cleanly (so the next run doesn't get the 'previous session' question)"
[ "$ACTIVE" = True ] && run "A hotkey '{\"keys\": [\"ctrl\", \"s\"]}'"
sleep 1
run "A close_window '{\"id\": $WIN}'"
sleep 1
run "A run_command '{\"command\": \"cat /tmp/agent-lab.txt; echo; rm -f /tmp/agent-lab.txt; pgrep -x mousepad || echo mousepad closed\"}' | jq_py 'print(d[\"stdout\"])'"

step "9. The takeover lock (manual): open desk-2's connect page in Canine, wiggle the mouse, then run:"
run "A takeover_status"
note "Now, within 5 seconds of moving the mouse in the browser, try:  ruby agent.rb left_click '{\"x\": 5, \"y\": 5}'"
note "It's refused with \"takeover\": true until you've been idle for 5s. Read-only commands (screenshot) still work."

step "10. Clean up"
pkill -f "^kubectl port-forward -n $NS" && echo "port-forward stopped"
