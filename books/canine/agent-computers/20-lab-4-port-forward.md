# Lab 4: Port-forward and masquerade networking

**Goal:** understand the one trick Canine's whole proxy is built on, and why the NetworkPolicy that locks agent
computers down doesn't lock Canine out. **Time:** 3 minutes.
**Chapters:** [KubeVirt → networking](03-kubevirt.md), [The Canine side](06-the-canine-side.md).

```bash
./labs/04-port-forward/run.sh
```

A VM runs a tiny web server on port 8080 **inside the guest** (the same port Selkies uses). Then:

1. Compare the pod's IP with what the guest thinks its IP is (`10.0.2.2`).
2. `kubectl port-forward` to the **launcher pod** → `curl localhost:18080` answers from inside the guest.
3. From another pod in the cluster, through a Service → HTTP 200.
4. Apply a deny-all-ingress NetworkPolicy (like Canine's) → in-cluster HTTP 000, **port-forward still 200**.

## Questions

**Q: The guest says its address is 10.0.2.2, but the pod's IP is 10.42.x.x. Who's right?**

<details>
<summary>Answer</summary>

Both. With masquerade networking the guest sits on a private network inside the launcher pod; KubeVirt NATs traffic between the pod's IP and the guest. Everything outside only ever sees the pod IP.

</details>

**Q: Why does port-forward still work after the NetworkPolicy blocks all ingress?**

<details>
<summary>Answer</summary>

NetworkPolicy filters traffic arriving over the pod network. `kubectl port-forward` goes client → API server → kubelet, and the kubelet connects from inside the pod's network namespace, so it never crosses the filtered path.

</details>

**Q: Why does Canine want exactly this combination?**

<details>
<summary>Answer</summary>

Selkies and the computer server have no authentication of their own. The policy stops every other pod in the cluster from reaching them, while Canine, which authenticates the user first, reaches them via port-forward.

</details>


## Expected output

<details>
<summary>📜 Expected output (a real run, captured while building the lab)</summary>

```text
== 1. Boot a VM whose guest runs a web server on :8080, plus a Service in front of it
$ kubectl apply -f web-vm.yaml
virtualmachine.kubevirt.io/web created
service/web created

  web: Running after 5s
   guest web server is up

== 2. Two different IPs: the pod's (on the cluster network) and the guest's (private, behind NAT inside the pod)
$ kubectl get pod virt-launcher-web-c8wqs -n lab -o jsonpath='pod IP: {.status.podIP}'; echo
pod IP: 10.42.0.98
$ curl -s localhost:18080 | sed 's/<[^>]*>/ /g' | tr -s ' '
 Hello from inside the VM
 guest hostname: web
 guest addresses (what the VM thinks its IP is):
 lo 127.0.0.1/8
enp1s0 10.0.2.2/24
   The guest thinks it's 10.0.2.2 (on enp1s0). KubeVirt's masquerade NATs the pod IP's ports to it.

== 3. kubectl port-forward to the launcher pod reached port 8080 INSIDE THE GUEST
   That curl went: your Mac -> Kubernetes API (:6443) -> kubelet -> pod network namespace -> NAT -> guest.
   AgentComputerProxy does exactly this for Selkies (8080) and the computer server (8000).

== 4. From inside the cluster, through the Service (what any other pod could do)
$ in_cluster_curl
HTTP 200

== 5. Lock it down the way Canine does: deny all ingress in the namespace
$ kubectl apply -f deny-ingress.yaml
networkpolicy.networking.k8s.io/deny-all-ingress created
$ in_cluster_curl
HTTP 000
   HTTP 000 = connection timed out: other pods can no longer reach the VM.
$ curl -s -o /dev/null -w 'port-forward: HTTP %{http_code}\n' localhost:18080
port-forward: HTTP 200
   port-forward still works: it doesn't come in over the pod network, so NetworkPolicy doesn't apply to it.
   That's why Canine can reach an agent computer's unauthenticated Selkies while nothing else in the cluster can.

== 6. Clean up
$ kubectl delete -f web-vm.yaml -f deny-ingress.yaml
virtualmachine.kubevirt.io "web" deleted
service "web" deleted
networkpolicy.networking.k8s.io "deny-all-ingress" deleted
```

</details>


## Try next

- `kubectl get pod <launcher> -n lab -o yaml | grep -A3 ports`: no ports are declared, yet 8080 works. Masquerade
  forwards everything unless you list ports on the VM's interface.
- Read `build_network_policy_yaml` in `app/jobs/agent_computers/provision_job.rb` and find the one namespace it still
  allows, and why.

