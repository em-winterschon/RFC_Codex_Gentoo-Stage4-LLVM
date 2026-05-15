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

Scheduled wrapper dry-run:

```bash
HASSLEHOFF_BACKUP_DRY_RUN=1 bash scripts/backup-hasslehoff-scheduled.sh
```

Default output:

```text
/root/operator-private/hasslehoff/backups/<UTC timestamp>/
```

Captured data includes `/etc/pve`, `/etc/network/interfaces`, `/etc/sysctl.d`,
Proxmox `pvesh` JSON, `qm list`, `pct list`, IP/route/bridge summaries, ZFS
summaries, and a SHA256 checksum.

## External Scheduled Backup Readiness

Thursday 2026-05-14 objective: prepare Hasslehoff for scheduled external
backups before additional VM migration, gateway, or X12AGAIN reimage work
depends on it.

Target backup layers:

- Config and control-plane state from `scripts/backup-hasslehoff-config.sh`,
  mirrored off-host after capture by `scripts/backup-hasslehoff-scheduled.sh`.
- VM and LXC recoverability through `vzdump` or Proxmox Backup Server for
  NetBox, FreeIPA, observability, syslog/search, netboot publisher,
  container-services, and workstation validation VMs.
- Host and ZFS datasets through recursive snapshots plus `zfs send` where the
  external target supports ZFS, otherwise encrypted `borg` or `restic`.
- Restore validation through checksums, manifest readback, and periodic
  disposable restore or offline image inspection.

Readiness gates:

- External backup target is reachable without relying on X12AGAIN.
- Target free space and retention are known before the first full VM run.
- Secrets stay in Ansible Vault or backup-tool repositories; raw backup
  artifacts are never committed to git.
- The job is throttleable and reports success/failure to local ntfy and later
  observability checks.
- Backout is limited to disabling the timer/job and leaving existing backups in
  place.

Example external mirror:

```bash
HASSLEHOFF_BACKUP_MIRROR_TARGET=backup-node:/srv/backups/hasslehoff \
HASSLEHOFF_BACKUP_MIRROR_VERIFY=1 \
HASSLEHOFF_BACKUP_NOTIFY=1 \
bash scripts/backup-hasslehoff-scheduled.sh
```

## Emergency Gateway Ethernet WAN Link

Before the CRS309 to CCR2004 swap, prepare a physical Ethernet cable path from
the on-host Codex system directly to the AT&T gateway or to the management L2
that still reaches it. This is the emergency path if the primary gateway is
offline long enough that Codex cannot reach network services while Hasslehoff
CCR2004 serial access remains available through
`/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A9888PID-if00-port0`
(currently observed as `/dev/ttyUSB0`; do not depend on the volatile tty name).
