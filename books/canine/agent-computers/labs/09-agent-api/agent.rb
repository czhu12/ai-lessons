# A 30-line "agent": sends one command to the computer server and prints the reply.
#   ruby agent.rb screenshot                   (saves the PNG, prints its size)
#   ruby agent.rb run_command '{"command": "uname -a"}'
# Talks to http://localhost:18000 (a port-forward to the VM's port 8000). Through Canine the same request goes to
# /agent_computers/:id/api/cmd with your browser session (API tokens are a TODO).
require "json"
require "net/http"
require "base64"

command = ARGV.fetch(0)
params = ARGV[1] ? JSON.parse(ARGV[1]) : {}
response = Net::HTTP.post(URI("http://localhost:18000/cmd"), { command: command, params: params }.to_json,
                          "Content-Type" => "application/json")
reply = JSON.parse(response.body)

if reply["image_data"]
  path = "/tmp/agent-#{command}.#{reply["format"] == "jpeg" ? "jpg" : "png"}"
  File.binwrite(path, Base64.decode64(reply.delete("image_data")))
  reply["saved_to"] = path
end
puts JSON.pretty_generate(reply)
