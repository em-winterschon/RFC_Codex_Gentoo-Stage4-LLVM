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

Preferred first durable target:

- FMT2 NASA storage controller `kvm-sfo200-nasa-9918.vernetzen.io`
  (`10.200.99.18`) over the temporary M70 OpenVPN transport. On 2026-05-15,
  DNS, ICMP, SSH `tcp/22`, and NFS `tcp/2049` validated from SUN99; rsync
  daemon `tcp/873` was closed or filtered. The X12AGAIN operator artifact
  `/root/operator-private/fmt2-nasa/nasa-nfs-exports` records NASA's reference
  client-facing mapping as `/srv/nfs/rfc1918/nasa/chunkers`, allowed for
  `172.16.99.0/24` and OpenVPN transit subnet `192.168.132.0/24` with
  `rw,sync,insecure,all_squash,no_subtree_check,sec=sys` and anonymous UID/GID
  `8888`. Live `exportfs -v` currently reports the canonical backing path
  `/opt/storage/local/zfs/ora-sas-mpaths/chunkers/rfc1918.nfs`. Use the M70
  NASA NFS relay pattern for bulky artifacts: mount NASA NFS only on
  `admin-sun99-forge-099070`, then rsync backup data to that mounted path on
  the M70 so the payload transits `tun-fmt2`. X12AGAIN must not mount NASA NFS.
  A successful M70 NFSv3 mount and backup write path validation passed on
  2026-05-15. Do not depend on rsync daemon service.

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
HASSLEHOFF_BACKUP_RESTORE_VERIFY=1 \
HASSLEHOFF_BACKUP_NOTIFY=1 \
bash scripts/backup-hasslehoff-scheduled.sh
```

Set `HASSLEHOFF_BACKUP_RESTORE_VERIFY=1` to require manifest readback and
SHA256 validation from the mirrored target after rsync completes. Use
`HASSLEHOFF_BACKUP_PREFLIGHT_ONLY=1` before scheduling a new target, and set
`HASSLEHOFF_BACKUP_RETENTION_DAYS=<days>` only after the retention window is
approved. Deletion requires `HASSLEHOFF_BACKUP_RETENTION_APPLY=1`.
Mirror rsync defaults to `HASSLEHOFF_BACKUP_MIRROR_RSYNC_OPTS="--no-owner --no-group"`
so squashed NFS relay targets such as NASA do not fail on ownership changes.

The scheduled wrapper refuses X12AGAIN-dependent mirror targets by name, known
alias, or `172.16.99.108`; X12AGAIN must never become the durable mirror target
for the work that prepares it to be reimaged.

## M70 NASA NFS relay

NASA mirror example, after M70 has mounted NASA NFS at the selected local
mountpoint:

```bash
HASSLEHOFF_BACKUP_MIRROR_TARGET='root@admin-sun99-forge-099070:/mnt/nasa/hasslehoff/config-bundles' \
HASSLEHOFF_BACKUP_MIRROR_VERIFY=1 \
HASSLEHOFF_BACKUP_RESTORE_VERIFY=1 \
HASSLEHOFF_BACKUP_MIRROR_RSYNC_OPTS='--no-owner --no-group' \
HASSLEHOFF_BACKUP_NOTIFY=1 \
bash scripts/backup-hasslehoff-scheduled.sh
```

If the scheduled wrapper runs directly on M70, use a local mirror target under
the NASA mountpoint instead:

```bash
HASSLEHOFF_BACKUP_MIRROR_TARGET='/mnt/nasa/hasslehoff/config-bundles' \
HASSLEHOFF_BACKUP_MIRROR_VERIFY=1 \
HASSLEHOFF_BACKUP_RESTORE_VERIFY=1 \
HASSLEHOFF_BACKUP_MIRROR_RSYNC_OPTS='--no-owner --no-group' \
HASSLEHOFF_BACKUP_NOTIFY=1 \
bash scripts/backup-hasslehoff-scheduled.sh
```

Use `sshfs` only for operator inspection or staging. Scheduled automation should
prefer rsync-over-SSH to the M70 relay plus M70-local NFS because NASA is
reachable only through the M70 OpenVPN link. If NFS is used for bulky VM
artifacts, first validate mount behavior from the M70 against the reference
mapping and the live `exportfs -v` canonical path, then mount it under a
dedicated backup path with explicit timeout, retry, and stale-mount detection.

Live validation on 2026-05-15 mounted the canonical export from M70 with
NFSv3/TCP through `tun-fmt2`. The export root is owned by UID/GID `4096`, while
NASA exports with `all_squash` to UID/GID 8888, so write probes fail at the
export root by design. The dedicated NASA-side directories
`hasslehoff/config-bundles` and `forge/transfer-stage` were created with
UID/GID 8888 and mode `2770`; M70 write/read/delete probes passed in both
directories. Because NASA uses `all_squash`, mirror jobs must not attempt
remote `chown`; the scheduled wrapper's default `--no-owner --no-group` mirror
options are required for this relay topology.

## Emergency Gateway Ethernet WAN Link

Before the CRS309 to CCR2004 swap, prepare a physical Ethernet cable path from
the on-host Codex system directly to the AT&T gateway or to the management L2
that still reaches it. This is the emergency path if the primary gateway is
offline long enough that Codex cannot reach network services while Hasslehoff
CCR2004 serial access remains available through
`/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A9888PID-if00-port0`
(currently observed as `/dev/ttyUSB0`; do not depend on the volatile tty name).
