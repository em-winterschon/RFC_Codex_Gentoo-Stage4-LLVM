# Hasslehoff Backup Workflow

This workflow captures Proxmox host configuration from `root@hasslehoff` into
on-host operator-private storage.

## Command

```bash
bash scripts/backup-hasslehoff-config.sh
```

Dry-run:

```bash
HASSLEHOFF_BACKUP_DRY_RUN=1 bash scripts/backup-hasslehoff-config.sh
```

Default output:

```text
/root/operator-private/hasslehoff/backups/<UTC timestamp>/
```

Captured data includes:

- `/etc/pve`
- `/etc/network/interfaces`
- `/etc/sysctl.d`
- Proxmox QEMU, LXC, storage, network, disk, and cluster resource JSON from
  `pvesh`
- `qm list`, `pct list`, IP, route, bridge, ZFS, and block-device summaries
- SHA256 checksum for the resulting tarball

## Emergency Gateway Ethernet WAN Link

Before the CRS309 to CCR2004 swap, prepare a physical Ethernet cable path from
the on-host Codex system directly to the AT&T gateway or to the management L2
that still reaches it. This is the emergency path if the primary gateway is
offline long enough that Codex cannot reach network services.

Emergency objective:

- keep local shell access on the Codex host
- keep Hasslehoff serial access to the CCR2004 available through
  `/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A9888PID-if00-port0`
- bypass the failed primary gateway long enough to review, repair, or roll back
  RouterOS

Minimum emergency procedure:

1. Patch the on-host emergency NIC directly to the AT&T gateway L2.
2. Bring up a temporary host IP in the AT&T subnet if DHCP does not work.
3. Confirm the host can reach `192.168.1.254`.
4. Use Hasslehoff serial console to repair or roll back CCR2004:
   `/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A9888PID-if00-port0`.
5. Do not remove the emergency cable until management reachability and default
   gateway behavior are stable through the planned fabric path.
