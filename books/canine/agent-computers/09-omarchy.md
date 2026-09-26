# Omarchy: a real desktop OS in a VM

**Omarchy** (4.0.4) is an opinionated Arch Linux setup around the **Hyprland** Wayland compositor, with its own
installer ISO. It's a desktop people choose as their daily driver, which was the point.

## Installing an OS unattended in KubeVirt

Normally you'd click through an installer. We used Omarchy's **unattended install** support:

- The ISO looks for a drive **labeled `cidata`** containing answer files, and installs without prompts:
  - `user_configuration.json` — the archinstall-style config: wipe `/dev/vda`, a 2 GiB EFI boot partition + a
    main partition, **Limine** bootloader, `linux-omarchy` kernel, PipeWire audio, `mode: full_disk`
  - `user_credentials.json` — the `omarchy` user (sudo) with a **hashed** password (`openssl passwd -6`)
  - `user_full_name.txt`, `user_email_address.txt`, `user_encrypt_installation.txt` (`false`),
    `authorized_keys` (our SSH public key)
- In KubeVirt, a **ConfigMap can be attached as a disk** with a volume label:
  `{ name: cidata, configMap: { name: omarchy-cidata, volumeLabel: cidata } }`. We attached it on the USB bus.

The VM spec (copy in `labs/.secrets/vm.yaml`):

```yaml
dataVolumeTemplates:
  - omarchy-iso:  source http https://iso.omarchy.org/omarchy-4.0.4.iso   (8Gi)   # CDI downloads the ISO
  - omarchy-root: source blank                                           (60Gi)  # empty disk to install onto
domain:
  firmware: { bootloader: { efi: { secureBoot: false } } }   # UEFI boot (Omarchy's ISO/Limine expect UEFI)
  cpu: { cores: 4, model: host-passthrough }                  # expose the real CPU model to the guest
  memory: { guest: 8Gi }
  devices:
    video: { type: virtio }                                   # virtual GPU (no 3D acceleration)
    inputs: [ { type: tablet, bus: usb } ]                    # absolute pointer, so VNC clicks land where you click
    disks:
      - root  bootOrder 1 (virtio)                            # empty on first boot → falls through to…
      - iso   bootOrder 2 (cdrom, sata)                       # …the installer. After install, root boots.
      - cidata (usb)                                          # the answer files
```

The boot-order trick: on first boot the root disk is empty, so firmware boots the ISO; the installer writes to root;
on reboot, root is bootable and wins.

**How we knew it finished:** SSH answering wasn't enough (the *live ISO* also runs sshd — a false positive we hit).
The done-signal became: log in as `omarchy` with our key and read the hostname `omarchy`. We reach guest SSH through
`kubectl port-forward <launcher-pod> 2223:22` (the `omarchy_ssh` helper in `labs/env.sh`).

Install time: ~5.5 min on AWS (faster than Hetzner).

## Making it stream

Steps done inside the installed Omarchy (all over SSH):

1. **Selkies:** install the Arch package `selkies-2.0.0-x86_64.pkg.tar.zst` with `pacman -U`.
2. **Auto-login** so there's always a Hyprland session to stream: `/etc/sddm.conf.d/50-autologin.conf` with
   `User=omarchy`, `Session=hyprland-uwsm.desktop`, `Relogin=true`. (SDDM is the graphical login manager; uwsm is the
   Wayland session manager that exports `WAYLAND_DISPLAY` to user services.)
3. **Selkies user service** attached to Hyprland (`--wayland-host-display="$WAYLAND_DISPLAY"`), with CSS scaling
   and manual 1920×1080.
4. **Firewall:** Omarchy enables `ufw`, which blocked 8080 → `ufw allow 8080/tcp`. (Only reachable through
   port-forward anyway.)
5. **Fixed resolution:** Hyprland's monitor set to `1920x1080@60` in `~/.config/hypr/monitors.lua`. With
   `preferred` mode, Selkies' resize requests and Hyprland's monitor changes fought each other in a loop.
6. **Readability & responsiveness** (in `~/.config/hypr/looknfeel.lua` / `monitors.lua`):
   - `scale = 1.25` → bigger, still-sharp text
   - `cursor.invisible = true` → no double cursor
   - `animations.enabled = false`, `decoration.blur.enabled = false`, `decoration.shadow.enabled = false` →
     every frame is drawn on the CPU (no GPU), so skip expensive effects

Omarchy's Hyprland config is Lua (`hyprland.lua` loads Omarchy defaults, then your override files). Options are set
with `hl.config({ section = { key = value } })`; `hyprctl reload` applies them and `hyprctl getoption cursor:invisible`
checks them.

## How the Omarchy VM appears in Canine

It was created by hand, so we inserted an `AgentComputer` row pointing at it (`desktop: "selkies"`, namespace
patched to `omarchy-spike`). The proxy only needs a namespace and a VM name to find the launcher pod, so the connect
page just works. Records: **id 11** (Hetzner, cluster 33), **id 12** (AWS, cluster 34).

Passwords: the Omarchy login password is in `labs/.secrets/password.txt` (you'll need it for the lock
screen and `sudo`).

✅ **Check yourself:** How does the installer find its answer files? Why does the ISO boot on the first start but
the installed OS on the second, with the same VM spec? Why did Selkies need `--wayland-host-display` here but not on
the Ubuntu image?

