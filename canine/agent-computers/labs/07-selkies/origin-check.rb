# Sends raw WebSocket upgrade requests to Selkies with different Origin headers and prints the response status.
# This is the check that made Canine's proxy fail with 403 until it rewrote Origin (lib/agent_computer_proxy.rb).
#   ruby origin-check.rb 18088
require "socket"
require "base64"
require "securerandom"

port = Integer(ARGV.fetch(0, "18088"))

def upgrade(port, origin)
  socket = TCPSocket.new("127.0.0.1", port)
  request = +"GET /api/websockets HTTP/1.1\r\n"
  request << "Host: 127.0.0.1:#{port}\r\n"
  request << "Upgrade: websocket\r\nConnection: Upgrade\r\n"
  request << "Sec-WebSocket-Key: #{Base64.strict_encode64(SecureRandom.random_bytes(16))}\r\n"
  request << "Sec-WebSocket-Version: 13\r\n"
  request << "Origin: #{origin}\r\n" if origin
  request << "\r\n"
  socket.write(request)
  status = socket.gets.to_s.strip
  socket.close
  status
rescue Errno::ECONNRESET, EOFError
  "(connection reset)"
end

[
  [ "http://127.0.0.1:#{port}", "same origin as the Host header (what the proxy now sends)" ],
  [ "http://localhost:3000", "Canine's origin, forwarded unchanged (the original bug)" ],
  [ "https://evil.example", "some other website trying to connect" ],
  [ nil, "no Origin header at all (curl, scripts)" ]
].each do |origin, meaning|
  printf "%-32s %-28s %s\n", (origin || "(none)"), upgrade(port, origin), meaning
end
