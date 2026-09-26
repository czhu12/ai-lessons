*Lab page 8 of 9*

# Lab 8: Build the proxy yourself

**Goal:** understand `lib/agent_computer_proxy.rb` by running a 60-line version of it, and reproduce the Origin
bug that broke Canine's connect page. **Time:** 5 minutes. **Chapter:** [The Canine side](06-the-canine-side.md).

```bash
cat labs/08-mini-proxy/config.ru    # read it first, it's short
./labs/08-mini-proxy/run.sh
```

`config.ru` is a Rack app run by Puma on `localhost:4000` in front of Omarchy's Selkies:

1. **Auth first**: nothing reaches Selkies without the `lab_session` cookie (`/login?password=lab` sets it).
2. **HTTP**: re-issue the request upstream with `Net::HTTP`, return the response.
3. **WebSocket**: `rack.hijack` the raw socket, replay the upgrade request with `Host` (and optionally `Origin`)
   rewritten, then copy bytes both ways in two threads.

Step 2 opens the desktop in your browser through **your** proxy. Step 3 restarts it with `REWRITE_ORIGIN=0`: reload
the tab and watch the stream fail, exactly like the original bug.

## Questions

**Q: Why does the proxy need `rack.hijack` for WebSockets instead of returning a normal Rack response?**

<details>
<summary>Answer</summary>

A Rack response is one request → one response. A WebSocket is a long-lived two-way stream after the 101 handshake. Hijacking hands the raw TCP socket to your code so it can keep reading and writing for as long as the stream lives.

</details>

**Q: The proxy strips the browser's `Cookie` header before talking to Selkies. Why?**

<details>
<summary>Answer</summary>

The session cookie is for the proxy, not the upstream. Forwarding it would leak your Canine session to a program running inside a VM that the agent (or anything installed there) controls.

</details>

**Q: With REWRITE_ORIGIN=0 the HTTP page still loads but the stream doesn't. Why only the stream?**

<details>
<summary>Answer</summary>

Selkies only checks Origin on the WebSocket upgrade. Page, JS and CSS loads are plain GETs, so the UI appears, then the WebSocket is refused with 403 and it keeps trying to reconnect.

</details>


## Expected output

<details>
<summary>📜 Expected output (a real run, captured while building the lab)</summary>

```text
== 1. Port-forward Omarchy's Selkies to localhost:18088 (the upstream) and start the proxy on :4000
$ curl -s -o /dev/null -w 'without login: HTTP %{http_code}\n' localhost:4000/
without login: HTTP 401
$ curl -s -o /dev/null -w 'with the session cookie: HTTP %{http_code}\n' -H 'Cookie: lab_session=ok' localhost:4000/
with the session cookie: HTTP 200
   Auth happens in the proxy, before anything reaches the unauthenticated Selkies. Canine uses your Devise
   session (Warden) plus an account-membership check instead of a password.

== 2. Use it: open http://localhost:4000/login?password=lab in your browser -> the Omarchy desktop
$ ws_status
WebSocket through the proxy: HTTP/1.1 101 Switching Protocols
   101: the proxy replayed the upgrade with Origin rewritten to the upstream's own address.

== 3. Reproduce the bug: restart the proxy with REWRITE_ORIGIN=0 (forward the browser's Origin as-is)
$ ws_status
WebSocket through the proxy: HTTP/1.1 403 Forbidden
$ grep 'Origin sent upstream' /tmp/mini-proxy.log | tail -1
[mini-proxy] WebSocket /api/websockets Origin sent upstream: "http://localhost:4000"
   403: Selkies saw Origin http://localhost:4000 but Host 127.0.0.1:18088 and refused. In the browser the
   page loads but the stream never connects: exactly what Canine's connect page did before the fix.

== 4. Read the real thing: lib/agent_computer_proxy.rb, handle_websocket
$ grep -n 'HTTP_ORIGIN\|rack.hijack\|proxy_bidirectional\|port-forward' "$CANINE_DIR/lib/agent_computer_proxy.rb" | head -12
10:# via kubectl port-forward. Authenticates via Rails session.
54:  # No port-forward: KubevirtVncRelay talks to the cluster API directly
119:      # Start new port-forward
169:    # KubeVirt's launcher pod runs the VM; port-forwarding to it reaches ports inside the guest (masquerade networking)
179:    cmd = "KUBECONFIG=#{Shellwords.shellescape(kubeconfig_file.path)} kubectl port-forward -n #{Shellwords.shellescape(sandbox.namespace)} #{Shellwords.shellescape...
248:    log_error "HTTP proxy error: #{e.class} #{e.message} — clearing stale port-forward"
266:    env["rack.hijack"].call
267:    client_socket = env["rack.hijack_io"]
279:      next unless key.start_with?("HTTP_") && !%w[HTTP_HOST HTTP_ORIGIN].include?(key)
286:    upgrade_request += "Origin: http://127.0.0.1:#{local_port}\r\n" if env["HTTP_ORIGIN"]
320:      proxy_bidirectional(client_socket, upstream)
329:  def proxy_bidirectional(client, upstream)
   Same shape, plus: per-computer kubectl port-forwards started on demand and reused, a 60s auth cache,
   and reconnect handling when a port-forward dies.

== 5. Clean up
stopped proxy and port-forward
```

</details>


## Try next

- Add a log line with the number of bytes in each direction, then drag a window around: see how lopsided video is.
- Kill the port-forward while the tab is open and see what the browser does. What does Canine's proxy do in the same
  situation? (Look for `invalidate_port_forward`.)

---

← [Lab 7: Selkies up close](23-lab-7-selkies.md) · [Index](README.md) · [Lab 9: Be the agent](25-lab-9-agent-api.md) →
