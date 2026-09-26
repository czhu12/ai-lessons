*Lab page 9 of 9*

# Lab 9: Be the agent

**Goal:** drive an agent computer the way an AI agent does: pixels, shell, windows, the accessibility tree, and the
takeover lock. **Time:** 5 minutes. **Chapter:** [The computer server](08-the-computer-server.md).

This lab uses **`desk-2`** (agent computer id 10, Ubuntu + XFCE, on the Hetzner cluster 33), because the AWS node
doesn't have memory for a 4 GiB agent computer next to Omarchy. Canine must be set up locally: step 1 reads the
cluster credentials from Canine's database with `bin/rails runner`.

```bash
cat labs/09-agent-api/agent.rb      # a 30-line "agent": POST {command, params} to /cmd
./labs/09-agent-api/run.sh          # or: run.sh <another agent computer id>
```

Open `desk-2`'s connect page in Canine to watch Mousepad open and text appear.

## Questions

**Q: The screenshot is 8192×4096. Is that the screen you see?**

<details>
<summary>Answer</summary>

It's the X screen's full size (`xrandr` confirms it): Selkies' X11 session sized the virtual screen to its maximum. It's a real finding from this lab: agent screenshots are needlessly huge and dialogs open around (4000, 2000). Fix: pin the resolution in provision.sh, like we did for Omarchy.

</details>

**Q: Why does the lab launch Mousepad and then check `list_windows` for its PID and `active: true` before typing?**

<details>
<summary>Answer</summary>

`type_text` goes to whatever window has focus. Matching our PID and checking focus guarantees we type into our own editor, never into something the person is using.

</details>

**Q: Mousepad once greeted the lab with 'the previous session did not end normally'. How did the agent answer without a screenshot?**

<details>
<summary>Answer</summary>

Through the accessibility tree: `find_element role=label` returned the question text, `role=push button` returned 'No' and 'Yes' with their bounds, and `click_element name=No` pressed it via AT-SPI's click action.

</details>

**Q: Reading the editor's text back through the tree fails with a TypeError. Whose bug is it?**

<details>
<summary>Answer</summary>

Ours, in the computer server: `accessibility.py` calls `text.get_text(0, n)` on the object the GObject bindings return, which resolves to a different `get_text`. Calling `Atspi.Text.get_text(text, 0, n)` fixes it. The same bug breaks `get_accessibility_tree` for apps with editable text. Found while building this lab.

</details>


## Expected output

<details>
<summary>📜 Expected output (a real run, captured while building the lab)</summary>

```text
== 1. Get the computer's cluster credentials from Canine and port-forward the computer server (guest :8000)
$ curl -s localhost:18000/status | python3 -m json.tool
{
    "status": "ok",
    "os_type": "linux",
    "takeover": {
        "monitoring": true,
        "human_active": false,
        "human_idle_seconds": 129574.4,
        "resumes_after_idle_seconds": 5.0
    }
}

== 2. What can an agent do? The command catalogue
$ curl -s localhost:18000/commands | jq_py 'print(len(d["commands"]), "commands:", ", ".join(sorted(d["commands"])))'
44 commands: activate_window, browser_back, browser_click, browser_fill, browser_goto, browser_open, browser_press, browser_snapshot, browser_switch_tab, browser_tabs,...

== 3. See the screen (pixels): the first thing a computer-use model asks for
$ A screenshot
{
  "success": true,
  "format": "png",
  "width": 8192,
  "height": 4096,
  "saved_to": "/tmp/agent-screenshot.png"
}

== 4. Run a shell command in the VM (stdin closed so launched programs can't hang it)
$ A run_command '{"command": "whoami; uname -r; df -h / | tail -1"}' | jq_py 'print(d["stdout"])'
computer
6.8.0-139-generic
/dev/vda1        38G  3.8G   34G  11% /

== 5. Windows: list them and launch an editor on a scratch file
$ A list_windows | jq_py '[print(("* " if w["active"] else "  ") + w["title"]) for w in d["windows"]]'
  xfce4-panel
  xfce4-panel
  xfce4-panel
* Desktop
   launched mousepad, pid 14043

== 6. Read the UI as structure: the accessibility tree (AT-SPI)
$ A find_element '{"app": "mousepad", "role": "menu"}' | jq_py 'print([(e["name"], e.get("bounds")) for e in d["elements"]][:3], "...")'
[('File', {'x': 3776, 'y': 1833, 'width': 37, 'height': 27}), ('Edit', {'x': 3813, 'y': 1833, 'width': 39, 'height': 27}), ('Search', {'x': 3852, 'y': 1833, 'width': 5...
   Every visible control has a role, a name and screen bounds. No image recognition needed to find 'File'.
   No dialog this time. (If Mousepad was ever killed mid-edit, it asks to restore the session; the lab then
   reads the question and clicks 'No' by name.)

== 7. Focus the editor and type, ONLY after confirming it's the active window
$ A list_windows | jq_py 'print([w["title"] for w in d["windows"] if w["active"]])'
['*/tmp/agent-lab.txt - Mousepad']
$ A type_text '{"text": "Hello from the agent API. Typed with xdotool via XTest."}'
{
  "success": true
}
   Now read it back WITHOUT a screenshot: editable text is exposed in the accessibility tree.
$ A find_element '{"app": "mousepad", "role": "text"}' | jq_py 'print([e.get("text") for e in d["elements"] if e.get("text")] if d["success"] else "error: " + d["error...
error: TypeError: Atspi.Accessible.get_text() takes exactly 1 argument (3 given)
   KNOWN BUG, found while building this lab: accessibility.py calls text.get_text(0, n) on the object the
   GObject bindings return, which fails. Fix: Atspi.Text.get_text(text, 0, n). Until then, reading editable
   text via the tree errors, but roles, names, bounds and clicks (step 6) work.
$ A screenshot
{
  "success": true,
  "format": "png",
  "width": 8192,
  "height": 4096,
  "saved_to": "/tmp/agent-screenshot.png"
}

== 8. Save and close the window cleanly (so the next run doesn't get the 'previous session' question)
$ A hotkey '{"keys": ["ctrl", "s"]}'
{
  "success": true
}
$ A close_window '{"id": 41943043}'
{
  "success": true
}
$ A run_command '{"command": "cat /tmp/agent-lab.txt; echo; rm -f /tmp/agent-lab.txt; pgrep -x mousepad || echo mousepad closed"}' | jq_py 'print(d["stdout"])'
Hello from the agent API. Typed with xdotool via XTest.
mousepad closed

== 9. The takeover lock (manual): open desk-2's connect page in Canine, wiggle the mouse, then run:
$ A takeover_status
{
  "success": true,
  "monitoring": true,
  "human_active": false,
  "human_idle_seconds": 129596.3,
... (trimmed)
```

</details>


## Try next

- `ruby agent.rb browser_open '{"url": "https://example.com"}'` then `ruby agent.rb browser_text`: the agent drives
  the person's real Chrome over CDP (port 9222), not a hidden headless browser.
- Step 9 (manual): wiggle the mouse in `desk-2`'s connect page and, within 5 seconds, run
  `ruby agent.rb left_click '{"x": 5, "y": 5}'`. You get `"takeover": true` back.

---

← [Lab 8: Build the proxy yourself](24-lab-8-mini-proxy.md) · [Index](README.md)
