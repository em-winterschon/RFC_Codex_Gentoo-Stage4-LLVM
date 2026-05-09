# Hasslehoff Maintenance Network GPU Design

## Goal

Prepare Hasslehoff for K1200 GPU passthrough, QLogic-to-CRS309 LACP, safe PVE8
maintenance upgrades with ZFS rollback points, and future NVIDIA DOCA/OFED
standardization without performing risky live upgrades by default.

## Decisions

- Keep Hasslehoff on Proxmox VE `8.x` for now. Do not move to PVE9 while the
  mixed cluster includes the custom ARM64 `nanoprime` node.
- Use CRS309 `sfp-sfpplus4` and `sfp-sfpplus5` for Hasslehoff
  `enp4s0f0/enp4s0f1`.
- Blacklist `snd_hda_intel` on Hasslehoff because the server has no audio use
  case and both K1200 PCI functions should stay clear for passthrough.
- Bind K1200 PCI IDs `10de:13bc` and `10de:0fbc` to `vfio-pci` through the
  GPU host policy role.
- Use `/etc/kernel/cmdline` plus `proxmox-boot-tool refresh` for Proxmox
  boot-tool hosts; do not rely only on GRUB drop-ins.
- Keep NVIDIA DOCA/OFED installation gated. Proxmox kernels are custom kernels,
  so a repo package and explicit custom-kernel acknowledgement are required.

## Safety Gates

- `proxmox_host_upgrade_apply: false` by default.
- `nvidia_doca_ofed_enabled: false` and `nvidia_doca_ofed_apply: false` by
  default.
- `gpu_host_policy_proxmox_boot_tool_refresh: false` by default, including
  Hasslehoff host vars until a reboot maintenance window is selected.
- RouterOS CRS309 changes remain render-only through
  `routeros_spine_distribution_apply: false`.

## Validation

- GPU render check must include `snd_hda_intel`, vfio-pci IDs, and a managed
  kernel command line.
- Proxmox upgrade playbook syntax must pass.
- NVIDIA DOCA/OFED playbook syntax must pass.
- Local-network inventory must parse with `hasslehoff` in `gpu_compute`,
  `bmc_managed`, and `roce_hosts`.
