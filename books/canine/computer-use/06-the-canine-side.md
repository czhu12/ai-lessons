# The Canine side: from Claude to the VM

The server in the VM speaks HTTP on port 8000, and nothing outside the VM can reach it directly. This chapter follows
one tool call from Claude Code to that port and back.

## Connecting Claude Code to Canine

Canine already has an MCP server at `/mcp` for deploying projects, reading logs, and so on. Claude Code connects to it
once:

```bash
claude mcp add --transport http canine https://<canine-host>/mcp
```

The first call goes through OAuth in the browser. After that, every request carries a token, and `McpController`
turns it into a user:

```ruby
before_action :doorkeeper_authorize!

def mcp_server
  ctx = { token: doorkeeper_token, user_id: doorkeeper_token.resource_owner_id }
  ...
```

Computer use adds four tools to the list in `McpController#mcp_tools`:

| Tool | Inputs | Returns |
|---|---|---|
| `list_agent_computers` | none | your computers: id, name, status, cluster |
| `computer_screenshot` | `agent_computer_id` | the screenshot as an **image**, plus its size as text |
| `computer_action` | `agent_computer_id`, `action`, and Anthropic's fields: `coordinate`, `start_coordinate`, `text`, `scroll_direction`, `scroll_amount`, `duration`, `region` | the action's result (`zoom` returns an image) |
| `computer_accessibility` | `agent_computer_id`, `operation` (`windows`, `tree`, `find`, `press`, `set_text`), `app`, `role`, `name`, `path`, `text`, `max_depth` | JSON |

`computer_action`'s inputs are the fields of Anthropic's computer-use tool, so what Claude already knows about
computer use carries over.

## A tool, top to bottom

`computer_action` is short, because the shared parts live in a concern:

```ruby
class ComputerAction < MCP::Tool
  include Tools::Concerns::Authentication
  include Tools::Concerns::AgentComputerAccess
  ...
  def self.call(agent_computer_id:, action:, server_context:, **params)
    with_agent_computer(agent_computer_id, server_context:) do |computer_use|
      result_response(computer_use.perform(params.merge(action: action)))
    end
  end
end
```

`Tools::Concerns::AgentComputerAccess` does three things every computer tool needs:

```ruby
def with_agent_computer(agent_computer_id, server_context:)
  with_account_users(server_context: server_context) do |user, account_users|
    computer = find_agent_computer(agent_computer_id, account_users)
    next error_response("Agent computer not found or you don't have access to it") unless computer
    next error_response("Agent computer '#{computer.name}' is #{computer.status}; start it first") unless computer.running?

    yield AgentComputers::ComputerUse.new(computer, K8::Connection.new(computer.cluster, user))
  end
rescue AgentComputers::ComputerUse::Error => e
  error_response(e.message)
end
```

1. **Access.** `find_agent_computer` only finds computers in accounts the user belongs to:
   `AgentComputer.joins(:account_user).where(account_users: { account_id: account_users.map(&:account_id) })`.
   Someone else's computer and a computer that doesn't exist get the same answer, so the tool doesn't reveal which
   IDs exist.
2. **State.** A stopped computer gets a clear "start it first" instead of a port-forward timeout.
3. **Replies.** `result_response` turns the server's JSON into MCP content. Screenshots become image content, so
   Claude sees the picture, not a base64 string:

```ruby
def result_response(result)
  content = []
  if result["image"]
    content << { type: "image", data: result.delete("image"), mimeType: "image/#{result.delete("format") || "png"}" }
  end
  content << { type: "text", text: result.to_json } if result.present? || content.empty?
  MCP::Tool::Response.new(content)
end
```

**Tool descriptions are the model's documentation.** `computer_action`'s description tells Claude that coordinates
are pixels in `computer_screenshot`'s image, and that the desktop is Hyprland, where **Super** is the main modifier
(`super+Return` opens a terminal). Without that, a model would reach for Windows or macOS shortcuts.

## ComputerUse: an HTTP client through a tunnel

`AgentComputers::ComputerUse` is a small `Net::HTTP` client with three methods, `perform(action)`, `windows` and
`accessibility(operation, params)`. It turns failures into one error type with a readable message. Each request runs
inside a port-forward:

```ruby
def request(http_request)
  response = PortForward.open(@computer, @connection, AgentComputer::COMPUTER_USE_PORT) do |port|
    Net::HTTP.start("127.0.0.1", port, open_timeout: 10, read_timeout: 120) { |http| http.request(http_request) }
  end
  body = JSON.parse(response.body)
  raise Error, body["error"] || "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

  body
end
```

The server's 400 errors ("coordinate [99999, 0] is off the 1280x720 screen") pass straight through to Claude as tool
errors, so it can correct itself.

## PortForward: the one trick

`AgentComputers::PortForward` was pulled out of `GuestShell` (which SSHes into the VM for setup) so both could use
it:

```ruby
PortForward.open(computer, connection, remote_port) do |local_port|
  # 127.0.0.1:local_port now reaches remote_port inside the VM
end
```

Inside, it:

1. writes the cluster's kubeconfig to a tempfile;
2. finds the VM's running **virt-launcher pod** (label `vm.kubevirt.io/name=<vm>`);
3. starts `kubectl port-forward <pod> <random 19000-19999>:<remote_port>`;
4. waits until the local port accepts connections, yields it, and kills kubectl afterwards.

Port-forwarding to the *launcher pod* reaches a port *inside the guest* because of KubeVirt's masquerade networking,
which NATs the pod's ports to the VM. It also gets past the computer's deny-all NetworkPolicy, because a
port-forward enters through the kubelet, not the pod network. The other book's
[Lab 4](../agent-computers/20-lab-4-port-forward.md) demonstrates both.

## What a call costs

Lab 5 times each tool call through Canine:

| Call | Time |
|---|---|
| `list_agent_computers` (database only) | 0.04 s |
| `computer_action` (cursor_position, mouse_move, a small zoom) | 3.3 – 3.8 s |
| `computer_screenshot` (1280x720 PNG, ~860 KB) | ~5 s |

Measuring the pieces directly shows where that goes:

| Step | Time |
|---|---|
| `kubectl get pods` to find the launcher pod | ~1.2 s |
| `kubectl port-forward` until the port answers | ~1.6 s |
| the action itself (e.g. `cursor_position`) | ~0.5 s |
| grim capture of the full screen | ~0.7 s |

So about 2.8 seconds of every call is setting up the tunnel, not doing the work. That's acceptable for an agent that
thinks for several seconds between actions, but it's the obvious next optimization. Canine's Rack proxy
(`lib/agent_computer_proxy.rb`) already keeps port-forwards open between requests for the Selkies stream, and the
same caching would take most of those seconds away.

## The other ways in

- **The Rack proxy route** `/agent_computers/:id/computer-use/*` reaches the same server from a signed-in browser
  session (the same middleware that serves the Selkies stream at `/proxy/*`). API-token access and
  `/api/v1/agent_computers` are still TODO.
- **Status probe.** `AgentComputers::Stats` checks the computer-use port along with the desktop and SSH ports, so
  the computer's page shows whether the server is up.

## A spec

`spec/mcp/tools/computer_action_spec.rb` covers the concern end to end with the HTTP client stubbed: an action
reaches a running computer, a screenshot becomes image content plus text, a stopped computer is refused, and a
stranger's computer is not found. Following the project's rule to keep specs few and short, it's one example with
several expectations.

## Check yourself

**Q: Why return "not found or you don't have access" for both missing and forbidden computers?**

<details>
<summary>Answer</summary>

So the tool doesn't reveal which IDs exist. With two different messages, anyone could probe IDs to learn how many
computers other accounts have.

</details>

**Q: Where does the ~3 second overhead per call come from, and how would you remove most of it?**

<details>
<summary>Answer</summary>

Looking up the launcher pod (~1.2 s) and starting `kubectl port-forward` (~1.6 s), fresh on every call. Keep the
forward open per computer between calls, the way the Rack proxy already does for Selkies.

</details>

**Q: Why does `computer_screenshot` return image content instead of the base64 string as text?**

<details>
<summary>Answer</summary>

MCP clients pass image content to the model as an actual image, which the model can look at. The same data as text
would just be a very long string, costing a huge number of tokens and showing the model nothing.

</details>

Next: [War stories](07-war-stories.md).
