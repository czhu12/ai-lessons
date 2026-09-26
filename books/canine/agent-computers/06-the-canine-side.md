# The Canine side: agent computers

## Data model

`AgentComputer` (`app/models/agent_computer.rb`, table `agent_computers`):

| Column | Meaning |
|---|---|
| `name` | Unique **per cluster**; same format rule as project names (`[a-z0-9-]`) |
| `namespace` | `computer-<name>`, assigned on create (Omarchy's record was patched to `omarchy-spike`) |
| `status` | enum: pending, provisioning, running, stopped, failed, destroying |
| `desktop` | `"selkies"` (stream from inside the guest) or `"vnc"` (the VM's own screen via KubeVirt) |
| `cluster_id`, `account_user_id` | where it runs and who owns it |

It `include`s `Namespaced`, so a computer's namespace **counts against** the cluster's namespace list alongside
projects and add-ons (no two things can grab the same namespace). Constants: 2 vCPU, 4Gi RAM, 40Gi disk,
`DESKTOP_PORT = 8080`, `COMPUTER_SERVER_PORT = 8000`.

Migrations from this work (all uncommitted):
- `20260922233000` unique index on (cluster_id, name)
- `20260922234500` namespace column
- `20260924050000` drop the old proxy tokens table; rename `sandboxes` → `agent_computers`
- `20260925220000` `desktop` column (default `"selkies"`)

(`20260926030000 direct_host` was created for the routing experiment, ran, and was **rolled back and deleted**.)

## Lifecycle jobs (GoodJob)

```
create (controller) ──► ProvisionJob
                          1. BuildImageJob.perform_now  (no-op if the golden image exists)
                          2. apply Namespace computer-<name>
                          3. apply NetworkPolicy (deny ingress except from the image namespace, for CDI cloning)
                          4. apply clone ClusterRole + RoleBinding (let this namespace clone the golden image)
                          5. apply VirtualMachine (dataVolumeTemplates → clone from DataSource)
                          6. poll until printableStatus == "Running"  (15 min timeout, 3 min grace for stale Failure)
                          7. running!

destroy (controller) ──► DestroyJob
                          delete namespace (takes the VM, disk, everything) + the clone RoleBinding
                          destroy the DB row
```

Things worth studying in `app/jobs/agent_computers/provision_job.rb`:
- **Why a NetworkPolicy:** Selkies and the computer server have *no authentication of their own*. Anything inside
  the cluster that could reach the VM's pod IP could control the desktop. The policy blocks all in-cluster ingress.
  `kubectl port-forward` goes through the kubelet into the pod's network namespace, so it **isn't** subject to
  NetworkPolicy — Canine still gets in.
- **Why the grace period:** a VM can briefly show a stale `Failure` condition from an earlier attempt (e.g. before
  the clone permission existed); KubeVirt retries with backoff, so we don't trust a Failure in the first 3 minutes.
- **Cross-namespace cloning RBAC:** CDI checks whether the *target namespace's service accounts* may create
  `datavolumes/source` in the *source* namespace. We grant that per computer with a RoleBinding to the group
  `system:serviceaccounts:computer-<name>`.

## The proxy: `lib/agent_computer_proxy.rb`

This is the heart of "use it from Canine". It's **Rack middleware**, so it sees every request before Rails routing.

Paths:
- `/agent_computers/:id/proxy/*` → guest port **8080** (Selkies: page, assets, `/api/websockets`)
- `/agent_computers/:id/api/*` → guest port **8000** (computer server: `/cmd`, `/ws`, `/status`, `/commands`)
- `/agent_computers/:id/vnc` → KubeVirt's VNC subresource (WebSocket relay, no port-forward)

Request flow:

1. **Authenticate:** read the Warden user from the Rails session; load the computer; check the user belongs to the
   computer's account; cache that decision for 60 s.
2. **Get a local port:** keep one `kubectl port-forward` process per (computer, remote port), on a random local
   port in 18000–19000. It writes a temp kubeconfig, finds the launcher pod by label `vm.kubevirt.io/name`, spawns
   `kubectl port-forward`, waits up to 5 s for the port to open, and reuses it until it dies.
3. **HTTP:** re-issue the request with `Net::HTTP` to `127.0.0.1:<local port>` and return the response.
4. **WebSocket:** `rack.hijack` the raw client socket, open a TCP socket to the local port, **replay the upgrade
   request** (with `Host` and `Origin` rewritten), forward the `101 Switching Protocols` back, then shovel bytes
   both ways in a thread (`IO.select` + `read_nonblock`). No frame parsing — it's a byte pipe.

Worth knowing: `proxy_bidirectional` ends the connection after **60 s with no traffic in either direction**. Selkies
streams constantly so it's fine; an idle agent WebSocket on `/api/ws` would be dropped and must reconnect.

## The VNC relay: `lib/kubevirt_vnc_relay.rb`

For `desktop: "vnc"` computers, the browser runs **noVNC** (`app/javascript/controllers/vnc_viewer_controller.js`,
package `@novnc/novnc`), which speaks VNC over a WebSocket. The relay:
- hijacks the browser's WebSocket,
- opens a **second** WebSocket, as a client, to the Kubernetes API:
  `wss://<api>/apis/subresources.kubevirt.io/v1/namespaces/<ns>/virtualmachineinstances/<vm>/vnc`,
  authenticating with the cluster kubeconfig's client certificate or bearer token,
- and copies messages between the two.

A bug worth remembering: the `websocket-driver` gem decides "am I the server side?" by checking whether the socket
object responds to `#env`. Our shared adapter had `env`, so the *client* connection behaved like a server. Fix:
separate `ClientAdapter` and `ServerAdapter` classes.

VNC shows the VM's **virtual monitor**, which needs nothing inside the guest. We used it to watch Omarchy install;
it's slower and lower quality than Selkies, so Selkies is the default.

## Views and UI

- `connect.html.erb` — full-window Selkies `<iframe src="/agent_computers/:id/proxy/">`, no Canine toolbar, a small
  reconnect overlay driven by a 5 s health check; or the noVNC viewer if `desktop == "vnc"`.
- `control.html.erb` + `computer_control_controller.js` — a proof-of-concept panel for calling the agent API.
- `show.html.erb` + `stats.html.erb` — overview with live stats (loaded lazily in a turbo frame) and copy-paste
  `kubectl` commands.
- `AgentComputers::Stats` — VM status, launcher pod CPU/memory (metrics-server), guest filesystems, and port
  probes (from inside the launcher pod to the guest).

## Cluster packages

- `config/system_packages.yml` has a `kubevirt` entry; `ClusterPackage::Installer::KubeVirt` replaced the old
  `agent-sandbox` installer.
- `Cluster` checks for the `kubevirt` package to decide whether agent computers are available on a cluster
  (`with_agent_computer` scope used by the "new computer" form).

**Bug fixed this session:** the install job runs kubectl through `Cli::RunAndLog`, which streams output to the
cluster's log page and returns a **`Process::Status`**, not the output string. The KubeVirt installer called
`.split` / `.include?` on that — `undefined method 'split' for an instance of Process::Status`. Fix: the two
read-only checks (`deployed?`, `ensure_kvm!`) use a separate `K8::Kubectl.new(connection)` whose default runner
returns output (`output_reader` helper).

Lesson: in this codebase, **the runner decides what `kubectl.(...)` returns**. `Cli::RunAndReturnOutput` → string;
`Cli::RunAndLog` → exit status. Always check which one you were handed before parsing the result.

✅ **Check yourself:** Trace a WebSocket frame from your browser to Selkies through `AgentComputerProxy`. What
rewrites happen? Why is the NetworkPolicy safe to apply even though Canine needs to reach the VM?

