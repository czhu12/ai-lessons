# Lab 5: Through Canine's MCP tools

**Goal:** reach the same server the way Claude Code does, through Canine's MCP tools, and see what each call costs.
**Time:** 2 minutes. **Chapters:** [The Canine side](06-the-canine-side.md).

```bash
./labs/05-mcp/run.sh
```

`labs/05-mcp/mcp_tools.rb` runs in the Canine app (`bin/rails runner`) and calls the tool classes exactly as
`McpController` does, with a `server_context` holding the user that the OAuth token would give:

1. Print the four computer tools' descriptions and inputs, which is what Claude sees.
2. Call them as the computer's owner and time each call. The last call uses a computer the user can't see.

## Questions

**Q: `list_agent_computers` took 0.04 s and every other call about 3.5 s. Where did the difference go?**

<details>
<summary>Answer</summary>

`list_agent_computers` only reads the database. The others look up the VM's launcher pod (~1.2 s) and open a new
`kubectl port-forward` (~1.6 s) before the ~0.5 s action. Keeping the forward open between calls is the obvious fix
(see [open work](08-current-state-and-open-work.md)).

</details>

**Q: The screenshot came back as `[image image/png, ...] + {"width":1280,"height":720}`. Why both?**

<details>
<summary>Answer</summary>

The image content is what the model looks at. The text tells it the image's size in pixels, which is the coordinate
space for its next action.

</details>

**Q: The last call used `agent_computer_id: -1`. Would a real computer in someone else's account get a different
error?**

<details>
<summary>Answer</summary>

No. Both get "not found or you don't have access to it", so the tool doesn't reveal which IDs exist.

</details>

## Expected output

<details>
<summary>📜 Expected output (a real run, captured while writing this book)</summary>

```text
== 1. The four tools Canine's /mcp endpoint offers for agent computers, and what they take
$ tools schemas
list_agent_computers: List the agent computers (cloud desktops) you can use. Their IDs are what the computer_* tools take.
   inputs:    (required: none)
computer_screenshot: Take a screenshot of an agent computer's desktop. Coordinates in the image are what computer_action takes.
   inputs: agent_computer_id   (required: agent_computer_id)
computer_action: Use an agent computer's mouse and keyboard, following Anthropic's computer-use tool: e.g. left_click at a c...
   inputs: agent_computer_id, action, coordinate, start_coordinate, text, scroll_direction, scroll_amount, duration, region   (required: agent_computer_id, action)
computer_accessibility: Read and use apps on an agent computer by their structure instead of pixels, through the accessibility tree...
   inputs: agent_computer_id, operation, app, role, name, path, text, max_depth   (required: agent_computer_id, operation)
   computer_action's inputs are the fields of Anthropic's computer-use tool, so a model's action passes straight through.

== 2. Call them as the computer's owner, and time each call
$ tools calls
list_agent_computers()  # which computers can I use?
   [{"id":11,"name":"omarchy","status":"running","cluster":"devserver"},{"id":12,"name":"omarchy","status":"running","cluster":"cluster"},{"id":14,"name":"omarchy-auto","status":"running","cluster":"devserver"}]   (0.04s)
computer_screenshot(agent_computer_id: 14)  # what's on screen?
   [image image/png, 1148000 base64 chars] + {"width":1280,"height":720}   (4.96s)
computer_action(agent_computer_id: 14, action: "cursor_position")  # where's the mouse?
   {"coordinate":[640,371]}   (3.69s)
computer_action(agent_computer_id: 14, action: "mouse_move", coordinate: [400, 300])  # move it
   {}   (3.67s)
computer_action(agent_computer_id: 14, action: "zoom", region: [0, 0, 320, 25])  # look closely at the top bar
   [image image/png, 4252 base64 chars]   (3.84s)
computer_accessibility(agent_computer_id: 14, operation: "tree", max_depth: 0)  # which apps have a tree?
   {"apps":[{"path":"0","role":"application","name":"quickshell","states":["disabled"]},{"path":"1","role":"application","name":"xdg-desktop-portal-gtk","states":["disabled"]},{"path":"2","role":"application","name":"qui...   (3.7s)
computer_action(agent_computer_id: 14, action: "left_click", coordinate: [99999, 0])  # a mistake
   ERROR coordinate [99999, 0] is off the 1280x720 screen   (3.27s)
computer_screenshot(agent_computer_id: -1)  # someone else's (or no) computer
   ERROR Agent computer not found or you don't have access to it   (0.01s)
   Every call looks up the VM's pod (~1s) and opens a fresh kubectl port-forward (~1.5s) before the action runs.
   Screenshots come back as MCP image content, so Claude sees the picture, plus the size as text.
```

</details>

## Try next

- Connect Claude Code to your local Canine (`claude mcp add --transport http canine http://localhost:3000/mcp`) and
  ask it to "open a terminal on agent computer 14 and run uname -a".
