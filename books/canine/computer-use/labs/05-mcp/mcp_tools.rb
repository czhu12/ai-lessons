# Calls Canine's computer-use MCP tools the way the /mcp endpoint does when Claude Code calls them: Tool.call with a
# server_context holding the signed-in user. Run from the Canine repo:
#   bin/rails runner <labs>/05-mcp/mcp_tools.rb <computer id>
computer = AgentComputer.find(ARGV.fetch(0))
context = { user_id: computer.user.id }   # /mcp builds this from the OAuth token

# Show a tool response compactly: images by type and size, text as-is (cut short)
def show(response, seconds)
  parts = response.content.map do |part|
    part[:type] == "image" ? "[image #{part[:mimeType]}, #{part[:data].size} base64 chars]" : part[:text].truncate(220)
  end
  puts "   #{response.error? ? "ERROR " : ""}#{parts.join(" + ")}   (#{seconds.round(2)}s)"
end

def call(label, tool, **args)
  puts "#{tool.name_value}(#{args.except(:server_context).map { |k, v| "#{k}: #{v.inspect}" }.join(", ")})  # #{label}"
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  response = tool.call(**args)
  show(response, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
  response
end

case ARGV[1]
when "schemas"
  [ Tools::ListAgentComputers, Tools::ComputerScreenshot, Tools::ComputerAction, Tools::ComputerAccessibility ].each do |tool|
    schema = tool.to_h
    puts "#{schema[:name]}: #{schema[:description].truncate(110)}"
    puts "   inputs: #{(schema[:inputSchema][:properties]&.keys || []).join(", ")}   (required: #{schema[:inputSchema][:required]&.join(", ") || "none"})"
  end
when "calls"
  id = computer.id
  call("which computers can I use?", Tools::ListAgentComputers, server_context: context)
  call("what's on screen?", Tools::ComputerScreenshot, agent_computer_id: id, server_context: context)
  call("where's the mouse?", Tools::ComputerAction, agent_computer_id: id, action: "cursor_position", server_context: context)
  call("move it", Tools::ComputerAction, agent_computer_id: id, action: "mouse_move", coordinate: [ 400, 300 ], server_context: context)
  call("look closely at the top bar", Tools::ComputerAction, agent_computer_id: id, action: "zoom", region: [ 0, 0, 320, 25 ], server_context: context)
  call("which apps have a tree?", Tools::ComputerAccessibility, agent_computer_id: id, operation: "tree", max_depth: 0, server_context: context)
  call("a mistake", Tools::ComputerAction, agent_computer_id: id, action: "left_click", coordinate: [ 99999, 0 ], server_context: context)
  call("someone else's (or no) computer", Tools::ComputerScreenshot, agent_computer_id: -1, server_context: context)
end
