#!/usr/bin/env bash
# Lab 4 walkthrough: masquerade networking, kubectl port-forward into a guest (Canine's core trick), and why the
# NetworkPolicy that locks agent computers down doesn't lock Canine out.
source "$(dirname "$0")/../env.sh"
cd "$(dirname "$0")"
in_cluster_curl() {   # fetch the Service from a throwaway pod inside the cluster
  local name="curl-$RANDOM"
  kubectl run "$name" -n lab --restart=Never --image=curlimages/curl:8.11.1 --command -- \
    curl -s -m 5 -o /dev/null -w "HTTP %{http_code}\n" http://web.lab.svc >/dev/null
  until [[ "$(kubectl get pod -n lab "$name" -o jsonpath='{.status.phase}' 2>/dev/null)" =~ ^(Succeeded|Failed)$ ]]; do sleep 1; done
  kubectl logs -n lab "$name"
  kubectl delete pod -n lab "$name" --wait=false >/dev/null
}

step "1. Boot a VM whose guest runs a web server on :8080, plus a Service in front of it"
lab_ns
run kubectl apply -f web-vm.yaml
wait_vm web
start=$SECONDS; until vm_console_log web 2>/dev/null | grep -q WEB_READY; do sleep 3; [ $((SECONDS - start)) -gt 240 ] && break; done
echo "   guest web server is up"

POD=$(vm_pod web)
step "2. Two different IPs: the pod's (on the cluster network) and the guest's (private, behind NAT inside the pod)"
run "kubectl get pod $POD -n lab -o jsonpath='pod IP: {.status.podIP}'; echo"
kubectl port-forward -n lab "$POD" 18080:8080 >/dev/null 2>&1 & disown
sleep 3
run "curl -s localhost:18080 | sed 's/<[^>]*>/ /g' | tr -s ' '"
note "The guest thinks it's 10.0.2.2 (on enp1s0). KubeVirt's masquerade NATs the pod IP's ports to it."

step "3. kubectl port-forward to the launcher pod reached port 8080 INSIDE THE GUEST"
note "That curl went: your Mac -> Kubernetes API (:6443) -> kubelet -> pod network namespace -> NAT -> guest."
note "AgentComputerProxy does exactly this for Selkies (8080) and the computer server (8000)."

step "4. From inside the cluster, through the Service (what any other pod could do)"
run in_cluster_curl

step "5. Lock it down the way Canine does: deny all ingress in the namespace"
run kubectl apply -f deny-ingress.yaml
sleep 3
run in_cluster_curl
note "HTTP 000 = connection timed out: other pods can no longer reach the VM."
run "curl -s -o /dev/null -w 'port-forward: HTTP %{http_code}\n' localhost:18080"
note "port-forward still works: it doesn't come in over the pod network, so NetworkPolicy doesn't apply to it."
note "That's why Canine can reach an agent computer's unauthenticated Selkies while nothing else in the cluster can."

step "6. Clean up"
pkill -f "^kubectl port-forward -n lab $POD" || true
run kubectl delete -f web-vm.yaml -f deny-ingress.yaml
