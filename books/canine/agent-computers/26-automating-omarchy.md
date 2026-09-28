# Automating Omarchy: how "New computer" builds a desktop

On 2026-09-28 the Ubuntu/XFCE agent computer was removed, and "New computer" in Canine started building Omarchy
VMs on its own. Everything the [Omarchy chapter](09-omarchy.md) did by hand now runs as a background job, and the
first clean run went from clicking create to a streaming desktop in **4.8 minutes**.

## The shape of it

```
AgentComputer.create!           generates a login password + an SSH key pair (stored on the record)
  └─ ProvisionJob
      1. Namespace computer-<name> + NetworkPolicy (deny all ingress)
      2. ConfigMap <name>-cidata     the unattended-install answers, mounted as a drive labeled "cidata"
      3. VirtualMachine <name>       ISO disk (imported by CDI) + blank 60Gi root disk + cidata drive
      4. wait: VM Running            ISO imported (~1.5 min for 6.2 GB on Hetzner), VM booted
      5. wait: SSH login works       the installer finished and rebooted into the installed system
      6. SSH: omarchy-setup.sh       Selkies, autologin, firewall, 1080p @ 1.25, no animations/cursor
      7. wait: Selkies listening     then status = running
```

The code: `app/models/agent_computer/omarchy.rb` (install answers and VM spec),
`app/jobs/agent_computers/provision_job.rb` (the steps), `app/services/agent_computers/guest_shell.rb` (SSH over
a port-forward), and `resources/agent_computer/omarchy-setup.sh` (what runs inside the VM).

## Why SSH, and not a post-install hook

The natural place for "install Selkies" would be a hook inside the installer. Omarchy's installer doesn't have one:
it reads `user_configuration.json` but runs its own orchestrator, so archinstall's `custom_commands` never run. What
it *does* support is an `authorized_keys` file on the `cidata` drive. With one, the installed system enables `sshd`
and opens port 22 in its firewall.

So Canine generates an SSH key per computer, puts the public half in `authorized_keys`, and after the install logs
in with the private half. It reaches port 22 the same way it reaches Selkies: `kubectl port-forward` to the VM's
launcher pod (masquerade networking passes the port into the guest; see [Lab 4](20-lab-4-port-forward.md)). The
NetworkPolicy still blocks everything else in the cluster.

**Knowing when the install is done.** The live ISO runs `sshd` too, so "port 22 answers" isn't enough; that false
positive bit us during the manual install. The job instead waits until *our key logs in as the desktop user* and
`hostname` returns the computer's name. Only the installed system has both.

## The password, without shelling out

The installer wants a crypt(3) hash in `user_credentials.json` and applies it with `chpasswd`. The README suggests
`openssl passwd -6`, but Ruby's built-in `crypt` can't make SHA-512 hashes on macOS, and Canine shouldn't depend on an
`openssl` binary. Canine already has the `bcrypt` gem (Devise uses it), and Arch's password library accepts bcrypt.
One wrinkle: the gem writes `$2a$` and Linux prefers `$2b$`. For normal passwords they're the same algorithm, so the
code swaps the prefix. The end-to-end run proved it: `sudo` inside the new VM accepted the password.

## What went wrong on the first run

The first attempt failed at step 6, and the failure taught two things.

1. **A fresh install has no package database.** Installing Selkies worked, because its dependencies were already on
   the system. But the next step (the QEMU guest agent, for disk stats) needed to download package lists. On Arch,
   refreshing the lists and installing one package (`pacman -Sy foo`) is a "partial upgrade" and unsupported. The
   supported way is a full `pacman -Syu`, which on a rolling-release distro can pull a new kernel. That's a lot of risk
   for a disk-usage number, so the guest agent was dropped.
2. **The error leaked the password.** The setup script gets `SETUP_PASSWORD` (for `sudo`) as an environment variable
   on the SSH command line, and the first version of the error message quoted the whole command. The password landed
   in Canine's log. Errors now name only the command (`bash -s`), never its environment. The leaked lines were
   redacted and the test VM was rebuilt from scratch.

## What was removed, and why it's fine

The golden-image pipeline ([chapter 7](07-the-golden-image-pipeline.md)) and the X11 computer server
([chapter 8](08-the-computer-server.md)) are gone. Omarchy is installed per computer instead of cloned. That's slower
than a clone (~5 minutes instead of ~1), but there's no per-cluster image build, no builder VM, and no cross-namespace
clone permissions. And since every machine is a fresh install, there's no "same machine-id on every clone" problem.

Agent control will need a Wayland-native replacement for the computer server (see
[Current state](14-current-state-and-open-work.md)).

## Check yourself

<details>
<summary>Why can't the job just wait for port 22 to open?</summary>

The live installer ISO also runs sshd. The job only trusts a successful login as the desktop user, with our key, on a
machine whose hostname is the computer's name. The live ISO has neither the user nor the hostname.

</details>

<details>
<summary>Why does Canine store a password at all, if it logs in with a key?</summary>

The key is only for Canine's setup step. The person using the desktop needs the password for Omarchy's lock screen
and for `sudo`. The overview page has a button that copies it.

</details>

<details>
<summary>What would it take to make provisioning take ~1 minute again?</summary>

A golden image of an *installed* Omarchy, cloned per computer, like the old Ubuntu pipeline. Each clone would then
need a new identity on first boot (machine-id, SSH host keys, hostname, password), which Omarchy has no cloud-init to
do. The cheaper first step is sharing one imported ISO per cluster instead of importing 6 GB per computer.

</details>
