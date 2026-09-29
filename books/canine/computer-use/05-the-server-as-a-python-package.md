# The server as a Python package

The server is about 760 lines of Python in `resources/agent_computer/computer_use/`, packaged so it can be installed
with `pip`, anywhere. This chapter covers the HTTP layer, the packaging, and how it gets onto a new agent computer.

## Layout

```text
resources/agent_computer/computer_use/
├── pyproject.toml          the package: name, entry point, the one dependency
├── README.md               what it needs on a desktop, how to run it, the API
├── computer_use/
│   ├── __main__.py         canine-computer-use [--host] [--port]
│   ├── server.py           HTTP routes, the lock, errors → status codes
│   ├── actions.py          Anthropic's computer-use actions → the modules below
│   ├── desktop.py          hyprctl, coordinates, screenshots, windows      (chapter 2)
│   ├── uinput.py           the virtual keyboard + mouse                    (chapter 3)
│   ├── keyboard.py         key names → key codes; text through wtype        (chapter 3)
│   ├── mouse.py            move, click, scroll, drag                        (chapter 3)
│   └── accessibility.py    AT-SPI: tree, find, press, set_text              (chapter 4)
└── tests/test_keyboard.py  key parsing against a fake device (runs anywhere)
```

## The HTTP API

It's the standard library's `ThreadingHTTPServer`, with a table of routes:

```python
ROUTES = {
    ("GET", "/status"): lambda body: {"ok": True, "screen": desktop.screen_size()},
    ("POST", "/computer-use"): actions.perform,
    ("GET", "/windows"): lambda body: {"windows": desktop.windows()},
    ("POST", "/accessibility/tree"): lambda body: {"apps": accessibility.tree(body.get("app"), int(body.get("max_depth", 8)))},
    ("POST", "/accessibility/find"): lambda body: {"elements": accessibility.find(body.get("role"), body.get("name"), body.get("app"))},
    ("POST", "/accessibility/press"): lambda body: accessibility.press(body["path"]),
    ("POST", "/accessibility/set_text"): lambda body: accessibility.set_text(body["path"], body["text"]),
}
```

`POST /computer-use` takes exactly the JSON that Anthropic's computer-use tool produces, so a harness can pass a
model's action through untouched. `actions.perform` looks up the action by name and validates its fields.

**Errors are for the agent to read.** A model that sends a bad action should get an explanation it can act on, not a
dropped connection:

| Exception | Status | Example |
|---|---|---|
| `ActionError`, `ValueError`, `KeyError`, `LookupError` | 400 | `coordinate [5000, 10] is off the 1280x720 screen`; `Unknown key 'nope'` |
| `subprocess.CalledProcessError` | 500 | `grim failed: ...` |
| anything else | 500 | `TypeName: message`, and the traceback goes to the journal |

**No authentication**, on purpose. The server listens inside the VM, and nothing can reach it except through a
`kubectl port-forward`, which needs cluster credentials. Canine checks the user before it opens one. A NetworkPolicy
blocks every other pod in the cluster (the [port-forward lab](../agent-computers/20-lab-4-port-forward.md) in the
other book shows why a port-forward still gets through). This is the same model as Selkies on port 8080.

## Why only the standard library?

The old Ubuntu computer server (removed) used FastAPI, Playwright and mss. For this one, every dependency is
something to install on every new computer, and Arch makes that awkward. Its system Python is **externally managed**
(PEP 668): `pip install` into it is refused, to protect the files pacman owns. So the server uses:

- `http.server`, `json`, `subprocess`, `fcntl`, `struct`: standard library
- **PyGObject** (`gi`) for AT-SPI: the only dependency, and Omarchy already has it as the `python-gobject` package

## pyproject.toml

```toml
[build-system]
requires = ["setuptools>=77"]
build-backend = "setuptools.build_meta"

[project]
name = "canine-computer-use"
version = "0.1.0"
requires-python = ">=3.10"
license = "Apache-2.0"
# PyGObject is the only Python dependency (for AT-SPI). On a desktop it's usually already installed by the
# distribution (Arch: python-gobject); a venv made with --system-site-packages picks it up.
dependencies = ["PyGObject>=3.42"]

[project.scripts]
canine-computer-use = "computer_use.__main__:main"

[tool.setuptools]
packages = ["computer_use"]
```

- `[project.scripts]` makes pip create a `canine-computer-use` command that calls `computer_use.__main__:main`.
  `python3 -m computer_use` still works too.
- `license = "Apache-2.0"` (a plain SPDX string) needs setuptools 77 or newer, hence the build requirement.
- `python -m build` makes a wheel. Checking what's inside is a quick way to see the packaging is right: the nine
  modules, plus `entry_points.txt` containing the script.

## Installing on Omarchy: a venv that can see PyGObject

```bash
python3 -m venv --system-site-packages ~/.local/share/canine/venv
~/.local/share/canine/venv/bin/pip install ~/.local/share/canine/computer_use
```

A venv avoids the externally-managed error. `--system-site-packages` lets it *also* see the system's packages, so
`import gi` finds Omarchy's PyGObject, and pip sees `PyGObject` as already satisfied instead of trying to build it
from source (which needs a C compiler and GObject headers). On computer 14, after setup:

```text
Name: canine-computer-use   Version: 0.1.0   Location: /home/omarchy/.local/share/canine/venv/lib/python3.14/site-packages
Name: PyGObject             Version: 3.56.3  Location: /usr/lib/python3.14/site-packages
```

One catch: `pip install` of a source directory builds it first, and the build downloads setuptools from PyPI. New VMs
have internet access (they already download Selkies), so that's fine, but it's worth knowing.

## How it gets onto a new computer

`AgentComputers::ProvisionJob` already SSHes into each new VM to run `omarchy-setup.sh`. Just before that, it streams
the package in as a tarball over the same SSH connection:

```ruby
GuestShell.open(agent_computer, connection) do |shell|
  shell.run("rm -rf ~/.local/share/canine/computer_use && mkdir -p ~/.local/share/canine && tar -xzf - -C ~/.local/share/canine",
            stdin: AgentComputer::Omarchy.computer_use_archive)
  shell.run("bash -s", stdin: AgentComputer::Omarchy::SETUP_SCRIPT.read, env: omarchy.setup_environment)
end
```

```ruby
# The computer-use server's Python project (pyproject.toml and the package) as a .tar.gz, which the setup unpacks
# into ~/.local/share/canine/computer_use and pip-installs
def self.computer_use_archive
  archive, status = Open3.capture2("tar", "-czf", "-", "--exclude=__pycache__", "--exclude=build", "--exclude=*.egg-info",
                                   "-C", COMPUTER_USE_SERVER.dirname.to_s, COMPUTER_USE_SERVER.basename.to_s, binmode: true)
  raise "Couldn't archive #{COMPUTER_USE_SERVER}" unless status.success?

  archive
end
```

No registry and no image rebuild: the code travels with Canine. Then the "Computer use" section of
`omarchy-setup.sh` does the rest:

1. creates the venv and pip-installs the package;
2. sets up `/dev/uinput` access (the udev rule, `modules-load.d`, `modprobe uinput`);
3. turns on accessibility for GTK, Qt and Chromium;
4. writes the systemd user service and opens port 8000 in Omarchy's firewall (`ufw`).

```ini
[Unit]
Description=Canine computer-use server
After=graphical-session.target
PartOf=graphical-session.target

[Service]
ExecStart=%h/.local/share/canine/venv/bin/canine-computer-use --port 8000
Restart=always
RestartSec=2

[Install]
WantedBy=graphical-session.target
```

`graphical-session.target` is the important part. uwsm (Omarchy's session manager) starts it once Hyprland is up and
exports `WAYLAND_DISPLAY` and `HYPRLAND_INSTANCE_SIGNATURE` to user services. So the server starts with the desktop,
inherits everything `hyprctl`, `grim` and `wtype` need, and stops when the session ends. It's the same pattern the
Selkies service uses.

## Updating a running computer

Re-running the first two steps is all it takes. That's how computer 14 was updated while the book was written:

```ruby
AgentComputers::GuestShell.open(computer, connection) do |shell|
  shell.run("rm -rf ~/.local/share/canine/computer_use && mkdir -p ~/.local/share/canine && tar -xzf - -C ~/.local/share/canine",
            stdin: AgentComputer::Omarchy.computer_use_archive)
  shell.run("~/.local/share/canine/venv/bin/pip install --quiet ~/.local/share/canine/computer_use && " \
            "systemctl --user restart canine-computer-use")
end
```

## Tests

`tests/test_keyboard.py` replaces the uinput device with a fake that records key events, so key parsing can be tested
on any machine:

```python
def test_combinations_press_modifiers_first_and_release_them_last(self):
    self.assertEqual(self.press("ctrl+a"), [(29, "down"), (30, "down"), (30, "up"), (29, "up")])
    self.assertEqual(self.press("cmd+2"), [(125, "down"), (3, "down"), (3, "up"), (125, "up")])
```

Everything else needs a real Hyprland session, so it's tested by the labs, against a real agent computer.

## Check yourself

**Q: Why `--system-site-packages`? Wouldn't a clean venv be tidier?**

<details>
<summary>Answer</summary>

A clean venv would have to pip-install PyGObject, which builds C extensions against GObject and needs a compiler and
headers. With system site packages, the venv uses the PyGObject Omarchy already has, and pip treats the dependency
as satisfied.

</details>

**Q: Why does the service hang off `graphical-session.target` instead of `default.target`?**

<details>
<summary>Answer</summary>

It needs the running desktop: `WAYLAND_DISPLAY` and `HYPRLAND_INSTANCE_SIGNATURE`, which uwsm exports when Hyprland
starts. Under `default.target` it could start before the session exists, and it wouldn't stop and restart with it.

</details>

**Q: The server has no authentication. What stops another pod in the cluster from clicking around?**

<details>
<summary>Answer</summary>

The deny-all-ingress NetworkPolicy in the computer's namespace. Only `kubectl port-forward` gets in, because it
doesn't come in over the pod network, and only Canine (after checking the user) or someone with cluster credentials
can open one.

</details>

Next: [The Canine side](06-the-canine-side.md).
