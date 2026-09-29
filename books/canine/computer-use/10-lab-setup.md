# Labs: setup

Five labs against a real Canine agent computer. Each lab is a script that walks through the steps one at a time
(press Enter to advance), printing every command before it runs, so you can copy it later.

**On your phone?** Every lab page has questions with hidden answers and a collapsible **expected output** section: a
real transcript captured while writing this book, against computer 14. You can follow along without running
anything.

## What the labs use

| Lab | Does to the desktop | Needs |
|---|---|---|
| 1. The raw API | moves the mouse | `curl`, `jq` |
| 2. Drive the desktop | opens a terminal on workspace 5, types into it, closes it | |
| 3. The accessibility tree | opens Chromium on workspace 6, loads example.com, closes it | |
| 4. uinput from scratch | switches workspaces | SSH (through a port-forward) |
| 5. Through Canine's MCP tools | moves the mouse | the Canine repo and its database |

All of them need a **running** agent computer that has the computer-use server (any computer created after it was
added, or one updated as in [chapter 5](05-the-server-as-a-python-package.md)), plus `kubectl`, `jq` and `nc`.

## One-time setup

The labs reach the computer the way Canine does: `kubectl port-forward` to its launcher pod, with the cluster's
kubeconfig, and SSH with the computer's generated key. `labs/fetch-access.rb` asks your local Canine for both and
writes them to `labs/.secrets/`, which is git-ignored:

```bash
cd ~/Documents/Github/canine
bin/rails runner ~/Documents/Github/ai-lessons/books/canine/computer-use/labs/fetch-access.rb <computer-id>
# Wrote kubeconfig, ssh_key and computer.env for omarchy-auto (running) to .../labs/.secrets

cd ~/Documents/Github/ai-lessons/books/canine/computer-use
source labs/env.sh      # works in bash and zsh
cu GET /status          # {"ok":true,"screen":{"width":1280,"height":720}}
```

If your Canine checkout isn't at `~/Documents/Github/canine`, put `CANINE_DIR=...` in `labs/.local.env` (also
ignored). Lab 5 uses it.

## The helpers

`labs/env.sh` is short; read it. It gives you:

| Helper | What it does |
|---|---|
| `cu GET /windows` / `cu POST /accessibility/find '{...}'` | call the server (opens the port-forward if needed); images in replies are shown as their length |
| `act '{"action": "..."}'` | one computer-use action (`cu POST /computer-use ...`) |
| `shot <file> [left top right bottom]` | save a screenshot, or a zoom of a region, as a PNG |
| `vm_ssh <command>` | SSH into the VM as the desktop user |
| `vm_ssh_desktop <command>` | the same, with the Hyprland session's environment, so `hyprctl`, `wtype` and `grim` work |
| `vm_pod` | the computer's virt-launcher pod |
| `lab_stop_forwards` | stop the port-forwards |

To run a lab: `./labs/01-the-api/run.sh`. To run it straight through: `LAB_AUTO=1 ./labs/01-the-api/run.sh`.

## Safety rules the labs follow

- They act on a **real desktop**. Open the computer's page in Canine and watch (the Watch button opens a view-only
  tab) so you can see what they do.
- They only type into windows they opened themselves, on an empty workspace, and they check that the window has
  focus before typing. Keys go to whatever has focus, so this check matters.
- They close what they open and return to workspace 1.
- The kubeconfig and SSH key stay in `labs/.secrets/`. This repo is public, so check `git status --ignored` shows
  them as ignored (`!!`) before you commit anything.
