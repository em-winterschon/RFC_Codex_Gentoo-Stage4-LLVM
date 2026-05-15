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

Captured data includes:

- `/etc/pve`
- `/etc/network/interfaces`
- `/etc/sysctl.d`
- Proxmox QEMU, LXC, storage, network, disk, and cluster resource JSON from
  `pvesh`
- `qm list`, `pct list`, IP, route, bridge, ZFS, and block-device summaries
- SHA256 checksum for the resulting tarball

## External Scheduled Backup Readiness

Thursday 2026-05-14 objective: prepare Hasslehoff for scheduled external
backups before additional VM migration, gateway, or X12AGAIN reimage work
depends on it.

The current script is only the first layer. It captures host configuration and
Proxmox state into operator-private local storage, but it does not yet provide a
durable off-host copy, VM disk coverage, retention, or restore validation.

The second-layer scheduled wrapper is:

```bash
bash scripts/backup-hasslehoff-scheduled.sh
```

It runs `scripts/backup-hasslehoff-config.sh`, writes a timestamped
`manifest.json`, uses a lockfile to prevent overlapping runs, and optionally
mirrors the timestamped output to an external target.

Example external mirror:

```bash
HASSLEHOFF_BACKUP_MIRROR_TARGET=backup-node:/srv/backups/hasslehoff \
HASSLEHOFF_BACKUP_MIRROR_VERIFY=1 \
HASSLEHOFF_BACKUP_NOTIFY=1 \
bash scripts/backup-hasslehoff-scheduled.sh
```

The wrapper uses `rsync -aH` and does not delete remote data. Set
`HASSLEHOFF_BACKUP_NOTIFY=1` to publish success/failure summaries to local ntfy.

Target backup layers:

- Config and control-plane state:
  `scripts/backup-hasslehoff-config.sh` captures Proxmox host state before and
  after risky changes, then the resulting timestamped bundle is mirrored to the
  external backup target.
- VM and LXC recoverability:
  selected non-ephemeral service VMs must have `vzdump` or Proxmox Backup
  Server coverage, starting with NetBox, FreeIPA, observability, syslog/search,
  netboot publisher, container-services, and workstation validation VMs.
- Host and ZFS datasets:
  use recursive ZFS snapshots plus `zfs send` to a ZFS-capable external target
  where possible. If the first external target is not ZFS-capable, use
  encrypted `borg` or `restic` repositories until a ZFS receive target exists.
- Restore validation:
  every scheduled backup class must have a restore validation gate. Minimum
  validation is checksum verification plus manifest readback; VM coverage also
  requires periodic restore into a disposable VM or offline image inspection.

Initial external target candidates:

- R86S/off-host backup node over SSH or mounted storage for immediate
  config-bundle mirroring.
- QNAP TS435XEU after NAS inventory, storage-pool validation, and RBAC/AAA
  integration.
- Future Proxmox Backup Server or ZFS receive target when storage architecture
  stabilizes.

Schedule intent:

- Run config/state backup daily before other automation windows and immediately
  before or after Proxmox/network changes.
- Run selected service-VM backups daily, with lower-frequency full coverage for
  bulky or rebuildable workloads.
- Retain short daily history locally, longer history externally, and define
  retention by service criticality instead of raw VM count.
- Emit success/failure notifications to the local ntfy service and scrape backup
  freshness through observability once exporters/checks are wired.

Readiness gates:

- External backup target is reachable without relying on X12AGAIN.
- Target free space and retention are known before the first full VM run.
- Secrets stay in Ansible Vault or backup-tool repositories; raw backup artifacts are never committed to git.
- The backup process is throttleable so it does not disrupt Hasslehoff VM
  service SLOs or the SUN99 management network.
- Backout is limited to disabling the timer/job and leaving existing backups in
  place; backup enablement must not require destructive host changes.

## Emergency Gateway Ethernet WAN Link

Before the CRS309 to CCR2004 swap, prepare a physical Ethernet cable path from
the on-host Codex system directly to the AT&T gateway or to the management L2
that still reaches it. This is the emergency path if the primary gateway is
offline long enough that Codex cannot reach network services.

Emergency objective:

- keep local shell access on the Codex host
- keep Hasslehoff serial access to the CCR2004 available through
  `/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A9888PID-if00-port0`
  (currently observed as `/dev/ttyUSB0`; do not depend on the volatile tty name)
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
