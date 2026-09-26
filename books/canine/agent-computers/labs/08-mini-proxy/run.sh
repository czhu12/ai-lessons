#!/usr/bin/env bash
# Lab 8 walkthrough: run your own mini proxy in front of Omarchy's Selkies and reproduce the Origin bug.
source "$(dirname "$0")/../env.sh"
cd "$(dirname "$0")"
CANINE="$CANINE_DIR"
POD=$(vm_pod omarchy omarchy-spike)
start_proxy() {   # start_proxy <REWRITE_ORIGIN 0|1>
  pkill -f "^puma.*tcp://127.0.0.1:4000" 2>/dev/null; sleep 1
  ( cd "$CANINE" && REWRITE_ORIGIN=$1 BUNDLE_GEMFILE="$CANINE/Gemfile" exec bundle exec puma -b tcp://127.0.0.1:4000 \
      "$LABS/08-mini-proxy/config.ru" ) > /tmp/mini-proxy.log 2>&1 &
  disown
  until nc -z 127.0.0.1 4000 2>/dev/null; do sleep 0.5; done
}
ws_status() {     # a browser-style WebSocket upgrade through the proxy, with Canine-like Origin
  ruby -rsocket -rbase64 -rsecurerandom -e '
    s = TCPSocket.new("127.0.0.1", 4000)
    s.write "GET /api/websockets HTTP/1.1\r\nHost: localhost:4000\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" \
            "Sec-WebSocket-Key: #{Base64.strict_encode64(SecureRandom.random_bytes(16))}\r\nSec-WebSocket-Version: 13\r\n" \
            "Origin: http://localhost:4000\r\nCookie: lab_session=ok\r\n\r\n"
    puts "WebSocket through the proxy: #{(s.gets || "(connection closed)").strip}"'
}

step "1. Port-forward Omarchy's Selkies to localhost:18088 (the upstream) and start the proxy on :4000"
kubectl port-forward -n omarchy-spike "$POD" 18088:8080 >/dev/null 2>&1 & disown
until nc -z 127.0.0.1 18088 2>/dev/null; do sleep 0.5; done
start_proxy 1
run "curl -s -o /dev/null -w 'without login: HTTP %{http_code}\n' localhost:4000/"
run "curl -s -o /dev/null -w 'with the session cookie: HTTP %{http_code}\n' -H 'Cookie: lab_session=ok' localhost:4000/"
note "Auth happens in the proxy, before anything reaches the unauthenticated Selkies. Canine uses your Devise"
note "session (Warden) plus an account-membership check instead of a password."

step "2. Use it: open http://localhost:4000/login?password=lab in your browser -> the Omarchy desktop"
[ -n "$LAB_AUTO" ] || open "http://localhost:4000/login?password=lab"
run ws_status
note "101: the proxy replayed the upgrade with Origin rewritten to the upstream's own address."

step "3. Reproduce the bug: restart the proxy with REWRITE_ORIGIN=0 (forward the browser's Origin as-is)"
start_proxy 0
run ws_status
run "grep 'Origin sent upstream' /tmp/mini-proxy.log | tail -1"
note "403: Selkies saw Origin http://localhost:4000 but Host 127.0.0.1:18088 and refused. In the browser the"
note "page loads but the stream never connects: exactly what Canine's connect page did before the fix."
[ -n "$LAB_AUTO" ] || { note "Reload the browser tab to see it fail."; read -r -p "   (Enter to continue) " _; }

step "4. Read the real thing: lib/agent_computer_proxy.rb, handle_websocket"
run "grep -n 'HTTP_ORIGIN\\|rack.hijack\\|proxy_bidirectional\\|port-forward' '$CANINE/lib/agent_computer_proxy.rb' | head -12"
note "Same shape, plus: per-computer kubectl port-forwards started on demand and reused, a 60s auth cache,"
note "and reconnect handling when a port-forward dies."

step "5. Clean up"
pkill -f "^puma.*tcp://127.0.0.1:4000"; pkill -f "^kubectl port-forward -n omarchy-spike $POD 18088"; echo "stopped proxy and port-forward"
