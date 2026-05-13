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

Captured data includes `/etc/pve`, `/etc/network/interfaces`, `/etc/sysctl.d`,
Proxmox `pvesh` JSON, `qm list`, `pct list`, IP/route/bridge summaries, ZFS
summaries, and a SHA256 checksum.

## Emergency Gateway Ethernet WAN Link

Before the CRS309 to CCR2004 swap, prepare a physical Ethernet cable path from
the on-host Codex system directly to the AT&T gateway or to the management L2
that still reaches it. This is the emergency path if the primary gateway is
offline long enough that Codex cannot reach network services while Hasslehoff
CCR2004 serial access remains available through
`/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A9888PID-if00-port0`
(currently observed as `/dev/ttyUSB0`; do not depend on the volatile tty name).
