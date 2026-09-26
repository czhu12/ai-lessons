# A 60-line version of Canine's AgentComputerProxy (lib/agent_computer_proxy.rb), minus Rails and kubectl.
# It fronts a Selkies you've port-forwarded to UPSTREAM_PORT, and shows the three things the real one does:
#   1. authentication before anything reaches the desktop (here: a cookie set by /login?password=lab)
#   2. plain HTTP forwarding (the Selkies page, JS, CSS)
#   3. WebSocket passthrough via rack.hijack: replay the upgrade, then shovel raw bytes both ways
# REWRITE_ORIGIN=0 turns off the Origin rewrite so you can reproduce the 403 that broke Canine's connect page.
require "socket"
require "net/http"

UPSTREAM_PORT = Integer(ENV.fetch("UPSTREAM_PORT", "18088"))
REWRITE_ORIGIN = ENV.fetch("REWRITE_ORIGIN", "1") == "1"

class MiniProxy
  def call(env)
    req = Rack::Request.new(env)
    if req.path == "/login"
      return [ 403, {}, [ "wrong password\n" ] ] unless req.params["password"] == "lab"
      return [ 302, { "location" => "/", "set-cookie" => "lab_session=ok; Path=/; HttpOnly" }, [] ]
    end
    return [ 401, { "content-type" => "text/plain" }, [ "Log in first: /login?password=lab\n" ] ] unless req.cookies["lab_session"] == "ok"

    env["HTTP_UPGRADE"]&.casecmp?("websocket") ? websocket(env, req) : http(env, req)
  end

  private

  def http(env, req)
    upstream = Net::HTTP.get_response(URI("http://127.0.0.1:#{UPSTREAM_PORT}#{req.fullpath}"))
    headers = upstream.to_hash.except("transfer-encoding", "connection").transform_values { |v| v.join(", ") }
    [ upstream.code.to_i, headers, [ upstream.body.to_s ] ]
  end

  def websocket(env, req)
    env["rack.hijack"].call
    client = env["rack.hijack_io"]
    upstream = TCPSocket.new("127.0.0.1", UPSTREAM_PORT)

    head = +"GET #{req.fullpath} HTTP/1.1\r\n"
    env.each do |key, value|
      next unless key.start_with?("HTTP_") && !%w[HTTP_HOST HTTP_ORIGIN HTTP_COOKIE].include?(key)
      head << "#{key.delete_prefix("HTTP_").split("_").map(&:capitalize).join("-")}: #{value}\r\n"
    end
    head << "Host: 127.0.0.1:#{UPSTREAM_PORT}\r\n"
    origin = REWRITE_ORIGIN ? "http://127.0.0.1:#{UPSTREAM_PORT}" : env["HTTP_ORIGIN"]
    head << "Origin: #{origin}\r\n" if origin
    upstream.write(head + "\r\n")
    warn "[mini-proxy] WebSocket #{req.path} Origin sent upstream: #{origin.inspect}"

    [ [ client, upstream ], [ upstream, client ] ].each do |from, to|
      Thread.new do
        loop { to.write(from.readpartial(16_384)) }
      rescue IOError, SystemCallError
        [ client, upstream ].each { |io| io.close rescue nil }
      end
    end
    [ -1, {}, [] ]
  end
end

run MiniProxy.new
