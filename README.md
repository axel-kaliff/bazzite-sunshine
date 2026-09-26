# Bazzite Sunshine

This image follows `ghcr.io/ublue-os/bazzite-dx-nvidia-gnome:stable`
and adds the native Sunshine RPM for a dedicated, single-user streaming host.
KMS capture needs `cap_sys_admin`, which the Flatpak cannot provide;
the native package also supports NVIDIA NVENC encoding.
The RPM's capability must survive both image construction and VM deployment.

Sunshine comes from `lizardbyte/stable`. Beta is used only when stable has
no Sunshine package for the Fedora release; other installation failures
fail the build. The enabled COPRs are disabled after installation.

Sunshine starts with the graphical session. A stream watchdog manages the
suspend inhibitor, and a health timer restarts stalled Sunshine after three
failed probes, excluding live streams and limiting restarts to three per hour.
Native configuration and logs live in `~/.config/sunshine/`.
Sunshine's `global_prep_cmd` can call
`/usr/libexec/bazzite-sunshine/stream-inhibit on` and `off` directly.

Daily builds resolve the current upstream digest. Tags mean:
- `candidate`: built and container-tested.
- `stable`: also booted and tested in a VM, then promoted without rebuilding.
- `stable-YYYYMMDD`: the day's promoted digest, available for rollback.

Switch, then reboot:
```sh
sudo bootc switch ghcr.io/axel-kaliff/bazzite-sunshine:stable
```

Return to the previous deployment, then reboot:
```sh
sudo bootc rollback
```

Or return to upstream, then reboot:
```sh
sudo bootc switch ghcr.io/ublue-os/bazzite-dx-nvidia-gnome:stable
```

CI signs the image digest with Cosign. Client-side signature enforcement is
not configured: `policy.json` falls back to `insecureAcceptAnything` for
this registry path.
