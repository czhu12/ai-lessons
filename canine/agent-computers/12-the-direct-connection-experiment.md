*Chapter 12 of 15*

# The direct-connection experiment (and why we rolled it back)

## The idea

Skip Canine and the Kubernetes API tunnel: browser → **Traefik ingress** on the node (443) → a Service → the
launcher pod → Selkies.

## The authentication problem

Selkies has no auth of its own (we disabled basic auth). If traffic doesn't go through Canine, something else must
decide who's allowed in. The design we sketched:

1. Canine checks access and signs a **short-lived ticket** (ES256 JWT: computer id, user, 60 s expiry, single-use id)
   with a **private** key.
2. The browser opens `https://c12.<cluster-domain>/?ticket=...`.
3. Traefik's **ForwardAuth** middleware asks a tiny in-cluster **gatekeeper** about every request. The gatekeeper
   holds only Canine's **public** key: it can verify tickets but never mint them (a compromised cluster can't forge
   access elsewhere). It swaps a valid ticket for an HttpOnly session cookie (HMAC-signed) and redirects to strip
   the ticket from the URL.
4. A NetworkPolicy lets only Traefik reach port 8080.

Web-platform problems it runs into:
- **Third-party cookies in iframes.** The desktop iframe (`c12.…sslip.io`) is a different site from Canine
  (`localhost:3000` or your prod domain). Its cookie is third-party → blocked or restricted by browsers. Fixes:
  put both under one registrable domain (`canine.example.com` + `c12.computers.canine.example.com` → same-site),
  or `Partitioned` (CHIPS) cookies, or open the desktop in a top-level tab.
- **HTTPS required** (secure context for Selkies; `Secure` required for `SameSite=None` cookies).
- **Revocation** with stateless cookies needs short lifetimes or a revocation signal.

## What we actually tested

To measure before building all that, we exposed Omarchy's Selkies at `https://c12.<aws-node-ip-dashed>.sslip.io`:
- **sslip.io**: a public DNS service where any name containing an IP resolves to that IP — no DNS setup needed.
- **cert-manager + Let's Encrypt** (HTTP-01 challenge on port 80, which must be open to the internet) for a real
  certificate. Canine's cluster setup already installs cert-manager with a `letsencrypt` ClusterIssuer.
- An IP allow-list first — failed because (a) k3s's built-in load balancer hides client IPs unless the Traefik
  Service uses `externalTrafficPolicy: Local` (set via a k3s `HelmChartConfig`), and (b) the browser's traffic
  exited via Cloudflare anyway. Switched to Traefik **basic auth**.
- Within minutes, bots were scanning the hostname (`/.env`, `/.git/config`, `/graphql`…). Anything you expose
  gets probed immediately; nothing can be unauthenticated.

## Outcome

Not noticeably faster, far more moving parts (DNS, certs, gatekeeper, cookies, public exposure). **Rolled back:**
test Ingress/Service/middleware/certificate/secrets deleted, access log disabled, prototype files and the
`direct_host` migration removed (migration properly rolled back with `db:migrate:down` first). Kept: Traefik's
`externalTrafficPolicy: Local` (harmless, preserves client IPs).

The takeaway is a good engineering habit: **prototype the cheapest version that answers the question** (here, "is
the proxy path the bottleneck?") before building the production design.

✅ **Check yourself:** Why is asymmetric signing (private key in Canine, public key in the cluster) better than a
shared secret here? Why do iframes make cookie-based auth harder?

---

← [Latency: where the time actually goes](11-latency.md) · [Index](README.md) · [Debugging war stories](13-debugging-war-stories.md) →
