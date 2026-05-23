# Thor AGX Stabilization

## Purpose

Track the live stabilization state for `agx-rfc99-bunnydev.rfc1918.host`
(`172.16.99.34`) so future Forge sessions can continue Thor AGX bring-up
without rediscovering the same Ubuntu L4T, network, package, and inference
facts.

This host is an Ubuntu/NVIDIA L4T exception. Do not generalize its systemd
commands or Ubuntu package handling to Gentoo/OpenRC hosts.

## Access Path

- Jump path: local Forge host to `root@172.16.99.70`, then
  `root@agx-rfc99-bunnydev.rfc1918.host`
- Management IP: `172.16.99.34/24`
- Management interface: `enP2p1s0`
- Management switch/port: CSS326 `ge7`
- DNS authority used during stabilization: M70 CoreDNS at `172.16.99.70`
- Router fallback DNS: `172.16.99.1`

## Live Facts Captured

- Captured at: `2026-05-23T13:06:17Z`
- OS: Ubuntu `24.04.4 LTS` on ARM64
- Kernel: `6.8.12-tegra`
- Firmware stack: NVIDIA Thor Developer Kit, L4T `38.4.0`
- GPU: NVIDIA Thor, driver `580.00`, CUDA shown by `nvidia-smi` as `13.0`
- Default route: `172.16.99.1`
- Local users observed: `bunnydev:1000`, `eva:1001`
- Central identity status: `sssd` installed but not enrolled/configured
- Running inference-adjacent service:
  `ghcr.io/nvidia/openshell/cluster:0.0.26`, container name
  `openshell-cluster-nemoclaw`, published as `0.0.0.0:8080->30051/tcp`

## Completed Live Changes

- Changed default boot target from graphical to headless multi-user mode.
- Stopped and disabled `gdm.service` and `gnome-remote-desktop.service`.
- Disabled and reset failed local DHCP/DNS services:
  `dnsmasq.service`, `isc-dhcp-server.service`, and
  `isc-dhcp-server6.service`.
- Disabled Ubuntu `noble-proposed` in `/etc/apt/sources.list` and saved the
  original file under `/root/forge-change-backups/`.
- Added `/etc/apt/preferences.d/99-forge-nvidia-l4t-pin` to pin NVIDIA/L4T
  packages from the NVIDIA origin at priority `1001`.
- Held NVIDIA/L4T/container integration packages with `apt-mark hold`.
- Set `enP2p1s0` DNS to `172.16.99.70 172.16.99.1`, disabled IPv6 on that
  NetworkManager connection, and reapplied the connection.
- Applied a conservative package update batch focused on security/runtime
  packages while avoiding `NetworkManager`, `snapd`, `linux-firmware`, desktop
  packages, WebKit/GNOME packages, and NVIDIA/L4T packages.
- Repaired an `openssh-server` post-install failure caused by an old standalone
  `sshd -D` process holding port 22 while `ssh.socket` tried to bind it.

## Validation Evidence

- `systemctl get-default` returned `multi-user.target`.
- `systemctl --failed` returned zero failed units.
- `gdm.service` and `gnome-remote-desktop.service` were inactive.
- `ssh.socket`, `docker.service`, and `containerd.service` were active.
- `dpkg --audit` returned clean.
- SSH through M70 to port 22 remained valid after the OpenSSH repair.
- `dig +short agx-rfc99-bunnydev.rfc1918.host @172.16.99.70` returned
  `172.16.99.34`.
- `nvidia-smi` reported no GUI processes and a low idle GPU state.
- Docker reported `openshell-cluster-nemoclaw` as healthy after Docker restart.

## Held Or Deferred Work

- No reboot has been performed after stabilization.
- `NetworkManager`, `snapd`, and `linux-firmware` were intentionally left at
  their installed versions pending a more specific regression review.
- `ollama`, `openwebui`, `vllm`, `mlc_llm`, `torch`, `transformers`,
  `triton`, `fastapi`, `uvicorn`, `podman`, and `nvcc` were not present in the
  live PATH or Python environment at the time of capture.
- `mgbe0_0` through `mgbe3_0` were up with link-local `169.254/16` state and
  are not yet bridged, attached to Open vSwitch, or connected to CRS354
  `qsfpplus2`.
- FreeIPA/SSSD enrollment is not complete; do not assume central user or sudo
  policy is available on Thor yet.

## Next Plan

1. Reboot once an operator is available to observe console or recover via the
   management path.
2. Validate post-reboot SSH, `nvidia-smi`, `docker ps`, DNS, and zero failed
   units.
3. Add Thor to the FreeIPA/SSSD workflow after the central identity variables
   and host OTP path are confirmed for Ubuntu clients.
4. Convert the four Thor `mgbe*` links into the agreed data-plane design after
   CRS354 `qsfpplus2` cabling is physically connected and validated.
5. Install inference services only after package pins and CUDA/L4T dependency
   boundaries are explicit; prefer containers where NVIDIA publishes supported
   ARM64 artifacts.
6. Replace Docker with Podman only after confirming the NVIDIA container runtime
   path for Thor/L4T is preserved or cleanly reproduced.

## Shared Memory Handoff

The live handoff note was also relayed to M70 at:

`/root/memory-transfers/forge-x12again/msg-relay/thor-agx-stabilization-20260523T130129Z.md`

Checksum recorded on M70:

`81dd0f647dd60c5daf60dc86fdf826a98b45559ddabe9d134bde6c891edd8249`
